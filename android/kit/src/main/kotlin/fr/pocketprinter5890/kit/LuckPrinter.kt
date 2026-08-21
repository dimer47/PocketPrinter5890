package fr.pocketprinter5890.kit

import java.util.Calendar
import java.util.Date

/**
 * Portage Kotlin du jeu de commandes du LuckPrinter SDK.
 *
 * Les octets proviennent de la decompilation de l'application officielle
 * `com.printer.lidloffice` (classe `BaseNormalDevice` et ses sous-classes).
 * Chaque commande porte le nom de la methode Java d'origine pour faciliter
 * les recoupements.
 *
 * Toutes les commandes ne sont pas forcement supportees par le firmware
 * A2Y / V1.06LY: le SDK est commun a plus d'une centaine de modeles. Celles
 * marquees « non verifiee » n'ont pas ete testees sur cette machine.
 */
object LuckPrinter {

    // MARK: - Cycle d'impression

    /**
     * `enablePrinterLuck()` — active le moteur d'impression.
     *
     * Sans cette commande, le firmware acquitte tout et n'execute rien.
     */
    fun enablePrinter(mode: Int = 3): ByteArray =
        byteArrayOf(0x10, 0xff.toByte(), 0xf1.toByte(), mode.toByte())

    /** `printerWakeupLuck()` — reveil, commande distincte du enable. */
    val wakeup: ByteArray = ByteArray(12)

    /** `stopPrintJobLuck()` — clot le travail et declenche l'impression. */
    val stopPrintJob: ByteArray = byteArrayOf(0x10, 0xff.toByte(), 0xf1.toByte(), 0x45)

    /**
     * `printerPositionLuck()` — calage de l'etiquette suivante.
     *
     * A n'utiliser qu'en mode etiquette: sur papier continu, cette commande
     * ne fait que derouler du papier.
     */
    val position: ByteArray = byteArrayOf(0x1d, 0x0c)

    /** `printLineDotsLuck(n)` — avance de n points (1/203 pouce). */
    fun feedDots(dots: Int): ByteArray =
        byteArrayOf(0x1b, 0x4a, (dots and 0xff).toByte())

    /** `printReverseLineDotsLuck(n)` — recul de n points. Non verifiee. */
    fun reverseFeedDots(dots: Int): ByteArray =
        byteArrayOf(0x1f, 0x11, 0x11, (dots and 0xff).toByte())

    /** `adjustPositionAuto(n)` — calage automatique. Non verifiee. */
    fun adjustPositionAuto(value: Int): ByteArray =
        byteArrayOf(0x1f, 0x11, (value and 0xff).toByte())

    // MARK: - Papier

    /**
     * `setPaperType(type, length)` — declare un papier de longueur fixe.
     *
     * L'application officielle utilise `(1, 32)` pour les etiquettes.
     * Ne pas envoyer sur papier continu.
     */
    fun setPaperType(type: Int = 1, length: Int = 32): ByteArray =
        byteArrayOf(0x1f, 0x80.toByte(), type.toByte(), length.toByte())

    /** `printerSetWidth(px)` — largeur d'impression, little-endian. Non verifiee. */
    fun setWidth(pixels: Int): ByteArray =
        byteArrayOf(
            0x10, 0xff.toByte(), 0x15,
            (pixels % 256).toByte(), (pixels / 256).toByte()
        )

    // MARK: - Marques de decoupe

    /** `setMarkPrintFirst()` — premiere etiquette d'une serie. Non verifiee. */
    val markPrintFirst: ByteArray = byteArrayOf(0x1b, 0xbb.toByte(), 0xcc.toByte())

    /** `setMarkPrintLast()` — derniere etiquette d'une serie. Non verifiee. */
    val markPrintLast: ByteArray = byteArrayOf(0x1b, 0xbb.toByte(), 0xbb.toByte())

    /** `setMarkPrintNotLast()` — etiquette intermediaire. Non verifiee. */
    val markPrintNotLast: ByteArray = byteArrayOf(0x1b, 0xbb.toByte(), 0xaa.toByte())

    // MARK: - Reglages

    /** `setDensityLuck(n)` — densite d'impression, 0 clair a 2 fonce. */
    fun setDensity(level: Int): ByteArray =
        byteArrayOf(0x10, 0xff.toByte(), 0x10, 0x00, minOf(level, 2).toByte())

    /** `getDensityLuck()` — lit la densite courante. */
    val getDensity: ByteArray = byteArrayOf(0x10, 0xff.toByte(), 0x11)

    /** `setSpeedLuck(n)` — vitesse d'impression. Non verifiee. */
    fun setSpeed(level: Int): ByteArray =
        byteArrayOf(0x10, 0xff.toByte(), 0xc0.toByte(), level.toByte())

    /** `getSpeedLuck()` — lit la vitesse courante. */
    val getSpeed: ByteArray = byteArrayOf(0x10, 0xff.toByte(), 0x20, 0xa0.toByte())

    /** `setHeatingLevel(n)` — niveau de chauffe de la tete. Non verifiee. */
    fun setHeatingLevel(level: Int): ByteArray =
        byteArrayOf(0x1f, 0x70, 0x01, level.toByte())

    /**
     * `setShutTimeLuck(minutes)` — delai d'extinction automatique.
     *
     * La valeur tient sur deux octets, **gros-boutiste**. A ne pas confondre
     * avec [setWidth] qui est petit-boutiste: le SDK n'est pas coherent entre
     * les deux, et se tromper produit une valeur plausible mais fausse.
     */
    fun setAutoShutdown(minutes: Int): ByteArray =
        byteArrayOf(
            0x10, 0xff.toByte(), 0x12,
            (minutes / 256).toByte(), (minutes % 256).toByte()
        )

    /** `getShutTimeLuck()` — lit le delai d'extinction. */
    val getAutoShutdown: ByteArray = byteArrayOf(0x10, 0xff.toByte(), 0x13)

    /** `setPrinterMode(n)` — mode de fonctionnement. Non verifiee. */
    fun setPrinterMode(mode: Int): ByteArray =
        byteArrayOf(0x10, 0xff.toByte(), 0x30, 0x27, mode.toByte())

    /** `setRecoveryLuck()` — retour aux reglages d'usine. Non verifiee. */
    val factoryReset: ByteArray = byteArrayOf(0x10, 0xff.toByte(), 0x04)

    /** `setPlatform()` — declare la plateforme cliente. Non verifiee. */
    val setPlatform: ByteArray =
        byteArrayOf(0xfc.toByte(), 0xff.toByte(), 0x00, 0x02, 0x45, 0x02, 0x00, 0x46)

    /** `getTimeFormat()` — lit le format d'horodatage. */
    val getTimeFormat: ByteArray = byteArrayOf(0x10, 0xff.toByte(), 0xb0.toByte())

    /**
     * `setTimeFormat(format, date)` — regle l'horloge interne. Non verifiee.
     *
     * Le SDK prefixe la charge utile par `10 FF 53 4A <format>`; envoyer les
     * sept octets de date seuls ne fait rien.
     *
     * L'annee occupe deux octets, puis mois, jour, heure, minute, seconde.
     */
    fun setTimeFormat(
        date: Date = Date(),
        format: Int = 0,
        calendar: Calendar = Calendar.getInstance()
    ): ByteArray {
        calendar.time = date
        val year = calendar.get(Calendar.YEAR)
        return byteArrayOf(0x10, 0xff.toByte(), 0x53, 0x4a, format.toByte()) +
            byteArrayOf(
                (year / 256).toByte(),
                (year % 256).toByte(),
                (calendar.get(Calendar.MONTH) + 1).toByte(),
                calendar.get(Calendar.DAY_OF_MONTH).toByte(),
                calendar.get(Calendar.HOUR_OF_DAY).toByte(),
                calendar.get(Calendar.MINUTE).toByte(),
                calendar.get(Calendar.SECOND).toByte()
            )
    }

    // MARK: - Informations

    /** `printerModelLuck()` — modele. Repond "A2Y" sur cette machine. */
    val model: ByteArray = byteArrayOf(0x10, 0xff.toByte(), 0x20, 0xf0.toByte())

    /** `printerVersionLuck()` — firmware. Repond "V1.06LY" sur cette machine. */
    val firmware: ByteArray = byteArrayOf(0x10, 0xff.toByte(), 0x20, 0xf1.toByte())

    /** `printerSNLuck()` — numero de serie. */
    val serialNumber: ByteArray = byteArrayOf(0x10, 0xff.toByte(), 0x20, 0xf2.toByte())

    /** `getDeviceBoot()` — version du bootloader. */
    val bootloader: ByteArray = byteArrayOf(0x10, 0xff.toByte(), 0x20, 0xef.toByte())

    /** `getBatteryLuck()` — niveau de batterie. */
    val battery: ByteArray = byteArrayOf(0x10, 0xff.toByte(), 0x50, 0xf1.toByte())

    /** `printerStatusLuck()` — etat papier et capot. */
    val status: ByteArray = byteArrayOf(0x10, 0xff.toByte(), 0x40)

    /** `printerSettingLuck()` — reglages courants. Non verifiee. */
    val settings: ByteArray = byteArrayOf(0x10, 0xff.toByte(), 0x70)
}

/**
 * Bits de l'octet de statut renvoye par [LuckPrinter.status].
 *
 * A ne pas confondre avec les trames `01 nn` qui sont des credits de flux,
 * pas des statuts.
 */
data class PrinterStatus(val raw: Int) {
    val isPrinting: Boolean get() = raw and 0x01 != 0
    val isCoverOpen: Boolean get() = raw and 0x02 != 0
    val isPaperEmpty: Boolean get() = raw and 0x04 != 0
    val isBatteryLow: Boolean get() = raw and 0x08 != 0
    val isCharging: Boolean get() = raw and 0x20 != 0
    val isOverheating: Boolean get() = raw and 0x50 != 0

    /** Etats qui empechent reellement d'imprimer. */
    val isBlocking: Boolean get() = isCoverOpen || isPaperEmpty || isOverheating

    val description: String
        get() {
            val parts = mutableListOf<String>()
            if (isPrinting) parts.add("impression en cours")
            if (isCoverOpen) parts.add("capot ouvert")
            if (isPaperEmpty) parts.add("papier absent")
            if (isBatteryLow) parts.add("batterie faible")
            if (isCharging) parts.add("en charge")
            if (isOverheating) parts.add("surchauffe")
            if (parts.isEmpty()) parts.add("pret")
            return parts.joinToString(", ")
        }
}
