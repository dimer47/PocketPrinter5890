import Foundation

/// Generateurs de codes-barres lineaires en Swift pur.
///
/// Aucune dependance a CoreImage, AppKit ni a une bibliotheque externe: le
/// code produit directement le motif de barres, ce qui rend la librairie
/// portable (Linux, CLI, serveur) et permet de couvrir des symbologies que
/// CoreImage n'offre pas.
///
/// Le firmware de cette imprimante n'implemente pas la commande ESC/POS
/// native `GS k`: elle s'imprime en clair. Passer par une image est donc la
/// seule voie fiable, et c'est aussi ce que fait l'application officielle.
public enum Barcode1D {

    public enum Symbology: String, CaseIterable, Identifiable, Sendable {
        case code128
        case code39
        case ean13
        case ean8

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .code128: return "Code 128"
            case .code39: return "Code 39"
            case .ean13: return "EAN-13"
            case .ean8: return "EAN-8"
            }
        }
    }

    public enum BarcodeError: Error, LocalizedError, Equatable {
        case emptyContent
        case unsupportedCharacter(Character, Symbology)
        case invalidLength(expected: String, actual: Int)
        case invalidCheckDigit

        public var errorDescription: String? {
            switch self {
            case .emptyContent:
                return "Contenu vide"
            case .unsupportedCharacter(let character, let symbology):
                return "Caractere '\(character)' non supporte en \(symbology.title)"
            case .invalidLength(let expected, let actual):
                return "Longueur invalide: \(actual) chiffres au lieu de \(expected)"
            case .invalidCheckDigit:
                return "Cle de controle invalide"
            }
        }
    }

    /// Motif de barres: `true` = barre noire, `false` = espace.
    ///
    /// Un module vaut une entree; la largeur physique est appliquee ensuite.
    public static func pattern(for content: String, symbology: Symbology) throws -> [Bool] {
        guard !content.isEmpty else { throw BarcodeError.emptyContent }
        switch symbology {
        case .code128: return try code128Pattern(content)
        case .code39: return try code39Pattern(content)
        case .ean13: return try eanPattern(content, digits: 13)
        case .ean8: return try eanPattern(content, digits: 8)
        }
    }

    // MARK: - Code 128

    /// Tables de Code 128: 107 motifs de 11 modules chacun.
    ///
    /// Chaque entree encode les largeurs successives barre/espace.
    private static let code128Widths: [[Int]] = [
        [2,1,2,2,2,2],[2,2,2,1,2,2],[2,2,2,2,2,1],[1,2,1,2,2,3],[1,2,1,3,2,2],
        [1,3,1,2,2,2],[1,2,2,2,1,3],[1,2,2,3,1,2],[1,3,2,2,1,2],[2,2,1,2,1,3],
        [2,2,1,3,1,2],[2,3,1,2,1,2],[1,1,2,2,3,2],[1,2,2,1,3,2],[1,2,2,2,3,1],
        [1,1,3,2,2,2],[1,2,3,1,2,2],[1,2,3,2,2,1],[2,2,3,2,1,1],[2,2,1,1,3,2],
        [2,2,1,2,3,1],[2,1,3,2,1,2],[2,2,3,1,1,2],[3,1,2,1,3,1],[3,1,1,2,2,2],
        [3,2,1,1,2,2],[3,2,1,2,2,1],[3,1,2,2,1,2],[3,2,2,1,1,2],[3,2,2,2,1,1],
        [2,1,2,1,2,3],[2,1,2,3,2,1],[2,3,2,1,2,1],[1,1,1,3,2,3],[1,3,1,1,2,3],
        [1,3,1,3,2,1],[1,1,2,3,1,3],[1,3,2,1,1,3],[1,3,2,3,1,1],[2,1,1,3,1,3],
        [2,3,1,1,1,3],[2,3,1,3,1,1],[1,1,2,1,3,3],[1,1,2,3,3,1],[1,3,2,1,3,1],
        [1,1,3,1,2,3],[1,1,3,3,2,1],[1,3,3,1,2,1],[3,1,3,1,2,1],[2,1,1,3,3,1],
        [2,3,1,1,3,1],[2,1,3,1,1,3],[2,1,3,3,1,1],[2,1,3,1,3,1],[3,1,1,1,2,3],
        [3,1,1,3,2,1],[3,3,1,1,2,1],[3,1,2,1,1,3],[3,1,2,3,1,1],[3,3,2,1,1,1],
        [3,1,4,1,1,1],[2,2,1,4,1,1],[4,3,1,1,1,1],[1,1,1,2,2,4],[1,1,1,4,2,2],
        [1,2,1,1,2,4],[1,2,1,4,2,1],[1,4,1,1,2,2],[1,4,1,2,2,1],[1,1,2,2,1,4],
        [1,1,2,4,1,2],[1,2,2,1,1,4],[1,2,2,4,1,1],[1,4,2,1,1,2],[1,4,2,2,1,1],
        [2,4,1,2,1,1],[2,2,1,1,1,4],[4,1,3,1,1,1],[2,4,1,1,1,2],[1,3,4,1,1,1],
        [1,1,1,2,4,2],[1,2,1,1,4,2],[1,2,1,2,4,1],[1,1,4,2,1,2],[1,2,4,1,1,2],
        [1,2,4,2,1,1],[4,1,1,2,1,2],[4,2,1,1,1,2],[4,2,1,2,1,1],[2,1,2,1,4,1],
        [2,1,4,1,2,1],[4,1,2,1,2,1],[1,1,1,1,4,3],[1,1,1,3,4,1],[1,3,1,1,4,1],
        [1,1,4,1,1,3],[1,1,4,3,1,1],[4,1,1,1,1,3],[4,1,1,3,1,1],[1,1,3,1,4,1],
        [1,1,4,1,3,1],[3,1,1,1,4,1],[4,1,1,1,3,1],[2,1,1,4,1,2],[2,1,1,2,1,4],
        [2,1,1,2,3,2],[2,3,3,1,1,1,2]
    ]

    private static func code128Pattern(_ content: String) throws -> [Bool] {
        // Jeu B: ASCII 32 a 126.
        var values: [Int] = []
        for character in content {
            guard let ascii = character.asciiValue, ascii >= 32, ascii <= 126 else {
                throw BarcodeError.unsupportedCharacter(character, .code128)
            }
            values.append(Int(ascii) - 32)
        }

        let startB = 104
        var checksum = startB
        for (index, value) in values.enumerated() {
            checksum += value * (index + 1)
        }
        checksum %= 103

        let symbols = [startB] + values + [checksum, 106]
        return modules(from: symbols.map { code128Widths[$0] })
    }

    // MARK: - Code 39

    /// Chaque caractere est code sur 9 elements, dont 3 larges.
    private static let code39Table: [Character: String] = [
        "0": "000110100", "1": "100100001", "2": "001100001", "3": "101100000",
        "4": "000110001", "5": "100110000", "6": "001110000", "7": "000100101",
        "8": "100100100", "9": "001100100", "A": "100001001", "B": "001001001",
        "C": "101001000", "D": "000011001", "E": "100011000", "F": "001011000",
        "G": "000001101", "H": "100001100", "I": "001001100", "J": "000011100",
        "K": "100000011", "L": "001000011", "M": "101000010", "N": "000010011",
        "O": "100010010", "P": "001010010", "Q": "000000111", "R": "100000110",
        "S": "001000110", "T": "000010110", "U": "110000001", "V": "011000001",
        "W": "111000000", "X": "010010001", "Y": "110010000", "Z": "011010000",
        "-": "010000101", ".": "110000100", " ": "011000100", "$": "010101000",
        "/": "010100010", "+": "010001010", "%": "000101010", "*": "010010100"
    ]

    private static func code39Pattern(_ content: String) throws -> [Bool] {
        let upper = content.uppercased()
        var encoded: [String] = ["010010100"]  // caractere de depart '*'
        for character in upper {
            guard let entry = code39Table[character], character != "*" else {
                throw BarcodeError.unsupportedCharacter(character, .code39)
            }
            encoded.append(entry)
        }
        encoded.append("010010100")  // caractere de fin '*'

        var pattern: [Bool] = []
        for (index, entry) in encoded.enumerated() {
            if index > 0 { pattern.append(false) }  // separateur inter-caractere
            for (position, flag) in entry.enumerated() {
                // Elements pairs: barres. Impairs: espaces.
                let isBar = position % 2 == 0
                let width = flag == "1" ? 3 : 1
                pattern += Array(repeating: isBar, count: width)
            }
        }
        return pattern
    }

    // MARK: - EAN 13 et EAN 8

    private static let eanLeftOdd = [
        "0001101","0011001","0010011","0111101","0100011",
        "0110001","0101111","0111011","0110111","0001011"
    ]
    private static let eanLeftEven = [
        "0100111","0110011","0011011","0100001","0011101",
        "0111001","0000101","0010001","0001001","0010111"
    ]
    private static let eanRight = [
        "1110010","1100110","1101100","1000010","1011100",
        "1001110","1010000","1000100","1001000","1110100"
    ]
    /// Parite des six chiffres de gauche selon le premier chiffre.
    private static let eanParity = [
        "OOOOOO","OOEOEE","OOEEOE","OOEEEO","OEOOEE",
        "OEEOOE","OEEEOO","OEOEOE","OEOEEO","OEEOEO"
    ]

    private static func eanPattern(_ content: String, digits count: Int) throws -> [Bool] {
        var characters = Array(content)
        for character in characters where !character.isNumber {
            throw BarcodeError.unsupportedCharacter(character, count == 13 ? .ean13 : .ean8)
        }

        // La cle de controle est calculee si elle manque, verifiee sinon.
        if characters.count == count - 1 {
            characters.append(Character(String(checkDigit(characters.map { $0.wholeNumberValue ?? 0 }))))
        }
        guard characters.count == count else {
            throw BarcodeError.invalidLength(expected: "\(count - 1) ou \(count)", actual: characters.count)
        }
        let values = characters.map { $0.wholeNumberValue ?? 0 }
        guard checkDigit(Array(values.dropLast())) == values[count - 1] else {
            throw BarcodeError.invalidCheckDigit
        }

        var bits = "101"  // garde de depart
        if count == 13 {
            let parity = eanParity[values[0]]
            for index in 1...6 {
                let table = parity[parity.index(parity.startIndex, offsetBy: index - 1)] == "O"
                    ? eanLeftOdd
                    : eanLeftEven
                bits += table[values[index]]
            }
            bits += "01010"  // garde centrale
            for index in 7...12 { bits += eanRight[values[index]] }
        } else {
            for index in 0...3 { bits += eanLeftOdd[values[index]] }
            bits += "01010"
            for index in 4...7 { bits += eanRight[values[index]] }
        }
        bits += "101"  // garde de fin

        return bits.map { $0 == "1" }
    }

    /// Cle de controle EAN, valable pour EAN-8 et EAN-13.
    public static func checkDigit(_ digits: [Int]) -> Int {
        var sum = 0
        // Le poids alterne 3/1 en partant de la droite.
        for (index, digit) in digits.reversed().enumerated() {
            sum += digit * (index % 2 == 0 ? 3 : 1)
        }
        return (10 - sum % 10) % 10
    }

    // MARK: - Aides

    /// Convertit des largeurs alternees barre/espace en modules booleens.
    private static func modules(from widths: [[Int]]) -> [Bool] {
        var pattern: [Bool] = []
        for symbol in widths {
            for (index, width) in symbol.enumerated() {
                pattern += Array(repeating: index % 2 == 0, count: width)
            }
        }
        return pattern
    }
}
