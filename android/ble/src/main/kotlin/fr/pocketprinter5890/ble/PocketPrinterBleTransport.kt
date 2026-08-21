package fr.pocketprinter5890.ble

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothStatusCodes
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import fr.pocketprinter5890.kit.Hex
import fr.pocketprinter5890.kit.LuckPrinter
import fr.pocketprinter5890.kit.PrinterStatus
import fr.pocketprinter5890.kit.PrinterTransport
import fr.pocketprinter5890.kit.ResponseDecoder
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.UUID

/** Appareil detecte pendant le scan. */
data class PrinterDevice(
    val address: String,
    val name: String?,
    val rssi: Int
) {
    /** Les imprimantes de cette famille annoncent un nom reconnaissable. */
    val looksLikePrinter: Boolean
        get() {
            val label = name ?: return false
            return listOf("printer", "pocket", "mini", "pt-", "mpt", "bt")
                .any { label.contains(it, ignoreCase = true) }
        }
}

/** Sens d'une entree de journal. */
enum class LogDirection { TX, RX, INFO }

/** Entree du journal hexadecimal. */
data class HexLogEntry(
    val direction: LogDirection,
    val label: String,
    val bytes: ByteArray = ByteArray(0),
    val decoded: String = ""
) {
    val hex: String get() = Hex.encode(bytes)

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is HexLogEntry) return false
        return direction == other.direction && label == other.label &&
            bytes.contentEquals(other.bytes) && decoded == other.decoded
    }

    override fun hashCode(): Int {
        var result = direction.hashCode()
        result = result * 31 + label.hashCode()
        result = result * 31 + bytes.contentHashCode()
        result = result * 31 + decoded.hashCode()
        return result
    }
}

/**
 * Transport BLE pour les imprimantes de poche 5890.
 *
 * Equivalent Android de `PocketPrinter5890BLE` cote Swift. Il implemente
 * [PrinterTransport], donc s'utilise directement avec
 * `fr.pocketprinter5890.kit.PocketPrinter`.
 *
 * Le point le plus important est le **controle de flux par credits**: les
 * trames `01 nn` recues sur FF03 ne sont ni des acquittements ni des statuts,
 * mais des autorisations d'envoyer `nn` paquets de plus. Les ignorer et
 * temporiser a la place divise le debit par environ vingt.
 *
 * Toutes les operations GATT doivent etre serialisees sur un seul thread:
 * Android n'accepte qu'une operation a la fois par connexion. C'est le role
 * du [Handler] sur le thread principal.
 */
@SuppressLint("MissingPermission")
class PocketPrinterBleTransport(
    context: Context
) : PrinterTransport {

    private val appContext: Context = context.applicationContext
    private val handler = Handler(Looper.getMainLooper())

    private val bluetoothManager: BluetoothManager? =
        appContext.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
    private val adapter: BluetoothAdapter? = bluetoothManager?.adapter

    private var gatt: BluetoothGatt? = null
    private var writeCharacteristic: BluetoothGattCharacteristic? = null
    private var activeProfile: BleUartProfile? = null

    private val writeQueue = ArrayDeque<WriteRequest>()
    private var waitingForWriteCallback = false
    private var queueWatchdogArmed = false

    /**
     * Credits de flux annonces par l'imprimante via les trames `01 nn`.
     *
     * Remis a zero a chaque connexion: des credits herites d'une session
     * precedente font croire que l'imprimante doit encore des paquets, et le
     * travail suivant se bloque en attendant un credit qui n'arrivera pas.
     */
    private var credits = 0
    private var totalBytesQueued = 0
    private var totalBytesSent = 0

    private var pendingResponseContexts = ArrayDeque<String>()

    // MARK: - Etat observable

    private val _devices = MutableStateFlow<List<PrinterDevice>>(emptyList())
    val devices: StateFlow<List<PrinterDevice>> = _devices.asStateFlow()

    private val _stateText = MutableStateFlow("Bluetooth non initialise")
    val stateText: StateFlow<String> = _stateText.asStateFlow()

    private val _isScanning = MutableStateFlow(false)
    val isScanning: StateFlow<Boolean> = _isScanning.asStateFlow()

    private val _isConnected = MutableStateFlow(false)
    val isConnected: StateFlow<Boolean> = _isConnected.asStateFlow()

    /**
     * Une connexion ou une deconnexion est en cours.
     *
     * `isConnected` ne bascule qu'une fois les services decouverts, plusieurs
     * secondes apres l'appui. Sans cet etat intermediaire, l'interface laisse
     * un bouton « Connecter » actif alors que la liaison s'etablit deja, et
     * chaque appui supplementaire ouvre un client GATT de plus.
     */
    private val _isBusy = MutableStateFlow(false)
    val isBusy: StateFlow<Boolean> = _isBusy.asStateFlow()

    /** Adresse de l'appareil en cours de connexion, pour cibler l'affichage. */
    private val _connectingAddress = MutableStateFlow<String?>(null)
    val connectingAddress: StateFlow<String?> = _connectingAddress.asStateFlow()

    private val _log = MutableStateFlow<List<HexLogEntry>>(emptyList())
    val log: StateFlow<List<HexLogEntry>> = _log.asStateFlow()

    /** Progression du travail en cours, de 0 a 1. Vaut 1 quand la file est vide. */
    private val _sendProgress = MutableStateFlow(1.0)
    val sendProgress: StateFlow<Double> = _sendProgress.asStateFlow()

    private val _batteryPercent = MutableStateFlow<Int?>(null)
    val batteryPercent: StateFlow<Int?> = _batteryPercent.asStateFlow()

    private val _printerStatus = MutableStateFlow<PrinterStatus?>(null)
    val printerStatus: StateFlow<PrinterStatus?> = _printerStatus.asStateFlow()

    private val _deviceModel = MutableStateFlow<String?>(null)
    val deviceModel: StateFlow<String?> = _deviceModel.asStateFlow()

    private val _deviceFirmware = MutableStateFlow<String?>(null)
    val deviceFirmware: StateFlow<String?> = _deviceFirmware.asStateFlow()

    private val _selectedService = MutableStateFlow("-")
    val selectedService: StateFlow<String> = _selectedService.asStateFlow()

    // MARK: - Reglages

    /**
     * Taille de paquet. L'application officielle negocie un MTU jusqu'a 512
     * octets; 180 fonctionne de maniere fiable. 20 (le minimum BLE) marche
     * aussi mais rend l'impression tres lente.
     */
    var maxChunkSize: Int = 180

    /** Utilise les trames `01 nn` comme credits de flux. */
    var useCreditFlowControl: Boolean = true

    /** Delai fixe entre paquets, en millisecondes. Inutile avec les credits. */
    var interPacketDelayMillis: Long = 0

    var showOnlyLikelyPrinters: Boolean = true

    var preferredProfileId: String = PrinterBleProfiles.AUTOMATIC_ID

    /**
     * Interroge modele, firmware, batterie et papier des la connexion etablie.
     *
     * Sans cela, les champs restent vides jusqu'a un appui manuel sur « Lire
     * infos », ce qui donne l'impression que la connexion a echoue.
     */
    var readInfoOnConnect: Boolean = true

    /**
     * Recopie le journal dans logcat, sous le tag [LOG_TAG].
     *
     * Utile pour diagnostiquer depuis un poste de developpement:
     * `adb logcat -s PocketPrinter5890`. Sans machine branchee, la console de
     * l'application affiche exactement les memes entrees.
     */
    var mirrorLogToLogcat: Boolean = true

    private class WriteRequest(var bytes: ByteArray, val label: String)

    // MARK: - Scan

    fun startScan() {
        val scanner = adapter?.bluetoothLeScanner
        if (adapter?.isEnabled != true || scanner == null) {
            _stateText.value = "Activez le Bluetooth"
            return
        }
        _devices.value = emptyList()
        _isScanning.value = true
        _stateText.value = "Recherche en cours"
        // Aucun filtre de service: certaines imprimantes n'annoncent pas
        // FF00 dans leur trame publicitaire alors qu'elles l'exposent.
        scanner.startScan(
            emptyList(),
            ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .build(),
            scanCallback
        )
    }

    fun stopScan() {
        adapter?.bluetoothLeScanner?.stopScan(scanCallback)
        _isScanning.value = false
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val device = PrinterDevice(
                address = result.device.address,
                name = runCatching { result.device.name }.getOrNull()
                    ?: result.scanRecord?.deviceName,
                rssi = result.rssi
            )
            if (showOnlyLikelyPrinters && !device.looksLikePrinter) return
            val current = _devices.value
            if (current.any { it.address == device.address }) {
                _devices.value = current.map { if (it.address == device.address) device else it }
            } else {
                _devices.value = current + device
            }
        }

        override fun onScanFailed(errorCode: Int) {
            _isScanning.value = false
            _stateText.value = "Echec du scan (code $errorCode)"
        }
    }

    // MARK: - Connexion

    fun connect(address: String) {
        // Verrou pose avant tout: deux appuis rapproches ouvraient deux
        // clients GATT, et le journal montrait la connexion s'etablir
        // plusieurs fois de suite.
        if (_isBusy.value || _isConnected.value) return

        val device: BluetoothDevice = runCatching { adapter?.getRemoteDevice(address) }
            .getOrNull() ?: run {
            _stateText.value = "Appareil introuvable"
            return
        }
        stopScan()
        _isBusy.value = true
        _connectingAddress.value = address
        _stateText.value = "Connexion en cours"
        gatt = device.connectGatt(appContext, false, gattCallback, BluetoothDevice.TRANSPORT_LE)

        // Une connexion qui n'aboutit pas ne doit pas bloquer l'interface
        // indefiniment.
        handler.postDelayed({
            if (_isBusy.value && !_isConnected.value) {
                gatt?.close()
                gatt = null
                resetConnectionState("Echec de la connexion")
            }
        }, CONNECT_TIMEOUT_MILLIS)
    }

    fun disconnect() {
        val current = gatt
        if (current == null) {
            resetConnectionState("Deconnecte")
            return
        }
        _isBusy.value = true
        // Android ne coupe pas le lien radio des l'appel a `disconnect()`: la
        // pile laisse expirer un temporisateur L2CAP avant de fermer la
        // connexion ACL (`l2c_link_timeout`, mesure a ~4 s sur Pixel 7a). La
        // LED de l'imprimante reste donc allumee un moment apres l'appui.
        //
        // `close()` libere le client GATT et accelere nettement la coupure;
        // l'appeler immediatement apres `disconnect()` reste correct, la
        // sequence recommandee etant precisement disconnect() puis close().
        // On garde l'etat « en cours » jusqu'a l'evenement systeme, pour ne
        // pas annoncer une deconnexion que la radio n'a pas encore faite.
        _stateText.value = "Deconnexion en cours"
        current.disconnect()
        current.close()
        gatt = null

        // Filet de securite: `close()` supprime les rappels, l'evenement de
        // deconnexion peut donc ne jamais arriver.
        handler.postDelayed({
            if (_isConnected.value) resetConnectionState("Deconnecte")
        }, 300)
    }

    private fun resetConnectionState(text: String) {
        _isConnected.value = false
        _isBusy.value = false
        _connectingAddress.value = null
        writeCharacteristic = null
        activeProfile = null
        writeQueue.clear()
        waitingForWriteCallback = false
        // Les credits appartiennent a une session: les conserver ferait
        // stagner le travail suivant.
        credits = 0
        totalBytesQueued = 0
        totalBytesSent = 0
        pendingResponseContexts.clear()
        _sendProgress.value = 1.0
        _batteryPercent.value = null
        _printerStatus.value = null
        _deviceModel.value = null
        _deviceFirmware.value = null
        _selectedService.value = "-"
        _stateText.value = text
    }

    private val gattCallback = object : BluetoothGattCallback() {

        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                _stateText.value = "Connecte, negociation du MTU"
                // Un MTU eleve reduit fortement le nombre de paquets. La
                // decouverte des services attend le resultat.
                if (!gatt.requestMtu(512)) {
                    gatt.discoverServices()
                }
                return
            }
            if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                // Eteindre l'imprimante ne remonte aucune erreur sur le chemin
                // d'ecriture: sans cet evenement, on continuerait a empiler
                // des octets dans le vide.
                gatt.close()
                this@PocketPrinterBleTransport.gatt = null
                handler.post { resetConnectionState("Deconnecte") }
            }
        }

        override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
            // 3 octets d'en-tete ATT sont retires du MTU utilisable.
            val usable = (mtu - 3).coerceAtLeast(20)
            maxChunkSize = minOf(maxChunkSize, usable)
            handler.post {
                appendLog(
                    HexLogEntry(
                        LogDirection.INFO,
                        "MTU $mtu, paquets de $maxChunkSize octets"
                    )
                )
            }
            gatt.discoverServices()
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            val profile = PrinterBleProfiles.orderedProfiles(preferredProfileId)
                .firstOrNull { candidate ->
                    val service = gatt.getService(candidate.service) ?: return@firstOrNull false
                    service.getCharacteristic(candidate.write) != null
                }

            if (profile == null) {
                val seen = gatt.services.joinToString(", ") { it.uuid.toString() }
                handler.post {
                    appendLog(HexLogEntry(LogDirection.INFO, "Services vus: $seen"))
                    // Sans cela l'interface resterait figee sur « connexion en
                    // cours » jusqu'a l'expiration du delai de securite.
                    gatt.close()
                    this@PocketPrinterBleTransport.gatt = null
                    resetConnectionState("Aucun profil compatible")
                }
                return
            }

            val service = gatt.getService(profile.service)
            activeProfile = profile
            writeCharacteristic = service.getCharacteristic(profile.write)

            // Il faut s'abonner aux DEUX caracteristiques: FF01 porte les
            // reponses, FF03 le statut et les credits de flux.
            val toSubscribe = listOfNotNull(profile.notify, profile.extraNotify)
            subscribeSequentially(gatt, service.uuid, toSubscribe, 0)

            handler.post {
                _selectedService.value = profile.id
                _isConnected.value = true
                _isBusy.value = false
                _connectingAddress.value = null
                _stateText.value = "Connecte (${profile.id})"
                appendLog(HexLogEntry(LogDirection.INFO, "Profil ${profile.id}"))
            }
        }

        /**
         * Active les notifications une par une.
         *
         * Android n'accepte qu'une ecriture de descripteur a la fois: les
         * enchainer sans attendre le rappel en perd silencieusement une, et
         * les credits n'arrivent alors jamais.
         */
        private fun subscribeSequentially(
            gatt: BluetoothGatt,
            serviceUuid: UUID,
            characteristics: List<UUID>,
            index: Int
        ) {
            if (index >= characteristics.size) {
                handler.post {
                    // L'interrogation part une fois les notifications actives:
                    // envoyee plus tot, ses reponses arriveraient avant qu'on
                    // ecoute et seraient perdues.
                    if (readInfoOnConnect) requestDeviceInformation()
                    drainWriteQueue()
                }
                return
            }
            val service = gatt.getService(serviceUuid)
            val characteristic = service?.getCharacteristic(characteristics[index])
            if (characteristic == null) {
                subscribeSequentially(gatt, serviceUuid, characteristics, index + 1)
                return
            }
            gatt.setCharacteristicNotification(characteristic, true)
            val descriptor = characteristic
                .getDescriptor(PrinterBleProfiles.clientCharacteristicConfig)
            if (descriptor == null) {
                subscribeSequentially(gatt, serviceUuid, characteristics, index + 1)
                return
            }
            pendingSubscriptions = Triple(serviceUuid, characteristics, index)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                gatt.writeDescriptor(
                    descriptor,
                    BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                )
            } else {
                @Suppress("DEPRECATION")
                descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                @Suppress("DEPRECATION")
                gatt.writeDescriptor(descriptor)
            }
        }

        override fun onDescriptorWrite(
            gatt: BluetoothGatt,
            descriptor: BluetoothGattDescriptor,
            status: Int
        ) {
            val pending = pendingSubscriptions ?: return
            subscribeSequentially(gatt, pending.first, pending.second, pending.third + 1)
        }

        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray
        ) {
            handler.post { handleNotification(value) }
        }

        @Deprecated("Rappel utilise avant Android 13")
        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic
        ) {
            @Suppress("DEPRECATION")
            val value = characteristic.value ?: return
            handler.post { handleNotification(value) }
        }

        override fun onCharacteristicWrite(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int
        ) {
            handler.post {
                waitingForWriteCallback = false
                if (interPacketDelayMillis > 0) {
                    handler.postDelayed({ drainWriteQueue() }, interPacketDelayMillis)
                } else {
                    drainWriteQueue()
                }
            }
        }
    }

    private var pendingSubscriptions: Triple<UUID, List<UUID>, Int>? = null

    // MARK: - Reception

    private fun handleNotification(bytes: ByteArray) {
        // Un credit de flux est emis en continu pendant les echanges. Le
        // traiter comme une reponse consomme le contexte en attente et fait
        // lire `01 01` comme « batterie 1 % » alors que la vraie reponse
        // (`00 62`, 98 %) arrive juste apres.
        val credit = ResponseDecoder.creditFrame(bytes)
        if (credit != null) {
            credits += credit
            appendLog(
                HexLogEntry(
                    LogDirection.RX, "Credit", bytes,
                    ResponseDecoder.decode(bytes, null)
                )
            )
            drainWriteQueue()
            return
        }

        val context = pendingResponseContexts.firstOrNull()
        val solicited = context != null &&
            ResponseDecoder.looksLikeSolicitedResponse(bytes, context)
        if (solicited) {
            pendingResponseContexts.removeFirst()
        }
        val decoded = ResponseDecoder.decode(bytes, context)
        appendLog(HexLogEntry(LogDirection.RX, context ?: "Notification", bytes, decoded))
        updatePrinterState(bytes, if (solicited) context else null)
    }

    /**
     * Met a jour l'etat affiche a partir d'une trame recue.
     *
     * @param solicitedContext libelle de la commande a laquelle cette trame
     *   repond, ou null si elle est arrivee spontanement.
     *
     * Une trame non sollicitee n'est jamais interpretee comme une valeur:
     * l'imprimante emet `02 64 00` a chaque connexion, et la lire comme un
     * pourcentage affichait « batterie 100 % » en permanence, y compris sur
     * une machine presque vide. Le SDK constructeur ne lit la batterie que
     * dans le callback de `10 FF 50 F1` (`lambda$getBatteryLuck$6`), jamais
     * au fil de l'eau.
     */
    private fun updatePrinterState(bytes: ByteArray, solicitedContext: String?) {
        if (solicitedContext == null) return
        val context = solicitedContext.lowercase()
        val unsigned = bytes.map { it.toInt() and 0xff }

        // Le pourcentage est le deuxieme octet, dans les deux formes
        // observees (`00 62` en reponse, `02 64 00` spontane).
        if (context.contains("batterie")) {
            val value = unsigned.getOrNull(1) ?: return
            if (value in 1..100) {
                _batteryPercent.value = value
                return
            }
        }

        // Reponse texte a une demande de modele ou de firmware. C'est la
        // commande envoyee qui dit de quoi il s'agit, pas la forme de la
        // reponse: "A2Y" et "V1.06LY" sont deux chaines ASCII.
        if (context.contains("modele") || context.contains("firmware")) {
            val printable = bytes.filter { (it.toInt() and 0xff) in 0x20..0x7e }
            if (printable.isEmpty()) return
            val text = String(printable.toByteArray(), Charsets.US_ASCII)
            if (context.contains("firmware")) {
                _deviceFirmware.value = text
            } else {
                _deviceModel.value = text
            }
            return
        }

        if (context.contains("papier")) {
            // L'octet de statut est le dernier: `01 nn` sur trois octets ou
            // un octet seul selon la forme de reponse.
            val status = unsigned.lastOrNull() ?: return
            _printerStatus.value = PrinterStatus(status)
        }
    }

    /**
     * Interroge l'imprimante sur son identite et son etat.
     *
     * Chaque commande est encadree par la sequence d'activation: envoyee nue,
     * elle serait acquittee puis ignoree (specification, section 3.1).
     */
    fun requestDeviceInformation() {
        for ((command, label) in listOf(
            LuckPrinter.model to "Lire modele",
            LuckPrinter.firmware to "Lire firmware",
            LuckPrinter.battery to "Lire batterie",
            LuckPrinter.status to "Lire papier"
        )) {
            send(LuckPrinter.enablePrinter(), "Activation moteur")
            send(LuckPrinter.wakeup, "Reveil")
            send(command, label)
            send(LuckPrinter.stopPrintJob, "Fin du travail")
        }
    }

    // MARK: - Emission

    override fun send(bytes: ByteArray, label: String) {
        handler.post {
            if (writeQueue.isEmpty()) {
                totalBytesQueued = 0
                totalBytesSent = 0
            }
            totalBytesQueued += bytes.size
            writeQueue.addLast(WriteRequest(bytes.copyOf(), label))
            rememberResponseContextIfNeeded(label, bytes)
            drainWriteQueue()
        }
    }

    /**
     * Retient le contexte d'une commande de lecture, pour decoder sa reponse.
     *
     * La file est bornee: si une reponse se perd, les contextes suivants ne
     * doivent pas s'empiler indefiniment et decaler tout ce qui suit.
     */
    private fun rememberResponseContextIfNeeded(label: String, bytes: ByteArray) {
        val lowered = label.lowercase()
        if (!lowered.startsWith("lire")) return
        pendingResponseContexts.addLast(label)
        while (pendingResponseContexts.size > MAX_PENDING_CONTEXTS) {
            pendingResponseContexts.removeFirst()
        }
    }

    /**
     * Relance la file apres un court delai.
     *
     * Sans ce filet, une file en attente de credit ne repart jamais si
     * l'imprimante n'emet plus rien, et le raster part tronque.
     */
    private fun scheduleQueueWatchdog() {
        if (queueWatchdogArmed) return
        queueWatchdogArmed = true
        handler.postDelayed({
            queueWatchdogArmed = false
            if (writeQueue.isNotEmpty()) drainWriteQueue()
        }, 150)
    }

    private fun drainWriteQueue() {
        val gatt = this.gatt
        val characteristic = writeCharacteristic
        if (gatt == null || characteristic == null) {
            if (writeQueue.isNotEmpty()) {
                _stateText.value = "Connectez une imprimante avant d'envoyer"
            }
            return
        }
        if (waitingForWriteCallback || writeQueue.isEmpty()) return

        // Attendre un credit avant d'ecrire, comme le fait l'application
        // officielle. Les commandes courtes de configuration passent toujours:
        // seul le gros volume raster doit etre regule.
        if (useCreditFlowControl && credits <= 0 &&
            (writeQueue.firstOrNull()?.bytes?.size ?: 0) > 64
        ) {
            scheduleQueueWatchdog()
            return
        }

        val request = writeQueue.removeFirst()
        val chunkSize = maxOf(1, minOf(maxChunkSize, request.bytes.size))
        val chunk = request.bytes.copyOfRange(0, chunkSize)
        if (request.bytes.size > chunkSize) {
            request.bytes = request.bytes.copyOfRange(chunkSize, request.bytes.size)
            writeQueue.addFirst(request)
        }

        appendLog(HexLogEntry(LogDirection.TX, request.label, chunk))

        val writeType = if (
            characteristic.properties and
            BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE != 0
        ) {
            BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
        } else {
            BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        }

        val accepted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // L'API introduite en Android 13 renvoie un BluetoothStatusCodes,
            // pas un code GATT: les deux valent 0 pour le succes, mais seul
            // le premier est le contrat de cette methode.
            gatt.writeCharacteristic(characteristic, chunk, writeType) ==
                BluetoothStatusCodes.SUCCESS
        } else {
            @Suppress("DEPRECATION")
            characteristic.writeType = writeType
            @Suppress("DEPRECATION")
            characteristic.value = chunk
            @Suppress("DEPRECATION")
            gatt.writeCharacteristic(characteristic)
        }

        if (!accepted) {
            // La pile est saturee: on remet le morceau en tete et on reessaie.
            writeQueue.addFirst(WriteRequest(chunk, request.label))
            scheduleQueueWatchdog()
            return
        }

        waitingForWriteCallback = true
        totalBytesSent += chunk.size
        if (useCreditFlowControl && credits > 0) {
            credits -= 1
        }
        updateProgress()
    }

    private fun updateProgress() {
        if (writeQueue.isEmpty()) {
            _sendProgress.value = 1.0
            return
        }
        if (totalBytesQueued <= 0) {
            _sendProgress.value = 1.0
            return
        }
        _sendProgress.value =
            minOf(1.0, totalBytesSent.toDouble() / totalBytesQueued.toDouble())
    }

    // MARK: - Journal

    private fun appendLog(entry: HexLogEntry) {
        if (mirrorLogToLogcat) {
            val suffix = if (entry.decoded.isEmpty()) "" else " — ${entry.decoded}"
            Log.d(LOG_TAG, "${entry.direction} ${entry.label} ${entry.hex}$suffix")
        }
        // Le journal est borne: un gros raster produit des milliers d'entrees.
        val current = _log.value
        _log.value = (current + entry).takeLast(500)
    }

    fun clearLog() {
        _log.value = emptyList()
    }

    companion object {
        /** Tag logcat: `adb logcat -s PocketPrinter5890`. */
        const val LOG_TAG: String = "PocketPrinter5890"

        /**
         * Nombre de lectures dont on garde le contexte en attente.
         *
         * `readDeviceInformation()` en envoie quatre d'affilee; au-dela, une
         * reponse perdue decalerait durablement l'appariement.
         */
        private const val MAX_PENDING_CONTEXTS = 4

        /** Delai au-dela duquel une tentative de connexion est abandonnee. */
        private const val CONNECT_TIMEOUT_MILLIS = 15_000L
    }
}
