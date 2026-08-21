package fr.pocketprinter5890.kit

import java.util.Calendar
import java.util.TimeZone
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Verifie les octets des commandes proprietaires contre le SDK constructeur.
 *
 * Ces valeurs sont des faits sur un format de fil: elles ne doivent pas
 * bouger sans une raison verifiee sur papier.
 */
class LuckPrinterTest {

    private fun bytes(vararg values: Int): ByteArray =
        ByteArray(values.size) { values[it].toByte() }

    @Test
    fun `cycle d'impression`() {
        assertContentEquals(bytes(0x10, 0xff, 0xf1, 0x03), LuckPrinter.enablePrinter())
        assertContentEquals(bytes(0x10, 0xff, 0xf1, 0x30), LuckPrinter.enablePrinter(0x30))
        // Le reveil est une commande distincte du enable, pas un bourrage
        // accole a `10 FF F1 03`: plusieurs documentations publiques se
        // trompent sur ce point, et les concatener ne fonctionne pas.
        assertEquals(12, LuckPrinter.wakeup.size)
        assertTrue(LuckPrinter.wakeup.all { it == 0.toByte() })
        assertContentEquals(bytes(0x10, 0xff, 0xf1, 0x45), LuckPrinter.stopPrintJob)
        assertContentEquals(bytes(0x1d, 0x0c), LuckPrinter.position)
        assertContentEquals(bytes(0x1b, 0x4a, 0x50), LuckPrinter.feedDots(80))
    }

    @Test
    fun `reglages`() {
        assertContentEquals(bytes(0x10, 0xff, 0x10, 0x00, 0x02), LuckPrinter.setDensity(2))
        // La densite est bornee a 2: une valeur superieure serait rejetee.
        assertContentEquals(bytes(0x10, 0xff, 0x10, 0x00, 0x02), LuckPrinter.setDensity(9))
        assertContentEquals(bytes(0x10, 0xff, 0x11), LuckPrinter.getDensity)
        assertContentEquals(bytes(0x10, 0xff, 0xc0, 0x05), LuckPrinter.setSpeed(5))
        assertContentEquals(bytes(0x1f, 0x70, 0x01, 0x08), LuckPrinter.setHeatingLevel(8))
        assertContentEquals(bytes(0x1f, 0x80, 0x01, 0x20), LuckPrinter.setPaperType())
    }

    @Test
    fun `l'extinction automatique est gros-boutiste sur deux octets`() {
        // 300 minutes = 0x012C: l'octet de poids fort vient en premier.
        assertContentEquals(bytes(0x10, 0xff, 0x12, 0x01, 0x2c), LuckPrinter.setAutoShutdown(300))
        assertContentEquals(bytes(0x10, 0xff, 0x12, 0x00, 0x0f), LuckPrinter.setAutoShutdown(15))
    }

    @Test
    fun `la largeur d'impression est petit-boutiste`() {
        // Le SDK n'est pas coherent: `10 FF 12` est gros-boutiste et
        // `10 FF 15` petit-boutiste. Se tromper produit une valeur plausible
        // mais fausse, d'ou ce test dedie.
        assertContentEquals(bytes(0x10, 0xff, 0x15, 0x80, 0x01), LuckPrinter.setWidth(384))
    }

    @Test
    fun `marques de decoupe`() {
        assertContentEquals(bytes(0x1b, 0xbb, 0xcc), LuckPrinter.markPrintFirst)
        assertContentEquals(bytes(0x1b, 0xbb, 0xbb), LuckPrinter.markPrintLast)
        assertContentEquals(bytes(0x1b, 0xbb, 0xaa), LuckPrinter.markPrintNotLast)
    }

    @Test
    fun `commandes de lecture`() {
        assertContentEquals(bytes(0x10, 0xff, 0x20, 0xf0), LuckPrinter.model)
        assertContentEquals(bytes(0x10, 0xff, 0x20, 0xf1), LuckPrinter.firmware)
        assertContentEquals(bytes(0x10, 0xff, 0x20, 0xf2), LuckPrinter.serialNumber)
        assertContentEquals(bytes(0x10, 0xff, 0x20, 0xef), LuckPrinter.bootloader)
        assertContentEquals(bytes(0x10, 0xff, 0x50, 0xf1), LuckPrinter.battery)
        assertContentEquals(bytes(0x10, 0xff, 0x40), LuckPrinter.status)
        assertContentEquals(bytes(0x10, 0xff, 0x13), LuckPrinter.getAutoShutdown)
    }

    @Test
    fun `l'horloge porte son en-tete et une annee sur deux octets`() {
        val calendar = Calendar.getInstance(TimeZone.getTimeZone("UTC"))
        calendar.set(2026, Calendar.FEBRUARY, 3, 14, 5, 9)
        val encoded = LuckPrinter.setTimeFormat(calendar.time, calendar = calendar)

        // Sans l'en-tete `10 FF 53 4A <format>`, les sept octets de date
        // seuls ne sont pas compris par l'imprimante.
        assertContentEquals(bytes(0x10, 0xff, 0x53, 0x4a, 0x00), encoded.copyOfRange(0, 5))
        // 2026 = 0x07EA, gros-boutiste.
        assertContentEquals(
            bytes(0x07, 0xea, 0x02, 0x03, 0x0e, 0x05, 0x09),
            encoded.copyOfRange(5, encoded.size)
        )
    }

    @Test
    fun `champ de bits du statut`() {
        assertTrue(PrinterStatus(0x02).isCoverOpen)
        assertTrue(PrinterStatus(0x04).isPaperEmpty)
        assertTrue(PrinterStatus(0x08).isBatteryLow)
        assertTrue(PrinterStatus(0x20).isCharging)
    }

    @Test
    fun `l'etat pret ne bloque pas`() {
        assertFalse(PrinterStatus(0x00).isBlocking)
        // 0x01 signifie « occupe », pas une erreur.
        assertFalse(PrinterStatus(0x01).isBlocking)
    }

    @Test
    fun `le capot ouvert bloque`() {
        assertTrue(PrinterStatus(0x02).isBlocking)
        assertTrue(PrinterStatus(0x04).isBlocking)
    }
}
