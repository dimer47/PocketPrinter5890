import PocketPrinter5890BLE
import XCTest

final class BLEProfileTests: XCTestCase {
    func testPreferredBLEProfileOrder() {
        XCTAssertEqual(PrinterBLEProfiles.preferred.map(\.id), [
            "Microchip Transparent UART",
            "FF00 UART",
            "18F0 UART",
            "E781 Combined UART"
        ])
        XCTAssertEqual(PrinterBLEProfiles.transparentUART.rx.uuidString.lowercased(), "49535343-8841-43f4-a8d4-ecbe34729bb3")
        XCTAssertEqual(PrinterBLEProfiles.transparentUART.tx.uuidString.lowercased(), "49535343-1e4d-4bd9-ba61-23c647249616")
    }

    func testAutomaticOrderStartsWithObservedResponsiveFF00() {
        XCTAssertEqual(PrinterBLEProfiles.orderedProfiles(preferredProfileID: PrinterBLEProfiles.automaticID).map(\.id), [
            "FF00 UART",
            "Microchip Transparent UART",
            "18F0 UART",
            "E781 Combined UART"
        ])
    }

    func testManualProfileSelectionIsTriedFirst() {
        XCTAssertEqual(
            PrinterBLEProfiles.orderedProfiles(preferredProfileID: "18F0 UART").first?.id,
            "18F0 UART"
        )
    }
}
