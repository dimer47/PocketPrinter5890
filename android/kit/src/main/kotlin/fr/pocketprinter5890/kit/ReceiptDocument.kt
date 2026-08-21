package fr.pocketprinter5890.kit

import java.text.SimpleDateFormat
import java.util.Locale

/**
 * Composition d'un ticket en texte natif.
 *
 * Le pendant de `ReceiptRenderer` du module `render`: meme ticket, meme
 * mise en page, mais compose par la police interne de l'imprimante au lieu
 * d'etre dessine puis envoye en pixels.
 */
object ReceiptDocument {

    /**
     * Construit le document a partir d'un ticket.
     *
     * @param columns nombre de colonnes disponibles. 32 a la largeur native.
     */
    fun build(
        receipt: Receipt,
        columns: Int = TextLayout.columns(MonochromeBitmap.nativeWidth),
        locale: Locale = Locale.FRANCE
    ): PrintDocument {
        val document = PrintDocument()

        document.append(PrintElement.title(receipt.merchantName.uppercase(locale)))
        if (receipt.address.isNotEmpty()) {
            document.append(PrintElement.centered(receipt.address))
        }
        document.append(
            PrintElement.centered(
                SimpleDateFormat("dd/MM/yyyy HH:mm", locale).format(receipt.date)
            )
        )
        document.append(PrintElement.Separator())

        for (item in receipt.items) {
            document.append(
                PrintElement.Text(
                    TextLayout.columns(
                        "${item.quantity}x ${item.name}",
                        formatCents(item.totalCents),
                        columns
                    )
                )
            )
        }

        document.append(PrintElement.Separator())
        // Le gras est demande mais sans effet sur ce firmware: la ligne reste
        // lisible grace a l'alignement, pas a la graisse.
        document.append(
            PrintElement.Text(
                TextLayout.columns(
                    "TOTAL",
                    "${formatCents(receipt.totalCents)} EUR",
                    columns
                ),
                bold = true
            )
        )

        if (receipt.footer.isNotEmpty()) {
            document.append(PrintElement.Separator('='))
            document.append(PrintElement.centered(receipt.footer))
        }
        document.append(PrintElement.Feed(2))
        return document
    }

    /**
     * Apercu texte, identique caractere pour caractere a ce qui sera imprime.
     *
     * L'apercu et l'impression partagent la meme mise en page: ce qui est
     * affiche est ce qui sort du papier.
     */
    fun preview(
        receipt: Receipt,
        columns: Int = TextLayout.columns(MonochromeBitmap.nativeWidth),
        locale: Locale = Locale.FRANCE,
        transliterate: Boolean = true
    ): String {
        val lines = mutableListOf<String>()
        for (element in build(receipt, columns, locale).elements) {
            when (element) {
                is PrintElement.Text -> lines.add(
                    if (transliterate) Escpos.transliterate(element.value) else element.value
                )
                is PrintElement.Separator ->
                    lines.add(element.character.toString().repeat(columns))
                else -> Unit
            }
        }
        return lines.joinToString("\n")
    }
}
