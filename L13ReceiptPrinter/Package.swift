// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "L13ReceiptPrinter",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "L13Core", targets: ["L13Core"]),
        .library(name: "L13BLETransport", targets: ["L13BLETransport"]),
        .executable(name: "L13ReceiptPrinter", targets: ["L13ReceiptPrinter"]),
        .executable(name: "L13BLEProbe", targets: ["L13BLEProbe"])
    ],
    targets: [
        .target(
            name: "L13Core",
            path: "Sources/L13Core"
        ),
        .target(
            name: "L13BLETransport",
            dependencies: ["L13Core"],
            path: "Sources/L13BLETransport"
        ),
        .executableTarget(
            name: "L13ReceiptPrinter",
            dependencies: ["L13Core", "L13BLETransport"],
            path: "Sources/L13ReceiptPrinter",
            resources: [.copy("BluetoothInfoTemplate.plist")]
        ),
        .executableTarget(
            name: "L13BLEProbe",
            dependencies: ["L13Core", "L13BLETransport"],
            path: "Sources/L13BLEProbe"
        ),
        .testTarget(
            name: "L13ReceiptPrinterTests",
            dependencies: ["L13Core", "L13BLETransport"],
            path: "Tests/L13ReceiptPrinterTests"
        )
    ]
)
