import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("kotlin-kapt")
    alias(libs.plugins.kotlin.compose)
}

// ── Release signing ────────────────────────────────────────────────────────
// Read keystore secrets from ./keystore.properties at the repo root.  The
// file is .gitignored so passwords + the .jks path never enter version
// control.  Template lives at ./keystore.properties.example — copy to
// keystore.properties and fill in the four values for your machine.
//
// If keystore.properties is missing (CI / fresh clone with no signing
// material) the release build falls back to debug signing so `assembleRelease`
// still succeeds for smoke-tests; only `bundleRelease` for Play Store
// upload requires the real keystore.
val keystorePropsFile = rootProject.file("keystore.properties")
val keystoreProps = Properties().apply {
    if (keystorePropsFile.exists()) {
        keystorePropsFile.inputStream().use { load(it) }
    }
}
val hasReleaseSigning: Boolean =
    (keystoreProps.getProperty("storeFile")?.isNotBlank() == true) &&
    (keystoreProps.getProperty("keyAlias")?.isNotBlank()  == true)

android {
    namespace = "com.warattil.app"
    compileSdk = 36

    defaultConfig {
        // applicationId is what Google Play uses to identify the app.
        // 2026-04-29: V3 absorbs the V2 listing — `.v3` suffix removed so
        // this build uploads as the next version of the existing
        // com.warattil.warattilmushaf app (replacing 2.2.2, not creating
        // a new listing).  Decision is one-way: V3's standalone .v3 Play
        // listing is now abandoned; future releases all go through the
        // unified V2 listing.
        applicationId = "com.warattil.warattilmushaf"
        minSdk = 24
        targetSdk = 36
        // versionCode MUST be higher than any prior version under THIS
        // applicationId on Play.  Now that V3 absorbs the V2 listing,
        // the next free code is 29 (V2's last shipped was 28 = 2.2.2).
        //
        // Ledger (unified com.warattil.warattilmushaf listing):
        //   2.2.2  = 28 (V2 — last release before V3 absorption)
        //   3.0.0  = 29 (KFGQPC content refresh + Hifz phase-1 + Tafseer
        //                 Muyassar + Ghareeb dictionary + wird anchor engine
        //                 + image shares)
        //   3.0.1  = 30 (Azan / prayer-time reminders with user-uploaded
        //                 audio, per-prayer mode picker, Umm al-Qura
        //                 calculation, AlarmManager scheduler)
        //   3.0.2  = 31 (Widget hybrid design: reading state + Azan countdown
        //                 line; T+20 post-prayer flip alarm made resilient to
        //                 Doze/force-stop; PrayerTimes.nextTwoAfter() added)
        //   3.1.0  = 32 (Target Android 16 / API 36 — Play Store policy
        //                 compliance (deadline Aug 31 2026); predictive-back
        //                 callback enabled; Azan stop-button in notification;
        //                 in-app Arabic help guide (HTML); iOS App Store QR
        //                 redirect live (id6766103481))
        versionCode = 33
        versionName = "3.1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables { useSupportLibrary = true }
    }

    // ── Signing configs ────────────────────────────────────────────────────
    // `release` reads from keystore.properties (see top-of-file block).
    // The actual .jks file lives OUTSIDE the repo on the developer's
    // machine and is referenced by absolute path inside keystore.properties
    // — we never check in keystore material, even encrypted.
    //
    // Verify the SHA-1 of the resolved keystore matches the registered
    // Play Store upload key BEFORE every upload.  Last verified
    // SHA-1: 75:50:B1:91:…  (warattil_new_upload.jks, alias `upload`).
    // Mismatch = Play Console will reject the AAB.
    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile     = file(keystoreProps.getProperty("storeFile")!!)
                storePassword = keystoreProps.getProperty("storePassword")
                keyAlias      = keystoreProps.getProperty("keyAlias")
                keyPassword   = keystoreProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Code-shrinking left OFF for now — historical decision; the
            // app's compose tree + KFGQPC fonts dominate APK size, and
            // R8's reflection rules would need careful tuning around
            // Room + Glance.  Revisit when APK size becomes the binding
            // constraint (currently ~32 MB, well under Play's 150 MB cap).
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")

            // Wire the release signing config when the keystore is
            // available; otherwise the release variant inherits the debug
            // signature so `assembleRelease` smoke-tests don't fail
            // outright on a fresh clone without keystore.properties.
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    buildFeatures {
        compose = true
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }

    // ── Lint configuration ──────────────────────────────────────────────────
    // Release lint currently reports ~84 errors, the vast majority being
    // transitive-library advisories — e.g. `InvalidFragmentVersionForActivity
    // Result` flagged on MainActivity.kt even though it extends
    // ComponentActivity (not Fragment), simply because *some* dep on the
    // graph pulls a pre-1.3.0 Fragment that we never use.
    //
    // Baseline approach (recommended by Google for exactly this situation):
    // snapshot the current findings as "known debt" so release builds stop
    // failing on them, but any NEW lint error in future code still blocks
    // the build. This preserves the quality gate without turning pre-
    // existing transitive noise into a release blocker.
    //
    // To regenerate the baseline after a dedicated lint-cleanup pass:
    //     ./gradlew updateLintBaseline
    lint {
        baseline = file("lint-baseline.xml")
    }
}

dependencies {
    // Core & Compose
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material.icons.extended)

    // Room Database (Quran Engine)
    implementation(libs.androidx.room.runtime)
    implementation(libs.androidx.room.ktx)
    kapt(libs.androidx.room.compiler)

    // Splash screen — Android 12+ windowSplash wrapper (compat API 23+)
    implementation(libs.androidx.core.splashscreen)

    // WorkManager — local scheduled notifications
    implementation(libs.androidx.work.runtime.ktx)

    // Glance — home-screen widget (core must be explicit; appwidget does not re-export ColorProvider)
    implementation(libs.androidx.glance)
    implementation(libs.androidx.glance.appwidget)
    implementation(libs.androidx.glance.material3)

    // Google Play In-App Update — flexible flow. Lets users install the next
    // release from inside the app instead of waiting for the Play Store badge
    // to appear (which relies on a client-side 24h cache). No backend, no
    // tokens — rides on Play Services that are already installed.
    implementation(libs.google.play.app.update.ktx)

    // Testing
    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(platform(libs.androidx.compose.bom))
}
