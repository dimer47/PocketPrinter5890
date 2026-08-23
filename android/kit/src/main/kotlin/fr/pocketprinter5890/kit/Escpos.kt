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

    /**
     * Substitutions explicites pour les symboles courants.
     *
     * Sans entree ici, un caractere non ASCII sans diacritique a retirer
     * finit en « ? » sur le papier. Les traitements de texte en produisent
     * beaucoup sans qu'on les tape: espaces insecables avant les deux-points
     * en francais, tirets typographiques, guillemets courbes.
     */
    private val asciiReplacements: Map<Char, String> = mapOf(
        // Monnaies et unites
        '\u00B0' to "deg", '\u20AC' to "EUR", '\u00A3' to "GBP", '\u00A5' to "JPY", '\u00A2' to "c",
        '\u2116' to "No",

        // Guillemets et apostrophes
        '\u00AB' to "\"", '\u00BB' to "\"", '\u2018' to "'", '\u2019' to "'",
        '\u201C' to "\"", '\u201D' to "\"", '\u201A' to ",", '\u201E' to "\"",
        '\u2039' to "<", '\u203A' to ">",
        '\u2032' to "'", '\u2033' to "\"",

        // Tirets: la famille est large, et un traitement de texte substitue
        // volontiers le cadratin a deux traits d'union.
        '\u2010' to "-", '\u2011' to "-", '\u2012' to "-",
        '\u2013' to "-", '\u2014' to "-", '\u2015' to "-",
        '\u2212' to "-", '\u00AD' to "",

        // Espaces: insecables et fines. Sans conversion, chacune devient un
        // « ? » au milieu d'une phrase — le cas le plus visible en francais,
        // ou l'espace insecable precede « : » et « » ».
        '\u00A0' to " ", '\u202F' to " ", '\u2009' to " ",
        '\u2007' to " ", '\u2008' to " ", '\u200A' to " ", '\u2002' to " ",
        '\u2003' to " ", '\u200B' to "",

        // Ponctuation et signes
        '\u2026' to "...", '\u00D7' to "x", '\u00F7' to "/", '\u00B1' to "+/-",
        '\u2044' to "/", '\u00A7' to "S", '\u00B6' to "P",
        '\u2020' to "+", '\u2021' to "++", '\u00B7' to "-",
        '\u2022' to "-", '\u00A9' to "(c)", '\u00AE' to "(R)",
        '\u2122' to "(TM)", '\u00BF' to "?", '\u00A1' to "!",

        // Comparaisons et fleches
        '\u2264' to "<=", '\u2265' to ">=", '\u2260' to "!=",
        '\u2192' to "->", '\u2190' to "<-", '\u2194' to "<->",
        '\u21D2' to "=>", '\u221E' to "inf",

        // Cases a cocher: une liste de taches copiee depuis une note garde
        // sa forme, et l'etat de chaque case reste lisible sur le papier.
        '\u2610' to "[ ]", '\u2611' to "[x]", '\u2612' to "[x]",
        '\u25A2' to "[ ]", '\u2751' to "[ ]", '\u2752' to "[ ]",

        // Symboles pleins: sans equivalent ASCII, on garde une trace visible
        // plutot qu'un point d'interrogation.
        '\u2713' to "v", '\u2714' to "v", '\u2717' to "x", '\u2718' to "x",
        '\u25CF' to "*", '\u25CB' to "o", '\u25A0' to "#", '\u25A1' to "#",
        '\u2605' to "*", '\u2606' to "*",

        // Fractions et exposants
        '\u00BC' to "1/4", '\u00BD' to "1/2", '\u00BE' to "3/4",
        '\u2153' to "1/3", '\u2154' to "2/3",
        '\u00B2' to "2", '\u00B3' to "3", '\u00B9' to "1",

        // Ligatures
        '\u0153' to "oe", '\u0152' to "OE", '\u00E6' to "ae", '\u00C6' to "AE", '\u00DF' to "ss",
        '\u0133' to "ij", '\u0132' to "IJ"
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
        // Parcours par point de code: un `Char` ne fait que 16 bits, et un
        // emoji arriverait en deux moities indechiffrables.
        var index = 0
        while (index < text.length) {
            val point = text.codePointAt(index)
            val largeur = Character.charCount(point)
            val morceau = text.substring(index, index + largeur)
            index += largeur

            if (point < 128) {
                result.append(morceau)
                continue
            }
            if (largeur == 1) {
                val replacement = asciiReplacements[morceau[0]]
                if (replacement != null) {
                    result.append(replacement)
                    continue
                }
            }
            // Retrait des diacritiques: "é" -> "e", "ç" -> "c".
            val folded = java.text.Normalizer
                .normalize(morceau, java.text.Normalizer.Form.NFD)
                .replace(Regex("\\p{Mn}+"), "")
            if (folded.all { it.code < 128 } && folded.isNotEmpty()) {
                result.append(folded)
                continue
            }
            result.append(categoryFallback(point))
        }
        return result.toString()
    }

    /**
     * Que faire d'un caractere qu'aucune table ne couvre.
     *
     * Enumerer les caracteres un par un ne finit jamais: Unicode en compte
     * plus de 150 000, et un traitement de texte pioche largement. On se
     * rabat donc sur la categorie du caractere, qui dit son role.
     *
     * Le « ? » reste pour ce qui porte un sens qu'on ne peut pas rendre —
     * une lettre d'un autre alphabet, un ideogramme: un blanc laisserait
     * croire a un texte complet.
     */
    private fun categoryFallback(codePoint: Int): String =
        when (Character.getType(codePoint).toByte()) {
            // Espaces de toute largeur: une espace ordinaire.
            Character.SPACE_SEPARATOR,
            Character.LINE_SEPARATOR,
            Character.PARAGRAPH_SEPARATOR -> " "

            // Caracteres de controle et de mise en forme — jointures,
            // marques de direction, indicateur d'ordre des octets.
            // Invisibles par nature: ils ne laissent rien sur le papier.
            Character.FORMAT,
            Character.CONTROL,
            Character.SURROGATE,
            Character.PRIVATE_USE,
            Character.UNASSIGNED -> ""

            // Marques combinantes orphelines: le caractere de base est deja
            // passe, l'accent seul n'a rien a rendre.
            Character.NON_SPACING_MARK,
            Character.COMBINING_SPACING_MARK,
            Character.ENCLOSING_MARK -> ""

            // Puces, fleches, pictogrammes, symboles mathematiques ou
            // monetaires: une trace visible vaut mieux qu'un point
            // d'interrogation, qui se lit comme une erreur.
            Character.OTHER_PUNCTUATION,
            Character.DASH_PUNCTUATION,
            Character.OTHER_SYMBOL,
            Character.MATH_SYMBOL,
            Character.MODIFIER_SYMBOL,
            Character.CURRENCY_SYMBOL -> "-"

            // Parentheses et guillemets: garder la paire ouvrante ou fermante.
            Character.START_PUNCTUATION,
            Character.INITIAL_QUOTE_PUNCTUATION -> "("
            Character.END_PUNCTUATION,
            Character.FINAL_QUOTE_PUNCTUATION -> ")"
            Character.CONNECTOR_PUNCTUATION -> "_"

            // Lettres, chiffres et le reste: un « ? » signale honnetement le
            // caractere perdu.
            else -> "?"
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
