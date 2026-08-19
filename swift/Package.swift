// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PocketPrinter5890",
    // Planchers determines empiriquement: `@Published` (Combine) n'existe
    // pas avant iOS 13 / macOS 10.15, ce qui fixe la limite basse.
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13)
    ],
    products: [
        // Coeur de la librairie: protocole, rendu, documents.
        // Aucune dependance a CoreBluetooth: utilisable avec n'importe quel
        // transport (BLE, USB, Bluetooth Classic, fichier).
        .library(name: "PocketPrinter5890Kit", targets: ["PocketPrinter5890Kit"]),
        // Transport CoreBluetooth pret a l'emploi.
        .library(name: "PocketPrinter5890BLE", targets: ["PocketPrinter5890BLE"]),
        // Outil console de diagnostic.
        .executable(name: "PocketPrinter5890Probe", targets: ["PocketPrinter5890Probe"])
    ],
    targets: [
        .target(
            name: "PocketPrinter5890Kit",
            path: "Sources/PocketPrinter5890Kit"
        ),
        .target(
            name: "PocketPrinter5890BLE",
            dependencies: ["PocketPrinter5890Kit"],
            path: "Sources/PocketPrinter5890BLE"
        ),
        .executableTarget(
            name: "PocketPrinter5890Probe",
            dependencies: ["PocketPrinter5890Kit", "PocketPrinter5890BLE"],
            path: "Sources/PocketPrinter5890Probe"
        ),
        .testTarget(
            name: "PocketPrinter5890Tests",
            dependencies: ["PocketPrinter5890Kit", "PocketPrinter5890BLE"],
            path: "Tests/PocketPrinter5890Tests"
        )
    ]
)
