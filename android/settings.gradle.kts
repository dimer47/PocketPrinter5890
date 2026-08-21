pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "PocketPrinter5890"

// Coeur de la librairie: protocole, rendu, documents.
// Module JVM pur, sans dependance Android: testable sans emulateur.
include(":kit")
// Rendu de tickets en image, via android.graphics. Optionnel: seul le
// chemin « ticket rasterise » en a besoin.
include(":render")
// Transport BLE Android pret a l'emploi.
include(":ble")
// Application de demonstration.
include(":demo")
