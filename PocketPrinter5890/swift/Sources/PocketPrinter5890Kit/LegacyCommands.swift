import Foundation

public enum PrintDensity: UInt8, CaseIterable, Identifiable {
    case light = 0
    case medium = 1
    case strong = 2

    public var id: UInt8 { rawValue }

    public var title: String {
        switch self {
        case .light: return "Faible"
        case .medium: return "Moyenne"
        case .strong: return "Forte"
        }
    }
}

public enum FormFeedMode: Equatable {
    case documentedPocketPrinter
    case standard

    public var bytes: [UInt8] {
        switch self {
        case .documentedPocketPrinter:
            return [0x10, 0x0c]
        case .standard:
            return [0x0c]
        }
    }

    public var title: String {
        switch self {
        case .documentedPocketPrinter:
            return "10 0C observe"
        case .standard:
            return "0C standard"
        }
    }
}

public enum PrinterCommand {
    public static let model: [UInt8] = [0x10, 0xff, 0x20, 0xf0]
    public static let firmware: [UInt8] = [0x10, 0xff, 0x20, 0xf1]
    public static let serialNumber: [UInt8] = [0x10, 0xff, 0x20, 0xf2]
    public static let battery: [UInt8] = [0x10, 0xff, 0x50, 0xf1]
    public static let paperStatus: [UInt8] = [0x10, 0xff, 0x40]
    public static let experimentalPrePrintF103: [UInt8] = [0x10, 0xff, 0xf1, 0x03] + Array(repeating: 0x00, count: 12)
    public static let experimentalPrePrintF130: [UInt8] = [0x10, 0xff, 0xf1, 0x30] + Array(repeating: 0x00, count: 12)
    public static let experimentalPostPrint: [UInt8] = [0x10, 0xff, 0xf1, 0x45]

    public static func setDensity(_ density: PrintDensity) -> [UInt8] {
        [0x10, 0xff, 0x10, 0x00, density.rawValue]
    }

    /// Extinction automatique.
    ///
    /// Le SDK officiel encode la valeur sur deux octets gros-boutistes
    /// (`setShutTimeLuck`): la version precedente n'en envoyait qu'un,
    /// ce qui plafonnait le delai a 255 minutes et decalait l'octet de poids
    /// fort. Preferer `LuckPrinter.setAutoShutdown(minutes:)`.
    public static func autoShutdown(minutes: Int) -> [UInt8] {
        LuckPrinter.setAutoShutdown(minutes: minutes)
    }

    public static func feedDots(_ dots: UInt8 = 0x28) -> [UInt8] {
        [0x1b, 0x4a, dots]
    }

    // MARK: - Sequence officielle LuckPrinter

    /// Commandes extraites de l'application officielle Pocket Printer
    /// (`com.printer.lidloffice`, LuckPrinter SDK), classe
    /// `DP_D1.printTagOnce` dont herite `MiniPocketPrinter` — la classe
    /// associee au nom BLE "Mini Pocket Printer" de cette machine.
    ///
    /// Sans cette sequence, le firmware acquitte chaque commande par `01 01`
    /// mais n'execute rien: ni impression, ni meme avance papier.
    public enum Luck {
        /// `enablePrinterLuck()` — active le moteur. Mode 3 par defaut.
        public static func enablePrinter(mode: UInt8 = 3) -> [UInt8] {
            [0x10, 0xff, 0xf1, mode]
        }

        /// `printerWakeupLuck()` — reveil. C'est une commande **distincte**
        /// du enable, contrairement a ce qu'indiquent certaines
        /// documentations publiques qui collent les 12 zeros a `10 FF F1 03`.
        public static let wakeup = [UInt8](repeating: 0x00, count: 12)

        /// `setPaperType(type, length)` — `1F 80 <type> <length>`.
        /// L'application utilise `(1, 32)` pour le papier continu.
        public static func setPaperType(type: UInt8 = 1, length: UInt8 = 32) -> [UInt8] {
            [0x1f, 0x80, type, length]
        }

        /// `printerPositionLuck()` — calage de fin de page.
        public static let position: [UInt8] = [0x1d, 0x0c]

        /// `stopPrintJobLuck()` — clot le travail et declenche l'impression.
        public static let stopPrintJob: [UInt8] = [0x10, 0xff, 0xf1, 0x45]
    }
}
