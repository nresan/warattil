# WARATTIL — Android

Kotlin + Jetpack Compose. `applicationId com.warattil.warattilmushaf`, minSdk 24, targetSdk 36.

    ./gradlew assembleDebug        # debug APK
    ./gradlew bundleRelease        # needs keystore.properties (see ../README.md)

Key packages under `app/src/main/java/com/warattil/app/`:

- `ui/` — Mushaf screen, header/footer, sheets (fihris, bookmarks, wird, hifz, tafseer, about, guide)
- `data/` — Room database over the bundled KFGQPC `quran_v2.db`, metadata, repository
- `azan/` — prayer-time computation (Umm al-Qura), AlarmManager scheduler, playback service
- `widget/` — Glance home-screen widget
- `core/` — share utilities, constants

Historical notes from the V2→V3 fork are in `NOTES_V3_FORK_HISTORY.md`; the changelog for 3.0.0 is in `CHANGELOG_3.0.0.md`.
