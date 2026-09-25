# Warattil 3.0.0 — release notes

**Build target:** versionCode `2` · versionName `3.0.0`
**applicationId:** `com.warattil.warattilmushaf.v3` (separate Play listing from V2)
**Track:** Internal Testing → Closed Testing → Production
**Min SDK:** 24 (Android 7.0) · **Target SDK:** 35 (Android 15)

---

## Play Console — "What's new" (Arabic, ≤500 chars)

Use this verbatim for the Arabic release notes field in Play Console:

```
🌿 إصدار جديد كبير
• خط KFGQPC الرسمي v2.0 ونص محقَّق من مجمع الملك فهد
• التفسير الميسر ومعاني الكلمات الغريبة لكل آية بضغطة طويلة
• خريطة الحفظ الجديدة بسبع مراتب وصورة قابلة للمشاركة
• محرّك «الورد اليومي» جديد بنموذج «الإشارة المرجعية» يكافئ الاستمرار
• «↩ تابع وردك» للعودة إلى موضعك بضغطة واحدة
• بحث متطوّر يجد كلَّ صيَغ الكلمة وتظليل النتائج داخل الصفحة
• مشاركة بطاقات الإنجاز كصور أنيقة
• تحسينات في وضع الليل والخطوط
بارك الله فيكم — تقبل الله طاعتكم
```

---

## What shipped

### Content + data layer
- **KFGQPC fonts upgraded** `v0.09 → v2.0`. Body text re-ingested from KFGQPC `hafsData_v2-0.json` (authoritative Uthmani text from King Fahd Complex; replaces Tanzil-derived content).
- **Tafseer Muyassar (التفسير الميسر)** shipped as `tafseer_muyassar.json` (1.9 MB, all 6,236 ayat) — parsed from KFGQPC v3 source via `pipeline_data/scripts/parse_tafseer.py`.
- **Ghareeb dictionary (الميسر في غريب القرآن)** shipped as `ghareeb.json` (1.1 MB, ~5,000 ayat covered).
- **About sheet copy** — KFGQPC credited as the sole source.

### Reading-aid sheets (long-press → 📖)
- 2-tab pager `AyahMeaningsSheet`: **«معاني الكلمات»** on the right (default — most common need: glance at a rare-word gloss) + **«التفسير الميسر»** on the left.
- Tafseer renderer uses Amiri (classical Naskh) for prose so commas «،» and periods «.» render as clean punctuation, not the Mushaf font's decorative dot-circles. Inline `<span class="aya">` Quran fragments stay in Hafs Uthmanic, gold + semibold.
- 📖 icon is `Icons.Filled.AutoStories` (open splayed pages) — clearer than the previous `MenuBook` glyph at the action-bar's compact 38dp.

### Wird (الورد اليومي) — cumulative-modulo cycling
- **New mental model:** the wird is a real-world Mushaf bookmark. Read N pages → place ribbon → close book. Comes back the same day or a week later → ribbon is exactly where left off, momentum picks up. When the cycle target is reached, the next page begins a fresh cycle automatically.
- **Math:** `pagesRead = max_continuous − wirdStartPage`; `withinCycle = ((pagesRead − 1) mod dailyPages) + 1`; ratio = `withinCycle / dailyPages`. Auto-wraps to a new cycle on completion.
- **No date dependency.** Skipping days has zero effect — the ribbon stays put. No «أمس» recap, no streaks, no debt accounting.
- **Sky Blue / >100% state REMOVED.** Maximum visible state is exactly 100% «أتممت ورد اليوم»; the next sequential page begins the next cycle at low single digits (Red tier). Three-tier color law: Red < 30% < Amber < 70% < Green ≤ 100%.
- **Al-Kahf jump fix preserved** — non-sequential navigation (Fihris jump, search-to-page) does not credit the wird counter; only contiguous forward swipes from the ribbon advance it.
- **WirdResumeChip** «↩ تابع وردك · ص N» appears beside the momentum message when the reader has wandered off the ribbon. One tap returns to the ribbon page. Hidden during sequential reading.
- **WirdDialog**:
  - Renamed «إيقاف الورد» → **«ابدأ ختمة جديدة»** (positive devotional framing).
  - Tapping it now also rewinds reading position to page 1 (semantically: a new khatma begins at the start of the Mushaf). Bookmarks + hifz progress are NOT touched.
  - Title: «إعداد الورد اليومي».
- **Header menu label**: «الورد اليومي» (the daily routine — noun, names the feature).
- **Open-Mushaf-on-rihal icon** (`ic_mushaf_rihal.xml`) replaces the generic calendar icon. Ribbon bookmark falls from the spine.
- **App startup**: when a wird is active, the app opens at the **wird ribbon page** (`today_max_continuous_page`), not the last-swiped page. So a reader who closed the app on Al-Kahf will reopen on their wird position to continue the routine.
- **Wird state survives every restart** — see Persistence section below.

### Search
- **Diacritic + orthography-aware matching.** A search for «ايمان» finds **إيمان**, **أيمان**, **الإِيمَٰن**, **الإيمان** all together. Folds applied:
  - Hamza variants أ إ آ → ا
  - Alef-wasla ٱ → ا
  - Dagger alef ٰ + subscript alef ٖ → ا (with **dual-form indexing** also handling words like الرحمن where the dagger doesn't correspond to a written alef)
  - Alef-maqsura ى → ي
  - Tatweel ـ stripped
  - All standard tashkeel, recitation pause marks, and KFGQPC's high-mark glyphs (incl. U+06E1 — KFGQPC's sukun) stripped
- **Search count chip**: 28sp Bold gold pill alongside the field on the same row, system-font digits so 3-digit counts («١٠٣ مرة») render cleanly without GSUB rosette splits.
- **Search results all RTL** — surah label «البقرة ﴿٢٤﴾» right edge, page «ص ٤» left edge, snippet right-aligned.
- **Inline page highlight after tap.** Tapping a result lands on the page with every match painted gold inline. The highlight is diacritic-aware — «الكافرون» highlights «ٱلۡكَٰفِرُونَ» including embedded marks. Persists across page swipes (scan adjacent pages for the same word).
- **Search sheet preserves last query + results** when reopened — no need to remember which word you were looking for.

### Returning-user UX
- **«أهلاً بعودتك» pill** — calm welcome-back when the reader returns after one or more days. Shown once per day. (The «أمس قرأت X من Y صفحة» variant was removed in pt.3 of the wird rework — it was tied to the per-day reset model that no longer exists.)

### Hifz (memorization)
- **7-tier ladder strip** on the garden share — full progression visible to the receiver, with the current rung gold-highlighted.
- **Heritage palette locked** on the garden share PNG. Even if the reader is in dark mode, the shared image renders cream + charcoal + gold (no dark-mode bleed).
- **Garden share enriched** with stage label + 4-way Juz/Surah/Page/Ayah stat row.
- **Background baked into the captured layer** so the PNG ships with a solid cream background, not transparency that lets dark-mode chat bubbles bleed through.
- **Hifz celebration dialog** (tier crossing) now shares as an image — the reader sends the actual rendered milestone card via `ShareUtil.shareHifzMilestone`, not a generic invite text.

### Share infrastructure
- All image-share paths route through one `sendImage` helper in `ShareUtil`.
- **Daily reading card**: Gregorian only (Hijri dropped per scope decision); 3-digit page rosette fix.
- **App-invite + QR code shares** reuse the unified PNG path.
- New: `shareHifzMilestone(context, bitmap)` for the celebration dialog.

### Mushaf reading surface
- **Surah name + juz** «سورة X · الجزء N» shown in the header on every page (was: only on surah's first page). **17sp** (bumped from 14sp) — readable at a glance.
- **Multi-ayah selection** range highlight follows the +/- chips, not just the anchor ayah.
- **AyahActionBar compacted** so the X close button stays visible on narrow phones.
- **FihrisSheet** — 3-digit page numbers no longer split into 2 rosettes (`FontFamily.Default` for digit text, kills GSUB substitution).
- **Dark mode** — body text invisibility fixed (theme key added to `remember` so SpanStyle colors rebuild on theme change).
- **«قريباً» placeholders dropped** from the meanings sheet — non-catalog principle.

### Footer
- **Footer when no wird is set** is a calm Quran-completion progress strip with a «تقدم القراءة» label. The previous «ابدأ ورداً يومياً» tappable invitation was removed (duplicated the menu item).
- **Wird-active footer** packs motivation message + (optional) WirdResumeChip on a single row, then progress bar + page badge on a second row. Tighter vertical footprint = more body content height per page.

### Page rendering
- **Adaptive font engine** floor lowered: `MIN_SP` 22 → 16 → **12** so dense pages with the chip visible never clip. Engine still prefers larger sizes — only the densest pages drop into the 12-16 range. Most pages stay at 30-40sp.
- **`BODY_BOTTOM_BREATHING`** bumped 12dp → 24dp for cleaner gap between body content and footer.

### Persistence + stability — the big architectural fix
- **`UserDatabase` split from `QuranDatabase`.** Pre-fix, both Quran content AND user state (bookmarks, wird) lived in `QuranDatabase`, which uses `createFromAsset` + `fallbackToDestructiveMigration`. The asset has no `room_master_table`, so Room destroyed and re-imported the DB on every cold start — silently wiping wird state and bookmarks.
- New `UserDatabase` holds Bookmark + UserPreferences entities. NO asset, NO destructive migration. State survives every restart, every Quran content refresh, and every future schema bump (proper migrations required from now on).
- `QuranDatabase` reduced to the single `Ayah` entity. Its destructive lifecycle is now safe — there's no user data inside it to lose.
- **«ابدأ ختمة جديدة» preserves bookmarks and hifz progress** — clears only the wird state and rewinds reading position. Toast: «بداية ختمة جديدة بإذن الله».
- **Wird-save failure diagnostic Toast** kept as a user-facing safety net.

---

## Pre-upload checklist

- [ ] `keystore.properties` exists at the repo root with valid `storeFile` / `storePassword` / `keyAlias` / `keyPassword` (template: `keystore.properties.example`).
- [ ] Keystore SHA-1 verified against Play Console's expected upload key:
      `keytool -list -v -keystore "$storeFile" -alias upload | grep SHA1`
      Expected: `75:50:B1:91:…`  (warattil_new_upload.jks)
- [ ] `./gradlew clean :app:bundleRelease` produces `app/build/outputs/bundle/release/app-release.aab`.
- [ ] AAB uploaded to Play Console → Internal Testing track first; install on a real device and verify:
  - **Persistence:** set a wird → force-stop the app from settings → relaunch. Wird state, bookmarks, last-read page, hifz progress all survive intact.
  - **App reopen:** with a wird active, swipe forward to Al-Kahf, close app, reopen → opens at the **wird ribbon page**, not Al-Kahf.
  - **Search:** «الكافرون», «الجنة», «الفتح», «الكهف», «الرحمن», «ايمان», «موسي» — every one returns non-zero results.
  - **Inline highlight:** tap a search result → land on the page → matches painted gold; swipe to the next matching page → still highlighted.
  - **Wird:** read forward to 100% → message «أتممت ورد اليوم»; one more page → cycle 2 begins at ~5%, never enters Sky Blue.
  - **Wird-resume chip:** jump via Fihris → chip «↩ تابع وردك · ص N» appears next to the momentum message. One tap → returns to ribbon.
  - **«ابدأ ختمة جديدة»** → app jumps to page 1; bookmarks + hifz still intact.
  - **Page rendering:** open page 50 (Aal Imran 1-7), 293 (Al-Isra → Al-Kahf), end-of-Juz-30 dense surahs — full content visible above the footer in every case, no clipping.
  - **Tafseer/Ghareeb:** long-press an ayah → 📖 → both tabs render, prose reads cleanly, no decorative dot-circles.
  - **Garden share:** Heritage palette regardless of active theme; 7-tier ladder + 4-way stats present.
  - **Celebration dialog:** trigger by memorising into a new tier; «شارك فرحتك» sends the rendered card as an image.
- [ ] Promote Internal → Closed → Production once the internal cohort confirms.

---

## Post-upload

- Tag the commit: `git tag v3.0.0 && git push origin v3.0.0`.
- Update `project_warattil_versioncodes.md` memory: V3 ledger `3.0.0 = versionCode 2` shipped.
- Schedule iOS port to land on parity (V3 → iOS sync — tasks #43–#51 in the Cowork task list, several still pending).
