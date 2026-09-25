# WARATTIL iOS Port — Blueprint & Scope

**For:** the iOS engineer agent who will build the iPhone version of WARATTIL.
**From:** Nasser (founder, sole developer).
**Status:** canonical spec. If anything in this document conflicts with a hunch, assumption, or pattern you remember from another project, this document wins. Confirm with Nasser before departing from it.

---

## 0. How to Read This Document

Read the whole file before writing a single line of Swift. The Android app is shipping in production at version 2.1.2 (Play Store: `com.warattil.warattilmushaf`). Your goal is not "a Quran app for iPhone" — it is **WARATTIL on iPhone at visual and behavioural parity with the Android build**, using Apple-native frameworks where mirroring is not possible.

Sections 1–3 are non-negotiable invariants. Sections 4–9 describe the Android reference and the proposed iOS translation. Sections 10–13 are your working plan. Section 14 is the "things that will make Nasser correct you if you do them" list — read it twice.

---

## 1. Project Identity

WARATTIL (ورتِّل) is a premium, ad-free Quran app for Arabic-reading Muslims. The aesthetic reference is the Golden Quran app and the physical Saudi Mushaf (KFGQPC Hafs). Every design decision resolves toward: scholarly precision, a traditional (Kuttāb) visual identity, and *ajr*-oriented product framing — not engagement/retention.

- **Android app:** shipping at versionCode 24 / versionName 2.1.2 as `com.warattil.warattilmushaf`.
- **iPhone target:** same name, same bundle ID (`com.warattil.warattilmushaf`), same brand, same colours, same typography, same Arabic copy. Users who have both should feel they are using one app with two skins, not two apps that happen to share a name.

---

## 2. Non-Negotiable Invariants

These are locked. Never propose alternatives.

### 2.1 Visual Identity (Heritage theme — the default)

```
Background   Cream        #F5F5DC
Body text    Charcoal     #1A1A1A
Accent       Mushaf Green #1B5E20
Gold         Deep Gold    #996515   (Islimi borders, ayah-marker brackets, separators)
Banner BG    Off-cream    #F0EED8   (surah name-plate fill)
Divider      Green 20%    #1B5E20 @ 33/255 alpha
```

Two additional themes exist and must be ported:

```
Dark (Obsidian)   bg #121212   text #E8DCC8   accent #4CAF50   gold #B8860B   banner #1E2A1E
Sepia             bg #F4E6C8   text #3B2A1A   accent #6B3A2A   gold #8B6914   banner #EDD9B0
```

Progress bar colours are theme-invariant (30-40-30-Beyond law, §2.4):

```
0–30 %     Red 700   #D32F2F
30–70 %    Amber 700 #FFA000
70–100 %   Mushaf Green #1B5E20
>100 %     Sky Blue  #03A9F4
```

### 2.2 Paging Law

The Mushaf has **exactly 604 pages** (standard Madani Mushaf). Page boundaries are derived **exclusively** from `quran_metadata_fixed.xml` bundled in the app. The SQLite `page` column in `quran_v2.db` is **never** used for boundary determination — it exists for legacy compatibility and is wrong in enough edge cases that relying on it produces off-by-one errors.

Range queries use the monotonic key formula:

```
key = surah * 10000 + ayah
```

For a given page N, `MetadataParser.getPageBoundaries(N)` returns `(startKey, endKey)`. All ayah fetches for a page are `WHERE monotonic_key BETWEEN startKey AND endKey`. This is invariant.

### 2.3 Typography

- **Quranic text:** KFGQPC Uthmanic Script HAFS (regular). Font file ships in Android at `app/src/main/res/font/kfgqpc_uthmanic_script_hafs_regular.otf` — copy that exact file into the iOS bundle.
- **Fallback for Quran text:** Amiri regular (shipped).
- **Chrome / UI:** Aref Ruqaa for headings, Noto Naskh Arabic or Reem Kufi for body UI. All shipped in `app/src/main/res/font/` on Android.
- **All numbers** (ayah markers ٥, page numbers, juz numbers, progress percentages) — **Eastern Arabic digits** (٠١٢٣٤٥٦٧٨٩). Latin digits (0–9) must not appear anywhere in the reading chrome. Implementation reference:

```swift
extension Int {
    /// Map Latin 0–9 → Eastern Arabic ٠–٩. Used everywhere a digit is rendered.
    var arabicDigits: String {
        String(self).map { ch -> Character in
            ch.asciiValue.map { Character(UnicodeScalar(0x0660 + Int($0 - 0x30))!) } ?? ch
        }.map(String.init).joined()
    }
}
```

### 2.4 Momentum Logic (Progress Bar)

The bottom progress bar reflects daily wird completion (user-set daily reading goal). Colour tiers are non-negotiable:

- **< 30 %** — Red (`#D32F2F`). The copy beside the bar reads in a gentle encouragement register.
- **30 % – 70 %** — Amber (`#FFA000`). Middle register.
- **> 70 %** — Mushaf Green (`#1B5E20`). Positive register.
- **≥ 100 %** — Sky Blue (`#03A9F4`). Celebratory register.

The bar width is 88 % of screen width, 12 pt tall, 6 pt corner radius. The percentage label is Eastern-Arabic-digits.

### 2.5 Large-Font Landscape Reading

In landscape orientation, ayah text forces to **48 pt / 72 pt line height**, and the header + footer minimize (small strip, no overflow menu). This is a *reading-quality* feature.

**Copy tone rule (critical):** Never describe this as "Elderly Mode", "accessibility", "for weak vision", or similar. It is "wide reading" / "manuscript reading" framing — describe the experience (generous spacing, unhurried glance), not the user. The internal constant name `AYAH_FONT_LANDSCAPE` is fine; user-facing copy must not frame it around impairment.

### 2.6 Ajr-First Product Philosophy

WARATTIL is built for *ajr* (spiritual reward earned by helping others reach good), not for engagement metrics. Concrete rules:

- **Share payloads get a MINIMAL signature:** one em-dash line `— تطبيق ورتّل` plus the App Store URL, separated from the ayah by a blank line. No hadith framing inside ayah shares. No taglines. No emoji. (The standalone "share the app" flow is different — see §11.3.)
- **Notifications default to OPT-IN.** Never default-on.
- **No in-app ads. No in-app purchases. No upsells.** The app is free and ad-free, permanently.
- **"Simple > complete"** when in doubt. Nasser has explicitly picked the simpler of two paths multiple times.

### 2.7 No Auto-Curation of Quran Content

This is the rule that killed an entire shipped feature on Android (آية اليوم / "Ayah of the Day"). Do not re-propose it in any form.

**The rule:** the app never chooses which ayah to show. Random selection surfaces inappropriate ayahs out of context (e.g., مقطعات letters like `الم`, single-word context-dependent ayahs like `مدهامتان`, or severe punishment verses). Any curation algorithm would impose editorial judgement and violate scholarly neutrality. **All ayah-level content surfacing must originate from a user gesture** (long-press, bookmark, selection).

What's OK: surfacing *the user's own* last-read position, their bookmarks, their hifz progress. These are their state, not the app's picks.

### 2.8 Share-URL Shortening

The share payload currently appends the full Play Store URL. On iOS it will append the App Store URL. **Do not propose URL shorteners (bit.ly, tinyurl, etc.).** Nasser has decided that when the brand domain is registered, the URL will move to a redirect on his own host (`warattil.app/get` or similar). Until then, the full store URL is correct. The canonical URL lives in one constant per platform — on Android it's `ShareUtil.PLAY_URL`, on iOS it should be `ShareUtil.appStoreURL` (or equivalent single source of truth).

### 2.9 Logo & Asset Handling

Nasser's supplied logo and assets are final art. Never recolour, re-composite, split layers, redraw in vector, or "enhance" them. If a transform seems technically necessary (e.g., generating iOS app-icon slices from a master), ask first.

---

## 3. Android Reference Implementation — File Map

These are the files you are translating. Read each one before starting its iOS counterpart. Paths are relative to `app/src/main/`.

**Core / data layer:**

- `java/com/warattil/app/core/WarattilConstants.kt` — locked colours, typography, layout metrics, database name, total pages (604), Basmala string. The source of truth for every hex code and sp value.
- `java/com/warattil/app/core/ShareUtil.kt` — app-share intent + canonical `PLAY_URL` constant.
- `java/com/warattil/app/data/MetadataParser.kt` — parses `quran_metadata_fixed.xml`. Supplies `getPageBoundaries(page)`, `getJuzBoundaries(juz)`, `getSuraName(surah)`. **This is the only correct source of page/juz boundaries.**
- `java/com/warattil/app/data/QuranMetadata.kt` — data models backing MetadataParser.
- `java/com/warattil/app/data/Ayah.kt` — the row model. Fields: `surah`, `ayah`, `text`, `page` (ignored), plus monotonic_key.
- `java/com/warattil/app/data/QuranDao.kt` — Room DAO. Key method: `getAyahsByMonotonicRange(start, end): Flow<List<Ayah>>`. Also has `searchAyahs(query)` which strips Arabic diacritics (tashkeel) before a LIKE comparison.
- `java/com/warattil/app/data/QuranDatabase.kt` — Room database reading from bundled `quran_v2.db`.
- `java/com/warattil/app/data/UserDatabase.kt` + `UserDao.kt` + `Bookmark.kt` — **separate** writable DB for bookmarks, preferences, hifz entries. Critical split.
- `java/com/warattil/app/data/QuranRepository.kt` — the only data-access gateway. Implements the paging law. Contains:
  - `getPageContent(pageNumber)` — returns `PageContent(pageNumber, ayahs, surahName, juzNumber)`.
  - `searchAyahs(query)` — returns `List<SearchResult>` with each hit resolved to its correct page via MetadataParser.
  - Lazy `surahStartPages: Map<Int,Int>` and `juzStartPages: Map<Int,Int>`.
  - Bookmark + preferences delegates to DAO.

**UI layer (Jetpack Compose / Material 3):**

- `java/com/warattil/app/ui/MushaFTheme.kt` — the three themes (`Heritage`, `Dark`, `Sepia`) as `ThemeColors` data classes. Passed explicitly to composables (no CompositionLocal).
- `java/com/warattil/app/ui/MushaFScreen.kt` — root screen, hosts `HorizontalPager` across 604 pages.
- `java/com/warattil/app/ui/MushaFHeader.kt` — top strip (surah name, juz label, overflow menu). Portrait + Landscape variants.
- `java/com/warattil/app/ui/MushaFFooter.kt` — bottom strip (progress bar, page number).
- `java/com/warattil/app/ui/MushaFBody.kt` — per-page text rendering with the Uthmani font and ornate ayah markers.
- `java/com/warattil/app/ui/MushaFViewModel.kt` — state for current page, selected ayah, theme, preferences.
- `java/com/warattil/app/ui/AyahActionBar.kt` — the floating Copy/Share/Close pill shown on long-press. **The `formatAyahForShare(ayah)` function is the canonical share formatter** — its output is locked:

  ```
  ﴿ {ayah text, annotations stripped} ﴾
  سورة {name} · الآية {n in Eastern Arabic digits}

  — تطبيق ورتّل
  {store URL}
  ```

- `java/com/warattil/app/ui/AboutSheet.kt` — "عن التطبيق".
- `java/com/warattil/app/ui/UsageGuideSheet.kt` — "دليل الاستخدام".
- `java/com/warattil/app/ui/HifzLogSheet.kt` — "حلقة الحفظ" entry log.

**System integrations:**

- `java/com/warattil/app/MainActivity.kt` — single activity, sets content.
- `java/com/warattil/app/WarattilApp.kt` — Application subclass.
- `java/com/warattil/app/NotificationHelper.kt` — local notifications.
- `java/com/warattil/app/WirdReminderWorker.kt` — WorkManager daily-wird reminder.
- `java/com/warattil/app/HifzRevisionWorker.kt` — WorkManager hifz revision schedule.
- `java/com/warattil/app/widget/WarattilWidgetReceiver.kt` + `WarattilWidget.kt` — Glance home-screen widget.

**Assets (portable to iOS as-is):**

- `assets/quran_v2.db` — the Hafs Mushaf text. Bundle read-only in iOS Resources.
- `assets/quran_metadata_fixed.xml` — page/juz boundaries. Bundle in iOS Resources.
- `res/font/kfgqpc_uthmanic_script_hafs_regular.otf` — the canonical Quran font.
- `res/font/amiri_*.ttf`, `arefruqaa_*.ttf`, `notonaskharabic_*.ttf`, `reemkufi_*.ttf` — UI/fallback fonts.

---

## 4. Proposed iOS Stack

Treat these as recommended defaults. Confirm with Nasser at kickoff (§13) before committing.

- **UI:** SwiftUI. Parallels Compose conceptually (declarative, reactive state). UIKit is not recommended — it forces a different mental model than the Android implementation and slows porting.
- **Minimum iOS:** iOS 16.0. NavigationStack, `.navigationDestination`, and `@Observable` (in iOS 17) are cleaner than older equivalents. If Nasser wants broader reach, drop to iOS 15 and use `NavigationView` + `ObservableObject`.
- **Language:** Swift 5.9+ (matches Xcode 15+).
- **Reactive/state:** SwiftUI native (`@State`, `@Binding`, `@Observable` or `@StateObject`). No RxSwift, no Combine beyond what SwiftUI already uses.
- **Database (Quran text, read-only):** [GRDB.swift](https://github.com/groue/GRDB.swift). Reads the bundled `quran_v2.db` directly without a copy step. Ships as SPM.
- **Database (user data, writable):** Either a second GRDB store in Documents directory, or `@AppStorage` + JSON for the tiny stuff. Bookmarks are a list of page numbers — `@AppStorage` with a JSON-encoded `[Int]` is sufficient. Hifz log might deserve GRDB if entries grow.
- **Dependency manager:** Swift Package Manager. No CocoaPods.
- **Icons:** SF Symbols for system chrome (menu dots, share, copy, close, search). **Do not** pull from Android's Material icons set — use the SF Symbol equivalent (`ellipsis`, `doc.on.doc`, `square.and.arrow.up`, `xmark`, `magnifyingglass`). This is the one place Apple-native visual language is preferred over parity.
- **Background work:** `BackgroundTasks` framework (`BGAppRefreshTask`) for the daily wird reminder. Local notifications via `UserNotifications` (`UNUserNotificationCenter`).
- **Widget:** WidgetKit (separate app extension target). **Deferred past v1** unless Nasser prioritises it — ship reading parity first.

---

## 5. Feature Parity Inventory

The menu on Android has seven items. Each is a surface to port.

| # | Label (Arabic) | Transliteration | What it is | Complexity |
|---|---|---|---|---|
| — | (Mushaf) | — | The 604-page reader. Default/home screen. | Highest |
| 1 | الفهرس | Al-Fihris | Surah + Juz index, tap jumps to page. | Medium |
| 2 | إشاراتي | Ishārātī | Bookmarks list. Tap jumps to page; swipe to delete. | Low |
| 3 | الورد اليومي | Al-Wird al-Yawmī | Daily wird tracker (set goal, show progress, opt-in reminder). | Medium |
| 4 | حلقة الحفظ | Ḥalqat al-Ḥifẓ | Hifz circle — logs revision entries, shows schedule. | Medium |
| 5 | دليل الاستخدام | Dalīl al-Istikhdām | Usage guide (sheet). | Low |
| 6 | عن التطبيق | ʿAn at-Taṭbīq | About screen (sheet). | Low |
| 7 | شارك ورتّل | Shārik Warattil | App-share flow (§11.3). | Low |
| — | Search | — | Magnifying-glass icon in header. Diacritic-tolerant text search. | Medium |
| — | Theme toggle | — | Palette icon in header; cycles Heritage → Dark → Sepia. | Low |

**Long-press on an ayah** surfaces the floating action bar (Copy / Share / Close). This is the primary content-share surface. Task #4 in the Android backlog is multi-ayah contiguous range share — currently pending; don't ship until requested.

---

## 6. Asset Reuse

Nothing in `assets/` or `res/font/` needs to be recreated. Copy these files verbatim into the iOS project's Resources folder:

```
quran_v2.db                                  → Resources/quran_v2.db          (read-only, bundled)
quran_metadata_fixed.xml                     → Resources/quran_metadata.xml   (bundled)
kfgqpc_uthmanic_script_hafs_regular.otf      → Resources/Fonts/               (+ register in Info.plist UIAppFonts)
amiri_regular.ttf, amiri_bold.ttf            → Resources/Fonts/               (+ register)
arefruqaa_regular.ttf, arefruqaa_bold.ttf    → Resources/Fonts/               (+ register)
notonaskharabic_regular.ttf (+ bold etc.)    → Resources/Fonts/               (+ register)
reemkufi_regular.ttf (+ bold etc.)           → Resources/Fonts/               (+ register)
```

After adding fonts, list each `.otf`/`.ttf` filename in `Info.plist` under `UIAppFonts` (array of strings).

The metadata XML parser must be ported. The Android implementation (`MetadataParser.kt`) uses Android's `XmlPullParser`. On iOS use `XMLParser` (Foundation) or a small Swift XML library. **The parsing logic and the output shape must match 1:1** — page/juz boundary lookups must return identical values for every page 1–604. Write a test that loads both the Android constants and the iOS-parsed values and asserts equality across all 604 page boundaries before declaring Phase 2 done.

---

## 7. Visual & Interaction Parity Rules

- **Same colours, same hex.** Cross-platform parity of the Heritage palette is exact to the hex.
- **Same typography scale.** 48 pt Quran text in landscape. 20 pt surah header. 14 pt juz label. 18 pt page number + Basmala. 13 pt momentum message. (Android sp ≈ iOS pt for our purposes — both respect user text-size scaling, which for the Quran body we opt out of.)
- **Same progress bar geometry.** 88 % width, 12 pt tall, 6 pt corner.
- **Same animation tempo.** Page swipes feel like turning a physical page — use SwiftUI's `TabView` with `.page` style for the default feel; if it reads too mechanical, fall back to a custom paged view with a subtle curl-ish transition.
- **Direction:** force `.environment(\.layoutDirection, .rightToLeft)` on the root scene. Set `CFBundleDevelopmentRegion` to `ar` so localisation tooling treats Arabic as primary.
- **Status bar / safe area:** tinted to match the current theme's background. The header strip starts at safe-area top, not at the very top of the screen (no content under the Dynamic Island).
- **Haptics on long-press ayah selection:** use `UIImpactFeedbackGenerator(style: .medium)`. Matches the Android haptic.

---

## 8. Platform-Specific Adaptations

| Concern | Android | iOS |
|---|---|---|
| Share sheet | `Intent(ACTION_SEND)` + `Intent.createChooser` | `UIActivityViewController` (wrapped in SwiftUI via `UIViewControllerRepresentable`, or the `ShareLink` SwiftUI view on iOS 16+) |
| Clipboard | `ClipboardManager.setPrimaryClip` | `UIPasteboard.general.string = …` |
| Toast ("نُسخت الآية") | `Toast.makeText` | No native toast. Use a brief SwiftUI overlay (`.overlay` + timer) or a small library. Match the 2-second dismiss timing. |
| Bottom sheet | Material 3 `ModalBottomSheet` | SwiftUI `.sheet` modifier. For partial-height use `.presentationDetents([.medium, .large])` (iOS 16+). |
| Long-press gesture | `pointerInput { detectTapGestures(onLongPress = …) }` | `.onLongPressGesture { … }` on the ayah span |
| Prefs persistence | DataStore / Room | `@AppStorage` (small scalars), GRDB (structured data) |
| Local notification | WorkManager + NotificationCompat | `UNUserNotificationCenter.add(UNNotificationRequest)` with a `UNCalendarNotificationTrigger` |
| Fonts | `res/font/*` + `FontFamily` | `.otf`/`.ttf` in bundle + `UIAppFonts` Info.plist + `Font.custom("KFGQPCUthmanicScriptHAFS", size: …)` |
| Widget | Glance (`WarattilWidget`) | WidgetKit extension target (defer past v1 unless prioritised) |
| Orientation detection | `LocalConfiguration.current.orientation` | `GeometryReader` + `horizontalSizeClass` / `verticalSizeClass` environment values, or `UIDevice.current.orientation` |

---

## 9. Anti-Hallucination Guardrails

Read these before proposing any feature. Each has a real history.

1. **Do not propose "ayah of the day", "featured ayah", "random inspiration", or any variant.** It was built on Android, shipped in code, then deleted. The reason: no algorithm — hashed, random, or editorial — can distinguish ayahs that are appropriate to show out of context. User-driven selection only.
2. **Do not propose bit.ly, tinyurl, Firebase Dynamic Links, or any third-party URL shortener.** Nasser has rejected these. The shortening path is "register a brand domain and set up a server-side redirect on existing hosting", and it is deferred.
3. **Do not use accessibility/elderly framing** in copy for the large-font landscape mode. Describe the reading quality, not the user.
4. **Do not recolour the logo, split layers, regenerate in a different style, or tweak the assets Nasser provides.** Ask first.
5. **Do not use the SQLite `page` column for paging.** Use `quran_metadata_fixed.xml` + the monotonic key formula.
6. **Do not render any number as Latin digits in the reading chrome.** Ayah markers, page numbers, juz numbers, percentages — all Eastern Arabic digits.
7. **Do not surface notifications unless the user opted in.** Never default-on.
8. **Do not add hadith framing, taglines, or marketing copy to ayah share payloads.** The locked four-line format (§2.6) is final.
9. **Do not propose in-app purchases, ads, upsells, subscriptions, or premium tiers.** The app is free and ad-free permanently.
10. **Do not reorder features Nasser has ordered.** If the priority is reading parity first, ship reading parity first — don't sneak widgets or complications into v1.
11. **Confirm the build stack with Nasser before altering it.** On Android he explicitly rejected the AGP upgrade nag and locked to Gradle 8.13 / AGP 8.11.1 / Kotlin 2.0.21. Treat the iOS equivalents (Xcode version, iOS minimum) the same way — propose, don't change unilaterally.

---

## 10. Phased Delivery Plan

Each phase ends with a working, demonstrable build. Do not skip phases or interleave unrelated work.

**Phase 0 — Kickoff (day 1).** Resolve the Open Decisions in §13 with Nasser. Agree on Xcode version, iOS minimum, bundle ID confirmation, and whether a Mac + Apple Developer account are already in place.

**Phase 1 — Project bootstrap.** Create the Xcode project. Add Resources (DB, metadata XML, fonts). Register fonts in Info.plist. Force RTL root environment. Add a "hello" screen in Cream/Charcoal/Mushaf-Green to validate the colour pipeline.

**Phase 2 — Metadata parser + data models.** Port `MetadataParser.kt` to Swift. Port `Ayah`, `QuranMetadata` data models. Write a test that compares page boundaries for all 604 pages against a fixture generated from the Android implementation. Do not move on until 604/604 match.

**Phase 3 — Repository layer.** Set up GRDB against the bundled `quran_v2.db`. Port `QuranRepository.getPageContent(page)` and `searchAyahs(query)`. Verify that page 1 returns Al-Fatiha's 7 ayahs, page 2 returns Al-Baqarah ayah 1–5, and a search for `الرحمن` returns the expected hit count.

**Phase 4 — Static Mushaf rendering.** Render one page at rest with the Uthmani font, Eastern-digit ayah markers, ornate brackets. Compare pixel-to-pixel against a screenshot of the Android build of the same page. Iterate until they're indistinguishable at a glance.

**Phase 5 — 604-page swipe.** Wrap the static page view in `TabView { … }.tabViewStyle(.page)`. Confirm smooth swiping across all 604 pages on a physical device. Verify RTL feel (swipe left advances to the next page in an Arabic book, i.e. higher page number).

**Phase 6 — Header & Footer.** Pin the surah-name-plate header to safe-area top and the progress bar + page-number footer to safe-area bottom. Neither should scroll with content. Implement the 30-40-30-Beyond colour tiers.

**Phase 7 — Long-press ayah action bar.** Copy + Share + Close. Use `ShareLink` (iOS 16+) or `UIActivityViewController`. Produce the exact four-line share payload from §2.6.

**Phase 8 — Overflow menu + navigation.** SwiftUI `Menu` in the trailing toolbar. Wire through to sheets for About, Usage Guide, Share App. Stubs for Index, Bookmarks, Wird, Hifz.

**Phase 9 — Bookmarks.** `@AppStorage` JSON-encoded `[Int]` of page numbers. Bookmark-toggle button in header. Bookmarks sheet lists saved pages; tap jumps.

**Phase 10 — Preferences & Theme switcher.** Palette icon in header cycles Heritage → Dark → Sepia. Persist via `@AppStorage`.

**Phase 11 — Search.** Port the diacritic-stripping SQL WHERE clause. Results sheet → tap jumps to page, with the hit ayah briefly highlighted.

**Phase 12 — Wird + Hifz circle.** Daily wird goal (pages per day), progress bar integration, opt-in local notification. Hifz log sheet, revision schedule.

**Phase 13 — Landscape large-font.** Force 48 pt ayah text + 72 pt line height, minimize header/footer.

**Phase 14 — About + Usage Guide polish.** Port the exact Arabic copy from the Android sheets. Do not rewrite, paraphrase, or "improve" the copy.

**Phase 15 — App Store readiness.** Icon slices, launch screen, privacy manifest, App Store Connect listing copy (Arabic + English), screenshots, TestFlight upload.

**Phase 16 (deferred) — Widget via WidgetKit.** Only if Nasser prioritises after v1 ships.

---

## 11. Canonical Arabic Strings

Copy these verbatim. Do not transliterate, paraphrase, or "modernise".

### 11.1 Menu Labels

```
الفهرس
إشاراتي
الورد اليومي
حلقة الحفظ
دليل الاستخدام
عن التطبيق
شارك ورتّل
```

### 11.2 Action Bar

```
نسخ الآية       (Copy ayah — icon contentDescription)
مشاركة الآية    (Share ayah — icon contentDescription)
إغلاق           (Close)
نُسخت الآية      (Copied toast)
مشاركة الآية    (Share-sheet chooser title)
```

### 11.3 Ayah Share Payload (Locked)

```
﴿ {text with annotations stripped} ﴾
سورة {surahName} · الآية {n.arabicDigits}

— تطبيق ورتّل
{App Store URL}
```

Annotation stripping = remove codepoints U+06D6 through U+06ED (Quranic annotation marks). This is done to keep the shared text clean in plain-text chat apps; marks render inconsistently across platforms.

### 11.4 App Share Payload (`شارك ورتّل`)

```
ورتّل — مصحف رقمي بخط عثماني كامل، بلا إعلانات ولا إلهاء.
اقرأ، احفظ، وتابع وردك اليومي.

قال النبي ﷺ: «من دلَّ على خير فله مثل أجر فاعله»

{App Store URL}
```

This payload is different from the ayah share — it *does* carry the hadith framing. App-share is a one-time invitation to try the app; ayah-share is recurring content and must stay content-forward.

### 11.5 Basmala

```
بِسۡمِ ٱللَّهِ ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ
```

Displayed above every surah except Surah 9 (At-Tawbah). Note `SURAH_TAWBAH = 9` in `WarattilConstants.Mushaf`.

---

## 12. Signing & Distribution

- **Bundle ID:** `com.warattil.warattilmushaf` (matches Android `applicationId` — intentional brand parity).
- **Team:** Nasser's Apple Developer account. Verify enrollment status at kickoff.
- **Signing certificates & provisioning profiles:** created in Apple Developer portal, managed via Xcode "Signing & Capabilities".
- **App Store Connect listing:** new record, primary language Arabic, secondary English.
- **Privacy manifest (`PrivacyInfo.xcprivacy`):** required as of May 2024. Declare:
  - `NSUserDefaults` usage reason (CA92.1 — user preferences).
  - No tracking, no third-party SDKs, no IDFA.
- **TestFlight first, production second.** Never push straight to App Store; always burn at least one TestFlight build for a physical-device smoke test.

**Versioning ledger** (mirror the Android ledger convention):

- iOS v1 will ship as `CFBundleShortVersionString = "1.0"` / `CFBundleVersion = "1"`.
- Every subsequent upload bumps `CFBundleVersion`, even if `CFBundleShortVersionString` stays the same. Apple requires monotonic increase.

---

## 13. Open Decisions for Kickoff

Resolve each with Nasser before writing code.

1. **Development environment.** Does Nasser have a Mac with Xcode 15+ installed? If not, the first task is environment setup, not coding.
2. **Apple Developer Program enrollment.** Active and paid for 2026? If not, schedule this early — enrollment can take 1–3 days and blocks TestFlight.
3. **iOS minimum version.** Recommend iOS 16.0; confirm with Nasser based on his users' devices.
4. **iPad support.** iPhone-only for v1 is recommended (faster ship, cleaner layout). iPad can be a v1.1 or v2 phase — layout needs a different grid for the two-page-spread reading model.
5. **Repository structure.** Separate git repo for iOS (recommended, clean Xcode workflow), or a monorepo alongside the Android project? If separate, the two asset files (`quran_v2.db`, `quran_metadata_fixed.xml`) are duplicated and updated manually on the (very rare) occasions they change.
6. **Widget / Complications in v1.** Default recommendation: no, ship reading parity first.
7. **Analytics.** Default recommendation: none. Matches the ajr-first philosophy and sidesteps privacy-manifest complications.
8. **Dark mode behaviour.** Should iOS Dark Mode system setting force the Obsidian theme automatically, or is theme selection always manual (matching Android, which has a palette cycle)? Recommend matching Android — manual, palette icon, no system override.
9. **Languages.** Arabic-only in v1 UI, or ship Arabic + English from day one? Android is Arabic-only. Recommend same.
10. **App Store listing copy.** Draft Arabic + English descriptions together with Nasser before submission; do not ship placeholder copy.

---

## 14. What NOT to Do (Restated, Because These Are the Common Failure Modes)

- Don't start coding before reading §1–3.
- Don't propose آية اليوم, daily ayah widget, random ayah surfacing, or any auto-curated content. Rejected in April 2026.
- Don't suggest bit.ly / tinyurl / any third-party shortener. Rejected.
- Don't frame landscape mode as "accessibility" or "elderly". Reading quality only.
- Don't use the `page` column in `quran_v2.db` for paging. Use the monotonic key + MetadataParser.
- Don't render any reading-chrome number in Latin digits.
- Don't recolour, redraw, or re-slice the logo. Ask first.
- Don't add ads, IAP, subscriptions, or upsells. Ever.
- Don't default notifications on.
- Don't rewrite Arabic copy. Port verbatim.
- Don't alter the share-payload format. §2.6 and §11.3 are locked.
- Don't bump the iOS minimum or Xcode version without Nasser's confirmation.

---

## 15. Starting the New Chat

When Nasser opens a fresh chat for the iOS work, he will attach this document (or paste it in). Your first response in that chat should be:

1. Confirm you have read the full document.
2. Ask the ten questions in §13 as a single upfront batch — don't drip them across turns.
3. After Nasser answers, propose the Phase 1 setup plan and wait for his "go" before writing code.

Do not skip step 2. The Open Decisions are load-bearing — they gate the whole stack choice.

---

*End of blueprint. Version 1.0 — April 2026.*
