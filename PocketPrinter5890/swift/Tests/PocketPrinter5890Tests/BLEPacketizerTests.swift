import PocketPrinter5890BLE
import XCTest

final class BLEPacketizerTests: XCTestCase {
    func testChunksWithoutLossOrDuplication() {
        let bytes = Array(UInt8(0)..<UInt8(100))
        let chunks = BLEPacketizer.chunks(bytes, maxWriteLength: 20)

        XCTAssertEqual(chunks.count, 5)
        XCTAssertEqual(chunks.flatMap { $0 }, bytes)
    }

    func testChunksNeverExceedMaximumWriteLength() {
        let bytes = Array(repeating: UInt8(0xaa), count: 2879)
        let chunks = BLEPacketizer.chunks(bytes, maxWriteLength: 182)

        XCTAssertTrue(chunks.allSatisfy { $0.count <= 182 })
        XCTAssertEqual(chunks.flatMap { $0 }.count, bytes.count)
    }
}
