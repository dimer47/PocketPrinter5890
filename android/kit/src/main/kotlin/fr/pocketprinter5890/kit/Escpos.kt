package fr.pocketprinter5890.kit

import java.nio.charset.Charset

/**
 * Jeu de commandes ESC/POS standard.
 *
 * La machine cible est une mini imprimante thermique de poche de la famille
 * generique 5890. Ces machines implementent le socle ESC/POS d'Epson. Les
 * commandes proprietaires `10 FF ...` sont un complement, pas le socle.
 */
object Escpos {

    // MARK: - Initialisation

    /** `ESC @` — reinitialise l'imprimante et vide les modes de mise en forme. */
    val initialize: ByteArray = byteArrayOf(0x1b, 0x40)

    // MARK: - Alignement

    enum class Alignment(val value: Int, val title: String) {
        LEFT(0, "Gauche"),
        CENTER(1, "Centre"),
        RIGHT(2, "Droite")
    }

    /** `ESC a n` */
    fun align(alignment: Alignment): ByteArray =
        byteArrayOf(0x1b, 0x61, alignment.value.toByte())

    // MARK: - Styles de texte

    /**
     * `ESC E n` — gras.
     *
     * Attention: le firmware A2Y **accepte la commande sans l'appliquer**.
     * Constate sur papier depuis Android et depuis macOS/iOS. Pour du gras
     * reellement visible, rendre le texte en image et l'envoyer en raster,
     * comme le fait l'application officielle pour tout son texte.
     */
    fun bold(enabled: Boolean): ByteArray =
        byteArrayOf(0x1b, 0x45, if (enabled) 1 else 0)

    /** `ESC - n` — 0 aucun, 1 fin, 2 epais. */
    fun underline(thickness: Int): ByteArray =
        byteArrayOf(0x1b, 0x2d, minOf(thickness, 2).toByte())

    /** `ESC { n` — impression tete-beche. */
    fun upsideDown(enabled: Boolean): ByteArray =
        byteArrayOf(0x1b, 0x7b, if (enabled) 1 else 0)

    /**
     * `GS B n` — inversion video (blanc sur noir).
     *
     * Attention: sans effet visible sur le firmware A2Y.
     */
    fun inverted(enabled: Boolean): ByteArray =
        byteArrayOf(0x1d, 0x42, if (enabled) 1 else 0)

    /** `GS ! n` — multiplicateur de taille, 1 a 8 sur chaque axe. */
    fun textSize(width: Int, height: Int): ByteArray {
        val w = maxOf(1, minOf(8, width)) - 1
        val h = maxOf(1, minOf(8, height)) - 1
        return byteArrayOf(0x1d, 0x21, ((w shl 4) or h).toByte())
    }

    // MARK: - Avance papier

    /** `LF` */
    val lineFeed: ByteArray = byteArrayOf(0x0a)

    /** `ESC d n` — avance de n lignes. */
    fun feedLines(lines: Int): ByteArray =
        byteArrayOf(0x1b, 0x64, (lines and 0xff).toByte())

    /** `ESC J n` — avance de n points (1/203 pouce), maximum 255. */
    fun feedDots(dots: Int): ByteArray =
        byteArrayOf(0x1b, 0x4a, (dots and 0xff).toByte())

    /**
     * Avance d'un nombre de points quelconque.
     *
     * `ESC J` ne prend qu'un octet: au-dela de 255 points (~32 mm) la commande
     * est repetee autant de fois que necessaire.
     */
    fun feed(dots: Int): ByteArray {
        if (dots <= 0) return ByteArray(0)
        var remaining = dots
        val output = mutableListOf<Byte>()
        while (remaining > 0) {
            val step = minOf(remaining, 255)
            output.addAll(feedDots(step).toList())
            remaining -= step
        }
        return output.toByteArray()
    }

    /** `ESC 2` — interligne par defaut. */
    val defaultLineSpacing: ByteArray = byteArrayOf(0x1b, 0x32)

    /** `ESC 3 n` — interligne de n points. */
    fun lineSpacing(dots: Int): ByteArray =
        byteArrayOf(0x1b, 0x33, (dots and 0xff).toByte())

    // MARK: - Jeu de caracteres

    /** `ESC t n` — page de code. 16 = WPC1252 (Europe de l'Ouest). */
    fun codePage(page: Int): ByteArray =
        byteArrayOf(0x1b, 0x74, (page and 0xff).toByte())

    /**
     * Page de code Windows-1252, adaptee au francais.
     *
     * Attention: le firmware A2Y **ignore** `ESC t` et laisse meme un octet
     * parasite s'imprimer (un `a` devant la ligne suivante). Une mire testant
     * les neuf pages de code a donne neuf lignes identiques, toutes
     * illisibles. Ne pas envoyer cette commande a cette machine: utiliser
     * [transliterate] a la place.
     */
    val codePageLatin1: ByteArray = codePage(16)

    /** Pages de code candidates pour le francais, avec leur numero ESC/POS. */
    enum class CodePageCandidate(val value: Int, val title: String) {
        PC437_USA(0, "PC437 (USA)"),
        KATAKANA(1, "Katakana"),
        PC850_MULTILINGUAL(2, "PC850 (multilingue)"),
        PC860_PORTUGUESE(3, "PC860 (portugais)"),
        PC863_CANADIAN(4, "PC863 (canadien)"),
        PC865_NORDIC(5, "PC865 (nordique)"),
        WESTERN_EUROPEAN(6, "Europe de l'Ouest"),
        PC858_EURO(19, "PC858 (euro)"),
        WPC1252(16, "WPC1252")
    }

    /** Substitutions explicites pour les symboles courants. */
    private val asciiReplacements: Map<Char, String> = mapOf(
        '°' to "deg", '€' to "EUR", '£' to "GBP", '¥' to "JPY",
        '«' to "\"", '»' to "\"", '‘' to "'", '’' to "'",
        '“' to "\"", '”' to "\"", '–' to "-", '—' to "-",
        '…' to "...", '×' to "x", '÷' to "/", '±' to "+/-",
        '¼' to "1/4", '½' to "1/2", '¾' to "3/4", '²' to "2", '³' to "3",
        'œ' to "oe", 'Œ' to "OE", 'æ' to "ae", 'Æ' to "AE", 'ß' to "ss"
    )

    /**
     * Translitere le texte en ASCII pur.
     *
     * Repli sur pour un firmware dont on ne connait pas la table: `°` devient
     * `deg`, les lettres accentuees perdent leur diacritique. Mieux vaut un
     * texte legerement approximatif qu'un carre illisible.
     */
    fun transliterate(text: String): String {
        val result = StringBuilder()
        for (character in text) {
            if (character.code < 128) {
                result.append(character)
                continue
            }
            val replacement = asciiReplacements[character]
            if (replacement != null) {
                result.append(replacement)
                continue
            }
            // Retrait des diacritiques: "é" -> "e", "ç" -> "c".
            val folded = java.text.Normalizer
                .normalize(character.toString(), java.text.Normalizer.Form.NFD)
                .replace(Regex("\\p{Mn}+"), "")
            result.append(if (folded.all { it.code < 128 } && folded.isNotEmpty()) folded else "?")
        }
        return result.toString()
    }

    private val cp1252: Charset = Charset.forName("windows-1252")

    /** Encode du texte en CP1252 avec repli ASCII sur les caracteres non representables. */
    fun encode(text: String): ByteArray {
        if (cp1252.newEncoder().canEncode(text)) {
            return text.toByteArray(cp1252)
        }
        // Repli: on retire les diacritiques puis on force l'ASCII.
        val folded = java.text.Normalizer
            .normalize(text, java.text.Normalizer.Form.NFD)
            .replace(Regex("\\p{Mn}+"), "")
        if (cp1252.newEncoder().canEncode(folded)) {
            return folded.toByteArray(cp1252)
        }
        return ByteArray(folded.length) { index ->
            val code = folded[index].code
            if (code < 128) code.toByte() else 0x3f
        }
    }

    /** Texte suivi d'un saut de ligne. */
    fun line(text: String): ByteArray = encode(text) + lineFeed

    // MARK: - Codes-barres
    //
    // Ces commandes font partie du standard ESC/POS mais ne sont pas
    // implementees par tous les firmwares. Sur l'A2Y de cette machine, elles
    // s'impriment en clair au lieu d'etre interpretees. L'application
    // officielle ne les utilise pas non plus: elle genere les codes en image
    // avec ZXing puis les imprime en raster.
    //
    // Voir CodeBitmaps pour la voie fiable.

    enum class BarcodeType(val value: Int) {
        UPC_A(65),
        UPC_E(66),
        EAN13(67),
        EAN8(68),
        CODE39(69),
        ITF(70),
        CODABAR(71),
        CODE93(72),
        CODE128(73)
    }

    /** `GS h n` — hauteur du code-barres en points. */
    fun barcodeHeight(dots: Int): ByteArray =
        byteArrayOf(0x1d, 0x68, maxOf(1, dots).toByte())

    /** `GS w n` — largeur de module, 2 a 6. */
    fun barcodeWidth(width: Int): ByteArray =
        byteArrayOf(0x1d, 0x77, maxOf(2, minOf(6, width)).toByte())

    /** `GS H n` — position du texte lisible. 0 aucun, 1 dessus, 2 dessous, 3 les deux. */
    fun barcodeTextPosition(position: Int): ByteArray =
        byteArrayOf(0x1d, 0x48, minOf(position, 3).toByte())

    /** `GS k m n <data>` — variante avec longueur explicite. */
    fun barcode(content: String, type: BarcodeType = BarcodeType.CODE128): ByteArray {
        var payload = content.toByteArray(Charsets.UTF_8)
        if (type == BarcodeType.CODE128) {
            // Jeu de caracteres B par defaut, requis par le format GS k etendu.
            payload = byteArrayOf(0x7b, 0x42) + payload
        }
        val length = minOf(payload.size, 255)
        return byteArrayOf(0x1d, 0x6b, type.value.toByte(), length.toByte()) +
            payload.copyOfRange(0, length)
    }

    // MARK: - QR code

    /**
     * Sequence complete de generation d'un QR code.
     *
     * @param moduleSize taille d'un module, 1 a 16.
     * @param errorCorrection 48 = L, 49 = M, 50 = Q, 51 = H.
     */
    fun qrCode(
        content: String,
        moduleSize: Int = 6,
        errorCorrection: Int = 49
    ): ByteArray {
        val data = content.toByteArray(Charsets.UTF_8)
        // Longueur = donnees + 3 octets d'en-tete de la fonction 80.
        val length = data.size + 3
        val pL = (length and 0xff).toByte()
        val pH = ((length shr 8) and 0xff).toByte()

        // Fonction 165: modele de symbole (2).
        return byteArrayOf(0x1d, 0x28, 0x6b, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00) +
            // Fonction 167: taille du module.
            byteArrayOf(
                0x1d, 0x28, 0x6b, 0x03, 0x00, 0x31, 0x43,
                maxOf(1, minOf(16, moduleSize)).toByte()
            ) +
            // Fonction 169: niveau de correction d'erreur.
            byteArrayOf(0x1d, 0x28, 0x6b, 0x03, 0x00, 0x31, 0x45, errorCorrection.toByte()) +
            // Fonction 180: stockage des donnees dans le tampon.
            byteArrayOf(0x1d, 0x28, 0x6b, pL, pH, 0x31, 0x50, 0x30) + data +
            // Fonction 181: impression du tampon.
            byteArrayOf(0x1d, 0x28, 0x6b, 0x03, 0x00, 0x31, 0x51, 0x30)
    }

    // MARK: - Statut

    /** `DLE EOT n` — demande de statut temps reel. */
    fun realTimeStatus(kind: Int): ByteArray =
        byteArrayOf(0x10, 0x04, minOf(maxOf(kind, 1), 4).toByte())
}
