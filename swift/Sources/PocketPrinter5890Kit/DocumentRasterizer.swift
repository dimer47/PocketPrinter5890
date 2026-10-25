import CoreGraphics
import CoreText
import Foundation

/// Rendu d'un `PrintDocument` en image.
///
/// La pocket 5890 recoit le texte en ESC/POS et le dessine elle-meme. Les
/// imprimantes Brother pilotees par le SDK n'acceptent que des images ou des
/// PDF: le document doit donc etre dessine cote application.
///
/// La mise en page reprend celle de la 5890 (police a chasse fixe de 12
/// points de large, 32 colonnes sur 384 points) pour qu'un document compose
/// pour le ticket sorte a l'identique. `scale` agrandit le rendu sans
/// changer la mise en page: le texte reste net sur une tete 300 dpi.
public struct DocumentRasterizer {
    /// Largeur logique de mise en page, en points.
    public var width: Int
    /// Nombre de colonnes de texte en taille 1.
    public var columns: Int

    /// Hauteur d'une ligne de texte en taille 1, comme la police A (12 x 24).
    private let lineHeight: CGFloat = 24

    public init(width: Int = MonochromeBitmap.nativeWidth, columns: Int? = nil) {
        self.width = width
        self.columns = columns ?? max(1, width / 12)
    }

    /// Image en niveaux de gris, prete pour `BRLMPrinterDriver.printImage`.
    public func image(_ document: PrintDocument, scale: CGFloat = 1) throws -> CGImage {
        let blocks = layout(document)
        let height = max(1, blocks.reduce(0) { $0 + $1.height })
        return try RasterCanvas.image(width: width, height: Int(height.rounded(.up)), scale: scale) { context in
            var y: CGFloat = 0
            for block in blocks {
                draw(block, in: context, y: y)
                y += block.height
            }
        }
    }

    // MARK: - Mise en page

    private enum Block {
        case text(String, size: Int, bold: Bool, underline: Bool, inverted: Bool, alignment: ESCPOS.Alignment)
        case bitmap(MonochromeBitmap, height: CGFloat)
        case blank(CGFloat)
        /// Trait plein, simple ou double, en travers de la page.
        case rule(double: Bool)

        var height: CGFloat {
            switch self {
            case let .text(_, size, _, _, _, _): return 24 * CGFloat(size)
            case let .bitmap(_, height): return height
            case let .blank(height): return height
            case .rule: return 24
            }
        }
    }

    private func layout(_ document: PrintDocument) -> [Block] {
        var blocks: [Block] = []
        for element in document.elements {
            switch element {
            case let .text(value, requestedSize, bold, underline, inverted, alignment):
                let size = min(8, max(1, requestedSize))
                let lineColumns = max(1, columns / size)
                for line in TextLayout.wrap(value, columns: lineColumns) {
                    blocks.append(.text(line, size: size, bold: bold, underline: underline,
                                        inverted: inverted, alignment: alignment))
                }

            case let .image(bitmap):
                blocks.append(.bitmap(bitmap, height: scaledHeight(of: bitmap)))

            case let .barcode(content, type, height):
                // Le firmware 5890 ne sait pas tracer `GS k`; ici on peut le
                // faire nous-memes, dans les symbologies que la librairie
                // genere. Les autres retombent sur le texte en clair.
                if let symbology = Self.symbology(for: type),
                   let bitmap = try? CodeBitmaps.barcode(content, symbology: symbology,
                                                         height: Int(height), printWidth: width) {
                    blocks.append(.bitmap(bitmap, height: scaledHeight(of: bitmap)))
                    blocks.append(.text(content, size: 1, bold: false, underline: false,
                                        inverted: false, alignment: .center))
                } else {
                    blocks.append(.text(content, size: 1, bold: false, underline: false,
                                        inverted: false, alignment: .center))
                }

            case let .qrCode(content, _):
                if let bitmap = try? CodeBitmaps.qrCode(content, printWidth: width) {
                    blocks.append(.bitmap(bitmap, height: scaledHeight(of: bitmap)))
                }

            case let .separator(character):
                // Des tirets en police sortent haches une fois seuilles:
                // les traits sont dessines pleins.
                switch character {
                case "-", "_", "\u{2014}", "\u{2500}":
                    blocks.append(.rule(double: false))
                case "=", "\u{2550}":
                    blocks.append(.rule(double: true))
                default:
                    blocks.append(.text(String(repeating: String(character), count: columns), size: 1,
                                        bold: false, underline: false, inverted: false, alignment: .left))
                }

            case let .feed(lines):
                blocks.append(.blank(lineHeight * CGFloat(lines)))

            case .raw:
                // Octets ESC/POS propres a la 5890: sans equivalent graphique.
                continue
            }
        }
        return blocks
    }

    private func scaledHeight(of bitmap: MonochromeBitmap) -> CGFloat {
        CGFloat(bitmap.height) * CGFloat(width) / CGFloat(max(1, bitmap.width))
    }

    private static func symbology(for type: ESCPOS.BarcodeType) -> Barcode1D.Symbology? {
        switch type {
        case .code128: return .code128
        case .code39: return .code39
        case .ean13: return .ean13
        case .ean8: return .ean8
        default: return nil
        }
    }

    // MARK: - Dessin

    private func draw(_ block: Block, in context: CGContext, y: CGFloat) {
        switch block {
        case let .text(value, size, bold, underline, inverted, alignment):
            drawText(value, size: size, bold: bold, underline: underline,
                     inverted: inverted, alignment: alignment, in: context, y: y)

        case let .bitmap(bitmap, height):
            guard let image = bitmap.makeCGImage() else { return }
            context.saveGState()
            // Les codes doivent rester nets: pas de lissage a l'agrandissement.
            context.interpolationQuality = .none
            // Le repere est retourne; on le retablit le temps de poser l'image.
            context.translateBy(x: 0, y: y + height)
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: height))
            context.restoreGState()

        case let .rule(double):
            context.setFillColor(gray: 0, alpha: 1)
            let thickness: CGFloat = 2
            let middle = y + 12
            if double {
                context.fill(CGRect(x: 0, y: middle - 3, width: CGFloat(width), height: thickness))
                context.fill(CGRect(x: 0, y: middle + 1, width: CGFloat(width), height: thickness))
            } else {
                context.fill(CGRect(x: 0, y: middle - 1, width: CGFloat(width), height: thickness))
            }

        case .blank:
            break
        }
    }

    private func drawText(
        _ text: String,
        size: Int,
        bold: Bool,
        underline: Bool,
        inverted: Bool,
        alignment: ESCPOS.Alignment,
        in context: CGContext,
        y: CGFloat
    ) {
        let height = lineHeight * CGFloat(size)
        // Menlo avance d'environ 0,602 em: on choisit le corps qui donne
        // 12 points par caractere, la chasse de la police A de la 5890.
        let fontSize = 12 / 0.602 * CGFloat(size)
        let font = CTFontCreateWithName((bold ? "Menlo-Bold" : "Menlo-Regular") as CFString, fontSize, nil)
        let ink: CGFloat = inverted ? 1 : 0
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CGColor(gray: ink, alpha: 1)
        ]
        guard let attributed = CFAttributedStringCreate(kCFAllocatorDefault, text as CFString,
                                                        attributes as CFDictionary) else { return }
        let line = CTLineCreateWithAttributedString(attributed)
        let lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))

        let x: CGFloat
        switch alignment {
        case .left: x = 0
        case .center: x = max(0, (CGFloat(width) - lineWidth) / 2)
        case .right: x = max(0, CGFloat(width) - lineWidth)
        }

        if inverted {
            context.setFillColor(gray: 0, alpha: 1)
            context.fill(CGRect(x: x, y: y, width: lineWidth, height: height))
        }

        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        let baseline = y + (height + ascent - descent) / 2

        context.saveGState()
        context.translateBy(x: 0, y: baseline)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = CGPoint(x: x, y: 0)
        CTLineDraw(line, context)
        context.restoreGState()

        if underline {
            context.setFillColor(gray: ink, alpha: 1)
            context.fill(CGRect(x: x, y: baseline + descent / 2, width: lineWidth, height: CGFloat(size)))
        }
    }
}

// MARK: - Canevas commun

/// Contexte graphique en niveaux de gris, oriente de haut en bas.
enum RasterCanvas {
    /// Dessine sur `width` x `height` points logiques, agrandis de `scale`.
    static func image(
        width: Int,
        height: Int,
        scale: CGFloat,
        _ draw: (CGContext) -> Void
    ) throws -> CGImage {
        let scale = max(0.1, scale)
        let pixelWidth = Int((CGFloat(width) * scale).rounded())
        let pixelHeight = Int((CGFloat(height) * scale).rounded())
        guard pixelWidth > 0, pixelHeight > 0, let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            throw RasterError.invalidDimensions
        }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        // Origine en haut a gauche, puis passage en points logiques.
        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: scale, y: -scale)
        draw(context)
        guard let image = context.makeImage() else { throw RasterError.invalidDimensions }
        return image
    }
}

public extension MonochromeBitmap {
    /// Image en niveaux de gris (noir = point imprime), pour l'affichage ou
    /// pour un SDK qui attend une `CGImage`.
    func makeCGImage() -> CGImage? {
        var gray = [UInt8](repeating: 255, count: width * height)
        let rowBytes = widthBytes
        for y in 0..<height {
            for x in 0..<width where bytes[y * rowBytes + x / 8] & UInt8(0x80 >> (x % 8)) != 0 {
                gray[y * width + x] = 0
            }
        }
        guard let provider = CGDataProvider(data: Data(gray) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
