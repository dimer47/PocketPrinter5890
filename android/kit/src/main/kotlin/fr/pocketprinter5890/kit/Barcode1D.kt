package fr.pocketprinter5890.kit

/** Erreurs de generation d'un code-barres lineaire. */
sealed class BarcodeException(message: String) : Exception(message) {
    object EmptyContent : BarcodeException("Contenu vide") {
        private fun readResolve(): Any = EmptyContent
    }

    class UnsupportedCharacter(character: Char, symbology: Barcode1D.Symbology) :
        BarcodeException("Caractere '$character' non supporte en ${symbology.title}")

    class InvalidLength(expected: String, actual: Int) :
        BarcodeException("Longueur invalide: $actual chiffres au lieu de $expected")

    object InvalidCheckDigit : BarcodeException("Cle de controle invalide") {
        private fun readResolve(): Any = InvalidCheckDigit
    }
}

/**
 * Codes-barres lineaires generes en Kotlin pur.
 *
 * Le firmware A2Y n'implemente pas `GS k`: la commande native s'imprime en
 * clair. Ces motifs sont donc convertis en bitmap puis envoyes en raster,
 * comme le fait l'application officielle.
 */
object Barcode1D {

    enum class Symbology(val title: String) {
        CODE128("Code 128"),
        CODE39("Code 39"),
        EAN13("EAN-13"),
        EAN8("EAN-8")
    }

    /**
     * Motif de barres: `true` = barre noire, `false` = espace.
     *
     * Un module vaut une entree; la largeur physique est appliquee ensuite.
     */
    @Throws(BarcodeException::class)
    fun pattern(content: String, symbology: Symbology): BooleanArray {
        if (content.isEmpty()) throw BarcodeException.EmptyContent
        return when (symbology) {
            Symbology.CODE128 -> code128Pattern(content)
            Symbology.CODE39 -> code39Pattern(content)
            Symbology.EAN13 -> eanPattern(content, 13)
            Symbology.EAN8 -> eanPattern(content, 8)
        }
    }

    // MARK: - Code 128

    /**
     * Tables de Code 128: 107 motifs de 11 modules chacun.
     *
     * Chaque entree encode les largeurs successives barre/espace.
     */
    private val code128Widths: Array<IntArray> = arrayOf(
        intArrayOf(2,1,2,2,2,2), intArrayOf(2,2,2,1,2,2), intArrayOf(2,2,2,2,2,1),
        intArrayOf(1,2,1,2,2,3), intArrayOf(1,2,1,3,2,2), intArrayOf(1,3,1,2,2,2),
        intArrayOf(1,2,2,2,1,3), intArrayOf(1,2,2,3,1,2), intArrayOf(1,3,2,2,1,2),
        intArrayOf(2,2,1,2,1,3), intArrayOf(2,2,1,3,1,2), intArrayOf(2,3,1,2,1,2),
        intArrayOf(1,1,2,2,3,2), intArrayOf(1,2,2,1,3,2), intArrayOf(1,2,2,2,3,1),
        intArrayOf(1,1,3,2,2,2), intArrayOf(1,2,3,1,2,2), intArrayOf(1,2,3,2,2,1),
        intArrayOf(2,2,3,2,1,1), intArrayOf(2,2,1,1,3,2), intArrayOf(2,2,1,2,3,1),
        intArrayOf(2,1,3,2,1,2), intArrayOf(2,2,3,1,1,2), intArrayOf(3,1,2,1,3,1),
        intArrayOf(3,1,1,2,2,2), intArrayOf(3,2,1,1,2,2), intArrayOf(3,2,1,2,2,1),
        intArrayOf(3,1,2,2,1,2), intArrayOf(3,2,2,1,1,2), intArrayOf(3,2,2,2,1,1),
        intArrayOf(2,1,2,1,2,3), intArrayOf(2,1,2,3,2,1), intArrayOf(2,3,2,1,2,1),
        intArrayOf(1,1,1,3,2,3), intArrayOf(1,3,1,1,2,3), intArrayOf(1,3,1,3,2,1),
        intArrayOf(1,1,2,3,1,3), intArrayOf(1,3,2,1,1,3), intArrayOf(1,3,2,3,1,1),
        intArrayOf(2,1,1,3,1,3), intArrayOf(2,3,1,1,1,3), intArrayOf(2,3,1,3,1,1),
        intArrayOf(1,1,2,1,3,3), intArrayOf(1,1,2,3,3,1), intArrayOf(1,3,2,1,3,1),
        intArrayOf(1,1,3,1,2,3), intArrayOf(1,1,3,3,2,1), intArrayOf(1,3,3,1,2,1),
        intArrayOf(3,1,3,1,2,1), intArrayOf(2,1,1,3,3,1), intArrayOf(2,3,1,1,3,1),
        intArrayOf(2,1,3,1,1,3), intArrayOf(2,1,3,3,1,1), intArrayOf(2,1,3,1,3,1),
        intArrayOf(3,1,1,1,2,3), intArrayOf(3,1,1,3,2,1), intArrayOf(3,3,1,1,2,1),
        intArrayOf(3,1,2,1,1,3), intArrayOf(3,1,2,3,1,1), intArrayOf(3,3,2,1,1,1),
        intArrayOf(3,1,4,1,1,1), intArrayOf(2,2,1,4,1,1), intArrayOf(4,3,1,1,1,1),
        intArrayOf(1,1,1,2,2,4), intArrayOf(1,1,1,4,2,2), intArrayOf(1,2,1,1,2,4),
        intArrayOf(1,2,1,4,2,1), intArrayOf(1,4,1,1,2,2), intArrayOf(1,4,1,2,2,1),
        intArrayOf(1,1,2,2,1,4), intArrayOf(1,1,2,4,1,2), intArrayOf(1,2,2,1,1,4),
        intArrayOf(1,2,2,4,1,1), intArrayOf(1,4,2,1,1,2), intArrayOf(1,4,2,2,1,1),
        intArrayOf(2,4,1,2,1,1), intArrayOf(2,2,1,1,1,4), intArrayOf(4,1,3,1,1,1),
        intArrayOf(2,4,1,1,1,2), intArrayOf(1,3,4,1,1,1), intArrayOf(1,1,1,2,4,2),
        intArrayOf(1,2,1,1,4,2), intArrayOf(1,2,1,2,4,1), intArrayOf(1,1,4,2,1,2),
        intArrayOf(1,2,4,1,1,2), intArrayOf(1,2,4,2,1,1), intArrayOf(4,1,1,2,1,2),
        intArrayOf(4,2,1,1,1,2), intArrayOf(4,2,1,2,1,1), intArrayOf(2,1,2,1,4,1),
        intArrayOf(2,1,4,1,2,1), intArrayOf(4,1,2,1,2,1), intArrayOf(1,1,1,1,4,3),
        intArrayOf(1,1,1,3,4,1), intArrayOf(1,3,1,1,4,1), intArrayOf(1,1,4,1,1,3),
        intArrayOf(1,1,4,3,1,1), intArrayOf(4,1,1,1,1,3), intArrayOf(4,1,1,3,1,1),
        intArrayOf(1,1,3,1,4,1), intArrayOf(1,1,4,1,3,1), intArrayOf(3,1,1,1,4,1),
        intArrayOf(4,1,1,1,3,1), intArrayOf(2,1,1,4,1,2), intArrayOf(2,1,1,2,1,4),
        intArrayOf(2,1,1,2,3,2), intArrayOf(2,3,3,1,1,1,2)
    )

    @Throws(BarcodeException::class)
    private fun code128Pattern(content: String): BooleanArray {
        // Jeu B: ASCII 32 a 126.
        val values = mutableListOf<Int>()
        for (character in content) {
            val code = character.code
            if (code < 32 || code > 126) {
                throw BarcodeException.UnsupportedCharacter(character, Symbology.CODE128)
            }
            values.add(code - 32)
        }

        val startB = 104
        var checksum = startB
        values.forEachIndexed { index, value -> checksum += value * (index + 1) }
        checksum %= 103

        val symbols = listOf(startB) + values + listOf(checksum, 106)
        return modules(symbols.map { code128Widths[it] })
    }

    // MARK: - Code 39

    /** Chaque caractere est code sur 9 elements, dont 3 larges. */
    private val code39Table: Map<Char, String> = mapOf(
        '0' to "000110100", '1' to "100100001", '2' to "001100001", '3' to "101100000",
        '4' to "000110001", '5' to "100110000", '6' to "001110000", '7' to "000100101",
        '8' to "100100100", '9' to "001100100", 'A' to "100001001", 'B' to "001001001",
        'C' to "101001000", 'D' to "000011001", 'E' to "100011000", 'F' to "001011000",
        'G' to "000001101", 'H' to "100001100", 'I' to "001001100", 'J' to "000011100",
        'K' to "100000011", 'L' to "001000011", 'M' to "101000010", 'N' to "000010011",
        'O' to "100010010", 'P' to "001010010", 'Q' to "000000111", 'R' to "100000110",
        'S' to "001000110", 'T' to "000010110", 'U' to "110000001", 'V' to "011000001",
        'W' to "111000000", 'X' to "010010001", 'Y' to "110010000", 'Z' to "011010000",
        '-' to "010000101", '.' to "110000100", ' ' to "011000100", '$' to "010101000",
        '/' to "010100010", '+' to "010001010", '%' to "000101010", '*' to "010010100"
    )

    @Throws(BarcodeException::class)
    private fun code39Pattern(content: String): BooleanArray {
        val upper = content.uppercase()
        val encoded = mutableListOf("010010100") // caractere de depart '*'
        for (character in upper) {
            val entry = code39Table[character]
            if (entry == null || character == '*') {
                throw BarcodeException.UnsupportedCharacter(character, Symbology.CODE39)
            }
            encoded.add(entry)
        }
        encoded.add("010010100") // caractere de fin '*'

        val pattern = mutableListOf<Boolean>()
        encoded.forEachIndexed { index, entry ->
            if (index > 0) pattern.add(false) // separateur inter-caractere
            entry.forEachIndexed { position, flag ->
                // Elements pairs: barres. Impairs: espaces.
                val isBar = position % 2 == 0
                val width = if (flag == '1') 3 else 1
                repeat(width) { pattern.add(isBar) }
            }
        }
        return pattern.toBooleanArray()
    }

    // MARK: - EAN 13 et EAN 8

    private val eanLeftOdd = arrayOf(
        "0001101", "0011001", "0010011", "0111101", "0100011",
        "0110001", "0101111", "0111011", "0110111", "0001011"
    )
    private val eanLeftEven = arrayOf(
        "0100111", "0110011", "0011011", "0100001", "0011101",
        "0111001", "0000101", "0010001", "0001001", "0010111"
    )
    private val eanRight = arrayOf(
        "1110010", "1100110", "1101100", "1000010", "1011100",
        "1001110", "1010000", "1000100", "1001000", "1110100"
    )

    /** Parite des six chiffres de gauche selon le premier chiffre. */
    private val eanParity = arrayOf(
        "OOOOOO", "OOEOEE", "OOEEOE", "OOEEEO", "OEOOEE",
        "OEEOOE", "OEEEOO", "OEOEOE", "OEOEEO", "OEEOEO"
    )

    @Throws(BarcodeException::class)
    private fun eanPattern(content: String, count: Int): BooleanArray {
        val symbology = if (count == 13) Symbology.EAN13 else Symbology.EAN8
        val characters = content.toMutableList()
        for (character in characters) {
            if (!character.isDigit()) {
                throw BarcodeException.UnsupportedCharacter(character, symbology)
            }
        }

        // La cle de controle est calculee si elle manque, verifiee sinon.
        if (characters.size == count - 1) {
            characters.add(checkDigit(characters.map { it.digitToInt() }).digitToChar())
        }
        if (characters.size != count) {
            throw BarcodeException.InvalidLength("${count - 1} ou $count", characters.size)
        }
        val values = characters.map { it.digitToInt() }
        if (checkDigit(values.dropLast(1)) != values[count - 1]) {
            throw BarcodeException.InvalidCheckDigit
        }

        val bits = StringBuilder("101") // garde de depart
        if (count == 13) {
            val parity = eanParity[values[0]]
            for (index in 1..6) {
                val table = if (parity[index - 1] == 'O') eanLeftOdd else eanLeftEven
                bits.append(table[values[index]])
            }
            bits.append("01010") // garde centrale
            for (index in 7..12) bits.append(eanRight[values[index]])
        } else {
            for (index in 0..3) bits.append(eanLeftOdd[values[index]])
            bits.append("01010")
            for (index in 4..7) bits.append(eanRight[values[index]])
        }
        bits.append("101") // garde de fin

        return BooleanArray(bits.length) { bits[it] == '1' }
    }

    /** Cle de controle EAN, valable pour EAN-8 et EAN-13. */
    fun checkDigit(digits: List<Int>): Int {
        var sum = 0
        // Le poids alterne 3/1 en partant de la droite.
        digits.reversed().forEachIndexed { index, digit ->
            sum += digit * (if (index % 2 == 0) 3 else 1)
        }
        return (10 - sum % 10) % 10
    }

    // MARK: - Aides

    /** Convertit des largeurs alternees barre/espace en modules booleens. */
    private fun modules(widths: List<IntArray>): BooleanArray {
        val pattern = mutableListOf<Boolean>()
        for (symbol in widths) {
            symbol.forEachIndexed { index, width ->
                repeat(width) { pattern.add(index % 2 == 0) }
            }
        }
        return pattern.toBooleanArray()
    }
}
