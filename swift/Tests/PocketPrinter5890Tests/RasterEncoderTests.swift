import PocketPrinter5890Kit
import XCTest

final class RasterEncoderTests: XCTestCase {
    func testValidatesRasterSize() throws {
        XCTAssertThrowsError(try MonochromeBitmap(width: 96, height: 240, bytes: [0x00]))
        let bytes = Array(repeating: UInt8(0), count: 12 * 240)
        let bitmap = try MonochromeBitmap(width: 96, height: 240, bytes: bytes)
        XCTAssertEqual(bitmap.bytes.count, 2880)
    }

    func testEncodesNinetySixPixelsAsTwelveBytes() throws {
        let pixels = Array(repeating: true, count: 96)
        let bitmap = try RasterEncoder.encodeBlackPixels(pixels, width: 96, height: 1)
        XCTAssertEqual(bitmap.widthBytes, 12)
        XCTAssertEqual(bitmap.bytes, Array(repeating: 0xff, count: 12))
    }

    func testBitOrderIsMostSignificantBitFirst() throws {
        let row = [true, false, true, false, false, true, false, true]
            + Array(repeating: false, count: 88)
        let bitmap = try RasterEncoder.encodeBlackPixels(row, width: 96, height: 1)
        XCTAssertEqual(bitmap.bytes[0], 0b1010_0101)
    }

    func testHeaderFor96By240Label() throws {
        let bitmap = try MonochromeBitmap(width: 96, height: 240, bytes: Array(repeating: 0, count: 12 * 240))
        XCTAssertEqual(Array(RasterEncoder.rasterCommand(for: bitmap).prefix(8)), [0x1d, 0x76, 0x30, 0x00, 0x0c, 0x00, 0xf0, 0x00])
    }

    func testHeightAbove255UsesLittleEndian() throws {
        let bitmap = try MonochromeBitmap(width: 96, height: 320, bytes: Array(repeating: 0, count: 12 * 320))
        XCTAssertEqual(Array(RasterEncoder.rasterCommand(for: bitmap).prefix(8)), [0x1d, 0x76, 0x30, 0x00, 0x0c, 0x00, 0x40, 0x01])
    }
}
