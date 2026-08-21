import Foundation

/// Jeu de commandes ESC/POS standard.
///
/// La machine cible est une mini imprimante thermique de poche de la famille
/// generique 5890. Ces machines implementent le socle ESC/POS d'Epson. Les
/// commandes proprietaires `10 FF ...` sont un complement, pas le socle.
public enum ESCPOS {
    // MARK: - Initialisation

    /// `ESC @` - reinitialise l'imprimante et vide les modes de mise en forme.
    public static let initialize: [UInt8] = [0x1b, 0x40]

    // MARK: - Alignement

    public enum Alignment: UInt8, CaseIterable, Identifiable, Sendable {
        case left = 0
        case center = 1
        case right = 2

        public var id: UInt8 { rawValue }

        public var title: String {
            switch self {
            case .left: return "Gauche"
            case .center: return "Centre"
            case .right: return "Droite"
            }
        }
    }

    /// `ESC a n`
    public static func align(_ alignment: Alignment) -> [UInt8] {
        [0x1b, 0x61, alignment.rawValue]
    }

    // MARK: - Styles de texte

    /// `ESC E n` — gras.
    ///
    /// - Warning: le firmware A2Y **accepte la commande sans l'appliquer**.
    ///   Constate sur papier depuis macOS/iOS et depuis Android. Pour du gras
    ///   reellement visible, rendre le texte en image et l'envoyer en raster
    ///   (`ReceiptRenderer`), comme le fait l'application officielle pour tout
    ///   son texte.
    public static func bold(_ enabled: Bool) -> [UInt8] {
        [0x1b, 0x45, enabled ? 1 : 0]
    }

    /// `ESC - n` - 0 aucun, 1 fin, 2 epais.
    public static func underline(_ thickness: UInt8) -> [UInt8] {
        [0x1b, 0x2d, min(thickness, 2)]
    }

    /// `ESC { n` - impression tete-beche.
    public static func upsideDown(_ enabled: Bool) -> [UInt8] {
        [0x1b, 0x7b, enabled ? 1 : 0]
    }

    /// `GS B n` - inversion video (blanc sur noir).
    public static func inverted(_ enabled: Bool) -> [UInt8] {
        [0x1d, 0x42, enabled ? 1 : 0]
    }

    /// `GS ! n` - multiplicateur de taille, 1 a 8 sur chaque axe.
    public static func textSize(width: Int, height: Int) -> [UInt8] {
        let w = UInt8(max(1, min(8, width)) - 1)
        let h = UInt8(max(1, min(8, height)) - 1)
        return [0x1d, 0x21, (w << 4) | h]
    }

    // MARK: - Avance papier

    /// `LF`
    public static let lineFeed: [UInt8] = [0x0a]

    /// `ESC d n` - avance de n lignes.
    public static func feedLines(_ lines: UInt8) -> [UInt8] {
        [0x1b, 0x64, lines]
    }

    /// `ESC J n` - avance de n points (1/203 pouce), maximum 255.
    public static func feedDots(_ dots: UInt8) -> [UInt8] {
        [0x1b, 0x4a, dots]
    }

    /// Avance d'un nombre de points quelconque.
    ///
    /// `ESC J` ne prend qu'un octet: au-dela de 255 points (~32 mm) la
    /// commande est repetee autant de fois que necessaire.
    public static func feed(dots: Int) -> [UInt8] {
        guard dots > 0 else { return [] }
        var remaining = dots
        var output: [UInt8] = []
        while remaining > 0 {
            let step = min(remaining, 255)
            output += feedDots(UInt8(step))
            remaining -= step
        }
        return output
    }

    /// `ESC 2` - interligne par defaut.
    public static let defaultLineSpacing: [UInt8] = [0x1b, 0x32]

    /// `ESC 3 n` - interligne de n points.
    public static func lineSpacing(_ dots: UInt8) -> [UInt8] {
        [0x1b, 0x33, dots]
    }

    // MARK: - Jeu de caracteres

    /// `ESC t n` - page de code. 16 = WPC1252 (Europe de l'Ouest, accents francais).
    public static func codePage(_ page: UInt8) -> [UInt8] {
        [0x1b, 0x74, page]
    }

    /// Page de code Windows-1252, adaptee au francais.
    ///
    /// - Warning: le firmware A2Y **ignore** `ESC t` et laisse meme un octet
    ///   parasite s'imprimer (un `a` devant la ligne suivante). Une mire
    ///   testant les neuf pages de code a donne neuf lignes identiques,
    ///   toutes illisibles. Ne pas envoyer cette commande a cette machine:
    ///   utiliser `transliterate(_:)` a la place.
    public static let codePageLatin1: [UInt8] = codePage(16)

    /// Pages de code candidates pour le francais, avec leur numero ESC/POS.
    ///
    /// Le firmware de cette machine ne documente pas sa table par defaut et
    /// semble ignorer `ESC t`. `CodePageProbe` permet de determiner
    /// experimentalement laquelle il utilise reellement.
    public enum CodePageCandidate: UInt8, CaseIterable, Identifiable, Sendable {
        case pc437USA = 0
        case katakana = 1
        case pc850Multilingual = 2
        case pc860Portuguese = 3
        case pc863Canadian = 4
        case pc865Nordic = 5
        case westernEuropean = 6
        case pc858Euro = 19
        case wpc1252 = 16

        public var id: UInt8 { rawValue }

        public var title: String {
            switch self {
            case .pc437USA: return "PC437 (USA)"
            case .katakana: return "Katakana"
            case .pc850Multilingual: return "PC850 (multilingue)"
            case .pc860Portuguese: return "PC860 (portugais)"
            case .pc863Canadian: return "PC863 (canadien)"
            case .pc865Nordic: return "PC865 (nordique)"
            case .westernEuropean: return "Europe de l'Ouest"
            case .pc858Euro: return "PC858 (euro)"
            case .wpc1252: return "WPC1252"
            }
        }

        /// Nom de l'encodage correspondant cote Foundation, quand il existe.
        var encoding: String.Encoding? {
            switch self {
            case .pc437USA, .pc850Multilingual, .pc858Euro: return nil  // pas dans Foundation
            case .wpc1252, .westernEuropean: return .windowsCP1252
            default: return nil
            }
        }
    }

    /// Translitere le texte en ASCII pur.
    ///
    /// Repli sur pour un firmware dont on ne connait pas la table: `°`
    /// devient `deg`, les lettres accentuees perdent leur diacritique.
    /// Mieux vaut un texte legerement approximatif qu'un carre illisible.
    public static func transliterate(_ text: String) -> String {
        var result = ""
        for character in text {
            if character.isASCII {
                result.append(character)
                continue
            }
            if let replacement = Self.asciiReplacements[character] {
                result += replacement
                continue
            }
            // Retrait des diacritiques: "é" -> "e", "ç" -> "c".
            let folded = String(character).folding(
                options: [.diacriticInsensitive],
                locale: Locale(identifier: "fr_FR")
            )
            result += folded.allSatisfy(\.isASCII) ? folded : "?"
        }
        return result
    }

    /// Substitutions explicites pour les symboles courants.
    private static let asciiReplacements: [Character: String] = [
        "°": "deg", "€": "EUR", "£": "GBP", "¥": "JPY",
        "«": "\"", "»": "\"", "\u{2018}": "'", "\u{2019}": "'",
        "\u{201C}": "\"", "\u{201D}": "\"", "\u{2013}": "-", "\u{2014}": "-",
        "\u{2026}": "...", "×": "x", "÷": "/", "±": "+/-",
        "¼": "1/4", "½": "1/2", "¾": "3/4", "²": "2", "³": "3",
        "œ": "oe", "Œ": "OE", "æ": "ae", "Æ": "AE", "ß": "ss"
    ]

    /// Encode du texte en CP1252 avec repli ASCII sur les caracteres non representables.
    public static func encode(_ text: String) -> [UInt8] {
        if let data = text.data(using: .windowsCP1252) {
            return Array(data)
        }
        // Repli: on retire les diacritiques puis on force l'ASCII.
        let folded = text.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
        if let data = folded.data(using: .windowsCP1252) {
            return Array(data)
        }
        return Array(folded.unicodeScalars.map { $0.isASCII ? UInt8($0.value) : 0x3f })
    }

    /// Texte suivi d'un saut de ligne.
    public static func line(_ text: String) -> [UInt8] {
        encode(text) + lineFeed
    }

    // MARK: - Codes-barres
    //
    // Ces commandes font partie du standard ESC/POS mais ne sont pas
    // implementees par tous les firmwares. Sur l'A2Y de cette machine,
    // elles s'impriment en clair au lieu d'etre interpretees. L'application
    // officielle ne les utilise pas non plus: elle genere les codes en image
    // avec ZXing puis les imprime en raster.
    //
    // Voir `CodeRenderer` pour la voie fiable.

    public enum BarcodeType: UInt8, Sendable {
        case upcA = 65
        case upcE = 66
        case ean13 = 67
        case ean8 = 68
        case code39 = 69
        case itf = 70
        case codabar = 71
        case code93 = 72
        case code128 = 73
    }

    /// `GS h n` - hauteur du code-barres en points.
    public static func barcodeHeight(_ dots: UInt8) -> [UInt8] {
        [0x1d, 0x68, max(1, dots)]
    }

    /// `GS w n` - largeur de module, 2 a 6.
    public static func barcodeWidth(_ width: UInt8) -> [UInt8] {
        [0x1d, 0x77, max(2, min(6, width))]
    }

    /// `GS H n` - position du texte lisible. 0 aucun, 1 dessus, 2 dessous, 3 les deux.
    public static func barcodeTextPosition(_ position: UInt8) -> [UInt8] {
        [0x1d, 0x48, min(position, 3)]
    }

    /// `GS k m n <data>` - variante avec longueur explicite.
    public static func barcode(_ content: String, type: BarcodeType = .code128) -> [UInt8] {
        var payload = Array(content.utf8)
        if type == .code128 {
            // Jeu de caracteres B par defaut, requis par le format GS k etendu.
            payload = [0x7b, 0x42] + payload
        }
        let length = UInt8(min(payload.count, 255))
        return [0x1d, 0x6b, type.rawValue, length] + payload.prefix(Int(length))
    }

    // MARK: - QR code

    /// Sequence complete de generation d'un QR code.
    /// - Parameters:
    ///   - content: donnees encodees.
    ///   - moduleSize: taille d'un module, 1 a 16.
    ///   - errorCorrection: 48 = L, 49 = M, 50 = Q, 51 = H.
    public static func qrCode(
        _ content: String,
        moduleSize: UInt8 = 6,
        errorCorrection: UInt8 = 49
    ) -> [UInt8] {
        let data = Array(content.utf8)
        // Longueur = donnees + 3 octets d'en-tete de la fonction 80.
        let length = data.count + 3
        let pL = UInt8(length & 0xff)
        let pH = UInt8((length >> 8) & 0xff)

        var bytes: [UInt8] = []
        // Fonction 165: modele de symbole (2).
        bytes += [0x1d, 0x28, 0x6b, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00]
        // Fonction 167: taille du module.
        bytes += [0x1d, 0x28, 0x6b, 0x03, 0x00, 0x31, 0x43, max(1, min(16, moduleSize))]
        // Fonction 169: niveau de correction d'erreur.
        bytes += [0x1d, 0x28, 0x6b, 0x03, 0x00, 0x31, 0x45, errorCorrection]
        // Fonction 180: stockage des donnees dans le tampon.
        bytes += [0x1d, 0x28, 0x6b, pL, pH, 0x31, 0x50, 0x30] + data
        // Fonction 181: impression du tampon.
        bytes += [0x1d, 0x28, 0x6b, 0x03, 0x00, 0x31, 0x51, 0x30]
        return bytes
    }

    // MARK: - Statut

    /// `DLE EOT n` - demande de statut temps reel.
    public static func realTimeStatus(_ kind: UInt8) -> [UInt8] {
        [0x10, 0x04, min(max(kind, 1), 4)]
    }
}
