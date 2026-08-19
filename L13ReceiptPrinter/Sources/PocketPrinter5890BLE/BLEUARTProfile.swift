import CoreBluetooth
import Foundation

public struct BLEUARTProfile: Equatable, Identifiable {
    public let id: String
    public let service: CBUUID
    public let tx: CBUUID
    public let rx: CBUUID
    public let combined: Bool
    public let extraNotify: CBUUID?

    public init(id: String, service: CBUUID, tx: CBUUID, rx: CBUUID, combined: Bool = false, extraNotify: CBUUID? = nil) {
        self.id = id
        self.service = service
        self.tx = tx
        self.rx = rx
        self.combined = combined
        self.extraNotify = extraNotify
    }
}

public enum PrinterBLEProfiles {
    public static let automaticID = "Automatique"

    public static let transparentUART = BLEUARTProfile(
        id: "Microchip Transparent UART",
        service: CBUUID(string: "49535343-fe7d-4ae5-8fa9-9fafd205e455"),
        tx: CBUUID(string: "49535343-1e4d-4bd9-ba61-23c647249616"),
        rx: CBUUID(string: "49535343-8841-43f4-a8d4-ecbe34729bb3"),
        extraNotify: CBUUID(string: "49535343-aca3-481c-91ec-d85e28a60318")
    )

    public static let ff00 = BLEUARTProfile(
        id: "FF00 UART",
        service: CBUUID(string: "FF00"),
        tx: CBUUID(string: "FF01"),
        rx: CBUUID(string: "FF02"),
        extraNotify: CBUUID(string: "FF03")
    )

    public static let service18F0 = BLEUARTProfile(
        id: "18F0 UART",
        service: CBUUID(string: "18F0"),
        tx: CBUUID(string: "2AF0"),
        rx: CBUUID(string: "2AF1")
    )

    public static let combinedE781 = BLEUARTProfile(
        id: "E781 Combined UART",
        service: CBUUID(string: "e7810a71-73ae-499d-8c15-faa9aef0c3f2"),
        tx: CBUUID(string: "bef8d6c9-9c21-4c9e-b632-bd58c1009f9f"),
        rx: CBUUID(string: "bef8d6c9-9c21-4c9e-b632-bd58c1009f9f"),
        combined: true
    )

    public static let preferred = [transparentUART, ff00, service18F0, combinedE781]
    public static let observedResponsive = [ff00, transparentUART, service18F0, combinedE781]
    public static let allServiceUUIDs = preferred.map(\.service)

    public static func profile(service uuid: CBUUID) -> BLEUARTProfile? {
        preferred.first { $0.service == uuid }
    }

    public static func orderedProfiles(preferredProfileID: String) -> [BLEUARTProfile] {
        guard preferredProfileID != automaticID,
              let selected = preferred.first(where: { $0.id == preferredProfileID })
        else {
            return observedResponsive
        }
        return [selected] + preferred.filter { $0.id != selected.id }
    }
}
