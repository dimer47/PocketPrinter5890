import Foundation

/// Mise en page du texte natif.
///
/// L'imprimante coupe brutalement au caractere pres quand une ligne depasse
/// la largeur disponible: « l'apres-midi. » devient « l'apres-m » puis
/// « idi. ». Ces fonctions decoupent proprement sur les espaces en amont.
public enum TextLayout {

    /// Nombre de colonnes disponibles selon la largeur et la taille de police.
    ///
    /// La police A fait 12 px de large; un multiplicateur de taille divise
    /// d'autant le nombre de colonnes.
    public static func columns(printWidth: Int, size: Int = 1) -> Int {
        max(1, printWidth / (12 * max(1, size)))
    }

    /// Decoupe un texte pour qu'aucune ligne ne depasse `columns`.
    ///
    /// La coupure se fait sur les espaces; un mot plus long qu'une ligne est
    /// coupe net, faute de mieux.
    public static func wrap(_ text: String, columns: Int) -> [String] {
        guard columns > 0 else { return [text] }
        var lines: [String] = []

        for paragraph in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var current = ""
            for word in paragraph.split(separator: " ", omittingEmptySubsequences: false) {
                let candidate = current.isEmpty ? String(word) : current + " " + word

                if candidate.count <= columns {
                    current = candidate
                    continue
                }

                if !current.isEmpty {
                    lines.append(current)
                    current = ""
                }

                // Mot seul trop long: on le coupe en tranches.
                var remainder = Substring(word)
                while remainder.count > columns {
                    lines.append(String(remainder.prefix(columns)))
                    remainder = remainder.dropFirst(columns)
                }
                current = String(remainder)
            }
            lines.append(current)
        }
        return lines
    }

    /// Compose une ligne avec une etiquette a gauche et une valeur a droite.
    ///
    /// Si les deux ne tiennent pas, l'etiquette est tronquee: la valeur est
    /// generalement l'information utile.
    public static func columns(
        _ left: String,
        _ right: String,
        width: Int
    ) -> String {
        let available = width - right.count - 1
        guard available > 0 else { return String(right.suffix(width)) }

        let label = left.count > available ? String(left.prefix(available)) : left
        let padding = max(1, width - label.count - right.count)
        return label + String(repeating: " ", count: padding) + right
    }
}
