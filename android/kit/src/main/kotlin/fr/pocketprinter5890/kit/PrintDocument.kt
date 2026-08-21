package fr.pocketprinter5890.kit

/**
 * Element d'un document d'impression.
 *
 * En Swift il s'agit d'un `enum` a valeurs associees; l'equivalent Kotlin est
 * une `sealed class`, qui offre le meme exhaustive-check dans un `when`.
 */
sealed class PrintElement {

    /** Ligne de texte avec mise en forme. */
    data class Text(
        val value: String,
        val size: Int = 1,
        val bold: Boolean = false,
        val underline: Boolean = false,
        val inverted: Boolean = false,
        val alignment: Escpos.Alignment = Escpos.Alignment.LEFT
    ) : PrintElement()

    /** Image deja convertie en bitmap monochrome. */
    data class Image(val bitmap: MonochromeBitmap) : PrintElement()

    /**
     * Code-barres via la commande ESC/POS native `GS k`.
     *
     * Attention: le firmware A2Y de cette machine **n'implemente pas** cette
     * commande: elle s'imprime en clair sous la forme `<I{BMETEO2026`.
     * Utiliser [CodeBitmaps.barcode] et [Image] a la place.
     */
    data class Barcode(
        val content: String,
        val type: Escpos.BarcodeType = Escpos.BarcodeType.CODE128,
        val height: Int = 80
    ) : PrintElement()

    /**
     * QR code via la commande ESC/POS native `GS ( k`.
     *
     * Attention: le firmware A2Y de cette machine **n'implemente pas** cette
     * commande: elle s'imprime en clair sous la forme `k1A2k1Ck1E1k1P0...`.
     * Utiliser [CodeBitmaps.qrCode] et [Image] a la place.
     */
    data class QrCode(val content: String, val moduleSize: Int = 6) : PrintElement()

    /** Ligne de separation composee d'un caractere repete. */
    data class Separator(val character: Char = '-') : PrintElement()

    /** Avance de n lignes. */
    data class Feed(val lines: Int) : PrintElement()

    /** Octets bruts, echappatoire pour une commande non couverte par la librairie. */
    data class Raw(val bytes: ByteArray) : PrintElement() {
        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is Raw) return false
            return bytes.contentEquals(other.bytes)
        }

        override fun hashCode(): Int = bytes.contentHashCode()
    }

    companion object {
        /** Titre: gros caracteres, gras, centre. */
        fun title(value: String): PrintElement =
            Text(value, size = 2, bold = true, alignment = Escpos.Alignment.CENTER)

        /** Ligne de texte centree en taille normale. */
        fun centered(value: String): PrintElement =
            Text(value, alignment = Escpos.Alignment.CENTER)
    }

    /**
     * Traduit l'element en octets ESC/POS.
     *
     * @param columns nombre de colonnes de texte disponibles, utilise pour
     *   les separateurs.
     */
    internal fun bytes(
        columns: Int,
        bandHeight: Int,
        transliterate: Boolean = false
    ): ByteArray = when (this) {
        is Text -> {
            val output = mutableListOf<Byte>()
            output.addAll(Escpos.align(alignment).toList())
            if (size != 1) output.addAll(Escpos.textSize(size, size).toList())
            if (bold) output.addAll(Escpos.bold(true).toList())
            if (underline) output.addAll(Escpos.underline(1).toList())
            if (inverted) output.addAll(Escpos.inverted(true).toList())

            // Une ligne trop longue est coupee au caractere pres par le
            // firmware: « l'apres-midi. » devenait « l'apres-m » / « idi. ».
            // On decoupe donc proprement sur les espaces, en tenant compte du
            // fait qu'une police agrandie reduit le nombre de colonnes.
            val text = if (transliterate) Escpos.transliterate(value) else value
            for (line in TextLayout.wrap(text, maxOf(1, columns / maxOf(1, size)))) {
                output.addAll(Escpos.line(line).toList())
            }

            // On remet systematiquement les modes a zero pour que l'element
            // suivant n'herite pas de la mise en forme.
            if (inverted) output.addAll(Escpos.inverted(false).toList())
            if (underline) output.addAll(Escpos.underline(0).toList())
            if (bold) output.addAll(Escpos.bold(false).toList())
            if (size != 1) output.addAll(Escpos.textSize(1, 1).toList())
            if (alignment != Escpos.Alignment.LEFT) {
                output.addAll(Escpos.align(Escpos.Alignment.LEFT).toList())
            }
            output.toByteArray()
        }

        is Image ->
            RasterEncoder.bandedRasterCommands(bitmap, bandHeight)
                .fold(ByteArray(0)) { accumulator, command -> accumulator + command }

        is Barcode ->
            Escpos.align(Escpos.Alignment.CENTER) +
                Escpos.barcodeHeight(height) +
                Escpos.barcodeWidth(2) +
                Escpos.barcodeTextPosition(2) +
                Escpos.barcode(content, type) +
                Escpos.lineFeed +
                Escpos.align(Escpos.Alignment.LEFT)

        is QrCode ->
            Escpos.align(Escpos.Alignment.CENTER) +
                Escpos.qrCode(content, moduleSize) +
                Escpos.lineFeed +
                Escpos.align(Escpos.Alignment.LEFT)

        is Separator -> Escpos.line(character.toString().repeat(columns))

        is Feed -> Escpos.feedLines(lines)

        is Raw -> bytes
    }
}

/**
 * Document d'impression compose d'elements de haut niveau.
 *
 * C'est le point d'entree de la librairie: on decrit ce que l'on veut
 * imprimer, puis [PrintJobBuilder] transforme le document en octets pour
 * l'imprimante. Le document est independant du transport (BLE, USB, SPP).
 *
 * ```kotlin
 * val document = PrintDocument()
 * document.append(PrintElement.title("BOULANGERIE"))
 * document.append(PrintElement.Separator())
 * document.append(PrintElement.Text("Baguette          1,20 EUR"))
 * document.append(PrintElement.Image(CodeBitmaps.qrCode("https://exemple.fr")))
 * document.append(PrintElement.Feed(3))
 * val bytes = PrintJobBuilder.bytes(document, PrintOptions())
 * ```
 */
class PrintDocument(elements: List<PrintElement> = emptyList()) {
    private val _elements: MutableList<PrintElement> = elements.toMutableList()

    val elements: List<PrintElement> get() = _elements.toList()

    fun append(element: PrintElement) {
        _elements.add(element)
    }

    operator fun plus(other: PrintDocument): PrintDocument =
        PrintDocument(elements + other.elements)

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is PrintDocument) return false
        return elements == other.elements
    }

    override fun hashCode(): Int = elements.hashCode()
}
