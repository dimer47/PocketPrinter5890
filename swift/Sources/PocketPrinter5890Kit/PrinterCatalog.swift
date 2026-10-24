import Foundation

// Catalogue des imprimantes que l'application sait piloter.
//
// Le choix de l'imprimante vient avant celui du papier: une pocket 5890
// n'accepte qu'un rouleau ticket de 58 mm, une Brother TD-4550DNWB des
// rouleaux et des etiquettes jusqu'a 4 pouces, une QL des rouleaux DK a
// reference fixe. Les listes de papier ci-dessous dependent donc toujours
// d'une imprimante.
//
// Ce fichier n'a aucune dependance au SDK Brother: il decrit les modeles et
// leurs capacites. Le pilotage reel (BRLMPrinterKit) vit dans l'application
// iOS, parce que le SDK est un binaire proprietaire que ce depot ne
// redistribue pas.

/// Famille d'imprimante, choisie en premier dans l'application.
public enum PrinterBrand: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Imprimante de poche Lidl (SilverCrest, Tronic, Parkside), modele 5890.
    case pocket5890
    /// Imprimantes Brother pilotees par le Brother Print SDK.
    case brother

    public var id: String { rawValue }
}

// MARK: - Brother

/// Serie Brother. Elle determine la classe de reglages du SDK et le type de
/// papier accepte.
public enum BrotherSeries: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Etiquettes et tickets, papier personnalise (`BRLMTDPrintSettings`).
    case td
    /// Mobiles ticket et etiquettes, papier personnalise (`BRLMRJPrintSettings`).
    case rj
    /// Etiquettes DK a references fixes (`BRLMQLPrintSettings`).
    case ql
    /// Rubans P-touch TZe/HSe (`BRLMPTPrintSettings`).
    case pt
    /// Mobiles A4/Letter (`BRLMPJPrintSettings`).
    case pj
    /// Mobiles A6/A7 (`BRLMMWPrintSettings`).
    case mw

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .td: return "TD"
        case .rj: return "RJ"
        case .ql: return "QL"
        case .pt: return "PT (P-touch)"
        case .pj: return "PJ"
        case .mw: return "MW"
        }
    }

    /// Origine de la liste des papiers proposes pour cette serie.
    public var paperSource: BrotherPaperSource {
        switch self {
        case .td, .rj: return .customPaper
        case .ql: return .qlLabel
        case .pt: return .ptTape
        case .pj: return .pjSheet
        case .mw: return .fixedByModel
        }
    }

    /// Ce que dit le SDK et le materiel de la coupe.
    ///
    /// Seules les series TD, QL et PT exposent `autoCut` dans le SDK. Sur
    /// les TD, le massicot est un accessoire: l'option ne sert a rien s'il
    /// n'est pas installe sur l'imprimante.
    public var cutter: BrotherCutterSupport {
        switch self {
        case .td: return .optionalUnit
        case .ql: return .builtIn
        case .pt: return .modelDependent
        case .rj, .pj, .mw: return .none
        }
    }
}

public enum BrotherCutterSupport: String, Codable, Sendable {
    /// Pas de coupe pilotable par le SDK pour cette serie.
    case none
    /// Massicot integre.
    case builtIn
    /// Massicot vendu en option (TD): a installer sur l'imprimante.
    case optionalUnit
    /// Selon le modele: certaines P-touch n'ont qu'une coupe manuelle.
    case modelDependent

    public var isControllable: Bool { self != .none }

    /// La coupe en fin de travail (`cutAtEnd`) n'existe que sur TD et QL.
    public var supportsCutAtEnd: Bool { self == .optionalUnit || self == .builtIn }
}

/// Interface de communication utilisable depuis iOS.
public enum BrotherConnection: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Bluetooth Low Energy: recherche par nom local annonce.
    case ble
    /// Wi-Fi: recherche sur le reseau local, ou adresse IP.
    case wifi
    /// Bluetooth Classic MFi: exige le framework `BT_Net`, un Product Plan ID
    /// Brother pour l'App Store et `UISupportedExternalAccessoryProtocols`.
    case bluetoothClassic

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .ble: return "Bluetooth LE"
        case .wifi: return "Wi-Fi"
        case .bluetoothClassic: return "Bluetooth Classic (MFi)"
        }
    }
}

/// Modeles de l'enumeration `BRLMPrinterModel` du Brother Print SDK iOS 4.13.
///
/// Le nom des cas reprend celui du SDK pour que la correspondance reste
/// evidente; la valeur brute est la reference commerciale.
public enum BrotherModel: String, CaseIterable, Identifiable, Codable, Sendable {
    // swiftlint:disable identifier_name
    case PJ_673 = "PJ-673"
    case PJ_763MFi = "PJ-763MFi"
    case PJ_773 = "PJ-773"
    case PJ_822 = "PJ-822"
    case PJ_823 = "PJ-823"
    case PJ_862 = "PJ-862"
    case PJ_863 = "PJ-863"
    case PJ_883 = "PJ-883"
    case MW_145MFi = "MW-145MFi"
    case MW_260MFi = "MW-260MFi"
    case MW_170 = "MW-170"
    case MW_270 = "MW-270"
    case RJ_2031 = "RJ-2031"
    case RJ_2050 = "RJ-2050"
    case RJ_2131 = "RJ-2131"
    case RJ_2140 = "RJ-2140"
    case RJ_2150 = "RJ-2150"
    case RJ_3050 = "RJ-3050"
    case RJ_3050Ai = "RJ-3050Ai"
    case RJ_3150 = "RJ-3150"
    case RJ_3150Ai = "RJ-3150Ai"
    case RJ_3230B = "RJ-3230B"
    case RJ_3235B = "RJ-3235B"
    case RJ_3250WB = "RJ-3250WB"
    case RJ_3255WB = "RJ-3255WB"
    case RJ_4030Ai = "RJ-4030Ai"
    case RJ_4040 = "RJ-4040"
    case RJ_4230B = "RJ-4230B"
    case RJ_4235B = "RJ-4235B"
    case RJ_4250WB = "RJ-4250WB"
    case RJ_4255WB = "RJ-4255WB"
    case TD_2030A = "TD-2030A"
    case TD_2120N = "TD-2120N"
    case TD_2125N = "TD-2125N"
    case TD_2125NWB = "TD-2125NWB"
    case TD_2130N = "TD-2130N"
    case TD_2135N = "TD-2135N"
    case TD_2135NWB = "TD-2135NWB"
    case TD_2310D_203 = "TD-2310D_203"
    case TD_2310D_300 = "TD-2310D_300"
    case TD_2320D_203 = "TD-2320D_203"
    case TD_2320D_300 = "TD-2320D_300"
    case TD_2320DF_203 = "TD-2320DF_203"
    case TD_2320DF_300 = "TD-2320DF_300"
    case TD_2320DSA_203 = "TD-2320DSA_203"
    case TD_2320DSA_300 = "TD-2320DSA_300"
    case TD_2350D_203 = "TD-2350D_203"
    case TD_2350D_300 = "TD-2350D_300"
    case TD_2350DF_203 = "TD-2350DF_203"
    case TD_2350DF_300 = "TD-2350DF_300"
    case TD_2350DSA_203 = "TD-2350DSA_203"
    case TD_2350DSA_300 = "TD-2350DSA_300"
    case TD_2350DFSA_203 = "TD-2350DFSA_203"
    case TD_2350DFSA_300 = "TD-2350DFSA_300"
    case TD_4100N = "TD-4100N"
    case TD_4415D = "TD-4415D"
    case TD_4420DN = "TD-4420DN"
    case TD_4425DN = "TD-4425DN"
    case TD_4425DNF = "TD-4425DNF"
    case TD_4455DNWB = "TD-4455DNWB"
    case TD_4520DN = "TD-4520DN"
    case TD_4525DN = "TD-4525DN"
    case TD_4550DNWB = "TD-4550DNWB"
    case TD_4555DNWB = "TD-4555DNWB"
    case TD_4555DNWBF = "TD-4555DNWBF"
    case QL_710W = "QL-710W"
    case QL_720NW = "QL-720NW"
    case QL_810W = "QL-810W"
    case QL_820NWB = "QL-820NWB"
    case QL_1110NWB = "QL-1110NWB"
    case QL_1115NWB = "QL-1115NWB"
    case PT_D410 = "PT-D410"
    case PT_D460BT = "PT-D460BT"
    case PT_D610BT = "PT-D610BT"
    case PT_D800W = "PT-D800W"
    case PT_E310BT = "PT-E310BT"
    case PT_E510 = "PT-E510"
    case PT_E550W = "PT-E550W"
    case PT_E560BT = "PT-E560BT"
    case PT_E720BT = "PT-E720BT"
    case PT_E800W = "PT-E800W"
    case PT_E850TKW = "PT-E850TKW"
    case PT_E920BT = "PT-E920BT"
    case PT_N25BT = "PT-N25BT"
    case PT_P300BT = "PT-P300BT"
    case PT_P300BTz = "PT-P300BTz"
    case PT_P710BT = "PT-P710BT"
    case PT_P715eBT = "PT-P715eBT"
    case PT_P750W = "PT-P750W"
    case PT_P750Wc = "PT-P750Wc"
    case PT_P900W = "PT-P900W"
    case PT_P910BT = "PT-P910BT"
    case PT_P950NW = "PT-P950NW"
    // swiftlint:enable identifier_name

    /// Modele propose par defaut quand on choisit Brother.
    public static let defaultModel = BrotherModel.TD_4550DNWB

    public var id: String { rawValue }

    /// Reference lisible. La resolution des TD-23xx est mise en evidence.
    public var title: String {
        rawValue
            .replacingOccurrences(of: "_203", with: " (203 dpi)")
            .replacingOccurrences(of: "_300", with: " (300 dpi)")
    }

    public var series: BrotherSeries {
        switch rawValue.prefix(2) {
        case "PJ": return .pj
        case "MW": return .mw
        case "RJ": return .rj
        case "TD": return .td
        case "QL": return .ql
        default: return .pt
        }
    }

    /// Interfaces utilisables depuis iOS pour imprimer une image.
    ///
    /// Source: tableau « Supported Printer / Print Image/PDF » du manuel du
    /// SDK 4.13. Les coches marquees « Android only » en sont exclues, ce
    /// qui retire par exemple le Bluetooth des RJ-3050/3150 et le Wi-Fi du
    /// TD-4100N. Un ensemble vide signifie que le manuel ne documente
    /// aucune interface iOS pour ce modele (USB seul, ou modele absent du
    /// tableau).
    ///
    /// Les TD-4410D, TD-4420DN et TD-4520DN n'ont pas de BLE. Seuls les
    /// modeles a suffixe « WB » des series TD-4 et TD-2, les TD-2350 et les
    /// RJ/PJ recents le proposent.
    public var connections: Set<BrotherConnection> {
        switch self {
        case .PJ_673, .PJ_773, .RJ_4040, .RJ_3050, .RJ_3150, .RJ_2140,
             .TD_2120N, .TD_2130N, .TD_4420DN, .TD_4520DN,
             .QL_710W, .QL_720NW, .QL_810W,
             .PT_E550W, .PT_P750W, .PT_P750Wc, .PT_D800W, .PT_E800W,
             .PT_E850TKW, .PT_P900W, .PT_P950NW,
             .TD_2125N, .TD_2135N,
             .TD_2320D_203, .TD_2320D_300, .TD_2320DF_203, .TD_2320DF_300,
             .TD_2320DSA_203, .TD_2320DSA_300,
             .TD_4425DN, .TD_4525DN, .TD_4425DNF:
            return [.wifi]
        case .PJ_763MFi, .MW_145MFi, .MW_260MFi, .MW_170, .MW_270,
             .RJ_4030Ai, .PT_E310BT, .PT_E560BT, .PT_E720BT, .PT_E920BT,
             .RJ_2031, .RJ_2131:
            return [.bluetoothClassic]
        case .RJ_3050Ai, .RJ_3150Ai, .RJ_2050, .RJ_2150,
             .QL_820NWB, .QL_1110NWB, .QL_1115NWB:
            return [.wifi, .bluetoothClassic]
        case .RJ_4230B, .RJ_3230B, .RJ_3235B, .RJ_4235B, .PJ_862, .PJ_863:
            return [.bluetoothClassic, .ble]
        case .RJ_4250WB, .RJ_3250WB, .RJ_3255WB, .RJ_4255WB, .PJ_883,
             .TD_4550DNWB, .TD_4455DNWB, .TD_4555DNWB, .TD_4555DNWBF,
             .TD_2125NWB, .TD_2135NWB,
             .TD_2350D_203, .TD_2350D_300, .TD_2350DF_203, .TD_2350DF_300,
             .TD_2350DSA_203, .TD_2350DSA_300, .TD_2350DFSA_203, .TD_2350DFSA_300:
            return [.wifi, .bluetoothClassic, .ble]
        case .PJ_822, .PJ_823, .TD_2030A, .TD_4100N, .TD_4415D,
             .TD_2310D_203, .TD_2310D_300, .PT_E510, .PT_P910BT,
             .PT_D410, .PT_D460BT, .PT_D610BT, .PT_N25BT,
             .PT_P300BT, .PT_P300BTz, .PT_P710BT, .PT_P715eBT:
            return []
        }
    }

    public var supportsBLE: Bool { connections.contains(.ble) }

    /// Interfaces que cette application sait utiliser pour ce modele.
    ///
    /// Le Bluetooth Classic MFi n'est pas implemente: il impose un
    /// framework different et une procedure d'agrement Brother.
    public var appConnections: [BrotherConnection] {
        [.ble, .wifi].filter { connections.contains($0) }
    }

    /// Nom de modele tel que le SDK le renvoie dans
    /// `BRLMChannelExtraInfoKeyModelName`, par exemple « Brother TD-4550DNWB ».
    /// La resolution des TD-23xx n'y figure pas.
    public var advertisedName: String {
        "Brother " + rawValue
            .replacingOccurrences(of: "_203", with: "")
            .replacingOccurrences(of: "_300", with: "")
    }

    /// Retrouve le modele d'apres le nom renvoye par la recherche.
    ///
    /// Le nom le plus long l'emporte: « TD-4555DNWBF » ne doit pas etre pris
    /// pour un « TD-4555DNWB ». Les TD-23xx existent en 203 et 300 dpi sous
    /// le meme nom; on renvoie alors la variante 203 dpi, que l'utilisateur
    /// peut corriger.
    public static func matching(advertisedName name: String) -> BrotherModel? {
        let lowered = name.lowercased()
        return allCases
            .filter { lowered.contains($0.advertisedName.dropFirst("Brother ".count).lowercased()) }
            .max { lhs, rhs in
                let lhsLength = lhs.advertisedName.count
                let rhsLength = rhs.advertisedName.count
                if lhsLength != rhsLength { return lhsLength < rhsLength }
                // A longueur egale (variantes 203/300), preferer 203 dpi.
                return lhs.rawValue.hasSuffix("_203") == false && rhs.rawValue.hasSuffix("_203")
            }
    }

    /// Papiers proposes pour ce modele quand la serie accepte un papier
    /// personnalise (TD, RJ). Vide pour les autres series, dont la liste
    /// vient du SDK (QL, PT) ou d'un format normalise (PJ, MW).
    public var paperPresets: [BrotherPaper] {
        guard series.paperSource == .customPaper else { return [] }
        let family = String(rawValue.prefix(4))
        switch family {
        case "TD-4":
            return [
                .roll(widthMM: 102),
                .roll(widthMM: 76),
                .roll(widthMM: 58),
                .dieCut(widthMM: 102, lengthMM: 152),
                .dieCut(widthMM: 102, lengthMM: 51),
                .dieCut(widthMM: 51, lengthMM: 26),
                .markRoll(widthMM: 102, lengthMM: 152)
            ]
        case "TD-2":
            return [
                .roll(widthMM: 58),
                .roll(widthMM: 51),
                .dieCut(widthMM: 40, lengthMM: 40),
                .dieCut(widthMM: 51, lengthMM: 26),
                .markRoll(widthMM: 58, lengthMM: 40)
            ]
        case "RJ-4":
            return [
                .roll(widthMM: 102),
                .roll(widthMM: 58),
                .dieCut(widthMM: 102, lengthMM: 152),
                .markRoll(widthMM: 102, lengthMM: 152)
            ]
        case "RJ-3":
            return [
                .roll(widthMM: 80),
                .roll(widthMM: 76),
                .dieCut(widthMM: 76, lengthMM: 44),
                .markRoll(widthMM: 76, lengthMM: 44)
            ]
        default: // RJ-2
            return [
                .roll(widthMM: 58),
                .roll(widthMM: 50),
                .dieCut(widthMM: 50, lengthMM: 85),
                .markRoll(widthMM: 58, lengthMM: 85)
            ]
        }
    }

    /// Largeur maximale de papier acceptee, en millimetres, pour borner la
    /// saisie d'un papier personnalise.
    public var maxPaperWidthMM: Double {
        switch String(rawValue.prefix(4)) {
        case "TD-4", "RJ-4": return 118
        case "RJ-3": return 80
        default: return 63
        }
    }
}

// MARK: - Papier

/// Origine de la liste des papiers d'une serie Brother.
public enum BrotherPaperSource: String, Codable, Sendable {
    /// Largeur et longueur libres (`BRLMCustomPaperSize`): TD, RJ.
    case customPaper
    /// References DK de `BRLMQLPrintSettingsLabelSize`.
    case qlLabel
    /// Largeurs de ruban de `BRLMPTPrintSettingsLabelSize`.
    case ptTape
    /// Formats de `BRLMPJPrintSettingsPaperSizeStandard`.
    case pjSheet
    /// Le format est impose par le modele (MW).
    case fixedByModel
}

/// Papier personnalise pour les series TD et RJ.
public struct BrotherPaper: Hashable, Codable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        /// Rouleau continu: la longueur suit le contenu.
        case roll
        /// Etiquettes predecoupees, separees par un espace que le capteur
        /// de l'imprimante detecte.
        case dieCut
        /// Rouleau a marque noire: chaque etiquette, de longueur fixe, est
        /// reperee par une marque noire imprimee au dos du papier.
        case markRoll

        /// Vrai si le papier a une longueur d'etiquette fixe.
        public var hasFixedLength: Bool { self != .roll }
    }

    public var kind: Kind
    public var widthMM: Double
    /// Longueur d'une etiquette, ignoree pour un rouleau continu.
    public var lengthMM: Double
    /// Espace entre deux etiquettes, utilise seulement en `dieCut`.
    public var gapMM: Double
    /// Marge appliquee sur les quatre cotes.
    public var marginMM: Double
    /// Decalage vertical de la marque noire par rapport au debut de
    /// l'etiquette (`markPosition` dans le SDK). Utilise en `markRoll`.
    public var markOffsetMM: Double
    /// Hauteur de la marque noire (`markHeight` dans le SDK). Utilise en
    /// `markRoll`.
    public var markLengthMM: Double

    public init(
        kind: Kind,
        widthMM: Double,
        lengthMM: Double = 0,
        gapMM: Double = 0,
        marginMM: Double = 1.5,
        markOffsetMM: Double = 0,
        markLengthMM: Double = 0
    ) {
        self.kind = kind
        self.widthMM = widthMM
        self.lengthMM = lengthMM
        self.gapMM = gapMM
        self.marginMM = marginMM
        self.markOffsetMM = markOffsetMM
        self.markLengthMM = markLengthMM
    }

    private enum CodingKeys: String, CodingKey {
        case kind, widthMM, lengthMM, gapMM, marginMM, markOffsetMM, markLengthMM
    }

    /// Les papiers enregistres avant l'ajout de la marque noire n'ont pas
    /// les champs `mark*`: ils restent lisibles.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        widthMM = try container.decode(Double.self, forKey: .widthMM)
        lengthMM = try container.decodeIfPresent(Double.self, forKey: .lengthMM) ?? 0
        gapMM = try container.decodeIfPresent(Double.self, forKey: .gapMM) ?? 0
        marginMM = try container.decodeIfPresent(Double.self, forKey: .marginMM) ?? 1.5
        markOffsetMM = try container.decodeIfPresent(Double.self, forKey: .markOffsetMM) ?? 0
        markLengthMM = try container.decodeIfPresent(Double.self, forKey: .markLengthMM) ?? 0
    }

    public static func roll(widthMM: Double) -> BrotherPaper {
        BrotherPaper(kind: .roll, widthMM: widthMM)
    }

    /// Les etiquettes du commerce laissent en general 3 mm entre elles.
    public static func dieCut(widthMM: Double, lengthMM: Double, gapMM: Double = 3) -> BrotherPaper {
        BrotherPaper(kind: .dieCut, widthMM: widthMM, lengthMM: lengthMM, gapMM: gapMM)
    }

    /// Valeurs de depart pour la marque: au debut de l'etiquette, 3 mm de
    /// haut. A ajuster selon le rouleau.
    public static func markRoll(
        widthMM: Double,
        lengthMM: Double,
        markOffsetMM: Double = 0,
        markLengthMM: Double = 3
    ) -> BrotherPaper {
        BrotherPaper(kind: .markRoll, widthMM: widthMM, lengthMM: lengthMM,
                     markOffsetMM: markOffsetMM, markLengthMM: markLengthMM)
    }

    public var id: String {
        switch kind {
        case .roll: return "roll-\(Self.format(widthMM))"
        case .dieCut: return "diecut-\(Self.format(widthMM))x\(Self.format(lengthMM))-gap\(Self.format(gapMM))"
        case .markRoll:
            return "mark-\(Self.format(widthMM))x\(Self.format(lengthMM))"
                + "-at\(Self.format(markOffsetMM))-h\(Self.format(markLengthMM))"
        }
    }

    /// Largeur imprimable, marges deduites.
    public var printableWidthMM: Double { max(1, widthMM - marginMM * 2) }

    static func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

/// Feuille normalisee des PJ.
public enum BrotherSheet: String, CaseIterable, Identifiable, Codable, Sendable {
    case a4, letter, legal, a5

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .a4: return "A4"
        case .letter: return "Letter"
        case .legal: return "Legal"
        case .a5: return "A5"
        }
    }

    public var widthMM: Double {
        switch self {
        case .a4: return 210
        case .letter, .legal: return 215.9
        case .a5: return 148
        }
    }
}

/// Etiquette ou ruban d'une liste du SDK (QL, PT).
///
/// `index` est la valeur brute de l'enumeration du SDK: les cas y sont
/// declares sans valeur explicite, donc numerotes a partir de 0 dans
/// l'ordre de ce tableau. Garder l'ordre identique a l'en-tete.
public struct BrotherLabelSize: Hashable, Sendable, Identifiable {
    public let index: Int
    /// Nom du cas dans l'en-tete du SDK, sans prefixe.
    public let name: String
    public let widthMM: Double
    /// Longueur d'une etiquette predecoupee, nil pour un rouleau continu.
    public let lengthMM: Double?

    public var id: Int { index }

    /// Ordre de `BRLMQLPrintSettingsLabelSize` (BRLMQLPrintSettings.h).
    public static let ql: [BrotherLabelSize] = make([
        ("DieCutW17H54", 17, 54), ("DieCutW17H87", 17, 87), ("DieCutW23H23", 23, 23),
        ("DieCutW29H42", 29, 42), ("DieCutW29H90", 29, 90), ("DieCutW38H90", 38, 90),
        ("DieCutW39H48", 39, 48), ("DieCutW52H29", 52, 29), ("DieCutW62H29", 62, 29),
        ("DieCutW62H60", 62, 60), ("DieCutW62H75", 62, 75), ("DieCutW62H100", 62, 100),
        ("DieCutW60H86", 60, 86), ("DieCutW54H29", 54, 29), ("DieCutW102H51", 102, 51),
        ("DieCutW102H152", 102, 152), ("DieCutW103H164", 103, 164),
        ("RollW12", 12, nil), ("RollW29", 29, nil), ("RollW38", 38, nil), ("RollW50", 50, nil),
        ("RollW54", 54, nil), ("RollW62", 62, nil), ("RollW62RB", 62, nil), ("RollW102", 102, nil),
        ("RollW103", 103, nil), ("DTRollW90", 90, nil), ("DTRollW102", 102, nil),
        ("DTRollW102H51", 102, 51), ("DTRollW102H152", 102, 152),
        ("RoundW12DIA", 12, 12), ("RoundW24DIA", 24, 24), ("RoundW58DIA", 58, 58)
    ])

    /// Ordre de `BRLMPTPrintSettingsLabelSize` (BRLMPTPrintSettings.h).
    public static let pt: [BrotherLabelSize] = make([
        ("Width3_5mm", 3.5, nil), ("Width6mm", 6, nil), ("Width9mm", 9, nil), ("Width12mm", 12, nil),
        ("Width18mm", 18, nil), ("Width24mm", 24, nil), ("Width36mm", 36, nil),
        ("WidthHS_5_8mm", 5.8, nil), ("WidthHS_8_8mm", 8.8, nil), ("WidthHS_11_7mm", 11.7, nil),
        ("WidthHS_17_7mm", 17.7, nil), ("WidthHS_23_6mm", 23.6, nil), ("WidthFL_21x45mm", 21, 45),
        ("WidthHS_5_2mm", 5.2, nil), ("WidthHS_9_0mm", 9, nil), ("WidthHS_11_2mm", 11.2, nil),
        ("WidthHS_21_0mm", 21, nil), ("WidthHS_31_0mm", 31, nil)
    ])

    private static func make(_ entries: [(String, Double, Double?)]) -> [BrotherLabelSize] {
        entries.enumerated().map { offset, entry in
            BrotherLabelSize(index: offset, name: entry.0, widthMM: entry.1, lengthMM: entry.2)
        }
    }

    public var title: String {
        let width = BrotherPaper.format(widthMM)
        if name.hasPrefix("Round") { return "Ø \(width) mm" }
        if name.hasPrefix("WidthHS") { return "\(width) mm HSe" }
        if name.hasPrefix("WidthFL") { return "21 × 45 mm FLe" }
        if name.hasPrefix("Width") { return "\(width) mm TZe" }
        let prefix = name.hasPrefix("DT") ? "DT " : ""
        let suffix = name.hasSuffix("RB") ? " rouge/noir" : ""
        if let lengthMM {
            return "\(prefix)\(width) × \(BrotherPaper.format(lengthMM)) mm\(suffix)"
        }
        return "\(prefix)\(width) mm continu\(suffix)"
    }
}

/// Support d'impression choisi pour une imprimante Brother.
public enum BrotherMedia: Hashable, Codable, Sendable {
    case custom(BrotherPaper)
    /// Index dans `BrotherLabelSize.ql`.
    case qlLabel(Int)
    /// Index dans `BrotherLabelSize.pt`.
    case ptTape(Int)
    case sheet(BrotherSheet)
    case fixedByModel

    /// Support propose par defaut pour un modele.
    public static func defaultMedia(for model: BrotherModel) -> BrotherMedia {
        switch model.series.paperSource {
        case .customPaper: return .custom(model.paperPresets.first ?? .roll(widthMM: 58))
        // DK-22205: rouleau continu 62 mm, la reference la plus courante.
        case .qlLabel: return .qlLabel(BrotherLabelSize.ql.firstIndex { $0.name == "RollW62" } ?? 0)
        case .ptTape: return .ptTape(BrotherLabelSize.pt.firstIndex { $0.name == "Width12mm" } ?? 0)
        case .pjSheet: return .sheet(.a4)
        case .fixedByModel: return .fixedByModel
        }
    }

    /// Vrai si ce support convient a la serie du modele.
    public func isCompatible(with model: BrotherModel) -> Bool {
        switch (self, model.series.paperSource) {
        case let (.custom(paper), .customPaper): return paper.widthMM <= model.maxPaperWidthMM
        case let (.qlLabel(index), .qlLabel): return BrotherLabelSize.ql.indices.contains(index)
        case let (.ptTape(index), .ptTape): return BrotherLabelSize.pt.indices.contains(index)
        case (.sheet, .pjSheet), (.fixedByModel, .fixedByModel): return true
        default: return false
        }
    }

    /// Largeur imprimable approximative, utilisee pour choisir la
    /// resolution du rendu. Le SDK met de toute facon l'image a l'echelle.
    public var printableWidthMM: Double {
        switch self {
        case let .custom(paper): return paper.printableWidthMM
        case let .qlLabel(index): return BrotherLabelSize.ql[safe: index]?.widthMM ?? 62
        case let .ptTape(index): return BrotherLabelSize.pt[safe: index]?.widthMM ?? 12
        case let .sheet(sheet): return sheet.widthMM
        case .fixedByModel: return 105
        }
    }
}

/// Reglages de coupe envoyes avec un travail Brother.
///
/// Correspondance avec le SDK (TD et QL):
/// - `autoCut`: coupe apres chaque page, ou toutes les
///   `autoCutForEachPageCount` pages;
/// - `cutAtEnd`: coupe apres la derniere page du travail, independamment
///   de `autoCut`. C'est ce qui separe le dernier ticket du rouleau.
///
/// Sur un travail d'une seule page, les deux reglages coupent au meme
/// endroit. Ils se distinguent avec plusieurs copies: `autoCut` seul avec
/// un pas de 3 coupe par paquets de trois, `cutAtEnd` seul ne coupe qu'une
/// fois a la fin.
///
/// Les deux valeurs sont desactivees par defaut: le massicot des TD est un
/// accessoire, et demander une coupe sans massicot ne coupe rien.
public struct BrotherCutOptions: Hashable, Codable, Sendable {
    public var autoCut: Bool
    /// Pas de coupe, de 1 a 255. Utilise seulement si `autoCut`.
    public var cutEveryPages: Int
    public var cutAtEnd: Bool

    public init(autoCut: Bool = false, cutEveryPages: Int = 1, cutAtEnd: Bool = false) {
        self.autoCut = autoCut
        self.cutEveryPages = cutEveryPages
        self.cutAtEnd = cutAtEnd
    }

    /// Pas de coupe borne a la plage acceptee par le SDK (`UInt8`, 1-255).
    public var clampedCutEveryPages: UInt8 {
        UInt8(clamping: min(255, max(1, cutEveryPages)))
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
