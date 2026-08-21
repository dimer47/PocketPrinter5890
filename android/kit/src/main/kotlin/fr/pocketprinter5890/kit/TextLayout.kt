package fr.pocketprinter5890.kit

/**
 * Mise en page du texte natif.
 *
 * L'imprimante coupe brutalement au caractere pres quand une ligne depasse la
 * largeur disponible: « l'apres-midi. » devient « l'apres-m » puis « idi. ».
 * Ces fonctions decoupent proprement sur les espaces en amont.
 */
object TextLayout {

    /**
     * Nombre de colonnes disponibles selon la largeur et la taille de police.
     *
     * La police A fait 12 px de large; un multiplicateur de taille divise
     * d'autant le nombre de colonnes.
     */
    fun columns(printWidth: Int, size: Int = 1): Int =
        maxOf(1, printWidth / (12 * maxOf(1, size)))

    /**
     * Decoupe un texte pour qu'aucune ligne ne depasse [columns].
     *
     * La coupure se fait sur les espaces; un mot plus long qu'une ligne est
     * coupe net, faute de mieux.
     */
    fun wrap(text: String, columns: Int): List<String> {
        if (columns <= 0) return listOf(text)
        val lines = mutableListOf<String>()

        for (paragraph in text.split("\n")) {
            var current = ""
            for (word in paragraph.split(" ")) {
                val candidate = if (current.isEmpty()) word else "$current $word"

                if (candidate.length <= columns) {
                    current = candidate
                    continue
                }

                if (current.isNotEmpty()) {
                    lines.add(current)
                    current = ""
                }

                // Mot seul trop long: on le coupe en tranches.
                var remainder = word
                while (remainder.length > columns) {
                    lines.add(remainder.take(columns))
                    remainder = remainder.drop(columns)
                }
                current = remainder
            }
            lines.add(current)
        }
        return lines
    }

    /**
     * Compose une ligne avec une etiquette a gauche et une valeur a droite.
     *
     * Si les deux ne tiennent pas, l'etiquette est tronquee: la valeur est
     * generalement l'information utile.
     */
    fun columns(left: String, right: String, width: Int): String {
        val available = width - right.length - 1
        if (available <= 0) return right.takeLast(width)

        val label = if (left.length > available) left.take(available) else left
        val padding = maxOf(1, width - label.length - right.length)
        return label + " ".repeat(padding) + right
    }
}
