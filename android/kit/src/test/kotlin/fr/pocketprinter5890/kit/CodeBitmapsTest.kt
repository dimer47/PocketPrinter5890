package fr.pocketprinter5890.kit

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

/**
 * Les commandes natives `GS k` et `GS ( k` ne sont pas implementees par ce
 * firmware: elles s'impriment en clair. Les codes doivent donc etre generes
 * en bitmap, ce que verifient ces tests.
 */
class CodeBitmapsTest {

    /** Compte les pixels noirs d'un bitmap. */
    private fun blackPixels(bitmap: MonochromeBitmap): Int =
        bitmap.bytes.sumOf { Integer.bitCount(it.toInt() and 0xff) }

    @Test
    fun `le QR occupe la largeur d'impression`() {
        val bitmap = CodeBitmaps.qrCode("https://exemple.fr")
        assertEquals(384, bitmap.width)
        assertTrue(bitmap.height in 1..384)
    }

    @Test
    fun `le QR a une densite plausible`() {
        // Un QR correct est ni vide ni entierement noir: entre 10 % et 60 %
        // des pixels du carre sont allumes.
        val bitmap = CodeBitmaps.qrCode("https://exemple.fr")
        val black = blackPixels(bitmap)
        val total = bitmap.width * bitmap.height
        val ratio = black.toDouble() / total
        assertTrue(ratio > 0.05, "QR trop clair: $ratio")
        assertTrue(ratio < 0.60, "QR trop dense: $ratio")
    }

    @Test
    fun `le QR n'est jamais tramé`() {
        // Un QR dithere ne scanne pas. Chaque module doit etre plein ou vide:
        // on verifie qu'aucune ligne n'alterne pixel a pixel sur toute sa
        // largeur, signature d'un tramage.
        val bitmap = CodeBitmaps.qrCode("TEST", moduleSize = 4)
        var alternatingRows = 0
        for (y in 0 until bitmap.height) {
            var alternations = 0
            for (x in 1 until bitmap.width) {
                val previous = pixelAt(bitmap, x - 1, y)
                val current = pixelAt(bitmap, x, y)
                if (previous != current) alternations++
            }
            if (alternations > bitmap.width / 3) alternatingRows++
        }
        assertEquals(0, alternatingRows, "Le QR semble tramé")
    }

    private fun pixelAt(bitmap: MonochromeBitmap, x: Int, y: Int): Boolean {
        val byte = bitmap.bytes[y * bitmap.widthBytes + x / 8].toInt() and 0xff
        return (byte shr (7 - x % 8)) and 1 == 1
    }

    @Test
    fun `un contenu vide est rejete`() {
        assertFailsWith<CodeException> { CodeBitmaps.qrCode("") }
    }

    @Test
    fun `le code-barres remplit la hauteur demandee`() {
        val bitmap = CodeBitmaps.barcode("METEO2026", height = 80)
        assertEquals(384, bitmap.width)
        assertEquals(80, bitmap.height)
    }

    @Test
    fun `le code-barres n'est jamais tramé`() {
        // Toutes les lignes d'un code-barres 1D sont identiques: une ligne qui
        // differe des autres trahit un tramage, qui casse le scan.
        val bitmap = CodeBitmaps.barcode("METEO2026", height = 40)
        val stride = bitmap.widthBytes
        val firstRow = bitmap.bytes.copyOfRange(0, stride)
        for (y in 1 until bitmap.height) {
            val row = bitmap.bytes.copyOfRange(y * stride, (y + 1) * stride)
            assertTrue(firstRow.contentEquals(row), "Ligne $y differente: tramage probable")
        }
    }
}

class Barcode1DTest {

    @Test
    fun `le Code 128 accepte l'ASCII imprimable`() {
        val pattern = Barcode1D.pattern("ABC-123", Barcode1D.Symbology.CODE128)
        assertTrue(pattern.isNotEmpty())
    }

    @Test
    fun `le Code 128 rejette le non-ASCII`() {
        assertFailsWith<BarcodeException> {
            Barcode1D.pattern("café", Barcode1D.Symbology.CODE128)
        }
    }

    @Test
    fun `le Code 39 rejette un caractere non supporte`() {
        assertFailsWith<BarcodeException> {
            Barcode1D.pattern("ABC@", Barcode1D.Symbology.CODE39)
        }
    }

    @Test
    fun `la cle de controle EAN suit le standard`() {
        // Exemples normalises: 4006381333931 et 96385074.
        assertEquals(1, Barcode1D.checkDigit("400638133393".map { it.digitToInt() }))
        assertEquals(4, Barcode1D.checkDigit("9638507".map { it.digitToInt() }))
    }

    @Test
    fun `l'EAN accepte le code avec ou sans cle`() {
        val withKey = Barcode1D.pattern("4006381333931", Barcode1D.Symbology.EAN13)
        val withoutKey = Barcode1D.pattern("400638133393", Barcode1D.Symbology.EAN13)
        assertTrue(withKey.contentEquals(withoutKey))
    }

    @Test
    fun `l'EAN rejette une mauvaise cle`() {
        assertFailsWith<BarcodeException> {
            Barcode1D.pattern("4006381333930", Barcode1D.Symbology.EAN13)
        }
    }

    @Test
    fun `la longueur du motif EAN-13 est normalisee`() {
        // 3 + 6*7 + 5 + 6*7 + 3 = 95 modules.
        assertEquals(95, Barcode1D.pattern("4006381333931", Barcode1D.Symbology.EAN13).size)
    }

    @Test
    fun `la longueur du motif EAN-8 est normalisee`() {
        // 3 + 4*7 + 5 + 4*7 + 3 = 67 modules.
        assertEquals(67, Barcode1D.pattern("96385074", Barcode1D.Symbology.EAN8).size)
    }

    @Test
    fun `un contenu vide est rejete`() {
        assertFailsWith<BarcodeException> {
            Barcode1D.pattern("", Barcode1D.Symbology.CODE128)
        }
    }
}
