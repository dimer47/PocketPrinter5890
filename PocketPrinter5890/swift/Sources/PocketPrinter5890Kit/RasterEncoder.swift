import Foundation

/// Largeurs d'impression supportees, exprimees en pixels.
///
/// La machine de l'utilisateur (SilverCrest/Tronic Lidl, famille generique 5890,
/// papier ticket ~56 mm, 203 dpi) imprime sur 384 px = 48 octets par ligne.
/// Les autres valeurs sont fournies pour d'autres materiels et ne doivent pas
/// devenir le defaut.
public enum PrinterWidth: Int, CaseIterable, Identifiable, Sendable {
    /// 58 mm de papier, 48 mm imprimables. Defaut de la famille 5890.
    case mm58 = 384
    /// 80 mm de papier, 72 mm imprimables.
    case mm80 = 576
    /// Etiquettes 14 mm de la L13 documentee par atctwo. Compatibilite uniquement.
    case label14mm = 96

    public var id: Int { rawValue }

    public var pixels: Int { rawValue }

    public var bytesPerLine: Int { rawValue / 8 }

    public var title: String {
        switch self {
        case .mm58: return "58 mm - 384 px (defaut)"
        case .mm80: return "80 mm - 576 px"
        case .label14mm: return "Etiquette 14 mm - 96 px"
        }
    }
}

public struct MonochromeBitmap: Equatable {
    /// Largeur native de la machine cible: 384 px.
    /// Anciennement 96 px, valeur heritee d'un modele different (L13 a etiquettes)
    /// qui empechait toute impression.
    public static let nativeWidth = PrinterWidth.mm58.pixels

    public let width: Int
    public let height: Int
    public let bytes: [UInt8]

    public var widthBytes: Int {
        (width + 7) / 8
    }

    public init(width: Int = Self.nativeWidth, height: Int, bytes: [UInt8]) throws {
        guard width > 0, height > 0 else { throw RasterError.invalidDimensions }
        guard width % 8 == 0 else { throw RasterError.widthNotByteAligned(width) }
        let expected = ((width + 7) / 8) * height
        guard bytes.count == expected else {
            throw RasterError.invalidDataSize(expected: expected, actual: bytes.count)
        }
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    /// Extrait une bande horizontale du bitmap, utilisee pour l'envoi fragmente.
    public func slice(fromLine start: Int, lineCount: Int) throws -> MonochromeBitmap {
        guard start >= 0, lineCount > 0, start + lineCount <= height else {
            throw RasterError.invalidDimensions
        }
        let stride = widthBytes
        let range = (start * stride)..<((start + lineCount) * stride)
        return try MonochromeBitmap(width: width, height: lineCount, bytes: Array(bytes[range]))
    }
}

public enum RasterError: Error, Equatable, LocalizedError {
    case invalidDimensions
    case invalidDataSize(expected: Int, actual: Int)
    case invalidPixelCount(expected: Int, actual: Int)
    case widthNotByteAligned(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidDimensions:
            return "Dimensions raster invalides"
        case .invalidDataSize(let expected, let actual):
            return "Taille raster invalide: \(actual) octets au lieu de \(expected)"
        case .invalidPixelCount(let expected, let actual):
            return "Nombre de pixels invalide: \(actual) au lieu de \(expected)"
        case .widthNotByteAligned(let width):
            return "Largeur \(width) px non multiple de 8"
        }
    }
}

public enum RasterEncoder {
    /// Nombre de lignes par bande envoyee a l'imprimante.
    ///
    /// Le firmware perd des donnees quand on lui envoie un raster de plusieurs
    /// milliers d'octets en une seule commande. Toutes les implementations qui
    /// fonctionnent sur cette famille decoupent en bandes.
    public static let defaultBandHeight = 24

    public static func encodeBlackPixels(
        _ pixels: [Bool],
        width: Int = MonochromeBitmap.nativeWidth,
        height: Int
    ) throws -> MonochromeBitmap {
        guard width > 0, height > 0 else { throw RasterError.invalidDimensions }
        guard width % 8 == 0 else { throw RasterError.widthNotByteAligned(width) }
        let expected = width * height
        guard pixels.count == expected else {
            throw RasterError.invalidPixelCount(expected: expected, actual: pixels.count)
        }

        let widthBytes = (width + 7) / 8
        var output = [UInt8](repeating: 0, count: widthBytes * height)
        for y in 0..<height {
            for x in 0..<width where pixels[y * width + x] {
                output[y * widthBytes + x / 8] |= UInt8(0x80 >> (x % 8))
            }
        }
        return try MonochromeBitmap(width: width, height: height, bytes: output)
    }

    /// Commande raster unique `1D 76 30 00 xL xH yL yH <pixels>`.
    ///
    /// Pour un bitmap de plus de quelques dizaines de lignes, preferer
    /// `bandedRasterCommands(for:bandHeight:)`.
    public static func rasterCommand(for bitmap: MonochromeBitmap) -> [UInt8] {
        let x = bitmap.widthBytes
        let y = bitmap.height
        return [
            0x1d, 0x76, 0x30, 0x00,
            UInt8(x & 0xff), UInt8((x >> 8) & 0xff),
            UInt8(y & 0xff), UInt8((y >> 8) & 0xff)
        ] + bitmap.bytes
    }

    /// Decoupe le bitmap en bandes, chacune etant une commande raster complete.
    public static func bandedRasterCommands(
        for bitmap: MonochromeBitmap,
        bandHeight: Int = defaultBandHeight
    ) -> [[UInt8]] {
        let bandHeight = max(1, bandHeight)
        var commands: [[UInt8]] = []
        var line = 0
        while line < bitmap.height {
            let count = min(bandHeight, bitmap.height - line)
            if let band = try? bitmap.slice(fromLine: line, lineCount: count) {
                commands.append(rasterCommand(for: band))
            }
            line += count
        }
        return commands
    }
}

public enum MonochromeConverter {
    public static func threshold(
        grayscale: [UInt8],
        width: Int,
        height: Int,
        threshold: UInt8
    ) throws -> MonochromeBitmap {
        guard grayscale.count == width * height else {
            throw RasterError.invalidPixelCount(expected: width * height, actual: grayscale.count)
        }
        return try RasterEncoder.encodeBlackPixels(
            grayscale.map { $0 < threshold },
            width: width,
            height: height
        )
    }

    public static func orderedDither(
        grayscale: [UInt8],
        width: Int,
        height: Int
    ) throws -> MonochromeBitmap {
        guard grayscale.count == width * height else {
            throw RasterError.invalidPixelCount(expected: width * height, actual: grayscale.count)
        }
        let matrix = [
            [0, 8, 2, 10],
            [12, 4, 14, 6],
            [3, 11, 1, 9],
            [15, 7, 13, 5]
        ]
        var pixels: [Bool] = []
        pixels.reserveCapacity(grayscale.count)
        for y in 0..<height {
            for x in 0..<width {
                let limit = UInt8((matrix[y % 4][x % 4] * 16) + 8)
                pixels.append(grayscale[y * width + x] < limit)
            }
        }
        return try RasterEncoder.encodeBlackPixels(pixels, width: width, height: height)
    }

    /// Diffusion d'erreur Floyd-Steinberg: bien meilleur rendu photo que le tramage ordonne.
    public static func floydSteinberg(
        grayscale: [UInt8],
        width: Int,
        height: Int
    ) throws -> MonochromeBitmap {
        guard grayscale.count == width * height else {
            throw RasterError.invalidPixelCount(expected: width * height, actual: grayscale.count)
        }
        var buffer = grayscale.map { Int($0) }
        var pixels = [Bool](repeating: false, count: width * height)

        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let old = buffer[index]
                let new = old < 128 ? 0 : 255
                pixels[index] = new == 0
                let error = old - new

                func spread(_ dx: Int, _ dy: Int, _ factor: Int) {
                    let nx = x + dx
                    let ny = y + dy
                    guard nx >= 0, nx < width, ny >= 0, ny < height else { return }
                    buffer[ny * width + nx] += error * factor / 16
                }

                spread(1, 0, 7)
                spread(-1, 1, 3)
                spread(0, 1, 5)
                spread(1, 1, 1)
            }
        }
        return try RasterEncoder.encodeBlackPixels(pixels, width: width, height: height)
    }
}
