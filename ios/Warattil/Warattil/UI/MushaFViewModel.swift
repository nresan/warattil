//
//  MushaFViewModel.swift
//  Warattil
//
//  Ports app/src/main/java/com/warattil/app/ui/MushaFViewModel.kt to Swift.
//
//  SCOPE — thin vertical slice:
//    ✅ Page state (currentPage + per-page loaded content cache)
//    ✅ Theme cycling (Heritage → Dark → Sepia), persisted
//    ✅ Last-read page persistence (UserDefaults)
//    ✅ Wird momentum engine — 30-40-30-beyond tier math + Arabic messages
//       (falls back to Quran-completion ratio when no wird is configured, matching
//       Android behaviour exactly)
//    ✅ Lazy surah/juz start-page maps for future TOC navigation
//
//  DEFERRED (until sheets + action bar are ported):
//    ❌ Bookmarks (toggle / clear)
//    ❌ Live search with 300ms debounce
//    ❌ Memorized pages (Hifz)
//    ❌ Wird target setting (setWirdTarget / resetProgress)
//    ❌ Widget broadcast (no iOS widget in v1)
//
//  Design notes:
//    - @MainActor + @Observable (iOS 17+ Observation framework). SwiftUI views
//      subscribe automatically; no @Published / ObservableObject ceremony.
//    - Page loads use structured concurrency (Task); state flows through
//      a [Int: PageLoadState] dictionary so the TabView can key subscriptions
//      per page.
//    - The momentum computations (`wirdProgressRatio` / `wirdProgressColor` /
//      `wirdProgressMessage`) preserve the exact Kotlin logic so the footer
//      renders the same messages as Android for the same state.
//

import Foundation
import SwiftUI
import Observation
import UIKit   // UIPasteboard (copy action in the long-press context menu)

// =============================================================================
// MARK: Per-page load state
// =============================================================================

/// Matches Android's `PageUiState` sealed class. Success carries the fully
/// resolved PageContent; Error carries an Arabic user-facing message.
enum PageLoadState: Equatable {
    case loading
    case loaded(PageContent)
    case failed(String)
}

/// Parallel state for the QCF per-page glyph layout (new in quran_v3.db).
/// Kept separate from `PageLoadState` so the ayah-based header/search path
/// continues to work unchanged — rendering consumes this, header/footer
/// consume `PageContent`.
enum MushafPageLoadState: Equatable {
    case loading
    case loaded(MushafPage)
    case failed(String)
}

// =============================================================================
// MARK: ViewModel
// =============================================================================

@MainActor
@Observable
final class MushaFViewModel {

    // -------------------------------------------------------------------------
    // Dependencies
    // -------------------------------------------------------------------------

    /// Non-observable — Observation would complain about tracking a reference
    /// with no @Published equivalent. This is a stable repo handle for the
    /// lifetime of the VM.
    @ObservationIgnored private let repository: QuranRepository
    @ObservationIgnored private let defaults: UserDefaults

    /// Keys for UserDefaults persistence. Match Android's SharedPreferences
    /// key names so a future cross-platform sync layer could reuse them.
    ///
    /// Note: no `@ObservationIgnored` needed — nested types and static members
    /// are not tracked by the @Observable macro. The macro only synthesizes
    /// accessors on *instance stored properties*, and attempting to attach
    /// it to an enum produces: "'accessor' macro cannot be attached to enum".
    ///
    /// Hifz keys (memorizedAyahs / memorizedPagesCount / legacyPages /
    /// lastCelebratedTier) re-export the canonical names from
    /// `WarattilConstants.Hifz` so the wire format is declared in exactly
    /// one place.  Do not rename here without updating Android in lockstep.
    private enum Keys {
        static let lastReadPage             = "last_read_page"
        static let appTheme                 = "app_theme"
        static let memorizedAyahs           = WarattilConstants.Hifz.prefAyahSet       // "memorized_ayahs"
        static let memorizedPagesCount      = WarattilConstants.Hifz.prefPageCount     // "memorized_pages_count"
        static let legacyPages              = WarattilConstants.Hifz.prefLegacyPages   // "memorized_pages" (pre-Phase-1)
        static let lastCelebratedTier       = WarattilConstants.Hifz.prefLastTier      // "hifz_last_celebrated_tier"
        // Wird ribbon: high-water mark of contiguous forward reading since
        // wirdStartPage.  Sequential swipes advance it; jumps (Fihris,
        // search-to-page) leave it untouched.  Drives the cumulative-modulo
        // progress math AND the WirdResumeChip's "return to wird page"
        // affordance.  Android-side key: "today_max_continuous_page"
        // (kept identical so an Android user re-installing on iOS picks
        // up their state).
        static let todayMaxContinuousPage   = "today_max_continuous_page"
        // Daily-acknowledgement pill keys (parity with Android V3 pill).
        // Both store ISO-style YYYY-MM-DD strings (US locale, gregorian
        // calendar) — NOT timestamps — so multi-day comparisons are robust
        // across timezone changes and the wire format matches Android.
        //
        //   `lastReadDate`         — written each time the user lands on a
        //                            page (onPageChanged).  Used to detect
        //                            "yesterday vs today vs further-past".
        //   `lastAcknowledgedDate` — written when the pill becomes visible.
        //                            Suppresses re-showing on the same day
        //                            after a foreground/background cycle.
        static let lastReadDate             = "last_read_date"
        static let lastAcknowledgedDate     = "last_acknowledged_date"
    }

    // -------------------------------------------------------------------------
    // Observable state
    // -------------------------------------------------------------------------

    /// Current Mushaf page (1…604). Updated from the pager's onPageChanged.
    private(set) var currentPage: Int

    /// Active theme. Cycles via `cycleTheme()`. Persisted by ordinal.
    private(set) var appTheme: AppTheme

    /// Per-page cache. The pager triggers `ensureLoaded(page:)` for its
    /// visible window; this dictionary holds loaded/loading/failed state.
    /// Using Int keys matches the Android ConcurrentHashMap<Int, …>.
    private(set) var pageStates: [Int: PageLoadState] = [:]

    /// Parallel cache of QCF glyph-layout state per page. Populated by
    /// `ensureLoaded(_:)` alongside `pageStates`.
    private(set) var mushafPageStates: [Int: MushafPageLoadState] = [:]

    /// Loaded when available — populated lazily from the user_preferences row.
    /// Nil when no Wird is configured yet (the default fresh-install state).
    private(set) var userPreferences: UserPreferences?

    /// All saved bookmarks, newest first. Refreshed eagerly on every
    /// write through `toggleBookmark` / `deleteBookmark` / `clearAllBookmarks`.
    private(set) var bookmarks: [Bookmark] = []

    /// Authoritative Hifz store — monotonic ayah keys (sura * 10000 + aya)
    /// the user has marked as memorized.  Any "page memorized" / "surah
    /// memorized" / "juz memorized" decision is derived from this set at
    /// query time, never stored separately.  Persisted to UserDefaults
    /// under `Hifz.prefAyahSet` as [String] (Int64-as-string) so the wire
    /// format matches Android's `prefs.getStringSet(…)` byte-for-byte.
    ///
    /// Ported from Android's `_memorizedAyahs: MutableStateFlow<Set<Long>>`.
    /// The `@Observable` macro makes every SwiftUI view that reads this
    /// property auto-subscribe — no `@Published` ceremony required.
    private(set) var memorizedAyahs: Set<Int64> = []

    /// Most-recently-crossed Hifz tier, set by `saveMemorizedAyahs(_:)`
    /// whenever the user enters a higher tier for the first time.  SwiftUI
    /// views observe this with `.onChange(of:vm.pendingCelebrationTier)`
    /// and then clear it back to nil via `acknowledgeCelebration()` once
    /// the HifzCelebrationDialog has been dismissed.
    ///
    /// Why a nullable property and not a `PassthroughSubject`:
    ///   • Cleanly participates in `@Observable` tracking — no Combine
    ///     subscription ceremony at the view side.
    ///   • Tier persistence (`Keys.lastCelebratedTier`) already gates
    ///     re-firing across process death, so we don't need a buffered
    ///     stream — a one-shot property is enough.
    private(set) var pendingCelebrationTier: Int? = nil

    /// Current search query — one-way input from the SearchSheet field.
    /// Changes trigger the 300 ms debounced search task via the @Observable
    /// accessor → explicit set path in `onSearchQueryChanged(_:)`.
    private(set) var searchQuery: String = ""

    /// Results from the most recent completed search. Cleared to `[]` when
    /// the query is empty.
    private(set) var searchResults: [SearchResult] = []

    /// `true` while a search is in flight. The SearchSheet uses this to
    /// render the indeterminate progress bar.
    private(set) var isSearching: Bool = false

    /// Active inline-highlight query for the Mushaf body render. Set when
    /// the user taps a search result so the destination page (and any
    /// adjacent pages they swipe to) paints every occurrence of the query
    /// with a gold background. Persists across page swipes — clears only
    /// on explicit `clearSearch()` / `setSearchHighlight(nil)`.
    ///
    /// 2026-05-03 — Android parity task #86, mirrors
    /// `MushaFViewModel.kt :: _searchHighlight`. Diacritic-aware matching
    /// is in `SearchHighlight.swift :: findHighlightRanges`.
    private(set) var searchHighlight: String? = nil

    /// Sets (or clears, with `nil`) the inline page-highlight query.
    /// Empty/whitespace-only inputs are treated as `nil` to match Android's
    /// `q?.takeIf { it.isNotBlank() }`.
    func setSearchHighlight(_ q: String?) {
        if let q = q?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty {
            searchHighlight = q
        } else {
            searchHighlight = nil
        }
    }

    // -------------------------------------------------------------------------
    // Init
    // -------------------------------------------------------------------------

    init(repository: QuranRepository? = nil,
         defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Build or accept a repository. We don't crash-on-init; if the
        // database isn't open yet we surface a meaningful error via pageStates.
        if let repo = repository {
            self.repository = repo
        } else {
            do {
                self.repository = try QuranRepository()
            } catch {
                // Last-resort stub: keep the VM alive and fail loudly on first
                // page load rather than crash at construction. The app-launch
                // bootstrap (WarattilApp.onAppear) is expected to have opened
                // the DB before anyone constructs this VM.
                fatalError("MushaFViewModel could not construct QuranRepository: \(error)")
            }
        }

        // Restore persisted state — prefer the wird ribbon when active,
        // fall back to last_read_page.  Same priority as Android (parity
        // memo project_warattil_wird_requirements): if the user closed
        // the app while browsing far from their wird position, the next
        // launch should land them BACK on the wird page so they can
        // continue the routine, not on the random browse page.
        let ribbon  = defaults.integer(forKey: Keys.todayMaxContinuousPage)
        let lastReadStored = defaults.integer(forKey: Keys.lastReadPage)
        let startPage = Self.clampPage(ribbon >= 1 ? ribbon : lastReadStored)
        self.currentPage = startPage

        let themeOrdinal = defaults.integer(forKey: Keys.appTheme)
        self.appTheme = AppTheme.from(ordinal: themeOrdinal)

        // Restore / migrate the memorized-ayah set.  `loadMemorizedAyahs()`
        // is a pure function of `defaults` + MetadataParser; it also
        // performs the one-shot legacy page-set → ayah-set migration and
        // persists the result before returning, so the next cold start
        // hits the fast path.
        self.memorizedAyahs = Self.loadMemorizedAyahs(from: defaults)

        // Pre-warm pages around the opening page (Android pre-warms -2…+5).
        Task { [weak self] in
            guard let self else { return }
            for offset in -2...5 {
                let p = startPage + offset
                if (1...WarattilConstants.Mushaf.totalPages).contains(p) {
                    self.ensureLoaded(p)
                }
            }
        }

        // Load user prefs + initial bookmark snapshot in the background.
        // If either fails, the corresponding UI path shows empty state;
        // reading must never block launch on a DB read.
        Task { [weak self] in
            guard let self else { return }
            do {
                self.userPreferences = try self.repository.getUserPreferences()
            } catch {
                self.userPreferences = nil
            }
            do {
                self.bookmarks = try self.repository.getAllBookmarks()
            } catch {
                self.bookmarks = []
            }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: Page state API
    // -------------------------------------------------------------------------

    /// Idempotent page load. The pager calls this on every visible page (the
    /// current one and a small pre-warm window on either side).
    ///
    /// Loads BOTH paths concurrently:
    ///   • `pageStates[n]` — ayah-based PageContent (used by header/footer,
    ///     share, bookmarks, search).
    ///   • `mushafPageStates[n]` — QCF per-page glyph layout (used by the
    ///     MushafPageView renderer).
    ///
    /// - Invalid page numbers map to a `.failed` state rather than crashing.
    func ensureLoaded(_ pageNumber: Int) {
        guard (1...WarattilConstants.Mushaf.totalPages).contains(pageNumber) else {
            pageStates[pageNumber] = .failed("صفحة غير صالحة: \(pageNumber)")
            mushafPageStates[pageNumber] = .failed("صفحة غير صالحة: \(pageNumber)")
            return
        }

        // Ayah-based content path.
        if pageStates[pageNumber] == nil {
            pageStates[pageNumber] = .loading
            Task { [weak self] in
                guard let self else { return }
                do {
                    let content = try await self.repository.getPageContent(pageNumber: pageNumber)
                    self.pageStates[pageNumber] = .loaded(content)
                } catch {
                    self.pageStates[pageNumber] = .failed(error.localizedDescription)
                }
            }
        }

        // QCF rendering path.
        if mushafPageStates[pageNumber] == nil {
            mushafPageStates[pageNumber] = .loading
            Task { [weak self] in
                guard let self else { return }
                do {
                    if let page = try await self.repository.getMushafPage(pageNumber: pageNumber) {
                        self.mushafPageStates[pageNumber] = .loaded(page)
                    } else {
                        self.mushafPageStates[pageNumber] =
                            .failed("تعذّر تحميل تخطيط الصفحة \(pageNumber)")
                    }
                } catch {
                    self.mushafPageStates[pageNumber] = .failed(error.localizedDescription)
                }
            }
        }
    }

    /// Called by the HorizontalPager (TabView) when the user swipes to a new page.
    /// Matches Android's `onPageChanged(pagerIndex)` — note Android uses a
    /// 0-based pagerIndex; our TabView selection is already 1-based, so no
    /// adjustment needed. Pre-warms ±2 pages.
    func onPageChanged(to page: Int) {
        guard (1...WarattilConstants.Mushaf.totalPages).contains(page) else { return }
        currentPage = page
        defaults.set(page, forKey: Keys.lastReadPage)

        // Stamp today's date as the reader's "last read" so the daily
        // acknowledgement pill can compute "yesterday vs further-past" on
        // next launch.  Cheap write — happens at most once per swipe and
        // SharedPreferences-equivalent UserDefaults coalesces same-value
        // sets.  Parity with Android writeLastReadDate(prefs).
        defaults.set(Self.todayDateKey(), forKey: Keys.lastReadDate)

        // ── Wird ribbon (today_max_continuous_page) — sequential-only ─────
        //   Advances when the new page equals (current ribbon + 1) — true
        //   sequential reading.  Non-sequential navigation (Fihris jump,
        //   search-to-page, bookmark hop) leaves it untouched.  Returning
        //   to the ribbon's next page resumes the count naturally.
        //   The wird is a SEQUENTIAL reading of the Mushaf — opening
        //   Al-Kahf on Friday is a distinct devotional act, not part of
        //   the wird, and shouldn't be credited.  See Android parity:
        //   feedback_warattil_no_debt_accounting + wird_requirements.
        let currentRibbon = defaults.integer(forKey: Keys.todayMaxContinuousPage)
        if page == currentRibbon + 1 {
            defaults.set(page, forKey: Keys.todayMaxContinuousPage)
        }

        for offset in -2...2 {
            let adj = page + offset
            if (1...WarattilConstants.Mushaf.totalPages).contains(adj) {
                ensureLoaded(adj)
            }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: Theme
    // -------------------------------------------------------------------------

    func setTheme(_ theme: AppTheme) {
        appTheme = theme
        defaults.set(theme.ordinal, forKey: Keys.appTheme)
    }

    /// Heritage → Dark → Sepia → Heritage → …
    func cycleTheme() {
        let all = AppTheme.allCases
        let nextIdx = (appTheme.ordinal + 1) % all.count
        setTheme(all[nextIdx])
    }

    /// Convenience — the resolved palette for the current theme. Views can
    /// read this directly instead of going through `WarattilTheme.of(appTheme)`.
    var themeColors: ThemeColors { WarattilTheme.of(appTheme) }

    // -------------------------------------------------------------------------
    // MARK: Wird Momentum Engine — direct port of the Kotlin logic
    //
    //   ratio = pagesReadToday / dailyPagesGoal
    //     < 0.30  → Red     (just starting)
    //     0.30–0.70 → Amber (steady progress)
    //     0.70–1.0  → Green (approaching goal)
    //     > 1.0   → Sky Blue (surpassing goal)
    //
    //   Fallback when no wird is configured: Quran-completion ratio (current
    //   page / 604), same tier boundaries.
    // -------------------------------------------------------------------------

    /// Daily pages goal for the user's configured Wird target.
    /// Ported verbatim from MushaFViewModel.wirdDailyPages(UserPreferences).
    func wirdDailyPages(_ p: UserPreferences) -> Int {
        let totalPages = WarattilConstants.Mushaf.totalPages
        switch p.wirdTargetType {
        case .finishInDays:
            let remaining = Double(totalPages - p.wirdStartPage + 1)
            let days      = Double(max(p.wirdTargetValue, 1))
            return max(Int((remaining / days).rounded(.down)), 1)
        case .pagesPerDay:
            return max(p.wirdTargetValue, 1)
        case .juzPerDay:
            let juzFraction = Double(totalPages) / Double(WarattilConstants.Mushaf.totalJuzaa)
            return max(Int((Double(p.wirdTargetValue) * juzFraction).rounded(.down)), 1)
        }
    }

    /// Page the reader needs to reach to complete the CURRENT cycle.
    /// REWORKED 2026-04-27 (pt. 3) — cumulative-modulo cycling.  Each
    /// cycle is exactly `dailyPages` long, starting from `wirdStartPage`:
    ///   Cycle 1: pages [wirdStartPage+1 .. wirdStartPage+dailyPages]
    ///   Cycle 2: pages [wirdStartPage+dailyPages+1 .. wirdStartPage+2*dailyPages]
    ///   ...
    /// Returns the LAST page of the cycle the reader is currently inside
    /// (the "100%" page — reaching it shows «أتممت ورد اليوم»; the next
    /// sequential page wraps to ~5%).  Nil if no wird is configured.
    func wirdTodayTargetPage(_ p: UserPreferences? = nil) -> Int? {
        let prefs = p ?? userPreferences
        guard let prefs, prefs.wirdStartDate != nil else { return nil }
        let ppd     = wirdDailyPages(prefs)
        let maxCont = max(defaults.integer(forKey: Keys.todayMaxContinuousPage), prefs.wirdStartPage)
        let pagesRead = max(maxCont - prefs.wirdStartPage, 0)
        let cycleIndex = pagesRead == 0 ? 0 : (pagesRead - 1) / ppd
        return min(prefs.wirdStartPage + (cycleIndex + 1) * ppd,
                   WarattilConstants.Mushaf.totalPages)
    }

    /// Wird-Centric Momentum — CUMULATIVE MODULO CYCLING.
    ///
    /// REWORKED 2026-04-27 (pt. 3) per Nasser's mental-model clarification:
    /// the wird mirrors the real-world Mushaf bookmark.  Reader reads N
    /// pages, places ribbon, closes book.  Comes back same day or a week
    /// later — ribbon is exactly where left off, momentum picks up.
    /// Cycle auto-wraps on completion.
    ///
    /// Formula:
    ///   pagesRead   = max_continuous − wirdStartPage     (cumulative)
    ///   withinCycle = ((pagesRead − 1) mod dailyPages) + 1
    ///   ratio       = withinCycle / dailyPages
    ///
    /// Sky Blue / >100% state REMOVED.  Maximum visible state is exactly
    /// 100% «أتممت ورد اليوم»; the next sequential page advances to a
    /// fresh cycle at low single digits.  Display ratio always in [0, 1].
    func wirdProgressRatio(currentPage: Int, p: UserPreferences? = nil) -> Double {
        let prefs = p ?? userPreferences
        let totalPages = Double(WarattilConstants.Mushaf.totalPages)

        // No wird → fall back to whole-Quran completion ratio.
        guard let prefs, prefs.wirdStartDate != nil else {
            let raw = Double(currentPage) / totalPages
            return min(max(raw, 0.0), 1.0)
        }

        let dailyPages = wirdDailyPages(prefs)
        let maxCont    = max(defaults.integer(forKey: Keys.todayMaxContinuousPage),
                             prefs.wirdStartPage)
        let pagesRead  = max(maxCont - prefs.wirdStartPage, 0)
        if pagesRead == 0 { return 0.0 }

        // Modulo-with-snap-to-100% — `(pagesRead - 1) % D + 1` ensures the
        // milestone page reads as exactly 100% rather than 0% (a naive
        // `pagesRead % D` would jump 95% → 0% across the boundary).
        let withinCycle = ((pagesRead - 1) % dailyPages) + 1
        let ratio = Double(withinCycle) / Double(dailyPages)
        return min(max(ratio, 0.0), 1.0)
    }

    /// Three-tier color mapping — Sky Blue removed 2026-04-27.  The
    /// cumulative-modulo engine never emits ratio > 1.0; completion is
    /// always exactly 100% and the next page begins a new cycle at
    /// low single digits.
    func wirdProgressColor(ratio: Double) -> Color {
        if ratio >= 0.70 { return WarattilConstants.Colors.progressHigh }  // Mushaf Green
        if ratio >= 0.30 { return WarattilConstants.Colors.progressMid  }  // Amber
        return                    WarattilConstants.Colors.progressLow      // Red
    }

    /// Arabic status message for the footer.  Sky Blue Duaa rotation
    /// removed alongside the >100% state.  Maximum visible state is
    /// «أتممت ورد اليوم» at exactly 100%; next sequential page begins
    /// the new cycle (Red tier).
    func wirdProgressMessage(ratio: Double, p: UserPreferences? = nil,
                             currentPage: Int = 0) -> String {
        let prefs = p ?? userPreferences
        // No wird → Quran-completion messages
        guard let prefs, prefs.wirdStartDate != nil else {
            if ratio >= 1.0   { return "ختمة جديدة مباركة" }
            if ratio >= 0.70  { return "شارفت على الختم" }
            if ratio >= 0.30  { return "عزيمة وإصرار" }
            return                    "بداية مباركة"
        }
        // Tight float-comparison epsilon for "exactly 100%".
        if ratio >= 0.999 { return "أتممت ورد اليوم" }
        if ratio >= 0.70  { return "شارفت على إتمام وردك" }
        if ratio >= 0.30  { return "عزيمة وإصرار" }
        return                    "ابدأ وردك اليوم"
    }

    /// Page the reader should "return to" to resume their wird, or nil
    /// when they're already on it (or no wird configured).  Drives the
    /// «↩ تابع وردك · ص N» chip's visibility.  Tolerance ±2 pages —
    /// verifying a verse one page back doesn't trigger the chip.
    func wirdResumePage(currentPage: Int, p: UserPreferences? = nil) -> Int? {
        let prefs = p ?? userPreferences
        guard let prefs, prefs.wirdStartDate != nil else { return nil }
        let maxCont = max(defaults.integer(forKey: Keys.todayMaxContinuousPage),
                          prefs.wirdStartPage)
        return abs(currentPage - maxCont) > 2 ? maxCont : nil
    }

    // -------------------------------------------------------------------------
    // MARK: Derived convenience — for the footer
    //
    // These wrap the full functions using the current state so the footer can
    // just read `vm.progressRatio` / `vm.progressColor` / `vm.progressMessage`.
    // -------------------------------------------------------------------------

    var progressRatio:   Double { wirdProgressRatio(currentPage: currentPage) }
    var progressColor:   Color  { wirdProgressColor(ratio: progressRatio) }
    var progressMessage: String { wirdProgressMessage(ratio: progressRatio, currentPage: currentPage) }

    /// Page the reader should return to to resume their wird, or nil
    /// when they're on the ribbon already (or no wird active).  The
    /// WirdResumeChip reads this directly.
    var wirdResume: Int? { wirdResumePage(currentPage: currentPage) }

    // -------------------------------------------------------------------------
    // MARK: Ayah actions — Copy / Share (task #35)
    //
    // The QCF renderer shows PUA glyphs that are only meaningful inside the
    // per-page font. For copy / share / bookmarks we MUST send the clean
    // Uthmani Unicode instead. The word-level map on `MushafWord.uthmani`
    // lets us resolve a long-press hit back to a (surah, ayah), and then the
    // ayah-based `PageContent` (or a direct DAO lookup) provides the full
    // ayah text for the canonical four-line share payload.
    //
    // See project_warattil_ios_qcf.md — this fulfils the "selection/copy/share
    // semantics" follow-up that was pinned when the QCF path landed.
    // -------------------------------------------------------------------------

    /// Returns the full clean Uthmani text for (surah, ayah).
    ///
    /// Fast path: scans every already-loaded `PageContent`. The pager
    /// pre-warms ±2 pages around `currentPage`, so any ayah visible on
    /// screen (or partially so on a neighbouring page) is almost always in
    /// the cache.
    ///
    /// Slow path: direct SQLite read via the repository. Synchronous and
    /// cheap (O(1) on the (sura, aya) PK) so it's safe to call from a menu
    /// action handler running on the main thread.
    func ayahText(surah: Int, ayah: Int) -> String? {
        for state in pageStates.values {
            if case .loaded(let content) = state,
               let hit = content.ayahs.first(where: { $0.surah == surah && $0.ayah == ayah }) {
                return hit.text
            }
        }
        return try? repository.getAyahText(surah: surah, ayah: ayah)
    }

    /// Canonical formatted share payload for (surah, ayah). Returns an empty
    /// string if the ayah can't be resolved — the caller's ShareLink will
    /// still present, but with no content, which is preferable to crashing.
    func shareText(surah: Int, ayah: Int) -> String {
        guard let text = ayahText(surah: surah, ayah: ayah) else { return "" }
        return ShareUtil.formatAyahForShare(
            text:       text,
            surahName:  MetadataParser.shared.getSuraName(surah),
            ayahNumber: ayah
        )
    }

    /// Canonical formatted share payload for a contiguous RANGE of ayahs
    /// within a single surah.  Builds the body by concatenating each ayah's
    /// text with a single space separator and an inline ayah-number glyph
    /// (Arabic-Indic digit + U+06DD "Arabic End Of Ayah") so recipients can
    /// tell where one ayah ends and the next begins without us re-rendering
    /// a Mushaf page.
    ///
    /// Delegates the framing to `ShareUtil.formatAyahRangeForShare` so both
    /// the single-ayah and range payloads live in one file.  Collapses to
    /// the single-ayah formatter when `from == to` so callers don't have to
    /// branch.  Returns "" if any ayah in the range can't be resolved —
    /// matches the conservative behaviour of the single-ayah `shareText`.
    func shareText(surah: Int, from: Int, to: Int) -> String {
        guard from <= to else { return "" }
        if from == to { return shareText(surah: surah, ayah: from) }

        // Collect each ayah's text + inline end-marker.  We join with " "
        // (U+0020) rather than a newline — a run of 2-5 ayahs should read as
        // one flowing quote when pasted into WhatsApp, not as a bulleted
        // list.  The U+06DD glyph natively renders the ayah number as a
        // circled figure on Arabic-capable platforms.
        var parts: [String] = []
        for n in from...to {
            guard let body = ayahText(surah: surah, ayah: n) else { return "" }
            // Build "<ayah body> <digit><U+06DD>" — the digit is Arabic-Indic
            // so iOS / Android / Windows all render it inside the rosette.
            // The marker trails the ayah it closes, matching Mushaf convention.
            parts.append("\(body) \(n.arabicDigits)\u{06DD}")
        }
        let joined = parts.joined(separator: " ")

        return ShareUtil.formatAyahRangeForShare(
            text:      joined,
            surahName: MetadataParser.shared.getSuraName(surah),
            fromAyah:  from,
            toAyah:    to
        )
    }

    /// Range-aware copy.  Mirrors `copyAyah(surah:ayah:)` so the action bar
    /// can treat single-ayah and range selections uniformly.  Returns
    /// `false` if the range is invalid or any ayah can't be resolved.
    @discardableResult
    func copyAyah(surah: Int, from: Int, to: Int) -> Bool {
        let payload = shareText(surah: surah, from: from, to: to)
        guard !payload.isEmpty else { return false }
        UIPasteboard.general.string = payload
        return true
    }

    /// Human-facing label for the context-menu section title, e.g.
    /// "سورة الفاتحة · الآية ١".
    func ayahLabel(surah: Int, ayah: Int) -> String {
        "سورة \(MetadataParser.shared.getSuraName(surah)) · الآية \(ayah.arabicDigits)"
    }

    /// Compact label for use when there is no section-header room — e.g.
    /// inside a flat (non-sectioned) context menu or a toast, "الفاتحة ١".
    func ayahLabelCompact(surah: Int, ayah: Int) -> String {
        "\(MetadataParser.shared.getSuraName(surah)) \(ayah.arabicDigits)"
    }

    /// Writes the canonical share payload to the system pasteboard.
    /// Matches Android's "Copy ayah" action exactly.
    ///
    /// Returns `true` on success so the view can drive a brief toast /
    /// haptic; `false` means the ayah wasn't resolvable.
    @discardableResult
    func copyAyah(surah: Int, ayah: Int) -> Bool {
        let payload = shareText(surah: surah, ayah: ayah)
        guard !payload.isEmpty else { return false }
        UIPasteboard.general.string = payload
        return true
    }

    // -------------------------------------------------------------------------
    // MARK: Fihris — lazy index maps (surah / juz start pages)
    //
    // Android uses `by lazy { repository.surahStartPages }`. Swift equivalent:
    // computed property backed by a nilable cache. Recomputed once on first
    // access, then cached for the lifetime of the VM.
    // -------------------------------------------------------------------------

    @ObservationIgnored private var _surahStartPages: [Int: Int]?
    @ObservationIgnored private var _juzStartPages:   [Int: Int]?

    var surahStartPages: [Int: Int] {
        if let cached = _surahStartPages { return cached }
        let map = repository.surahStartPages
        _surahStartPages = map
        return map
    }

    var juzStartPages: [Int: Int] {
        if let cached = _juzStartPages { return cached }
        let map = repository.juzStartPages
        _juzStartPages = map
        return map
    }

    // -------------------------------------------------------------------------
    // MARK: Navigation — programmatic jumps from sheets (Fihris / Bookmarks /
    // Search). The pager observes `currentPage` through a Binding that routes
    // writes back through `onPageChanged` — so setting `currentPage` here both
    // updates the visible page and persists the new last-read value.
    // -------------------------------------------------------------------------

    func navigateToPage(_ page: Int) {
        guard (1...WarattilConstants.Mushaf.totalPages).contains(page) else { return }
        onPageChanged(to: page)
    }

    // -------------------------------------------------------------------------
    // MARK: Bookmarks
    // -------------------------------------------------------------------------

    func isBookmarked(_ page: Int) -> Bool {
        bookmarks.contains(where: { $0.pageNumber == page })
    }

    /// Toggles the bookmark for `page`. Multiple bookmarks are allowed —
    /// the caller is the only one who can remove a bookmark, matching
    /// Android's "no auto-clear" behaviour.
    func toggleBookmark(_ page: Int) {
        do {
            if isBookmarked(page) {
                try repository.removeBookmark(pageNumber: page)
            } else {
                try repository.saveBookmark(pageNumber: page)
            }
            bookmarks = (try? repository.getAllBookmarks()) ?? bookmarks
        } catch {
            // Swallow — a DB write failure here shouldn't crash the reader.
        }
    }

    func deleteBookmark(_ page: Int) {
        do {
            try repository.removeBookmark(pageNumber: page)
            bookmarks = (try? repository.getAllBookmarks()) ?? bookmarks
        } catch {}
    }

    func clearAllBookmarks() {
        do {
            try repository.clearAllBookmarks()
            bookmarks = []
        } catch {}
    }

    // -------------------------------------------------------------------------
    // MARK: Hifz — ayah-atomic memorization store (Phase 1)
    //
    //   `memorizedAyahs` is the authoritative source of truth.  A page /
    //   surah / juz is "memorized" iff every ayah it contains is in this
    //   set (see `isPageMemorized(_:)` / `pageMemorizationRatio(_:)`).
    //
    //   Persistence strategy (matches Android):
    //     • Primary:       Keys.memorizedAyahs      ([String] Int64-as-string)
    //     • Worker mirror: Keys.memorizedPagesCount (Int)
    //     • Migration:     Keys.legacyPages         (read once, then removed)
    //     • Tier gate:     Keys.lastCelebratedTier  (Int — monotonically up)
    //
    //   Port of Kotlin MushaFViewModel `_memorizedAyahs` + `saveMemorizedAyahs`.
    // -------------------------------------------------------------------------

    /// One-time loader invoked from init.  Either reads the modern ayah
    /// set or — if only the legacy page-set exists — expands the pages to
    /// an ayah set in-place, persists, and removes the legacy key so the
    /// next launch hits the fast path.
    ///
    /// Pure static so it can run before `self` is available (init calls
    /// this before the observable properties are assigned).
    private static func loadMemorizedAyahs(from defaults: UserDefaults) -> Set<Int64> {
        // Modern fast path — key exists (even if empty).
        if let stored = defaults.array(forKey: Keys.memorizedAyahs) as? [String] {
            return Set(stored.compactMap { Int64($0) })
        }

        // Migration path — legacy page-set exists but not the new key.
        let legacy = (defaults.array(forKey: Keys.legacyPages) as? [String]) ?? []
        if legacy.isEmpty {
            // Seed the modern key + count so we never re-enter this branch.
            defaults.set([String](), forKey: Keys.memorizedAyahs)
            defaults.set(0,          forKey: Keys.memorizedPagesCount)
            return []
        }

        // Expand each legacy page to its ayah keys via MetadataParser.
        // Requires MetadataParser to be loaded by app-launch bootstrap;
        // if it isn't, the expansion yields empty arrays and we end up
        // with an empty set — acceptable degradation (user re-marks),
        // never a crash.
        var expanded = Set<Int64>()
        expanded.reserveCapacity(legacy.count * 12)
        for token in legacy {
            guard let page = Int(token),
                  (1...WarattilConstants.Mushaf.totalPages).contains(page) else { continue }
            for key in MetadataParser.shared.getPageAyahKeys(page) {
                expanded.insert(key)
            }
        }
        let legacyPageCount = legacy.compactMap { Int($0) }.count
        defaults.set(expanded.map(String.init),   forKey: Keys.memorizedAyahs)
        defaults.set(legacyPageCount,             forKey: Keys.memorizedPagesCount)
        defaults.removeObject(forKey:             Keys.legacyPages)
        return expanded
    }

    /// Persist a new ayah set, refresh the page-count mirror, and fire a
    /// tier-celebration event when the user has just entered a higher
    /// hifz tier for the first time.  Ported from Android
    /// `saveMemorizedAyahs(set: Set<Long>)`.
    ///
    /// Write-before-emit ordering: `Keys.lastCelebratedTier` is committed
    /// BEFORE `pendingCelebrationTier` is set, so a crash between the two
    /// doesn't re-fire the celebration next launch.
    private func saveMemorizedAyahs(_ set: Set<Int64>) {
        memorizedAyahs = set
        let fullyPages = countFullyMemorizedPages(set)
        let fullyJuz   = countFullyMemorizedJuz(set)
        let tier       = WarattilConstants.Hifz.hifzTier(juzCount: fullyJuz)
        let lastTier   = defaults.integer(forKey: Keys.lastCelebratedTier)

        defaults.set(set.map(String.init), forKey: Keys.memorizedAyahs)
        defaults.set(fullyPages,           forKey: Keys.memorizedPagesCount)
        if tier > lastTier {
            defaults.set(tier, forKey: Keys.lastCelebratedTier)
            pendingCelebrationTier = tier
        }
    }

    /// Walks all 604 pages counting those fully in `set`. O(604 × avg ayahs/page)
    /// ≈ 6236 set lookups; runs in well under a millisecond.
    private func countFullyMemorizedPages(_ set: Set<Int64>) -> Int {
        if set.isEmpty { return 0 }
        var count = 0
        for page in 1...WarattilConstants.Mushaf.totalPages {
            let keys = MetadataParser.shared.getPageAyahKeys(page)
            if !keys.isEmpty && keys.allSatisfy({ set.contains($0) }) {
                count += 1
            }
        }
        return count
    }

    /// Count of juz (1..30) fully contained in `set`. Drives tier state.
    private func countFullyMemorizedJuz(_ set: Set<Int64>) -> Int {
        if set.isEmpty { return 0 }
        var count = 0
        for j in 1...WarattilConstants.Mushaf.totalJuzaa {
            let keys = MetadataParser.shared.getJuzAyahKeys(j)
            if !keys.isEmpty && keys.allSatisfy({ set.contains($0) }) {
                count += 1
            }
        }
        return count
    }

    // ── Public query helpers ──────────────────────────────────────────

    func isAyahMemorized(surah: Int, ayah: Int) -> Bool {
        memorizedAyahs.contains(WarattilConstants.Hifz.ayahKey(sura: surah, aya: ayah))
    }

    /// True iff every ayah on `page` is in the memorized set.
    func isPageMemorized(_ page: Int) -> Bool {
        let keys = MetadataParser.shared.getPageAyahKeys(page)
        if keys.isEmpty { return false }
        return keys.allSatisfy { memorizedAyahs.contains($0) }
    }

    /// 0 … 1 fraction of ayahs on `page` that are memorized.
    func pageMemorizationRatio(_ page: Int) -> Double {
        let keys = MetadataParser.shared.getPageAyahKeys(page)
        if keys.isEmpty { return 0 }
        let hits = keys.reduce(0) { $0 + (memorizedAyahs.contains($1) ? 1 : 0) }
        return Double(hits) / Double(keys.count)
    }

    // ── Public mutation actions ───────────────────────────────────────

    /// Toggle a single ayah's membership.
    func toggleAyah(surah: Int, ayah: Int) {
        let key = WarattilConstants.Hifz.ayahKey(sura: surah, aya: ayah)
        var next = memorizedAyahs
        if next.contains(key) {
            next.remove(key)
        } else {
            next.insert(key)
        }
        saveMemorizedAyahs(next)
    }

    /// Toggle a whole page: if fully memorized → unmark all its ayahs;
    /// otherwise → mark the missing ones.  Matches the MushaFHeader
    /// strip-tap semantics: one gesture, result depends on current density.
    func togglePage(_ page: Int) {
        let keys = MetadataParser.shared.getPageAyahKeys(page)
        if keys.isEmpty { return }
        var next = memorizedAyahs
        let allMemorized = keys.allSatisfy { next.contains($0) }
        if allMemorized {
            for k in keys { next.remove(k) }
        } else {
            for k in keys { next.insert(k) }
        }
        saveMemorizedAyahs(next)
    }

    /// Complete-or-clear at surah granularity.
    func toggleSurah(_ surah: Int) {
        let keys = MetadataParser.shared.getSurahAyahKeys(surah)
        if keys.isEmpty { return }
        var next = memorizedAyahs
        let allMemorized = keys.allSatisfy { next.contains($0) }
        if allMemorized {
            for k in keys { next.remove(k) }
        } else {
            for k in keys { next.insert(k) }
        }
        saveMemorizedAyahs(next)
    }

    /// Complete-or-clear at juz granularity.
    func toggleJuz(_ juz: Int) {
        let keys = MetadataParser.shared.getJuzAyahKeys(juz)
        if keys.isEmpty { return }
        var next = memorizedAyahs
        let allMemorized = keys.allSatisfy { next.contains($0) }
        if allMemorized {
            for k in keys { next.remove(k) }
        } else {
            for k in keys { next.insert(k) }
        }
        saveMemorizedAyahs(next)
    }

    /// Low-level bulk set/clear, used by HifzBulkPickerSheet to apply a
    /// multi-select decision (e.g. "mark these 7 juz memorized") in a
    /// single UserDefaults write.
    func setAyahsMemorized<S: Sequence>(_ keys: S, memorized: Bool) where S.Element == Int64 {
        var next = memorizedAyahs
        var changed = false
        if memorized {
            for k in keys where !next.contains(k) {
                next.insert(k); changed = true
            }
        } else {
            for k in keys where next.contains(k) {
                next.remove(k); changed = true
            }
        }
        guard changed else { return }
        saveMemorizedAyahs(next)
    }

    /// Mark a closed `fromPage…toPage` range as memorized / unmemorized in
    /// one pass.  Seeds an existing-hifz user ("I already know the first
    /// 300 pages") without iterating page-by-page at the UI layer.
    func setPagesRangeMemorized(fromPage: Int, toPage: Int, memorized: Bool) {
        let a = min(max(fromPage, 1), WarattilConstants.Mushaf.totalPages)
        let b = min(max(toPage,   1), WarattilConstants.Mushaf.totalPages)
        let lo = min(a, b)
        let hi = max(a, b)
        var keys = [Int64]()
        keys.reserveCapacity(256)
        for p in lo...hi {
            keys.append(contentsOf: MetadataParser.shared.getPageAyahKeys(p))
        }
        setAyahsMemorized(keys, memorized: memorized)
    }

    /// Called by HifzCelebrationDialog after the user dismisses the modal.
    /// Clears the one-shot tier so the same dialog doesn't re-present on
    /// recomposition / tab-switch.  The persistent `lastCelebratedTier`
    /// gate in UserDefaults prevents the same tier from re-firing after
    /// process death.
    func acknowledgeCelebration() {
        pendingCelebrationTier = nil
    }

    // -------------------------------------------------------------------------
    // MARK: Wird target setting / reset
    //
    // `setWirdTarget` starts a fresh reading plan anchored on `currentPage`
    // (or an explicit `startPage`). `resetProgress` wipes the plan, clears
    // bookmarks, and emits a nav event back to page 1.
    // -------------------------------------------------------------------------

    func setWirdTarget(_ type: ReadingTargetType, value: Int, startPage: Int? = nil) {
        let anchor = startPage ?? currentPage
        let existing = userPreferences ?? UserPreferences()
        let updated = UserPreferences(
            id:                    existing.id,
            lastReadPage:          existing.lastReadPage,
            wirdTargetType:        type,
            wirdTargetValue:       max(1, value),
            wirdStartDate:         Int64(Date().timeIntervalSince1970 * 1000),
            wirdStartPage:         anchor,
            wirdLastCompletedPage: 0
        )
        do {
            try repository.saveUserPreferences(updated)
            userPreferences = updated
            // Seed the wird ribbon at the start page so the very first
            // wirdProgressRatio call after setup measures from here.
            // Sequential reads from this anchor advance the ribbon;
            // jumps leave it untouched.
            defaults.set(anchor, forKey: Keys.todayMaxContinuousPage)
            // Confirmation toast (parity with Android setWirdTarget) —
            // the dialog dismisses synchronously while the persistence
            // is async; the toast bridges the perception gap.
            ToastCenter.show("تم ضبط الورد · بدأت رحلة جديدة")
        } catch {
            ToastCenter.show("تعذّر حفظ الورد — أعد المحاولة")
        }
    }

    /// Stop the wird AND rewind reading position to page 1 (semantically:
    /// «ابدأ ختمة جديدة» — begin a new khatma at the Mushaf's first page).
    /// Bookmarks + hifz progress are NOT touched (those are the bug we
    /// fixed in pt.4 — clearing the wird should never wipe them).  Same
    /// shape as Android's cancelWird.
    func cancelWird() {
        let existing = userPreferences ?? UserPreferences()
        let updated = UserPreferences(
            id:                    existing.id,
            lastReadPage:          1,
            wirdTargetType:        existing.wirdTargetType,
            wirdTargetValue:       existing.wirdTargetValue,
            wirdStartDate:         nil,
            wirdStartPage:         existing.wirdStartPage,
            wirdLastCompletedPage: 0
        )
        do {
            try repository.saveUserPreferences(updated)
            userPreferences = updated
            defaults.set(1, forKey: Keys.lastReadPage)
            defaults.removeObject(forKey: Keys.todayMaxContinuousPage)
            navigateToPage(1)
            ToastCenter.show("بداية ختمة جديدة بإذن الله")
        } catch {
            ToastCenter.show("تعذّر إيقاف الورد — أعد المحاولة")
        }
    }

    /// Full factory-style reset — wipes wird, bookmarks, reading position.
    /// Reserved for an explicit "reset everything" admin action which we
    /// do NOT currently expose.  See cancelWird() for the user-facing
    /// «ابدأ ختمة جديدة» button which preserves bookmarks and hifz.
    func resetProgress() {
        let existing = userPreferences ?? UserPreferences()
        let reset = UserPreferences(
            id:                    existing.id,
            lastReadPage:          1,
            wirdTargetType:        existing.wirdTargetType,
            wirdTargetValue:       existing.wirdTargetValue,
            wirdStartDate:         nil,
            wirdStartPage:         existing.wirdStartPage,
            wirdLastCompletedPage: 0
        )
        do {
            try repository.saveUserPreferences(reset)
            try repository.clearAllBookmarks()
            userPreferences = reset
            bookmarks = []
            defaults.set(1, forKey: Keys.lastReadPage)
            defaults.removeObject(forKey: Keys.todayMaxContinuousPage)
            navigateToPage(1)
        } catch {}
    }

    // -------------------------------------------------------------------------
    // MARK: Search — 300 ms debounced
    //
    // Android uses `_searchQuery.debounce(300L).distinctUntilChanged().collect`
    // on a viewModelScope coroutine. The Swift equivalent is a cancellable
    // task held on the VM: each keystroke cancels the previous task and
    // schedules a new one. The task sleeps 300 ms, then — if still live —
    // runs the search.
    // -------------------------------------------------------------------------

    @ObservationIgnored private var searchDebounceTask: Task<Void, Never>?

    func onSearchQueryChanged(_ query: String) {
        searchQuery = query
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        searchDebounceTask?.cancel()

        if trimmed.isEmpty {
            isSearching = false
            searchResults = []
            return
        }

        searchDebounceTask = Task { [weak self] in
            // 300 ms debounce — matches Android's Flow.debounce(300L) exactly.
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }

            self.isSearching = true
            do {
                let hits = try await self.repository.searchAyahs(query: trimmed)
                guard !Task.isCancelled else { return }
                self.searchResults = hits
            } catch {
                self.searchResults = []
            }
            self.isSearching = false
        }
    }

    func clearSearch() {
        searchDebounceTask?.cancel()
        searchQuery = ""
        searchResults = []
        isSearching = false
        searchHighlight = nil      // also drop any active inline highlight
    }

    // -------------------------------------------------------------------------
    // MARK: Daily acknowledgement pill
    //
    // Parity with Android V3 YesterdayAcknowledgementPill (2026-04-29).
    //
    // The pill is a one-shot greeting that surfaces on app open when the
    // reader is returning after a multi-day absence — calm, ungamified,
    // explicitly NOT a streak counter.  Under the cumulative-modulo wird
    // engine the only mode shipping today is `welcomeBack` («أهلاً بعودتك»);
    // the `yesterdayRead` variant is preserved in the enum for future use
    // but the decision tree always routes to welcomeBack to match Android.
    //
    // Detection:  date-key comparison via SharedPreferences-style strings.
    //   • lastReadDate         — stamped each onPageChanged.
    //   • lastAcknowledgedDate — stamped when the pill becomes visible.
    // The pill shows at most once per calendar day, only when the reader
    // hasn't been seen *today* and was last seen *before* today.
    // -------------------------------------------------------------------------

    enum DailyAcknowledgement: Equatable {
        /// Returning after 1+ day(s) absence, or no last-read stamp at all.
        case welcomeBack
        /// Reserved — last-read was literally yesterday and a wird is active.
        /// Currently never produced (cumulative-modulo engine routes all
        /// returns to `welcomeBack`); kept for future expansion.
        case yesterdayRead(pagesRead: Int, pagesGoal: Int)
    }

    /// Resolves whether to show the pill on this app open.  Returns nil when:
    ///   • The reader was already seen today (no greeting needed), or
    ///   • The reader has already been acknowledged today (suppress dupes
    ///     across foreground/background cycles), or
    ///   • There's no `lastReadDate` AND `lastReadPage` is 1 (a true first
    ///     install — silent welcome, no pill).
    var dailyAcknowledgement: DailyAcknowledgement? {
        let today     = Self.todayDateKey()
        let lastRead  = defaults.string(forKey: Keys.lastReadDate) ?? ""
        let lastAck   = defaults.string(forKey: Keys.lastAcknowledgedDate) ?? ""

        // Don't re-show inside the same calendar day.
        if lastAck == today { return nil }

        // Reader is already active today — they don't need a greeting.
        if lastRead == today { return nil }

        // First install with no reading history → no pill.  Distinguishing
        // "first install" from "returning after a year" matters here:
        // both have `lastRead == ""`, but the first install has the
        // default `lastReadPage == 1`.  Real returning users will have
        // a non-default page state.
        let lastPage = defaults.integer(forKey: Keys.lastReadPage)
        if lastRead.isEmpty && lastPage <= 1 { return nil }

        // Anything else = returning reader.  Show the welcome pill.
        return .welcomeBack
    }

    /// Stamps today's date as the last-acknowledged day so the pill won't
    /// re-appear inside this calendar day.  Called by the pill view as
    /// soon as it becomes visible — same fire-on-show pattern Android
    /// uses (callback in `LaunchedEffect` rather than on fade-out).
    func markDailyAcknowledged() {
        defaults.set(Self.todayDateKey(), forKey: Keys.lastAcknowledgedDate)
    }

    /// "YYYY-MM-DD" in Gregorian / US locale — wire-compatible with
    /// Android's `SimpleDateFormat("yyyy-MM-dd", Locale.US)`.  Using
    /// US locale (not current) guarantees the format never localises
    /// to «٢٠٢٦-٠٤-٢٩» which would break string-equality detection.
    fileprivate static func todayDateKey() -> String {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale   = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }

    // -------------------------------------------------------------------------
    // MARK: Private helpers
    // -------------------------------------------------------------------------

    /// Clamps a restored page number to 1…604. A freshly-installed app has
    /// no persisted value, so `defaults.integer(forKey:)` returns 0 — we
    /// bump that to 1.
    private static func clampPage(_ raw: Int) -> Int {
        if raw < 1 { return 1 }
        if raw > WarattilConstants.Mushaf.totalPages { return WarattilConstants.Mushaf.totalPages }
        return raw
    }
}

// =============================================================================
// MARK: AppTheme ordinal helpers
//
// Android persists the theme as an enum ordinal (0/1/2). We keep the same
// wire format so a future sync layer stays compatible.
// =============================================================================

extension AppTheme {
    /// 0-based ordinal matching the Kotlin enum declaration order.
    var ordinal: Int {
        switch self {
        case .heritage: return 0
        case .dark:     return 1
        case .sepia:    return 2
        }
    }

    /// Inverse of `ordinal`. Invalid ordinals fall back to Heritage.
    static func from(ordinal: Int) -> AppTheme {
        switch ordinal {
        case 0: return .heritage
        case 1: return .dark
        case 2: return .sepia
        default: return .heritage
        }
    }
}

