# WARATTIL V3 — Hifz experimental branch

Forked from `WarattilV2/` on 2026-04-23 so the Hifz phase-1 overhaul can be
iterated on without destabilising the published v2.2.1 Android app.

## Identity vs. V2

|                  | V2 (stable)                     | V3 (this folder)                    |
|------------------|---------------------------------|-------------------------------------|
| applicationId    | `com.warattil.warattilmushaf`   | `com.warattil.warattilmushaf.v3`    |
| versionCode      | 28 (internal) / 27 live         | restarts at 1                       |
| versionName      | 2.2.2                           | 3.0.0-alpha                         |
| Launcher label   | "Warattil V2"                   | "ورتّل V3"                           |
| Kotlin namespace | `com.warattil.app`              | `com.warattil.app` (unchanged)      |

Because the applicationId differs, V3 installs **alongside** V2 on the same
phone. Each app gets its own sandboxed SharedPreferences and Room database,
so V3 starts from an empty Hifz state and the Phase-1 migration can be
exercised on a truly clean slate.

## What's new in V3

Phase-1 Hifz storage (already applied on arrival):

- Ayah-atomic storage (`Set<Long>` keyed by `sura × 10000 + aya`) with
  one-time migration from the legacy `Set<Int>` page set.
- Bulk picker sheet (juz / surah / page-range tabs) for restoring prior
  memorization.
- Density heatmap with desert → garden gradient + gold flower overlay on
  the last page of every fully-memorized juz (max 30 flowers).
- Per-ayah memorize toggle in the long-press action bar.
- Tri-state page-strip tint (empty / partial / full) driven by per-page
  ayah ratio.
- Fractional juz rows with percent readouts on the stats tab.

## iOS

Intentionally not copied. iOS work continues in `WarattilV2/ios/` for now;
V3 is Android-only until Hifz stabilises.

## Signing

V3 should **not** be signed with the production upload keystore
(`warattil_new_upload.jks`). Use the Android Studio debug keystore for
local testing. If V3 ever gets a Play Store listing of its own, it needs
a new, distinct upload key to avoid collision with V2's identity.
