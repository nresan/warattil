pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}

// AGP pinned at the last stable 8.x (8.11.1) — AGP 9.x removed BaseExtension,
// which Kotlin 1.9.24's Gradle plugin still casts to, causing a ClassCastException
// at KotlinAndroidPlugin.kt:39. Revisit AGP 9 migration after 2.1.2 ships.
plugins {
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.0.21" apply false
    id("com.android.library") version "8.11.1" apply false
    id("org.gradle.toolchains.foojay-resolver-convention") version "0.8.0"
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "Warattil V3"
include(":app")