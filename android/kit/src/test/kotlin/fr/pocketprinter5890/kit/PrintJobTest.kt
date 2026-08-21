package fr.pocketprinter5890.kit

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** Transport factice qui enregistre ce qui lui est remis. */
private class RecordingTransport : PrinterTransport {
    val sent = mutableListOf<Pair<String, ByteArray>>()

    override fun send(bytes: ByteArray, label: String) {
        sent.add(label to bytes)
    }

    /** Concatenation de tout ce qui a ete envoye. */
    fun flattened(): ByteArray =
        sent.fold(ByteArray(0)) { accumulator, entry -> accumulator + entry.second }
}

/** Recherche une sous-sequence d'octets. */
private fun ByteArray.containsSequence(needle: ByteArray): Boolean {
    if (needle.isEmpty() || needle.size > size) return false
    outer@ for (start in 0..size - needle.size) {
        for (offset in needle.indices) {
            if (this[start + offset] != needle[offset]) continue@outer
        }
        return true
    }
    return false
}

class PrintJobTest {

    private fun bytes(vararg values: Int): ByteArray =
        ByteArray(values.size) { values[it].toByte() }

    @Test
    fun `une impression emet la sequence d'activation complete`() {
        val transport = RecordingTransport()
        val printer = PocketPrinter(transport)

        val document = PrintDocument()
        document.append(PrintElement.Text("Bonjour"))
        printer.print(document)

        val labels = transport.sent.map { it.first }
        assertTrue(labels.contains("Activation moteur"))
        assertTrue(labels.contains("Reveil"))
        assertTrue(labels.contains("Fin du travail"))

        // Sans l'activation, le firmware acquitte tout et n'execute rien:
        // l'ordre compte autant que la presence.
        assertTrue(labels.indexOf("Activation moteur") < labels.indexOf("Reveil"))
        assertTrue(labels.indexOf("Reveil") < labels.indexOf("Fin du travail"))
    }

    @Test
    fun `un document vide porte quand meme l'activation`() {
        val segments = PrintJobBuilder.segments(PrintDocument(), PrintOptions())
        val labels = segments.map { it.name }
        assertTrue(labels.contains("Activation moteur"))
        assertTrue(labels.contains("Fin du travail"))
    }

    @Test
    fun `le papier continu n'envoie ni longueur d'etiquette ni calage`() {
        // `1F 80` declare une longueur fixe: sur rouleau continu, l'imprimante
        // deroulerait jusqu'a la fin de l'etiquette declaree.
        val segments = PrintJobBuilder.segments(
            PrintDocument(listOf(PrintElement.Text("x"))),
            PrintOptions(paperMode = PaperMode.CONTINUOUS)
        )
        val labels = segments.map { it.name }
        assertFalse(labels.contains("Longueur d'etiquette"))
        assertFalse(labels.contains("Calage etiquette"))
    }

    @Test
    fun `le mode etiquette ajoute la longueur et le calage`() {
        val segments = PrintJobBuilder.segments(
            PrintDocument(listOf(PrintElement.Text("x"))),
            PrintOptions(paperMode = PaperMode.LABEL)
        )
        val labels = segments.map { it.name }
        assertTrue(labels.contains("Longueur d'etiquette"))
        assertTrue(labels.contains("Calage etiquette"))
    }

    @Test
    fun `une avance longue est repartie sur plusieurs commandes`() {
        // `ESC J` ne prend qu'un octet: au-dela de 255 points il faut repeter.
        val encoded = Escpos.feed(600)
        assertContentEquals(
            bytes(0x1b, 0x4a, 0xff, 0x1b, 0x4a, 0xff, 0x1b, 0x4a, 0x5a),
            encoded
        )
    }

    @Test
    fun `les commandes experimentales sont absentes par defaut`() {
        val segments = PrintJobBuilder.segments(
            PrintDocument(listOf(PrintElement.Text("x"))),
            PrintOptions()
        )
        val labels = segments.map { it.name }
        assertFalse(labels.any { it.contains("experimental", ignoreCase = true) })
    }

    @Test
    fun `un texte multiligne produit un element par ligne`() {
        val transport = RecordingTransport()
        PocketPrinter(transport).print(text = "une\ndeux\ntrois")
        val textSegments = transport.sent.filter { it.first.startsWith("Texte") }
        assertEquals(3, textSegments.size)
    }

    @Test
    fun `le raster annonce 48 octets par ligne`() {
        val bitmap = MonochromeBitmap(384, 10, ByteArray(48 * 10))
        val command = RasterEncoder.rasterCommand(bitmap)
        // `1D 76 30 00` puis xL xH = 48 = 0x30 0x00, puis yL yH = 10.
        assertContentEquals(bytes(0x1d, 0x76, 0x30, 0x00, 0x30, 0x00, 0x0a, 0x00), command.copyOfRange(0, 8))
    }

    @Test
    fun `le raster est decoupe en bandes`() {
        // Un raster envoye d'un bloc est perdu par le firmware: on verifie
        // que 240 lignes deviennent 10 commandes de 24 lignes.
        val bitmap = MonochromeBitmap(384, 240, ByteArray(48 * 240))
        val commands = RasterEncoder.bandedRasterCommands(bitmap)
        assertEquals(10, commands.size)
        for (command in commands) {
            assertEquals(24, command[6].toInt() and 0xff)
            assertEquals(8 + 48 * 24, command.size)
        }
    }

    @Test
    fun `le dernier bloc porte la hauteur restante`() {
        val bitmap = MonochromeBitmap(384, 50, ByteArray(48 * 50))
        val commands = RasterEncoder.bandedRasterCommands(bitmap)
        assertEquals(3, commands.size)
        assertEquals(2, commands.last()[6].toInt() and 0xff)
    }

    @Test
    fun `un bit a 1 imprime un point noir en MSB d'abord`() {
        // Le pixel le plus a gauche est le bit 7 du premier octet.
        val pixels = BooleanArray(8 * 1)
        pixels[0] = true
        val bitmap = RasterEncoder.encodeBlackPixels(pixels, width = 8, height = 1)
        assertEquals(0x80, bitmap.bytes[0].toInt() and 0xff)
    }

    @Test
    fun `le degagement final est present par defaut`() {
        // Sans avance finale, la fin du ticket reste coincee sous le capot.
        val segments = PrintJobBuilder.segments(
            PrintDocument(listOf(PrintElement.Text("x"))),
            PrintOptions()
        )
        assertTrue(segments.any { it.name.startsWith("Degagement") })
    }

    @Test
    fun `une avance papier porte la sequence d'activation`() {
        // Regression: un `1B 4A nn` envoye nu est acquitte par le firmware et
        // ignore (specification, section 3.1). Le bouton « degager le papier »
        // ne faisait donc rien du tout.
        val transport = RecordingTransport()
        PocketPrinter(transport).feed(80)

        val labels = transport.sent.map { it.first }
        assertTrue(labels.contains("Activation moteur"))
        assertTrue(labels.contains("Reveil"))
        assertTrue(labels.contains("Fin du travail"))
        assertTrue(transport.flattened().containsSequence(bytes(0x1b, 0x4a, 0x50)))
    }

    @Test
    fun `une avance papier n'ajoute pas de degagement supplementaire`() {
        // L'avance demandee doit etre la seule: sinon feed(80) ferait avancer
        // de 160 points.
        val transport = RecordingTransport()
        PocketPrinter(transport).feed(80)
        assertFalse(transport.sent.any { it.first.startsWith("Degagement") })
    }

    @Test
    fun `une lecture d'information porte la sequence d'activation`() {
        // Meme piege: `10 FF 20 F0` envoye nu est acquitte et ignore, ce qui
        // laissait les champs Modele et Firmware desesperement vides.
        val transport = RecordingTransport()
        PocketPrinter(transport).readDeviceInformation()

        val labels = transport.sent.map { it.first }
        assertTrue(labels.contains("Activation moteur"))
        assertTrue(labels.contains("Lire modele"))
        assertTrue(transport.flattened().containsSequence(bytes(0x10, 0xff, 0x20, 0xf0)))
    }

    @Test
    fun `les reglages sont transmis au transport`() {
        val transport = RecordingTransport()
        val printer = PocketPrinter(transport)
        printer.setDensity(PrintDensity.STRONG)
        printer.setAutoShutdown(30)

        assertTrue(transport.flattened().containsSequence(bytes(0x10, 0xff, 0x10, 0x00, 0x02)))
        assertTrue(transport.flattened().containsSequence(bytes(0x10, 0xff, 0x12, 0x00, 0x1e)))
        // Le reglage de densite met aussi a jour les options par defaut.
        assertEquals(PrintDensity.STRONG, printer.options.density)
    }
}
