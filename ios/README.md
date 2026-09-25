# WARATTIL — iOS Port

iOS counterpart of the WARATTIL Android app (`com.warattil.warattilmushaf`, live on Google Play since December 2025).

- **[`docs/FIRST_LAUNCH.md`](docs/FIRST_LAUNCH.md)** — open this first if you've just sat down at the Mac and want to run the app in Xcode.
- `docs/BLUEPRINT.md` — canonical spec.
- `docs/KICKOFF.md` — historical (2026-04-19) decision record. Most "not done yet" items are now done.

## Layout

```
ios/
├── BLUEPRINT.md                         # (in docs/) — canonical spec
├── docs/
│   ├── BLUEPRINT.md
│   └── KICKOFF.md                       # current decisions + environment status
│
├── Package.swift                        # SPM manifest for pure-Swift test runs
│
├── Tools/
│   └── generate_boundary_fixture.py     # regenerates the page/juz fixtures
│
├── Warattil/
│   ├── Sources/
│   │   ├── Core/
│   │   │   ├── WarattilConstants.swift  # locked colours, typography, Mushaf constants
│   │   │   └── ShareUtil.swift          # ayah-share + app-share payload builders
│   │   ├── Data/
│   │   │   ├── Ayah.swift               # quran_text row model
│   │   │   ├── QuranMetadata.swift      # metadata records + Int.arabicDigits helper
│   │   │   └── MetadataParser.swift     # ports MetadataParser.kt (XMLParser-based)
│   │   ├── UI/                          # (empty — SwiftUI views come next)
│   │   └── App/                         # (empty — @main App struct comes next)
│   │
│   ├── Resources/
│   │   ├── quran_v2.db                  # Hafs Mushaf text (bundled read-only)
│   │   ├── quran_metadata.xml           # page + juz + sura boundaries (renamed from Android)
│   │   └── Fonts/                       # 15 .otf/.ttf files registered in Info.plist
│   │
│   └── SupportingFiles/
│       ├── Info.plist                   # UIAppFonts, orientation, locale, bundle id
│       └── PrivacyInfo.xcprivacy        # required-reason APIs + tracking declaration
│
└── WarattilTests/
    ├── MetadataParserTests.swift        # 604-page + 30-juz parity vs. Android fixture
    └── Fixtures/
        ├── page_boundaries.json         # ground-truth, regenerated from the XML
        └── juz_boundaries.json
```

## What's here vs. what comes next

**Here now (Phase 0–2 ported):**

- Complete data layer for the paging law: metadata parser + fixture + XCTest.
- Locked visual constants and share-payload builders.
- Info.plist and privacy manifest drafted.

**Coming next (pending Xcode + Nasser's kickoff answers):**

- Xcode project file — created on the Mac, in Xcode, not by hand.
- SwiftUI views (`MushaFScreen`, `MushaFHeader`, `MushaFFooter`, `MushaFBody`, `AyahActionBar`, the six sheets).
- GRDB.swift integration and `QuranRepository.swift`.
- App icon set + launch screen.
- TestFlight upload (blocked on Apple Developer enrollment).

## Running the parser test (once Xcode is installed)

```bash
cd ios
swift test                  # runs MetadataParserTests on the command line
```

Or from Xcode: open `Package.swift`, press ⌘U. Expect 604/604 pages and 30/30 juz to match.

If the fixture ever drifts from the XML, regenerate it:

```bash
python3 ios/Tools/generate_boundary_fixture.py
```

## Invariants (condensed — see BLUEPRINT for full treatment)

- Paging comes from `quran_metadata.xml`, NEVER the DB `page` column.
- Monotonic key = `surah * 10000 + ayah`.
- All reading-chrome digits are Eastern Arabic (٠–٩).
- Heritage palette: Cream `#F5F5DC`, Charcoal `#1A1A1A`, Mushaf Green `#1B5E20`, Deep Gold `#996515`.
- Progress bar: <30 % red, 30–70 % amber, >70 % green, ≥100 % sky blue.
- Landscape = 48 pt ayah text (NEVER call this "accessibility" or "elderly mode" in copy).
- No ads. No IAP. No analytics. No tracking. No auto-curated ayahs.
