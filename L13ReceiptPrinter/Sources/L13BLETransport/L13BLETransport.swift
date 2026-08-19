import CoreBluetooth
import Foundation
import L13Core

public struct PrinterDevice: Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let rssi: Int
    public let isLikelyL13: Bool

    public init(id: UUID, name: String, rssi: Int, isLikelyL13: Bool) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.isLikelyL13 = isLikelyL13
    }
}

public struct HexLogEntry: Identifiable, Equatable {
    public enum Direction: String {
        case tx = "TX"
        case rx = "RX"
        case info = "INFO"
        case error = "ERR"
    }

    public let id = UUID()
    public let date = Date()
    public let direction: Direction
    public let label: String
    public let hex: String
    public let decoded: String

    public init(direction: Direction, label: String, bytes: [UInt8], decoded: String = "") {
        self.direction = direction
        self.label = label
        self.hex = Hex.encode(bytes)
        self.decoded = decoded
    }

    public init(direction: Direction, label: String, message: String) {
        self.direction = direction
        self.label = label
        self.hex = message
        self.decoded = ""
    }

    public var line: String {
        let decodedSuffix = decoded.isEmpty ? "" : "  \(decoded)"
        return "\(Self.dateFormatter.string(from: date)) \(direction.rawValue) \(label): \(hex)\(decodedSuffix)"
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

@MainActor
public final class L13BLETransport: NSObject, ObservableObject {
    public let logFileURL: URL
    private var central: CBCentralManager?
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    private var connectedPeripheral: CBPeripheral?
    private var rxCharacteristic: CBCharacteristic?
    private var txCharacteristic: CBCharacteristic?
    private var activeProfile: BLEUARTProfile?
    private var writeQueue: [WriteRequest] = []
    private var waitingForResponseWrite = false
    private var waitingForInterPacketDelay = false
    private var pendingResponseContexts: [String] = []
    private var pendingResponseIDs: [String: UUID] = [:]
    private var queueWatchdogArmed = false
    /// Credits de flux annonces par l'imprimante via les trames `01 nn`.
    private var credits = 0
    private var totalBytesQueued = 0
    private var totalBytesSent = 0

    @Published public private(set) var devices: [PrinterDevice] = []
    @Published public private(set) var stateText = "Bluetooth non initialise"
    @Published public private(set) var isScanning = false
    @Published public private(set) var isConnected = false
    @Published public private(set) var selectedService = "-"
    @Published public private(set) var selectedRX = "-"
    @Published public private(set) var selectedTX = "-"
    @Published public private(set) var selectedNotify = "-"
    @Published public private(set) var log: [HexLogEntry] = []
    /// Delai fixe entre paquets. Inutile quand le controle de flux par
    /// credits est actif: l'imprimante dit elle-meme quand elle peut recevoir.
    @Published public var interPacketDelay: TimeInterval = 0
    /// Taille de paquet. L'application officielle negocie un MTU jusqu'a 512
    /// octets; 20 octets etait la valeur minimale du BLE et rendait
    /// l'impression extremement lente.
    @Published public var maxChunkSize = 180
    /// Utilise les trames `01 nn` comme credits de flux.
    @Published public var useCreditFlowControl = true
    @Published public var showOnlyLikelyPrinters = true
    @Published public var preferWriteWithResponse = false
    @Published public var preferredProfileID = L13BLEProfiles.automaticID
    /// Progression du travail en cours, de 0 a 1. Vaut 1 quand la file est vide.
    @Published public private(set) var sendProgress: Double = 1
    /// Niveau de batterie en pourcentage, nil tant qu'il n'a pas ete lu.
    @Published public private(set) var batteryPercent: Int?
    /// Dernier etat papier/capot connu.
    @Published public private(set) var printerStatus: PrinterStatus?
    /// Modele et firmware annonces par l'imprimante.
    @Published public private(set) var deviceModel: String?
    @Published public private(set) var deviceFirmware: String?

    private var batteryTimer: Timer?

    public override init() {
        logFileURL = Self.makeLogFileURL()
        super.init()
        prepareLogFile()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    public func startScan() {
        guard central?.state == .poweredOn else {
            stateText = "Activez Bluetooth pour rechercher l'imprimante"
            return
        }
        devices.removeAll()
        discoveredPeripherals.removeAll()
        isScanning = true
        stateText = "Recherche BLE non filtree..."
        central?.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
    }

    public func stopScan() {
        central?.stopScan()
        isScanning = false
    }

    public func connect(to device: PrinterDevice) {
        guard let peripheral = discoveredPeripherals[device.id] else { return }
        stopScan()
        stateText = "Connexion a \(device.name)..."
        connectedPeripheral = peripheral
        peripheral.delegate = self
        central?.connect(peripheral)
    }

    public func disconnect() {
        guard let connectedPeripheral else { return }
        central?.cancelPeripheralConnection(connectedPeripheral)
    }

    public func send(_ bytes: [UInt8], label: String) {
        guard !bytes.isEmpty else { return }
        if writeQueue.isEmpty {
            totalBytesQueued = 0
            totalBytesSent = 0
        }
        totalBytesQueued += bytes.count
        writeQueue.append(WriteRequest(bytes: bytes, label: label))
        updateProgress()
        drainWriteQueue()
    }

    /// Reprise de securite de la file d'ecriture.
    ///
    /// Elle couvre le cas ou le buffer BLE est plein et ou CoreBluetooth ne
    /// declenche pas `peripheralIsReady(toSendWriteWithoutResponse:)`.
    private func scheduleQueueWatchdog() {
        guard !queueWatchdogArmed else { return }
        queueWatchdogArmed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            self.queueWatchdogArmed = false
            if !self.writeQueue.isEmpty {
                self.drainWriteQueue()
            }
        }
    }

    /// Met a jour l'etat publie a partir d'une trame recue.
    ///
    /// La batterie arrive sous deux formes selon le moment:
    /// - `02 64 00` emis spontanement sur FF03 a la connexion;
    /// - `00 62` en reponse a `10 FF 50 F1` sur FF01.
    ///
    /// Dans les deux cas le pourcentage est le **deuxieme** octet, ce que fait
    /// aussi le SDK officiel (`lambda$getBatteryLuck$6` lit `bArr[1]` sans
    /// tester le premier octet).
    private func updatePrinterState(with bytes: [UInt8], context: String?) {
        // Un credit de flux `01 nn` n'est jamais une donnee: il est emis en
        // continu et son second octet serait pris pour un pourcentage.
        if bytes.count == 2, bytes[0] == 0x01 { return }

        // Deux formes de trame batterie, toutes deux longues de 2 ou 3 octets
        // avec le pourcentage en deuxieme position:
        //   `02 64 00` emis spontanement a la connexion,
        //   `00 62`    en reponse a `10 FF 50 F1`.
        // On ne se fie pas au contexte: la reponse arrive sur FF01 apres un
        // credit, et le contexte peut deja avoir ete resolu.
        let looksLikeBattery = (bytes.count == 3 && bytes[0] == 0x02)
            || (bytes.count == 2 && bytes[0] == 0x00)
        if looksLikeBattery {
            let value = Int(bytes[1])
            if value > 0, value <= 100 {
                batteryPercent = value
                return
            }
        }

        // Reponse texte a une demande de modele ou de firmware.
        if bytes.count >= 3,
           let text = String(bytes: bytes.filter { $0 >= 0x20 && $0 <= 0x7e }, encoding: .ascii),
           !text.isEmpty {
            if text.hasPrefix("V"), text.contains(".") {
                deviceFirmware = text
            } else if deviceModel == nil, text.count <= 12, text.allSatisfy({ $0.isLetter || $0.isNumber }) {
                deviceModel = text
            }
        }
    }

    /// Interroge la batterie periodiquement, comme le `BatteryLoader` de
    /// l'application officielle qui utilise une periode de 25 secondes.
    private func startBatteryPolling() {
        stopBatteryPolling()
        readBattery()
        let timer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.readBattery()
            }
        }
        batteryTimer = timer
    }

    private func stopBatteryPolling() {
        batteryTimer?.invalidate()
        batteryTimer = nil
    }

    /// Demande le niveau de batterie sans polluer la file d'impression.
    public func readBattery() {
        guard isConnected, writeQueue.isEmpty else { return }
        send(LuckPrinter.battery, label: "Lire batterie")
    }

    private func updateProgress() {
        guard totalBytesQueued > 0 else {
            sendProgress = 1
            return
        }
        let remaining = writeQueue.reduce(0) { $0 + $1.bytes.count }
        sendProgress = remaining == 0
            ? 1
            : min(1, Double(totalBytesSent) / Double(totalBytesQueued))
    }

    public func send(_ segments: [PrintSegment]) {
        for segment in segments {
            send(segment.bytes, label: segment.name)
        }
    }

    public func readDeviceInformation() {
        send(L13Command.model, label: "Lire modele")
        send(L13Command.firmware, label: "Lire firmware")
        send(L13Command.battery, label: "Lire batterie")
        send(L13Command.paperStatus, label: "Lire papier")
    }

    public func recordLocalError(_ message: String) {
        appendLog(HexLogEntry(direction: .error, label: "Application", message: message))
    }

    private func drainWriteQueue() {
        guard let peripheral = connectedPeripheral, let characteristic = rxCharacteristic else {
            if !writeQueue.isEmpty {
                stateText = "Connectez une imprimante avant d'envoyer"
            }
            return
        }
        guard !waitingForResponseWrite, !waitingForInterPacketDelay, !writeQueue.isEmpty else { return }

        let canWriteWithResponse = characteristic.properties.contains(.write)
        let writeType: CBCharacteristicWriteType = preferWriteWithResponse && canWriteWithResponse
            ? .withResponse
            : (characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse)
        // Attendre un credit avant d'ecrire, comme le fait l'application
        // officielle. Les commandes courtes de configuration passent toujours:
        // seul le gros volume raster doit etre regule.
        if useCreditFlowControl, credits <= 0, writeQueue.first.map({ $0.bytes.count > 64 }) == true {
            scheduleQueueWatchdog()
            return
        }

        if writeType == .withoutResponse, !peripheral.canSendWriteWithoutResponse {
            // CoreBluetooth ne rappelle `peripheralIsReady(toSendWriteWithoutResponse:)`
            // de maniere fiable que lorsqu'une ecriture a reellement sature le buffer.
            // En sortant ici sans replanifier, la file restait bloquee definitivement
            // et le raster partait tronque (ex. 20 octets envoyes sur 2168 annonces).
            // On arme donc une reprise de securite.
            scheduleQueueWatchdog()
            return
        }

        var request = writeQueue.removeFirst()
        let mtu = peripheral.maximumWriteValueLength(for: writeType)
        let chunkSize = max(1, min(mtu, maxChunkSize))
        let chunk = Array(request.bytes.prefix(chunkSize))
        request.bytes.removeFirst(chunk.count)
        if !request.bytes.isEmpty {
            writeQueue.insert(request, at: 0)
        }

        appendLog(HexLogEntry(direction: .tx, label: request.label, bytes: chunk))
        rememberResponseContextIfNeeded(label: request.label, bytes: chunk)
        peripheral.writeValue(Data(chunk), for: characteristic, type: writeType)
        totalBytesSent += chunk.count
        if useCreditFlowControl, credits > 0 {
            credits -= 1
        }
        updateProgress()

        if writeType == .withResponse {
            waitingForResponseWrite = true
        } else {
            if interPacketDelay <= 0 {
                DispatchQueue.main.async { [weak self] in
                    self?.drainWriteQueue()
                }
            } else {
                waitingForInterPacketDelay = true
                DispatchQueue.main.asyncAfter(deadline: .now() + interPacketDelay) { [weak self] in
                    self?.waitingForInterPacketDelay = false
                    self?.drainWriteQueue()
                }
            }
        }
    }

    private func resetConnectionState(_ text: String) {
        stopBatteryPolling()
        batteryPercent = nil
        printerStatus = nil
        deviceModel = nil
        deviceFirmware = nil
        isConnected = false
        rxCharacteristic = nil
        txCharacteristic = nil
        activeProfile = nil
        selectedService = "-"
        selectedRX = "-"
        selectedTX = "-"
        selectedNotify = "-"
        stateText = text
    }

    private struct WriteRequest {
        var bytes: [UInt8]
        var label: String
    }

    private static func makeLogFileURL() -> URL {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        return base
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("L13ReceiptPrinter", isDirectory: true)
            .appendingPathComponent("ble.log")
    }

    private func prepareLogFile() {
        let directory = logFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
    }

    private func appendLog(_ entry: HexLogEntry) {
        log.append(entry)
        guard let data = (entry.line + "\n").data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: logFileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            _ = try? handle.write(contentsOf: data)
        }
    }
}

extension L13BLETransport: CBCentralManagerDelegate {
    public nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn: stateText = "Pret a rechercher"
            case .poweredOff: resetConnectionState("Bluetooth desactive")
            case .unauthorized: resetConnectionState("Autorisation Bluetooth refusee")
            case .unsupported: resetConnectionState("Bluetooth non pris en charge")
            default: resetConnectionState("Bluetooth indisponible")
            }
        }
    }

    public nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            let name = peripheral.name
                ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
                ?? "BLE \(peripheral.identifier.uuidString.prefix(8))"
            let advertisedServices = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
            let lowercasedName = name.lowercased()
            let hasKnownService = advertisedServices.contains { L13BLEProfiles.allServiceUUIDs.contains($0) }
            let hasPrinterName = lowercasedName.contains("printer")
                || lowercasedName.contains("pocket")
                || lowercasedName.contains("l13")
                || lowercasedName.contains("dp-l13")
            let device = PrinterDevice(
                id: peripheral.identifier,
                name: name,
                rssi: RSSI.intValue,
                isLikelyL13: hasKnownService || hasPrinterName
            )
            discoveredPeripherals[peripheral.identifier] = peripheral
            devices.removeAll { $0.id == device.id }
            if !showOnlyLikelyPrinters || device.isLikelyL13 {
                devices.append(device)
            }
            devices.sort { $0.rssi > $1.rssi }
            stateText = "\(devices.count) peripherique(s) trouve(s)"
        }
    }

    public nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            appendLog(HexLogEntry(direction: .info, label: "BLE", message: "Connecte, decouverte des services"))
            stateText = "Decouverte des services..."
            peripheral.discoverServices(nil)
        }
    }

    public nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            resetConnectionState(error?.localizedDescription ?? "Deconnecte")
        }
    }

    public nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            resetConnectionState(error?.localizedDescription ?? "Connexion impossible")
        }
    }
}

extension L13BLETransport: CBPeripheralDelegate {
    public nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard error == nil else {
                resetConnectionState("Services BLE introuvables")
                return
            }
            let services = peripheral.services ?? []
            let profileOrder = L13BLEProfiles.orderedProfiles(preferredProfileID: preferredProfileID)
            guard let profile = profileOrder.first(where: { wanted in
                services.contains { $0.uuid == wanted.service }
            }) else {
                resetConnectionState("Aucun UART L13 connu trouve")
                return
            }
            activeProfile = profile
            selectedService = profile.service.uuidString
            guard let service = services.first(where: { $0.uuid == profile.service }) else { return }
            var characteristics = [profile.rx, profile.tx]
            if let extraNotify = profile.extraNotify {
                characteristics.append(extraNotify)
            }
            peripheral.discoverCharacteristics(characteristics, for: service)
        }
    }

    public nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            guard error == nil, let profile = activeProfile else {
                resetConnectionState("Caracteristiques BLE introuvables")
                return
            }

            for characteristic in service.characteristics ?? [] {
                if characteristic.uuid == profile.rx {
                    rxCharacteristic = characteristic
                    selectedRX = characteristic.uuid.uuidString
                }
                if characteristic.uuid == profile.tx {
                    txCharacteristic = characteristic
                    selectedTX = characteristic.uuid.uuidString
                    if characteristic.properties.contains(.notify) {
                        peripheral.setNotifyValue(true, for: characteristic)
                        appendNotifyUUID(characteristic.uuid)
                    }
                }
                if characteristic.uuid == profile.extraNotify, characteristic.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: characteristic)
                    appendNotifyUUID(characteristic.uuid)
                }
            }

            guard rxCharacteristic != nil else {
                resetConnectionState("Caracteristique RX absente")
                return
            }

            isConnected = true
            credits = 0
            startBatteryPolling()
            stateText = "Pret via \(profile.id)"
            appendLog(HexLogEntry(direction: .info, label: "Profil", message: profile.id))
            drainWriteQueue()
        }
    }

    public nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if let error {
                appendLog(HexLogEntry(direction: .error, label: characteristic.uuid.uuidString, message: error.localizedDescription))
                return
            }
            let bytes = Array(characteristic.value ?? Data())

            // Controle de flux par credits.
            //
            // Une trame `01 nn` n'est pas un acquittement ni un statut papier:
            // c'est l'imprimante qui annonce pouvoir accepter `nn` paquets
            // supplementaires. L'application officielle attend d'avoir des
            // credits puis envoie plusieurs paquets d'un coup, au lieu de
            // temporiser a l'aveugle.
            if useCreditFlowControl, bytes.count == 2, bytes[0] == 0x01 {
                credits += Int(bytes[1])
                drainWriteQueue()
            }

            let contextIndex = pendingResponseContexts.firstIndex {
                L13ResponseDecoder.looksLikeSolicitedResponse(bytes, context: $0)
            }
            let context = contextIndex.map { pendingResponseContexts[$0] }
            updatePrinterState(with: bytes, context: context)
            let decoded = L13ResponseDecoder.decode(bytes, context: context)
            if let contextIndex {
                let resolvedContext = pendingResponseContexts.remove(at: contextIndex)
                pendingResponseIDs[resolvedContext] = nil
            }
            let label = context.map { "\($0) reponse" } ?? characteristic.uuid.uuidString
            appendLog(HexLogEntry(direction: .rx, label: label, bytes: bytes, decoded: decoded))
            updateStateFromStatusFrame(bytes)
        }
    }

    public nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            waitingForResponseWrite = false
            if let error {
                appendLog(HexLogEntry(direction: .error, label: "Ecriture", message: error.localizedDescription))
            }
            drainWriteQueue()
        }
    }

    public nonisolated func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        Task { @MainActor in
            drainWriteQueue()
        }
    }
}

private extension L13BLETransport {
    func appendNotifyUUID(_ uuid: CBUUID) {
        let value = uuid.uuidString
        if selectedNotify == "-" {
            selectedNotify = value
        } else if !selectedNotify.contains(value) {
            selectedNotify += " + \(value)"
        }
    }

    func rememberResponseContextIfNeeded(label: String, bytes: [UInt8]) {
        switch bytes {
        case L13Command.model,
            L13Command.firmware,
            L13Command.serialNumber,
            L13Command.battery,
            L13Command.paperStatus:
            pendingResponseContexts.append(label)
            scheduleResponseTimeout(for: label)
        default:
            break
        }
    }

    func scheduleResponseTimeout(for label: String) {
        let responseID = UUID()
        pendingResponseIDs[label] = responseID
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.pendingResponseIDs[label] == responseID else { return }
            self.pendingResponseIDs[label] = nil
            self.pendingResponseContexts.removeAll { $0 == label }
            self.appendLog(HexLogEntry(
                direction: .info,
                label: "\(label) reponse",
                message: "Aucune reponse decodee recue dans 1,5 s"
            ))
        }
    }

    func updateStateFromStatusFrame(_ bytes: [UInt8]) {
        guard bytes.count >= 2, bytes[0] == 0x01 else { return }
        if bytes[1] & 0x04 != 0 {
            stateText = "Capteur papier: papier absent ou mal cale"
        } else if bytes[1] == 0x00 {
            stateText = "Capteur papier: papier detecte"
        }
    }
}

extension L13BLETransport: PrinterTransport {}
