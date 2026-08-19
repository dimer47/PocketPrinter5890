import L13BLETransport
import XCTest

final class BLEProfileTests: XCTestCase {
    func testPreferredBLEProfileOrder() {
        XCTAssertEqual(L13BLEProfiles.preferred.map(\.id), [
            "Microchip Transparent UART",
            "FF00 UART",
            "18F0 UART",
            "E781 Combined UART"
        ])
        XCTAssertEqual(L13BLEProfiles.transparentUART.rx.uuidString.lowercased(), "49535343-8841-43f4-a8d4-ecbe34729bb3")
        XCTAssertEqual(L13BLEProfiles.transparentUART.tx.uuidString.lowercased(), "49535343-1e4d-4bd9-ba61-23c647249616")
    }

    func testAutomaticOrderStartsWithObservedResponsiveFF00() {
        XCTAssertEqual(L13BLEProfiles.orderedProfiles(preferredProfileID: L13BLEProfiles.automaticID).map(\.id), [
            "FF00 UART",
            "Microchip Transparent UART",
            "18F0 UART",
            "E781 Combined UART"
        ])
    }

    func testManualProfileSelectionIsTriedFirst() {
        XCTAssertEqual(
            L13BLEProfiles.orderedProfiles(preferredProfileID: "18F0 UART").first?.id,
            "18F0 UART"
        )
    }
}
