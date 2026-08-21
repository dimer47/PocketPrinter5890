package fr.pocketprinter5890.kit

import java.util.Date
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ReceiptDocumentTest {

    private val receipt = Receipt(
        merchantName = "Boulangerie",
        address = "",
        date = Date(1_720_000_000_000L),
        items = listOf(
            ReceiptItem("Baguette", 2, 120),
            ReceiptItem("Cafe", 1, 249)
        ),
        footer = "Merci"
    )

    @Test
    fun `les montants en centimes evitent les arrondis flottants`() {
        // 0,1 + 0,2 en Double ne fait pas 0,3: sur un ticket, l'ecart finit
        // par se voir dans le total.
        val cents = Receipt(
            merchantName = "x", address = "", date = Date(0),
            items = listOf(
                ReceiptItem("a", 3, 10),
                ReceiptItem("b", 1, 20)
            ),
            footer = ""
        )
        assertEquals(50, cents.totalCents)
    }

    @Test
    fun `le total est la somme des lignes`() {
        assertEquals(240 + 249, receipt.totalCents)
    }

    @Test
    fun `le formatage des centimes garde deux decimales`() {
        assertEquals("2,49", formatCents(249))
        assertEquals("2,40", formatCents(240))
        assertEquals("0,05", formatCents(5))
        assertEquals("12,00", formatCents(1200))
    }

    @Test
    fun `un montant negatif garde son signe`() {
        // Une remise est une ligne comme une autre.
        assertEquals("-0,50", formatCents(-50))
    }

    @Test
    fun `l'apercu et l'impression partagent la mise en page`() {
        // Ce qui s'affiche doit etre ce qui sort du papier: les lignes de
        // l'apercu se retrouvent telles quelles dans le document.
        val preview = ReceiptDocument.preview(receipt, columns = 32)
        val document = ReceiptDocument.build(receipt, columns = 32)

        val documentLines = document.elements
            .filterIsInstance<PrintElement.Text>()
            .map { Escpos.transliterate(it.value) }

        for (line in documentLines) {
            assertTrue(preview.contains(line), "Ligne absente de l'apercu: $line")
        }
    }

    @Test
    fun `aucune ligne ne depasse la largeur disponible`() {
        for (line in ReceiptDocument.preview(receipt, columns = 32).split("\n")) {
            assertTrue(line.length <= 32, "Ligne trop longue (${line.length}): $line")
        }
    }

    @Test
    fun `le total porte le montant aligne a droite`() {
        val preview = ReceiptDocument.preview(receipt, columns = 32)
        val totalLine = preview.split("\n").first { it.startsWith("TOTAL") }
        assertTrue(totalLine.endsWith("4,89 EUR"), "Ligne inattendue: $totalLine")
        assertEquals(32, totalLine.length)
    }

    @Test
    fun `le document porte la sequence d'activation une fois assemble`() {
        val segments = PrintJobBuilder.segments(
            ReceiptDocument.build(receipt, columns = 32),
            PrintOptions()
        )
        val labels = segments.map { it.name }
        assertTrue(labels.contains("Activation moteur"))
        assertTrue(labels.contains("Fin du travail"))
    }

    @Test
    fun `les deux modes d'impression sont decrits`() {
        // Le libelle sert a choisir en connaissance de cause: aucun des deux
        // modes n'est meilleur en toutes circonstances.
        for (mode in ReceiptPrintMode.entries) {
            assertTrue(mode.title.isNotEmpty())
            assertTrue(mode.detail.isNotEmpty())
        }
    }
}
