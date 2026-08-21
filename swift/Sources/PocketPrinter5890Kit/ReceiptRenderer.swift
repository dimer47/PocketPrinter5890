import CoreGraphics
import CoreText
import Foundation

public enum ReceiptOrientation: String, CaseIterable, Identifiable, Sendable {
    case normal
    case rotated90

    public var id: String { rawValue }
    public var title: String { self == .normal ? "Normal" : "Rotation 90 deg" }
}

public enum DitherMode: String, CaseIterable, Identifiable, Sendable {
    case threshold
    case ordered
    case floydSteinberg

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .threshold: return "Seuil"
        case .ordered: return "Tramage ordonne"
        case .floydSteinberg: return "Floyd-Steinberg"
        }
    }
}

/// Rendu d'un ticket en bitmap monochrome.
///
/// Ecrit sur CoreGraphics et CoreText plutot qu'AppKit: le rendu fonctionne
/// ainsi a l'identique sur macOS, iOS et iPadOS. Une version anterieure
/// s'appuyait sur `NSImage`, ce qui restreignait la librairie a macOS et
/// exposait a un piege: sur ecran Retina, `NSImage.cgImage` renvoie une image
/// deux fois plus large en 64 bits par pixel, illisible telle quelle.
public struct ReceiptRenderer {
    public var width: Int
    public var threshold: UInt8
    public var ditherMode: DitherMode
    public var orientation: ReceiptOrientation

    public init(
        width: Int = MonochromeBitmap.nativeWidth,
        // Un ticket est fait de traits, pas de degrades. Floyd-Steinberg
        // disperse les pixels pour simuler du gris: applique a du texte, il
        // transforme chaque trait plein en semis de points, et le rendu sort
        // tres clair et tres fin. Le tramage ne vaut que pour une photo.
        //
        // Le seuil est relevé a 160: l'antialiasing du texte produit des bords
        // gris qu'un seuil trop bas efface, ce qui amaigrit le trait.
        threshold: UInt8 = 160,
        ditherMode: DitherMode = .threshold,
        orientation: ReceiptOrientation = .normal
    ) {
        self.width = width
        self.threshold = threshold
        self.ditherMode = ditherMode
        self.orientation = orientation
    }

    /// Compatibilite avec l'ancienne API booleenne.
    public init(width: Int, threshold: UInt8, dither: Bool, orientation: ReceiptOrientation = .normal) {
        self.init(
            width: width,
            threshold: threshold,
            ditherMode: dither ? .ordered : .threshold,
            orientation: orientation
        )
    }

    // MARK: - Rendu de ticket

    public func render(_ receipt: Receipt) throws -> MonochromeBitmap {
        let height = contentHeight(for: receipt)
        let gray = try drawToGrayscale(width: width, height: height) { context in
            drawReceipt(receipt, in: context, size: CGSize(width: width, height: height))
        }
        return try convert(gray: gray, width: width, height: height)
    }

    /// Image de previsualisation, utilisable directement par l'interface.
    public func previewImage(_ receipt: Receipt) throws -> CGImage {
        let height = contentHeight(for: receipt)
        return try drawToImage(width: width, height: height) { context in
            drawReceipt(receipt, in: context, size: CGSize(width: width, height: height))
        }
    }

    private func contentHeight(for receipt: Receipt) -> Int {
        90 + receipt.items.count * 22 + 80
    }

    // MARK: - Conversion d'image quelconque

    /// Convertit une image en bitmap a la largeur d'impression, proportions
    /// conservees.
    public func bitmap(from image: CGImage) throws -> MonochromeBitmap {
        guard image.width > 0, image.height > 0 else {
            throw RasterError.invalidDimensions
        }
        let scale = Double(width) / Double(image.width)
        let height = max(1, Int((Double(image.height) * scale).rounded()))

        let gray = try drawToGrayscale(width: width, height: height) { context in
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return try convert(gray: gray, width: width, height: height)
    }

    // MARK: - Mire

    public func testPattern(height: Int = 240) throws -> MonochromeBitmap {
        let gray = try drawToGrayscale(width: width, height: height) { context in
            drawTestPattern(in: context, height: height)
        }
        return try convert(gray: gray, width: width, height: height)
    }

    // MARK: - Dessin

    private func drawReceipt(_ receipt: Receipt, in context: CGContext, size: CGSize) {
        let margin: CGFloat = 8
        let right = size.width - margin
        var y: CGFloat = 10

        drawText(receipt.merchantName.uppercased(), in: context,
                 at: .center(size.width), y: y, size: 22, bold: true)
        y += 30
        drawText(receipt.address, in: context, at: .center(size.width), y: y, size: 12)
        y += 18
        drawText(Self.dateFormatter.string(from: receipt.date), in: context,
                 at: .center(size.width), y: y, size: 12)
        y += 22

        strokeLine(in: context, from: margin, to: right, y: y)
        y += 10

        for item in receipt.items {
            drawText("\(item.quantity)x \(item.name)", in: context, at: .left(margin), y: y, size: 13)
            drawText(Self.money(item.total), in: context, at: .right(right), y: y, size: 13)
            y += 20
        }

        y += 4
        strokeLine(in: context, from: margin, to: right, y: y)
        y += 10

        drawText("TOTAL", in: context, at: .left(margin), y: y, size: 17, bold: true)
        drawText(Self.money(receipt.total), in: context, at: .right(right), y: y, size: 17, bold: true)
        y += 32

        drawText(receipt.footer, in: context, at: .center(size.width), y: y, size: 13)
    }

    private func drawTestPattern(in context: CGContext, height: Int) {
        let width = CGFloat(self.width)
        context.setStrokeColor(gray: 0, alpha: 1)
        context.setFillColor(gray: 0, alpha: 1)
        context.setLineWidth(1)

        // Cadre: verifie que toute la largeur est imprimee.
        context.stroke(CGRect(x: 0.5, y: 0.5, width: width - 1, height: CGFloat(height) - 1))

        // Graduation, reperes longs tous les 64 px.
        for x in stride(from: 0, to: self.width, by: 8) {
            let long = x % 64 == 0
            context.move(to: CGPoint(x: CGFloat(x), y: 0))
            context.addLine(to: CGPoint(x: CGFloat(x), y: long ? 20 : 10))
            context.strokePath()
        }

        // Damier de controle de densite.
        for row in 0..<6 {
            for column in 0..<12 where (row + column).isMultiple(of: 2) {
                context.fill(CGRect(x: 10 + column * 6, y: 34 + row * 6, width: 6, height: 6))
            }
        }

        // Aplat plein: revele une largeur mal cadree.
        context.fill(CGRect(x: 0, y: height - 30, width: Int(width), height: 12))

        drawText("\(self.width) px", in: context, at: .left(250), y: 44, size: 15, bold: true)
        drawText("GAUCHE", in: context, at: .left(4), y: CGFloat(height) - 52, size: 11)
        drawText("DROITE", in: context, at: .right(width - 4), y: CGFloat(height) - 52, size: 11)
    }

    // MARK: - Primitives de dessin

    private enum Anchor {
        case left(CGFloat)
        case right(CGFloat)
        case center(CGFloat)
    }

    private func strokeLine(in context: CGContext, from x1: CGFloat, to x2: CGFloat, y: CGFloat) {
        context.setStrokeColor(gray: 0, alpha: 1)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: x1, y: y))
        context.addLine(to: CGPoint(x: x2, y: y))
        context.strokePath()
    }

    private func drawText(
        _ text: String,
        in context: CGContext,
        at anchor: Anchor,
        y: CGFloat,
        size: CGFloat,
        bold: Bool = false
    ) {
        // Police a chasse fixe: les colonnes d'un ticket doivent s'aligner.
        let font = CTFontCreateWithName(
            (bold ? "Menlo-Bold" : "Menlo-Regular") as CFString,
            size,
            nil
        )
        // Cles CoreText plutot qu'AppKit/UIKit: elles existent sur toutes
        // les plateformes.
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CGColor(gray: 0, alpha: 1)
        ]
        let attributed = CFAttributedStringCreate(
            kCFAllocatorDefault,
            text as CFString,
            attributes as CFDictionary
        )
        guard let attributed else { return }
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

        let x: CGFloat
        switch anchor {
        case .left(let value): x = value
        case .right(let value): x = value - bounds.width
        case .center(let total): x = (total - bounds.width) / 2
        }

        // Le contexte est retourne pour que la mise en page se lise de haut
        // en bas; CoreText dessinerait alors le texte en miroir. On annule
        // le retournement localement, le temps de tracer la ligne.
        context.saveGState()
        context.translateBy(x: 0, y: y + bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = CGPoint(x: x, y: 0)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    // MARK: - Contexte graphique

    /// Dessine dans un contexte 8 bits par canal et renvoie les niveaux de gris.
    private func drawToGrayscale(
        width: Int,
        height: Int,
        _ draw: (CGContext) -> Void
    ) throws -> [UInt8] {
        guard width > 0, height > 0 else { throw RasterError.invalidDimensions }
        var pixels = [UInt8](repeating: 255, count: width * height)

        try pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else {
                throw RasterError.invalidDimensions
            }
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))

            // CoreGraphics place son origine en bas a gauche; l'imprimante
            // attend la premiere ligne en haut. On retourne le repere pour
            // que le code de mise en page se lise de haut en bas.
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            draw(context)
        }
        return pixels
    }

    private func drawToImage(
        width: Int,
        height: Int,
        _ draw: (CGContext) -> Void
    ) throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            throw RasterError.invalidDimensions
        }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        draw(context)

        guard let image = context.makeImage() else {
            throw RasterError.invalidDimensions
        }
        return image
    }

    private func convert(gray: [UInt8], width: Int, height: Int) throws -> MonochromeBitmap {
        if orientation == .rotated90 {
            var rotated = [UInt8](repeating: 255, count: width * height)
            for y in 0..<height {
                for x in 0..<width {
                    rotated[x * height + (height - 1 - y)] = gray[y * width + x]
                }
            }
            return try binarise(gray: rotated, width: height, height: width)
        }
        return try binarise(gray: gray, width: width, height: height)
    }

    private func binarise(gray: [UInt8], width: Int, height: Int) throws -> MonochromeBitmap {
        switch ditherMode {
        case .threshold:
            return try MonochromeConverter.threshold(
                grayscale: gray, width: width, height: height, threshold: threshold
            )
        case .ordered:
            return try MonochromeConverter.orderedDither(grayscale: gray, width: width, height: height)
        case .floydSteinberg:
            return try MonochromeConverter.floydSteinberg(grayscale: gray, width: width, height: height)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private static func money(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "EUR"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }
}
