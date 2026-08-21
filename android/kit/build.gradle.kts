plugins {
    kotlin("jvm")
}

// Le coeur est un module JVM pur, sans SDK Android: les tests tournent
// directement sur la machine de developpement, sans emulateur.
// On cible le bytecode 17 (plancher de l'Android Gradle Plugin) sans exiger
// qu'un JDK 17 exact soit installe: le JDK courant compile vers cette cible.
kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

dependencies {
    // ZXing pour les QR codes. Ecrire un encodeur QR conforme (masques,
    // penalites, format BCH) est une source d'erreurs silencieuses: un QR
    // faux ne se voit qu'au scanner. C'est aussi ce qu'utilise l'application
    // officielle. Les codes-barres lineaires restent en Kotlin pur.
    implementation("com.google.zxing:core:3.5.3")

    testImplementation(kotlin("test"))
}

tasks.test {
    useJUnitPlatform()
}
