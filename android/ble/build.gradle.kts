plugins {
    id("com.android.library")
    kotlin("android")
}

android {
    namespace = "fr.pocketprinter5890.ble"
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
    api(project(":kit"))
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
}
