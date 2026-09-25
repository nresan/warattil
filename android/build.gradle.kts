// Project-level build file
// MAINTAINER: Nasser (WARATTIL V2)
// ARCHITECTURE: Root delegations for AGP 8.4.0 / Gradle 8.7 stability

plugins {
    // We only declare the IDs here. The versions are delegated to settings.gradle.kts
    id("com.android.application") apply false
    id("org.jetbrains.kotlin.android") apply false
    id("com.android.library") apply false
    alias(libs.plugins.kotlin.compose) apply false

}