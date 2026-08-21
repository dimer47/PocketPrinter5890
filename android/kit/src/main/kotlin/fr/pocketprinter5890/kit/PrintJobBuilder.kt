package fr.pocketprinter5890.kit

/** Fragment nomme d'un travail d'impression, pour le journal et le debogage. */
class PrintSegment(val name: String, val bytes: ByteArray) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is PrintSegment) return false
        return name == other.name && bytes.contentEquals(other.bytes)
    }

    override fun hashCode(): Int = name.hashCode() * 31 + bytes.contentHashCode()
}

/** Densite d'impression. */
enum class PrintDensity(val value: Int, val title: String) {
    LIGHT(0, "Faible"),
    MEDIUM(1, "Moyenne"),
    STRONG(2, "Forte")
}

/** Mode de sortie papier. */
enum class PaperMode(val title: String) {
    /**
     * Rouleau continu type ticket de caisse. Ne declare pas de longueur:
     * l'imprimante s'arrete a la fin du contenu.
     */
    CONTINUOUS("Papier continu"),

    /** Etiquettes predecoupees de longueur fixe, avec calage entre chaque. */
    LABEL("Etiquettes")
}

/** Variante de form feed. Inutile sur papier continu. */
enum class FormFeedMode(val bytes: ByteArray, val title: String) {
    DOCUMENTED_POCKET_PRINTER(byteArrayOf(0x10, 0x0c), "10 0C observe"),
    STANDARD(byteArrayOf(0x0c), "0C standard")
}

/** Options appliquees a un travail d'impression. */
data class PrintOptions(
    /** Largeur d'impression. 384 px pour la machine de reference. */
    val width: PrinterWidth = PrinterWidth.MM58,
    val density: PrintDensity = PrintDensity.MEDIUM,
    /**
     * Nombre de lignes par bande raster. Le firmware perd des donnees si on
     * envoie le raster complet en une seule commande.
     */
    val bandHeight: Int = RasterEncoder.defaultBandHeight,
    /**
     * Avance de fin de travail, en points (1/203 de pouce).
     *
     * Elle degage le contenu imprime de la tete d'impression, qui se trouve en
     * retrait dans le boitier. Sans elle, la fin du ticket reste coincee sous
     * le capot et n'est pas lisible.
     *
     * Le SDK appelle cela `endLineDot` et le regle par modele: de 50 points
     * (D82S) a 144 points (PPS1H). 80 points valent environ 10 mm a 203 dpi.
     *
     * La valeur n'est pas bornee a 255: [Escpos.feed] enchaine plusieurs
     * commandes `1B 4A` quand c'est necessaire.
     */
    val trailingFeedDots: Int = 80,
    /** Envoie `ESC @` au debut du travail. */
    val sendInitialize: Boolean = true,
    /**
     * Encadre le travail par la sequence d'activation LuckPrinter.
     * Indispensable sur cette machine: sans elle le firmware acquitte les
     * commandes mais n'execute rien.
     */
    val useLuckSequence: Boolean = true,
    /**
     * Convertit les caracteres non-ASCII en equivalents ASCII.
     *
     * Le firmware n'affiche pas correctement `°` ni les lettres accentuees:
     * il imprime un carre plein. La transliteration donne « deg », « e », ce
     * qui reste lisible.
     */
    val transliterateText: Boolean = true,
    /** Mode de sortie: papier continu ou etiquettes predecoupees. */
    val paperMode: PaperMode = PaperMode.CONTINUOUS,
    /** Longueur d'etiquette passee a `1F 80`, ignoree en papier continu. */
    val labelLength: Int = 32,
    /**
     * Interroge l'etat du papier avant d'imprimer. Purement informatif: le
     * resultat ne doit jamais bloquer l'impression.
     */
    val checkPaper: Boolean = false,
    /**
     * Commandes proprietaires observees dans une capture de l'application
     * officielle, non confirmees sur ce materiel. Desactivees par defaut.
     */
    val includeExperimentalPrePrint: Boolean = false,
    val experimentalPrePrintUsesF130: Boolean = false,
    val includeExperimentalPostPrint: Boolean = false,
    /** Emet un form feed en fin de travail. Inutile sur papier continu. */
    val includeFormFeed: Boolean = false,
    val formFeed: FormFeedMode = FormFeedMode.STANDARD
) {
    /** Nombre approximatif de colonnes de texte en police A (12 px de large). */
    val textColumns: Int get() = maxOf(1, width.pixels / 12)
}

/**
 * Commandes proprietaires heritees, conservees pour la parite avec le
 * portage Swift. Preferer [LuckPrinter] pour tout nouveau code.
 */
object PrinterCommand {
    val model: ByteArray = LuckPrinter.model
    val firmware: ByteArray = LuckPrinter.firmware
    val serialNumber: ByteArray = LuckPrinter.serialNumber
    val battery: ByteArray = LuckPrinter.battery
    val paperStatus: ByteArray = LuckPrinter.status

    val experimentalPrePrintF103: ByteArray =
        byteArrayOf(0x10, 0xff.toByte(), 0xf1.toByte(), 0x03) + ByteArray(12)
    val experimentalPrePrintF130: ByteArray =
        byteArrayOf(0x10, 0xff.toByte(), 0xf1.toByte(), 0x30) + ByteArray(12)
    val experimentalPostPrint: ByteArray =
        byteArrayOf(0x10, 0xff.toByte(), 0xf1.toByte(), 0x45)

    fun setDensity(density: PrintDensity): ByteArray = LuckPrinter.setDensity(density.value)

    /**
     * Extinction automatique, sur deux octets gros-boutistes.
     * Alias de [LuckPrinter.setAutoShutdown].
     */
    fun autoShutdown(minutes: Int): ByteArray = LuckPrinter.setAutoShutdown(minutes)

    fun feedDots(dots: Int = 0x28): ByteArray = LuckPrinter.feedDots(dots)
}

/** Assemble un document en une suite de segments prets a envoyer. */
object PrintJobBuilder {

    // MARK: - Documents

    fun segments(document: PrintDocument, options: PrintOptions): List<PrintSegment> {
        val result = mutableListOf<PrintSegment>()
        result.addAll(prologue(options))

        document.elements.forEachIndexed { index, element ->
            val bytes = element.bytes(
                columns = options.textColumns,
                bandHeight = options.bandHeight,
                transliterate = options.transliterateText
            )
            if (bytes.isEmpty()) return@forEachIndexed
            result.add(PrintSegment(label(element, index), bytes))
        }

        result.addAll(epilogue(options))
        return result
    }

    fun bytes(document: PrintDocument, options: PrintOptions): ByteArray =
        segments(document, options)
            .fold(ByteArray(0)) { accumulator, segment -> accumulator + segment.bytes }

    // MARK: - Bitmap seul

    fun segments(bitmap: MonochromeBitmap, options: PrintOptions): List<PrintSegment> =
        segments(PrintDocument(listOf(PrintElement.Image(bitmap))), options)

    fun bytes(bitmap: MonochromeBitmap, options: PrintOptions): ByteArray =
        segments(bitmap, options)
            .fold(ByteArray(0)) { accumulator, segment -> accumulator + segment.bytes }

    // MARK: - Assemblage

    private fun prologue(options: PrintOptions): List<PrintSegment> {
        val result = mutableListOf<PrintSegment>()
        if (options.checkPaper) {
            result.add(PrintSegment("Verifier papier", PrinterCommand.paperStatus))
        }
        if (options.useLuckSequence) {
            result.add(PrintSegment("Activation moteur", LuckPrinter.enablePrinter()))
            result.add(PrintSegment("Reveil", LuckPrinter.wakeup))
            // `1F 80` declare une etiquette de longueur fixe: l'imprimante
            // deroule alors jusqu'a la fin de l'etiquette declaree. En papier
            // continu, l'application officielle ne l'envoie pas du tout
            // (cf. `printOnce` vs `printTagOnce` dans le SDK).
            if (options.paperMode == PaperMode.LABEL) {
                result.add(
                    PrintSegment(
                        "Longueur d'etiquette",
                        LuckPrinter.setPaperType(length = options.labelLength)
                    )
                )
            }
        }
        if (options.sendInitialize) {
            result.add(PrintSegment("Init ESC @", Escpos.initialize))
            // `ESC t` n'est pas envoye: ce firmware l'ignore et laisse un
            // octet parasite s'imprimer. Le texte est translitere en ASCII.
            if (!options.transliterateText) {
                result.add(PrintSegment("Page de code Latin-1", Escpos.codePageLatin1))
            }
        }
        result.add(
            PrintSegment(
                "Densite ${options.density.title}",
                PrinterCommand.setDensity(options.density)
            )
        )
        if (options.includeExperimentalPrePrint) {
            val bytes = if (options.experimentalPrePrintUsesF130) {
                PrinterCommand.experimentalPrePrintF130
            } else {
                PrinterCommand.experimentalPrePrintF103
            }
            result.add(PrintSegment("Pre-impression experimentale", bytes))
        }
        return result
    }

    private fun epilogue(options: PrintOptions): List<PrintSegment> {
        val result = mutableListOf<PrintSegment>()
        if (options.includeFormFeed) {
            result.add(
                PrintSegment("Form feed ${options.formFeed.title}", options.formFeed.bytes)
            )
        }
        if (options.trailingFeedDots > 0) {
            result.add(
                PrintSegment(
                    "Degagement ${options.trailingFeedDots} points",
                    Escpos.feed(options.trailingFeedDots)
                )
            )
        }
        if (options.useLuckSequence) {
            // `1D 0C` cale l'etiquette suivante; sur papier continu il ne fait
            // que gaspiller du papier.
            if (options.paperMode == PaperMode.LABEL) {
                result.add(PrintSegment("Calage etiquette", LuckPrinter.position))
            }
            result.add(PrintSegment("Fin du travail", LuckPrinter.stopPrintJob))
        }
        if (options.includeExperimentalPostPrint) {
            result.add(PrintSegment("Fin experimentale", PrinterCommand.experimentalPostPrint))
        }
        return result
    }

    private fun label(element: PrintElement, index: Int): String = when (element) {
        is PrintElement.Text -> "Texte ${index + 1}"
        is PrintElement.Image -> "Image ${element.bitmap.width}x${element.bitmap.height}"
        is PrintElement.Barcode -> "Code-barres"
        is PrintElement.QrCode -> "QR code"
        is PrintElement.Separator -> "Separateur"
        is PrintElement.Feed -> "Avance"
        is PrintElement.Raw -> "Octets bruts"
    }
}
