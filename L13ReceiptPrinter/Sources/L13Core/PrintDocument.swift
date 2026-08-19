import Foundation

/// Document d'impression compose d'elements de haut niveau.
///
/// C'est le point d'entree de la librairie: on decrit ce que l'on veut imprimer,
/// puis `PrintJobBuilder` transforme le document en octets pour l'imprimante.
/// Le document est independant du transport (BLE, USB, SPP).
///
/// Exemple:
/// ```swift
/// var document = PrintDocument()
/// document.append(.text("BOULANGERIE", size: 2, bold: true, alignment: .center))
/// document.append(.separator())
/// document.append(.text("Baguette          1,20 EUR"))
/// document.append(try PrintElement.qrCodeImage("https://exemple.fr"))
/// document.append(.feed(lines: 3))
/// let bytes = PrintJobBuilder.bytes(document: document, options: PrintOptions())
/// ```
public struct PrintDocument: Equatable {
    public var elements: [PrintElement]

    public init(elements: [PrintElement] = []) {
        self.elements = elements
    }

    public mutating func append(_ element: PrintElement) {
        elements.append(element)
    }

    public static func + (lhs: PrintDocument, rhs: PrintDocument) -> PrintDocument {
        PrintDocument(elements: lhs.elements + rhs.elements)
    }
}

public enum PrintElement: Equatable {
    /// Ligne de texte avec mise en forme.
    case text(
        String,
        size: Int = 1,
        bold: Bool = false,
        underline: Bool = false,
        inverted: Bool = false,
        alignment: ESCPOS.Alignment = .left
    )
    /// Image deja convertie en bitmap monochrome.
    case image(MonochromeBitmap)
    /// Code-barres via la commande ESC/POS native `GS k`.
    ///
    /// - Warning: le firmware A2Y de cette machine **n'implemente pas** cette
    ///   commande: elle s'imprime en clair sous la forme `<I{BMETEO2026`.
    ///   Utiliser `PrintElement.barcodeImage(_:)` a la place.
    case barcode(String, type: ESCPOS.BarcodeType = .code128, height: UInt8 = 80)
    /// QR code via la commande ESC/POS native `GS ( k`.
    ///
    /// - Warning: le firmware A2Y de cette machine **n'implemente pas** cette
    ///   commande: elle s'imprime en clair sous la forme `k1A2k1Ck1E1k1P0...`.
    ///   Utiliser `PrintElement.qrCodeImage(_:)` a la place.
    case qrCode(String, moduleSize: UInt8 = 6)
    /// Ligne de separation composee d'un caractere repete.
    case separator(character: Character = "-")
    /// Avance de n lignes.
    case feed(lines: UInt8)
    /// Octets bruts, echappatoire pour une commande non couverte par la librairie.
    case raw([UInt8])

    // Constructeurs de confort, pour eviter d'ecrire les valeurs par defaut.

    /// Titre: gros caracteres, gras, centre.
    public static func title(_ value: String) -> PrintElement {
        .text(value, size: 2, bold: true, underline: false, inverted: false, alignment: .center)
    }

    /// Ligne de texte centree en taille normale.
    public static func centered(_ value: String) -> PrintElement {
        .text(value, size: 1, bold: false, underline: false, inverted: false, alignment: .center)
    }
}

extension PrintElement {
    /// Traduit l'element en octets ESC/POS.
    /// - Parameter columns: nombre de colonnes de texte disponibles, utilise
    ///   pour les separateurs.
    func bytes(columns: Int, bandHeight: Int, transliterate: Bool = false) -> [UInt8] {
        switch self {
        case let .text(value, size, bold, underline, inverted, alignment):
            var output: [UInt8] = []
            output += ESCPOS.align(alignment)
            if size != 1 { output += ESCPOS.textSize(width: size, height: size) }
            if bold { output += ESCPOS.bold(true) }
            if underline { output += ESCPOS.underline(1) }
            if inverted { output += ESCPOS.inverted(true) }

            // Une ligne trop longue est coupee au caractere pres par le
            // firmware: « l'apres-midi. » devenait « l'apres-m » / « idi. ».
            // On decoupe donc proprement sur les espaces, en tenant compte
            // du fait qu'une police agrandie reduit le nombre de colonnes.
            let text = transliterate ? ESCPOS.transliterate(value) : value
            for line in TextLayout.wrap(text, columns: max(1, columns / max(1, size))) {
                output += ESCPOS.line(line)
            }

            // On remet systematiquement les modes a zero pour que l'element
            // suivant ne herite pas de la mise en forme.
            if inverted { output += ESCPOS.inverted(false) }
            if underline { output += ESCPOS.underline(0) }
            if bold { output += ESCPOS.bold(false) }
            if size != 1 { output += ESCPOS.textSize(width: 1, height: 1) }
            if alignment != .left { output += ESCPOS.align(.left) }
            return output

        case let .image(bitmap):
            return RasterEncoder
                .bandedRasterCommands(for: bitmap, bandHeight: bandHeight)
                .flatMap { $0 }

        case let .barcode(content, type, height):
            return ESCPOS.align(.center)
                + ESCPOS.barcodeHeight(height)
                + ESCPOS.barcodeWidth(2)
                + ESCPOS.barcodeTextPosition(2)
                + ESCPOS.barcode(content, type: type)
                + ESCPOS.lineFeed
                + ESCPOS.align(.left)

        case let .qrCode(content, moduleSize):
            return ESCPOS.align(.center)
                + ESCPOS.qrCode(content, moduleSize: moduleSize)
                + ESCPOS.lineFeed
                + ESCPOS.align(.left)

        case let .separator(character):
            return ESCPOS.line(String(repeating: String(character), count: columns))

        case let .feed(lines):
            return ESCPOS.feedLines(lines)

        case let .raw(bytes):
            return bytes
        }
    }
}
