package fr.pocketprinter5890.kit

import java.util.Date

/**
 * Ligne d'un ticket.
 *
 * Les montants sont en centimes: un `Double` accumule des erreurs
 * d'arrondi qui finissent par se voir sur un total.
 */
data class ReceiptItem(
    val name: String,
    val quantity: Int,
    /** Prix unitaire, en centimes. */
    val unitPriceCents: Long
) {
    /** Total de la ligne, en centimes. */
    val totalCents: Long get() = unitPriceCents * quantity
}

/** Ticket de caisse, independant du mode d'impression retenu. */
data class Receipt(
    val merchantName: String,
    val address: String,
    val date: Date,
    val items: List<ReceiptItem>,
    val footer: String
) {
    /** Total du ticket, en centimes. */
    val totalCents: Long get() = items.sumOf { it.totalCents }

    companion object {
        val sample: Receipt = Receipt(
            merchantName = "LIDL TEST",
            address = "Ticket 58 mm - 384 px",
            date = Date(1_720_000_000_000L),
            items = listOf(
                ReceiptItem("Cafe", 1, 249),
                ReceiptItem("Pain", 2, 120),
                ReceiptItem("Remise", 1, -50)
            ),
            footer = "Merci"
        )
    }
}

/**
 * Mode d'impression d'un ticket.
 *
 * Les deux chemins existent parce qu'aucun n'est meilleur en toutes
 * circonstances, et le choix se voit sur le papier.
 */
enum class ReceiptPrintMode(val title: String, val detail: String) {
    /**
     * Texte natif: l'imprimante compose avec sa police interne.
     *
     * Net, rapide (quelques dizaines d'octets par ligne), mais limite a
     * 32 colonnes, sans gras ni logo, et le texte doit etre translitere en
     * ASCII.
     */
    NATIVE_TEXT(
        "Texte natif",
        "Net et rapide. 32 colonnes, sans gras ni accents."
    ),

    /**
     * Image rasterisee: le ticket est dessine puis envoye en pixels.
     *
     * Mise en page libre, gras et accents possibles — c'est ce que fait
     * l'application officielle. En contrepartie le rendu est plus doux et
     * le travail pese des milliers d'octets.
     */
    RASTER_IMAGE(
        "Image rasterisee",
        "Mise en page libre, gras et accents. Plus doux, plus lourd."
    )
}

/** Mise en forme d'un montant en centimes: `249` devient `2,49`. */
fun formatCents(cents: Long): String {
    val sign = if (cents < 0) "-" else ""
    val absolute = kotlin.math.abs(cents)
    return "$sign${absolute / 100},${(absolute % 100).toString().padStart(2, '0')}"
}
