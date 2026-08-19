import L13Core
import XCTest

final class ReceiptRendererTests: XCTestCase {
    func testNativeWidthIs384Pixels() {
        // Regression: la largeur native etait 96 px, valeur heritee d'un modele
        // d'imprimante different (L13 a etiquettes 14 mm). La machine cible est
        // une 58 mm et attend 384 px, soit 48 octets par ligne.
        XCTAssertEqual(MonochromeBitmap.nativeWidth, 384)
        XCTAssertEqual(PrinterWidth.mm58.pixels, 384)
        XCTAssertEqual(PrinterWidth.mm58.bytesPerLine, 48)
    }

    func testReceiptRendersAtNativeWidth() throws {
        let bitmap = try ReceiptRenderer(orientation: .normal).render(.sample)

        XCTAssertEqual(bitmap.width, 384)
        XCTAssertEqual(bitmap.widthBytes, 48)
        XCTAssertEqual(
            Array(RasterEncoder.rasterCommand(for: bitmap).prefix(6)),
            [0x1d, 0x76, 0x30, 0x00, 0x30, 0x00]
        )
    }

    func testRendererHonoursExplicitWidth() throws {
        let bitmap = try ReceiptRenderer(width: PrinterWidth.mm80.pixels).render(.sample)

        XCTAssertEqual(bitmap.width, 576)
        XCTAssertEqual(bitmap.widthBytes, 72)
    }

    func testTestPatternMatchesRequestedWidth() throws {
        let bitmap = try ReceiptRenderer(width: 384).testPattern(height: 64)

        XCTAssertEqual(bitmap.width, 384)
        XCTAssertEqual(bitmap.height, 64)
        XCTAssertEqual(bitmap.bytes.count, 48 * 64)
    }

    func testRejectsWidthNotMultipleOfEight() {
        XCTAssertThrowsError(
            try RasterEncoder.encodeBlackPixels(Array(repeating: false, count: 100), width: 100, height: 1)
        ) { error in
            XCTAssertEqual(error as? RasterError, .widthNotByteAligned(100))
        }
    }

    func testArbitraryWidthsAreAcceptedWhenByteAligned() throws {
        // Contrairement a l'ancienne implementation, l'encodeur ne doit plus
        // rejeter les largeurs autres que 96 px.
        let bitmap = try RasterEncoder.encodeBlackPixels(
            Array(repeating: false, count: 192), width: 192, height: 1
        )
        XCTAssertEqual(bitmap.widthBytes, 24)
    }
}
