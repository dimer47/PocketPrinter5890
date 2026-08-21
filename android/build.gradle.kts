plugins {
    id("com.android.library") version "8.7.3" apply false
    id("com.android.application") version "8.7.3" apply false
    kotlin("android") version "2.0.21" apply false
    kotlin("jvm") version "2.0.21" apply false
    // Compose exige son plugin compilateur depuis Kotlin 2.0.
    id("org.jetbrains.kotlin.plugin.compose") version "2.0.21" apply false
}
