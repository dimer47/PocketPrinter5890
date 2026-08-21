import Foundation

/// Mode d'impression d'un ticket.
///
/// Les deux chemins existent parce qu'aucun n'est meilleur en toutes
/// circonstances, et le choix se voit sur le papier.
public enum ReceiptPrintMode: String, CaseIterable, Identifiable, Sendable {
    /// Texte natif: l'imprimante compose avec sa police interne.
    ///
    /// Net, rapide (quelques dizaines d'octets par ligne), mais limite a
    /// 32 colonnes, sans gras ni logo, et le texte doit etre translitere
    /// en ASCII.
    case nativeText

    /// Image rasterisee: le ticket est dessine puis envoye en pixels.
    ///
    /// Mise en page libre, gras et accents possibles — c'est ce que fait
    /// l'application officielle. En contrepartie le rendu est plus doux et
    /// le travail pese des milliers d'octets.
    case rasterImage

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .nativeText: return "Texte natif"
        case .rasterImage: return "Image rasterisee"
        }
    }

    public var detail: String {
        switch self {
        case .nativeText:
            return "Net et rapide. 32 colonnes, sans gras ni accents."
        case .rasterImage:
            return "Mise en page libre, gras et accents. Plus doux, plus lourd."
        }
    }
}

/// Composition d'un ticket en texte natif.
///
/// Le pendant de `ReceiptRenderer`: meme ticket, meme mise en page, mais
/// compose par la police interne de l'imprimante au lieu d'etre dessine puis
/// envoye en pixels.
public enum ReceiptDocument {

    /// Construit le document a partir d'un ticket.
    ///
    /// - Parameter columns: nombre de colonnes disponibles. 32 a la largeur
    ///   native.
    public static func build(
        _ receipt: Receipt,
        columns: Int = TextLayout.columns(printWidth: MonochromeBitmap.nativeWidth),
        locale: Locale = Locale(identifier: "fr_FR")
    ) -> PrintDocument {
        var document = PrintDocument()

        document.append(.title(receipt.merchantName.uppercased(with: locale)))
        if !receipt.address.isEmpty {
            document.append(.centered(receipt.address))
        }
        document.append(.centered(Self.dateFormatter.string(from: receipt.date)))
        document.append(.separator())

        for item in receipt.items {
            document.append(.text(
                TextLayout.columns(
                    "\(item.quantity)x \(item.name)",
                    Self.money(item.total),
                    width: columns
                )
            ))
        }

        document.append(.separator())
        // Le gras est demande mais sans effet sur ce firmware: la ligne reste
        // lisible grace a l'alignement, pas a la graisse.
        document.append(.text(
            TextLayout.columns("TOTAL", "\(Self.money(receipt.total)) EUR", width: columns),
            size: 1,
            bold: true,
            underline: false,
            inverted: false,
            alignment: .left
        ))

        if !receipt.footer.isEmpty {
            document.append(.separator(character: "="))
            document.append(.centered(receipt.footer))
        }
        document.append(.feed(lines: 2))
        return document
    }

    /// Apercu texte, identique caractere pour caractere a ce qui sera imprime.
    public static func preview(
        _ receipt: Receipt,
        columns: Int = TextLayout.columns(printWidth: MonochromeBitmap.nativeWidth),
        locale: Locale = Locale(identifier: "fr_FR"),
        transliterate: Bool = true
    ) -> String {
        var lines: [String] = []
        for element in build(receipt, columns: columns, locale: locale).elements {
            switch element {
            case let .text(value, _, _, _, _, _):
                lines.append(transliterate ? ESCPOS.transliterate(value) : value)
            case let .separator(character):
                lines.append(String(repeating: String(character), count: columns))
            default:
                continue
            }
        }
        return lines.joined(separator: "\n")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "dd/MM/yyyy HH:mm"
        return formatter
    }()

    private static func money(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "0,00"
    }
}
