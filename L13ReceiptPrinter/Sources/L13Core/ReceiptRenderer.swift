import AppKit
import Foundation

public enum ReceiptOrientation: String, CaseIterable, Identifiable {
    case normal
    case rotated90

    public var id: String { rawValue }
    public var title: String { self == .normal ? "Normal" : "Rotation 90 deg" }
}

public enum DitherMode: String, CaseIterable, Identifiable {
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

public struct ReceiptRenderer {
    public var width: Int
    public var threshold: UInt8
    public var ditherMode: DitherMode
    public var orientation: ReceiptOrientation

    public init(
        width: Int = MonochromeBitmap.nativeWidth,
        threshold: UInt8 = 128,
        ditherMode: DitherMode = .floydSteinberg,
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
        let image = drawReceipt(receipt, size: CGSize(width: width, height: height))
        return try bitmap(from: image, rotateClockwise: orientation == .rotated90)
    }

    public func previewImage(_ receipt: Receipt) -> NSImage {
        drawReceipt(receipt, size: CGSize(width: width, height: contentHeight(for: receipt)))
    }

    private func contentHeight(for receipt: Receipt) -> Int {
        // En-tete + lignes d'articles + total + pied.
        90 + receipt.items.count * 22 + 80
    }

    // MARK: - Conversion d'image quelconque

    /// Convertit une image arbitraire en bitmap a la largeur de l'imprimante,
    /// en conservant les proportions.
    public func bitmap(from image: NSImage) throws -> MonochromeBitmap {
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            throw RasterError.invalidDimensions
        }
        let scale = CGFloat(width) / sourceSize.width
        let targetHeight = max(1, Int((sourceSize.height * scale).rounded()))

        let canvas = NSImage(size: CGSize(width: width, height: targetHeight), flipped: true) { rect in
            NSColor.white.setFill()
            rect.fill()
            image.draw(
                in: rect,
                from: NSRect(origin: .zero, size: sourceSize),
                operation: .sourceOver,
                fraction: 1
            )
            return true
        }
        return try bitmap(from: canvas, rotateClockwise: false)
    }

    // MARK: - Mire

    public func testPattern(height: Int = 240) throws -> MonochromeBitmap {
        let size = CGSize(width: width, height: height)
        let image = NSImage(size: size, flipped: true) { _ in
            self.drawTestPatternContents(size: size, height: height)
            return true
        }
        return try bitmap(from: image, rotateClockwise: false)
    }

    private func drawTestPatternContents(size: CGSize, height: Int) {
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor.black.setStroke()
        NSColor.black.setFill()

        // Cadre: permet de verifier que toute la largeur est imprimee.
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width - 1, height: height - 1)).stroke()

        // Graduation tous les 8 px, reperes longs tous les 64 px.
        for x in stride(from: 0, to: width, by: 8) {
            let long = x % 64 == 0
            NSBezierPath.strokeLine(
                from: CGPoint(x: x, y: 0),
                to: CGPoint(x: x, y: long ? 20 : 10)
            )
        }

        // Damier de controle de densite, cantonne a la moitie gauche.
        for y in 0..<6 {
            for x in 0..<12 where (x + y).isMultiple(of: 2) {
                NSRect(x: 10 + x * 6, y: 34 + y * 6, width: 6, height: 6).fill()
            }
        }

        // Aplat plein: revele une largeur mal cadree.
        NSRect(x: 0, y: height - 30, width: width, height: 12).fill()

        // Libelle a droite du damier pour rester lisible.
        draw("\(width) px", x: 250, y: 44, size: 15, bold: true)
        draw("GAUCHE", x: 4, y: height - 52, size: 11)
        draw("DROITE", x: width - 62, y: height - 52, size: 11)
    }

    // MARK: - Dessin

    private func drawReceipt(_ receipt: Receipt, size: CGSize) -> NSImage {
        // `flipped: true` place l'origine en haut a gauche, ce qui correspond
        // a l'ordre des lignes attendu par l'imprimante et rend le code de
        // mise en page lisible de haut en bas.
        let image = NSImage(size: size, flipped: true) { _ in
            self.drawReceiptContents(receipt, size: size)
            return true
        }
        return image
    }

    private func drawReceiptContents(_ receipt: Receipt, size: CGSize) {
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor.black.setStroke()

        let margin: CGFloat = 8
        let right = size.width - margin
        var y: CGFloat = 10

        drawCentered(receipt.merchantName.uppercased(), y: y, size: 22, width: size.width, bold: true)
        y += 30
        drawCentered(receipt.address, y: y, size: 12, width: size.width)
        y += 18
        drawCentered(Self.dateFormatter.string(from: receipt.date), y: y, size: 12, width: size.width)
        y += 22

        strokeLine(from: margin, to: right, y: y)
        y += 10

        for item in receipt.items {
            let label = "\(item.quantity)x \(item.name)"
            draw(label, x: Int(margin), y: Int(y), size: 13)
            drawRightAligned(Self.money(item.total), right: right, y: y, size: 13)
            y += 20
        }

        y += 4
        strokeLine(from: margin, to: right, y: y)
        y += 10

        draw("TOTAL", x: Int(margin), y: Int(y), size: 17, bold: true)
        drawRightAligned(Self.money(receipt.total), right: right, y: y, size: 17, bold: true)
        y += 32

        drawCentered(receipt.footer, y: y, size: 13, width: size.width)
    }

    private func strokeLine(from x1: CGFloat, to x2: CGFloat, y: CGFloat) {
        NSBezierPath.strokeLine(from: CGPoint(x: x1, y: y), to: CGPoint(x: x2, y: y))
    }

    private func draw(_ text: String, x: Int, y: Int, size: CGFloat, bold: Bool = false) {
        text.draw(at: CGPoint(x: x, y: y), withAttributes: Self.attributes(size: size, bold: bold))
    }

    private func drawCentered(_ text: String, y: CGFloat, size: CGFloat, width: CGFloat, bold: Bool = false) {
        let attributes = Self.attributes(size: size, bold: bold)
        let textWidth = (text as NSString).size(withAttributes: attributes).width
        text.draw(at: CGPoint(x: (width - textWidth) / 2, y: y), withAttributes: attributes)
    }

    private func drawRightAligned(_ text: String, right: CGFloat, y: CGFloat, size: CGFloat, bold: Bool = false) {
        let attributes = Self.attributes(size: size, bold: bold)
        let textWidth = (text as NSString).size(withAttributes: attributes).width
        text.draw(at: CGPoint(x: right - textWidth, y: y), withAttributes: attributes)
    }

    private static func attributes(size: CGFloat, bold: Bool) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular),
            .foregroundColor: NSColor.black
        ]
    }

    // MARK: - Conversion en bitmap

    private func bitmap(from image: NSImage, rotateClockwise: Bool) throws -> MonochromeBitmap {
        let width = Int(image.size.width.rounded())
        let height = Int(image.size.height.rounded())
        guard width > 0, height > 0 else {
            throw RasterError.invalidDimensions
        }

        // On dessine dans un contexte 8 bits par canal que l'on maitrise
        // entierement, au lieu de passer par le CGImage de la NSImage.
        // Sur un ecran Retina/HDR ce dernier revient en 768 px de large et
        // 64 bits par pixel: relire ces octets comme du RGBA8 produisait une
        // image entierement noire.
        var gray = [UInt8](repeating: 255, count: width * height)
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 255, count: bytesPerRow * height)

        try pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                throw RasterError.invalidDimensions
            }

            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.interpolationQuality = .high

            // Le dessin passe par le contexte AppKit adosse a notre CGContext,
            // ce qui evite tout aller-retour par une representation Retina.
            //
            // CoreGraphics place son origine en bas a gauche alors que
            // l'imprimante attend la premiere ligne raster en haut. Sans ce
            // retournement, le ticket sortait la tete en bas.
            let graphicsContext = NSGraphicsContext(cgContext: context, flipped: true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphicsContext
            image.draw(
                in: NSRect(x: 0, y: 0, width: width, height: height),
                from: NSRect(origin: .zero, size: image.size),
                operation: .sourceOver,
                fraction: 1
            )
            NSGraphicsContext.restoreGraphicsState()
        }

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                let red = Int(pixels[offset])
                let green = Int(pixels[offset + 1])
                let blue = Int(pixels[offset + 2])
                gray[y * width + x] = UInt8((red * 299 + green * 587 + blue * 114) / 1000)
            }
        }

        if rotateClockwise {
            var rotated = [UInt8](repeating: 255, count: width * height)
            let rotatedWidth = height
            let rotatedHeight = width
            for y in 0..<height {
                for x in 0..<width {
                    rotated[x * rotatedWidth + (height - 1 - y)] = gray[y * width + x]
                }
            }
            return try convert(gray: rotated, width: rotatedWidth, height: rotatedHeight)
        }

        return try convert(gray: gray, width: width, height: height)
    }

    private func convert(gray: [UInt8], width: Int, height: Int) throws -> MonochromeBitmap {
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
