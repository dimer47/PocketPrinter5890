plugins {
    id("com.android.library")
    kotlin("android")
}

android {
    namespace = "fr.pocketprinter5890.render"
    compileSdk = 35

    defaultConfig {
        minSdk = 24
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    // Le rendu produit un MonochromeBitmap: il depend du coeur, jamais
    // l'inverse. `kit` reste un module JVM pur, testable sans emulateur.
    api(project(":kit"))
}
