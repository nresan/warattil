# Third-party content bundled with WARATTIL

The application source code in this repository is MIT-licensed (see `LICENSE`).
The following bundled content is **not** covered by that licence and remains
under the terms of its respective owner. If you redistribute a build of
WARATTIL, you are responsible for respecting these terms.

## Quran text and scholarly data — King Fahd Glorious Quran Printing Complex (KFGQPC)

| Item | Files | Origin |
| --- | --- | --- |
| Uthmani Hafs text, page/line layout (Madinah Mushaf) | `android/app/src/main/assets/quran_v2.db`, `ios/Warattil/Warattil/Resources/quran_v*.db` | KFGQPC `hafsData_v2-0` |
| التفسير الميسر (Tafseer al-Muyassar) | `tafseer_muyassar.json` | KFGQPC |
| الميسر في غريب القرآن (rare-word dictionary) | `ghareeb.json` | KFGQPC |
| KFGQPC Uthmanic Script HAFS font | `kfgqpc_uthmanic_script_hafs_regular.otf` and per-page QCF fonts under `ios/.../Resources/Fonts/qcf/` | KFGQPC (fonts published for the Madinah Mushaf project) |

KFGQPC makes these available free of charge for non-commercial use with the
text unaltered. WARATTIL ships the text byte-for-byte as received and is
free of charge and ad-free. Verified-text acknowledgement to the Tanzil
project is kept in the in-app About sheet.

## Fonts (SIL Open Font License 1.1)

- **Amiri** — Khaled Hosny
- **Aref Ruqaa** — Abdullah Aref, Khaled Hosny
- **Noto Naskh Arabic** — Google

## Libraries

Android: AndroidX / Jetpack Compose, Room, WorkManager, Glance, Google Play
In-App Update — Apache-2.0. iOS: system frameworks only (SwiftUI, UserNotifications,
CoreLocation).

## Trademarks

"ورتّل" / "WARATTIL", the app icon and the Mushaf-page visual identity are
the marks of the project. You may build and publish derivative apps under
the MIT licence, but please give them their own name and icon so users are
not confused about which build they are installing.
