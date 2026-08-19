import Foundation

/// Portage Swift du jeu de commandes du LuckPrinter SDK.
///
/// Les octets proviennent de la decompilation de l'application officielle
/// `com.printer.lidloffice` (classe `BaseNormalDevice` et ses sous-classes).
/// Chaque commande porte le nom de la methode Java d'origine pour faciliter
/// les recoupements.
///
/// Toutes les commandes ne sont pas forcement supportees par le firmware
/// A2Y / V1.06LY: le SDK est commun a plus d'une centaine de modeles.
/// Celles marquees « non verifiee » n'ont pas ete testees sur cette machine.
public enum LuckPrinter {

    // MARK: - Cycle d'impression

    /// `enablePrinterLuck()` — active le moteur d'impression.
    ///
    /// Sans cette commande, le firmware acquitte tout et n'execute rien.
    public static func enablePrinter(mode: UInt8 = 3) -> [UInt8] {
        [0x10, 0xff, 0xf1, mode]
    }

    /// `printerWakeupLuck()` — reveil, commande distincte du enable.
    public static let wakeup = [UInt8](repeating: 0x00, count: 12)

    /// `stopPrintJobLuck()` — clot le travail et declenche l'impression.
    public static let stopPrintJob: [UInt8] = [0x10, 0xff, 0xf1, 0x45]

    /// `printerPositionLuck()` — calage de l'etiquette suivante.
    ///
    /// A n'utiliser qu'en mode etiquette: sur papier continu, cette commande
    /// ne fait que derouler du papier.
    public static let position: [UInt8] = [0x1d, 0x0c]

    /// `printLineDotsLuck(n)` — avance de n points (1/203 pouce).
    public static func feedDots(_ dots: UInt8) -> [UInt8] {
        [0x1b, 0x4a, dots]
    }

    /// `printReverseLineDotsLuck(n)` — recul de n points. Non verifiee.
    public static func reverseFeedDots(_ dots: UInt8) -> [UInt8] {
        [0x1f, 0x11, 0x11, dots]
    }

    /// `adjustPositionAuto(n)` — calage automatique. Non verifiee.
    public static func adjustPositionAuto(_ value: UInt8) -> [UInt8] {
        [0x1f, 0x11, value]
    }

    // MARK: - Papier

    /// `setPaperType(type, length)` — declare un papier de longueur fixe.
    ///
    /// L'application officielle utilise `(1, 32)` pour les etiquettes.
    /// Ne pas envoyer sur papier continu.
    public static func setPaperType(type: UInt8 = 1, length: UInt8 = 32) -> [UInt8] {
        [0x1f, 0x80, type, length]
    }

    /// `printerSetWidth(px)` — largeur d'impression, little-endian. Non verifiee.
    public static func setWidth(pixels: Int) -> [UInt8] {
        [0x10, 0xff, 0x15, UInt8(pixels % 256), UInt8(pixels / 256)]
    }

    // MARK: - Marques de decoupe

    /// `setMarkPrintFirst()` — premiere etiquette d'une serie. Non verifiee.
    public static let markPrintFirst: [UInt8] = [0x1b, 0xbb, 0xcc]

    /// `setMarkPrintLast()` — derniere etiquette d'une serie. Non verifiee.
    public static let markPrintLast: [UInt8] = [0x1b, 0xbb, 0xbb]

    /// `setMarkPrintNotLast()` — etiquette intermediaire. Non verifiee.
    public static let markPrintNotLast: [UInt8] = [0x1b, 0xbb, 0xaa]

    // MARK: - Reglages

    /// `setDensityLuck(n)` — densite d'impression, 0 clair a 2 fonce.
    public static func setDensity(_ level: UInt8) -> [UInt8] {
        [0x10, 0xff, 0x10, 0x00, min(level, 2)]
    }

    /// `getDensityLuck()` — lit la densite courante.
    public static let getDensity: [UInt8] = [0x10, 0xff, 0x11]

    /// `setSpeedLuck(n)` — vitesse d'impression. Non verifiee.
    public static func setSpeed(_ level: UInt8) -> [UInt8] {
        [0x10, 0xff, 0xc0, level]
    }

    /// `getSpeedLuck()` — lit la vitesse courante.
    public static let getSpeed: [UInt8] = [0x10, 0xff, 0x20, 0xa0]

    /// `setHeatingLevel(n)` — niveau de chauffe de la tete. Non verifiee.
    public static func setHeatingLevel(_ level: UInt8) -> [UInt8] {
        [0x1f, 0x70, 0x01, level]
    }

    /// `setShutTimeLuck(minutes)` — delai d'extinction automatique.
    ///
    /// La valeur tient sur deux octets, gros-boutiste.
    public static func setAutoShutdown(minutes: Int) -> [UInt8] {
        [0x10, 0xff, 0x12, UInt8(minutes / 256), UInt8(minutes % 256)]
    }

    /// `getShutTimeLuck()` — lit le delai d'extinction.
    public static let getAutoShutdown: [UInt8] = [0x10, 0xff, 0x13]

    /// `setPrinterMode(n)` — mode de fonctionnement. Non verifiee.
    public static func setPrinterMode(_ mode: UInt8) -> [UInt8] {
        [0x10, 0xff, 0x30, 0x27, mode]
    }

    /// `setRecoveryLuck()` — retour aux reglages d'usine. Non verifiee.
    public static let factoryReset: [UInt8] = [0x10, 0xff, 0x04]

    /// `setPlatform()` — declare la plateforme cliente. Non verifiee.
    public static let setPlatform: [UInt8] = [0xfc, 0xff, 0x00, 0x02, 0x45, 0x02, 0x00, 0x46]

    /// `getTimeFormat()` — lit le format d'horodatage.
    public static let getTimeFormat: [UInt8] = [0x10, 0xff, 0xb0]

    /// `setTimeFormat(format, date)` — regle l'horloge interne. Non verifiee.
    ///
    /// Le SDK prefixe la charge utile par `10 FF 53 4A <format>`; la version
    /// precedente de ce portage n'envoyait que les octets de date, sans
    /// l'en-tete, et n'aurait donc pas ete comprise.
    ///
    /// L'annee occupe deux octets, puis mois, jour, heure, minute, seconde.
    public static func setTimeFormat(
        _ date: Date,
        format: UInt8 = 0,
        calendar: Calendar = .current
    ) -> [UInt8] {
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        return [0x10, 0xff, 0x53, 0x4a, format] + [
            UInt8((parts.year ?? 2000) / 256),
            UInt8((parts.year ?? 2000) % 256),
            UInt8(parts.month ?? 1),
            UInt8(parts.day ?? 1),
            UInt8(parts.hour ?? 0),
            UInt8(parts.minute ?? 0),
            UInt8(parts.second ?? 0)
        ]
    }

    // MARK: - Informations

    /// `printerModelLuck()` — modele. Repond "A2Y" sur cette machine.
    public static let model: [UInt8] = [0x10, 0xff, 0x20, 0xf0]

    /// `printerVersionLuck()` — firmware. Repond "V1.06LY" sur cette machine.
    public static let firmware: [UInt8] = [0x10, 0xff, 0x20, 0xf1]

    /// `printerSNLuck()` — numero de serie.
    public static let serialNumber: [UInt8] = [0x10, 0xff, 0x20, 0xf2]

    /// `getDeviceBoot()` — version du bootloader.
    public static let bootloader: [UInt8] = [0x10, 0xff, 0x20, 0xef]

    /// `getBatteryLuck()` — niveau de batterie.
    public static let battery: [UInt8] = [0x10, 0xff, 0x50, 0xf1]

    /// `printerStatusLuck()` — etat papier et capot.
    public static let status: [UInt8] = [0x10, 0xff, 0x40]

    /// `printerSettingLuck()` — reglages courants. Non verifiee.
    public static let settings: [UInt8] = [0x10, 0xff, 0x70]
}

/// Bits de l'octet de statut renvoye par `LuckPrinter.status`.
///
/// Signification issue de la documentation de retro-ingenierie publique de
/// cette famille d'imprimantes. A ne pas confondre avec les trames `01 nn`
/// qui sont des credits de flux, pas des statuts.
public struct PrinterStatus: Equatable {
    public let raw: UInt8

    public init(raw: UInt8) {
        self.raw = raw
    }

    public var isPrinting: Bool { raw & 0x01 != 0 }
    public var isCoverOpen: Bool { raw & 0x02 != 0 }
    public var isPaperEmpty: Bool { raw & 0x04 != 0 }
    public var isBatteryLow: Bool { raw & 0x08 != 0 }
    public var isCharging: Bool { raw & 0x20 != 0 }
    public var isOverheating: Bool { raw & 0x50 != 0 }

    /// Etats qui empechent reellement d'imprimer.
    public var isBlocking: Bool {
        isCoverOpen || isPaperEmpty || isOverheating
    }

    public var description: String {
        var parts: [String] = []
        if isPrinting { parts.append("impression en cours") }
        if isCoverOpen { parts.append("capot ouvert") }
        if isPaperEmpty { parts.append("papier absent") }
        if isBatteryLow { parts.append("batterie faible") }
        if isCharging { parts.append("en charge") }
        if isOverheating { parts.append("surchauffe") }
        if parts.isEmpty { parts.append("pret") }
        return parts.joined(separator: ", ")
    }
}
