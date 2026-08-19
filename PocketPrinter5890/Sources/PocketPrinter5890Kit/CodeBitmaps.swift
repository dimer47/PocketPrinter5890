import Foundation
#if canImport(CoreImage)
import CoreImage
import CoreGraphics
#endif

/// Conversion des codes en bitmaps imprimables.
///
/// Les codes-barres lineaires sont generes en Swift pur (`Barcode1D`), donc
/// portables partout. Les QR codes s'appuient sur CoreImage: ecrire un
/// encodeur QR conforme (masques, evaluation de penalite, format BCH) est
/// une source d'erreurs silencieuses, et un QR faux ne se voit qu'au
/// scanner. Le moteur est isole ici pour pouvoir etre remplace sans toucher
/// au reste de la librairie.
///
/// Dans tous les cas les modules sont ecrits directement dans le bitmap,
/// sans interpolation: un code redimensionne en douceur devient illisible.
public enum CodeBitmaps {

    /// QR code centre sur la largeur d'impression.
    ///
    /// - Parameters:
    ///   - content: donnees a encoder.
    ///   - correction: niveau de correction d'erreur.
    ///   - moduleSize: taille d'un module en pixels. Calculee automatiquement
    ///     pour occuper environ deux tiers de la largeur si elle vaut nil.
    ///   - quietZone: marge blanche autour du code, en modules. La norme en
    ///     exige 4; en dessous, beaucoup de lecteurs echouent.
    public static func qrCode(
        _ content: String,
        correction: QRCorrectionLevel = .medium,
        moduleSize: Int? = nil,
        quietZone: Int = 4,
        printWidth: Int = MonochromeBitmap.nativeWidth
    ) throws -> MonochromeBitmap {
        guard !content.isEmpty else { throw CodeError.emptyContent }
        let matrix = try qrMatrix(content, correction: correction)
        let totalModules = matrix.size + quietZone * 2

        // Taille de module par defaut: le code occupe environ deux tiers de
        // la largeur, sans jamais la depasser.
        let scale = moduleSize ?? max(1, (printWidth * 2 / 3) / totalModules)
        let codeSize = min(totalModules * scale, printWidth)

        let widthBytes = (printWidth + 7) / 8
        var bytes = [UInt8](repeating: 0, count: widthBytes * codeSize)

        let originX = (printWidth - codeSize) / 2
        for y in 0..<codeSize {
            let moduleY = y / scale - quietZone
            guard moduleY >= 0, moduleY < matrix.size else { continue }
            for x in 0..<codeSize {
                let moduleX = x / scale - quietZone
                guard moduleX >= 0, moduleX < matrix.size else { continue }
                guard matrix[moduleX, moduleY] else { continue }
                let pixelX = originX + x
                bytes[y * widthBytes + pixelX / 8] |= UInt8(0x80 >> (pixelX % 8))
            }
        }
        return try MonochromeBitmap(width: printWidth, height: codeSize, bytes: bytes)
    }

    public enum QRCorrectionLevel: String, CaseIterable, Identifiable, Sendable {
        case low = "L"
        case medium = "M"
        case quartile = "Q"
        case high = "H"

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .low: return "Faible (7 %)"
            case .medium: return "Moyen (15 %)"
            case .quartile: return "Bon (25 %)"
            case .high: return "Maximal (30 %)"
            }
        }
    }

    public enum CodeError: Error, LocalizedError {
        case emptyContent
        case generationFailed
        case unavailable

        public var errorDescription: String? {
            switch self {
            case .emptyContent: return "Contenu vide"
            case .generationFailed: return "Generation du QR code impossible"
            case .unavailable: return "Generateur de QR code indisponible sur cette plateforme"
            }
        }
    }

    /// Matrice de modules d'un QR code.
    public struct QRMatrix {
        public let size: Int
        public let modules: [Bool]

        public subscript(x: Int, y: Int) -> Bool {
            modules[y * size + x]
        }
    }

    /// Produit la matrice de modules, sans mise a l'echelle.
    ///
    /// CoreImage rend le code avec une quiet zone d'un module: elle est
    /// retiree ici pour que l'appelant maitrise sa propre marge.
    public static func qrMatrix(
        _ content: String,
        correction: QRCorrectionLevel = .medium
    ) throws -> QRMatrix {
        #if canImport(CoreImage)
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            throw CodeError.unavailable
        }
        filter.setValue(Data(content.utf8), forKey: "inputMessage")
        filter.setValue(correction.rawValue, forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { throw CodeError.generationFailed }

        let width = Int(output.extent.width)
        let height = Int(output.extent.height)
        guard width > 2, height > 2 else { throw CodeError.generationFailed }

        let context = CIContext(options: [.useSoftwareRenderer: true])
        guard let cgImage = context.createCGImage(output, from: output.extent) else {
            throw CodeError.generationFailed
        }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        // CoreImage ajoute une bordure d'un module: on la retire.
        let border = 1
        let size = width - border * 2
        var modules = [Bool](repeating: false, count: size * size)
        for y in 0..<size {
            for x in 0..<size {
                let offset = ((y + border) * width + (x + border)) * 4
                modules[y * size + x] = pixels[offset] < 128
            }
        }
        return QRMatrix(size: size, modules: modules)
        #else
        throw CodeError.unavailable
        #endif
    }

    /// Code-barres lineaire centre sur la largeur d'impression.
    ///
    /// - Parameters:
    ///   - moduleWidth: largeur d'une barre elementaire. Calculee pour
    ///     remplir la largeur disponible si elle vaut nil.
    ///   - quietZone: marge blanche laterale en pixels.
    public static func barcode(
        _ content: String,
        symbology: Barcode1D.Symbology = .code128,
        height: Int = 80,
        moduleWidth: Int? = nil,
        quietZone: Int = 20,
        printWidth: Int = MonochromeBitmap.nativeWidth
    ) throws -> MonochromeBitmap {
        let pattern = try Barcode1D.pattern(for: content, symbology: symbology)
        let available = max(1, printWidth - quietZone * 2)
        let scale = moduleWidth ?? max(1, available / pattern.count)
        let codeWidth = min(pattern.count * scale, printWidth)

        let height = max(8, height)
        let widthBytes = (printWidth + 7) / 8
        var bytes = [UInt8](repeating: 0, count: widthBytes * height)

        let originX = (printWidth - codeWidth) / 2
        for x in 0..<codeWidth {
            let index = x / scale
            guard index < pattern.count, pattern[index] else { continue }
            let pixelX = originX + x
            for y in 0..<height {
                bytes[y * widthBytes + pixelX / 8] |= UInt8(0x80 >> (pixelX % 8))
            }
        }
        return try MonochromeBitmap(width: printWidth, height: height, bytes: bytes)
    }
}

public extension PrintElement {
    /// QR code genere en Swift pur, portable et sans dependance systeme.
    ///
    /// A preferer a `.qrCode(_:moduleSize:)`, qui repose sur la commande
    /// native `GS ( k` que ce firmware n'implemente pas.
    static func qr(
        _ content: String,
        correction: CodeBitmaps.QRCorrectionLevel = .medium,
        moduleSize: Int? = nil,
        printWidth: Int = MonochromeBitmap.nativeWidth
    ) throws -> PrintElement {
        .image(try CodeBitmaps.qrCode(
            content,
            correction: correction,
            moduleSize: moduleSize,
            printWidth: printWidth
        ))
    }

    /// Code-barres genere en Swift pur.
    static func code(
        _ content: String,
        symbology: Barcode1D.Symbology = .code128,
        height: Int = 80,
        printWidth: Int = MonochromeBitmap.nativeWidth
    ) throws -> PrintElement {
        .image(try CodeBitmaps.barcode(
            content,
            symbology: symbology,
            height: height,
            printWidth: printWidth
        ))
    }
}
