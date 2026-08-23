// swift-tools-version: 5.9

import PackageDescription

// Manifeste a la racine du depot.
//
// SwiftPM exige que `Package.swift` soit a la racine pour qu'un projet tiers
// puisse declarer ce depot comme dependance par son URL GitHub. Les sources
// restent dans `swift/`, ou elles cohabitent avec les portages Android et
// Web: seuls les chemins sont prefixes.
//
// Le manifeste `swift/Package.swift` est conserve pour qui travaille
// directement dans ce sous-dossier.
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
        .library(name: "PocketPrinter5890BLE", targets: ["PocketPrinter5890BLE"])
    ],
    targets: [
        .target(
            name: "PocketPrinter5890Kit",
            path: "swift/Sources/PocketPrinter5890Kit"
        ),
        .target(
            name: "PocketPrinter5890BLE",
            dependencies: ["PocketPrinter5890Kit"],
            path: "swift/Sources/PocketPrinter5890BLE"
        )
    ]
)
