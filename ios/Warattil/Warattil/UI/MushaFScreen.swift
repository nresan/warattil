//
//  MushaFScreen.swift
//  Warattil
//
//  Ports the root Mushaf screen from
//  app/src/main/java/com/warattil/app/ui/MushaFScreen.kt.
//
//  SCOPE (integration step — every menu item now wired):
//    ✅ HorizontalPager equivalent: SwiftUI TabView(.page) over 604 pages
//    ✅ RTL swipe direction — right-to-left, matching Mushaf convention
//    ✅ Pinned MushaFHeader with all 11 callbacks + bookmark/memorize state
//    ✅ Pinned MushaFFooter (momentum bar + Arabic status + page number)
//    ✅ Per-page on-appear load trigger (in case the VM's pre-warm missed)
//    ✅ Overflow-menu sheets: Fihris · Bookmarks · Search · Wird · HifzLog ·
//       UsageGuide · About — each presented via `.sheet(isPresented:)`
//    ✅ Theme cycle wired to vm.cycleTheme()
//    ✅ Bookmark / Memorize toggles wired to vm (state reads re-render the
//       header automatically via @Observable tracking).
//    ✅ "شارك ورتّل" app-share action — UIActivityViewController bridge.
//
//  DEFERRED (non-blocking polish):
//    ❌ Long-press ayah selection action bar
//    ❌ Landscape "Elderly" large-reading mode override (48 sp, immersive box)
//    ❌ Ornate surah-header cartouche — current banner is a placeholder line.
//

import SwiftUI
import UIKit

struct MushaFScreen: View {

    /// The sole source of truth. Construction + lifecycle is managed by the
    /// App entry point; we take an existing instance so the pre-warm in its
    /// init has already kicked off before this view appears.
    @Bindable var viewModel: MushaFViewModel

    // MARK: - Sheet presentation state
    //
    // One boolean per overflow-menu destination. Kept on the screen (not the
    // VM) because they describe UI navigation, not data — mirrors the Android
    // Compose `var showX by remember { mutableStateOf(false) }` pattern.

    @State private var showFihris:      Bool = false
    @State private var showBookmarks:   Bool = false
    @State private var showSearch:      Bool = false
    @State private var showWird:        Bool = false
    @State private var showHifzLog:     Bool = false
    @State private var showAzan:        Bool = false   // أوقات الصلاة (added 2026-05-20)
    @State private var showUsageGuide:  Bool = false
    @State private var showAbout:       Bool = false
    @State private var showShare:       Bool = false
    // Overflow dropdown state — hoisted out of MushaFHeader so the card
    // can be overlaid at screen level, pinned to the top-right corner
    // (see OverflowMenuCard for the rationale).
    @State private var showOverflow:    Bool = false

    // ── Hifz phase-1 surfaces ─────────────────────────────────────────────
    // The bulk picker is launched from inside HifzLogSheet's stats tab.
    // When it confirms (`onApply`), we re-open the HifzLogSheet on tab 1
    // (خريطة الحفظ) so the user sees the effect of their تثبيت on the
    // garden immediately — mirrors task #20 on Android.
    @State private var showBulkPicker:  Bool = false
    @State private var hifzLogInitialTab: Int = 0

    // ── Daily acknowledgement pill (parity with Android V3) ───────────────
    // Resolved once on `.task` from the view model's persisted date keys
    // and stashed here so subsequent renders don't recompute it.  The
    // pill view drives its own fade-in / dwell / fade-out timeline; this
    // state stays non-nil for the full session after first appearance,
    // which is fine because the pill becomes hit-test-transparent and
    // opacity-zero after its 5 s dwell.  Resetting to nil isn't needed
    // (and would risk a double-fire if SwiftUI re-runs the task).
    @State private var dailyAck:        MushaFViewModel.DailyAcknowledgement?

    // MARK: - Derived bindings

    /// Two-way binding from the VM's `currentPage` into TabView selection.
    /// The setter routes through `onPageChanged(to:)` so persistence +
    /// pre-warm of neighbors happen on every swipe.
    private var pageBinding: Binding<Int> {
        Binding(
            get: { viewModel.currentPage },
            set: { newPage in
                if newPage != viewModel.currentPage {
                    viewModel.onPageChanged(to: newPage)
                }
            }
        )
    }

    /// Two-way binding into the VM's searchQuery — the TextField writes back
    /// via `.onChange` → `viewModel.onSearchQueryChanged`, which also kicks
    /// off the 300 ms debounce and updates `searchResults`/`isSearching`.
    private var searchQueryBinding: Binding<String> {
        Binding(
            get: { viewModel.searchQuery },
            set: { viewModel.onSearchQueryChanged($0) }
        )
    }

    // MARK: - Body

    var body: some View {
        let theme = viewModel.themeColors
        let font  = quranFont()

        // Resolve the current page's surah + juz info from the loaded state.
        // Fallback strings keep the header stable during the loading frame
        // before the first page appears.
        let (surahName, juzNumber) = resolveHeaderInfo()

        VStack(spacing: 0) {

            MushaFHeader(
                surahName:    surahName,
                juzNumber:    juzNumber,
                currentPage:  viewModel.currentPage,
                theme:        theme,
                font:         font,
                isBookmarked:   viewModel.isBookmarked(viewModel.currentPage),
                // Tri-state alpha via Hifz.stripAlpha(ratio) — see
                // MushaFHeader.memorizedRatio.  Reads at every body render;
                // @Observable tracks `memorizedAyahs` so the tint updates
                // immediately after a toggle.
                memorizedRatio: viewModel.pageMemorizationRatio(viewModel.currentPage),
                onBookmark:     { viewModel.toggleBookmark(viewModel.currentPage) },
                onMemorize:     { viewModel.togglePage(viewModel.currentPage) },
                onThemeCycle: { viewModel.cycleTheme() },
                onSearch:     { showSearch     = true },
                onFihris:     { showFihris     = true },
                onBkm:        { showBookmarks  = true },
                onWird:       { showWird       = true },
                onHifzLog:    { showHifzLog    = true },
                onAzan:       { showAzan       = true },
                onUsageGuide: { showUsageGuide = true },
                onAbout:      { showAbout      = true },
                onShare:      { showShare      = true },
                onMenuTap:    { showOverflow   = true }
            )

            // RTL pager — pages swipe right-to-left as the Arabic reader
            // advances. The `.environment(\.layoutDirection, .rightToLeft)`
            // applied to the TabView flips the swipe direction.
            //
            // The renderer consumes ayah-based `pageStates` (PageContent) —
            // the same source that drives the header/footer (surah name /
            // juz number / share). As of 2026-04-21 rendering no longer
            // depends on the QCF per-page glyph tables: ayah text and inline
            // gold ﴿N﴾ markers are composed directly from `quran_text`,
            // matching the Android MushaFBody approach pixel-for-pixel.
            TabView(selection: pageBinding) {
                ForEach(1...WarattilConstants.Mushaf.totalPages, id: \.self) { pageNumber in
                    MushaFPageView(
                        state:     viewModel.pageStates[pageNumber] ?? .loading,
                        theme:     theme,
                        viewModel: viewModel
                    )
                    .tag(pageNumber)
                    // On-demand load for any page the TabView shows but the
                    // VM didn't pre-warm. The VM's ensureLoaded is idempotent,
                    // so re-calling it on every appearance is cheap.
                    .task(id: pageNumber) { viewModel.ensureLoaded(pageNumber) }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .environment(\.layoutDirection, .rightToLeft)

            MushaFFooter(
                currentPage:     viewModel.currentPage,
                progressRatio:   viewModel.progressRatio,
                progressColor:   viewModel.progressColor,
                progressMsg:     viewModel.progressMessage,
                theme:           theme,
                font:            font,
                wirdResumePage:  viewModel.wirdResume,
                onWirdResumeTap: {
                    if let p = viewModel.wirdResume {
                        viewModel.navigateToPage(p)
                    }
                }
            )
        }
        .background(theme.background.ignoresSafeArea())
        .toastOverlay(theme: theme)

        // ──────────────────────────────────────────────────────────────────
        // Overflow dropdown — screen-level overlay pinned to the top-RIGHT
        // corner. Rendered here (not inside MushaFHeader) so it hugs the
        // right edge of the screen regardless of where the ≡ button sits
        // inside the header's HStack. A full-screen transparent scrim behind
        // the card catches outside taps to dismiss. Animation mirrors the
        // Android Compose DropdownMenu (fade + scale anchored top-right).
        //
        // RTL NOTE (2026-04-22 fix):
        //   ContentView wraps the whole Mushaf tree in
        //   `.environment(\.layoutDirection, .rightToLeft)` so Arabic text
        //   flows the right way. But SwiftUI resolves `.topTrailing` against
        //   the inherited layout direction — so under RTL, `.topTrailing`
        //   means top-LEFT visually. The overflow card was landing on the
        //   WRONG side of the screen (Nasser reported "the menu moved to
        //   the left side should be on the right side").
        //
        //   Fix: force the overlay's POSITIONING wrapper to LTR so
        //   `.topTrailing` + `.padding(.trailing, 8)` literally mean
        //   top-right + right-gutter. The OverflowMenuCard's own internal
        //   content still uses its own `.rightToLeft` env for Arabic labels
        //   (see MushaFHeader.swift → OverflowMenuCard).
        //
        // The card's `onDismiss` is wired to flip `showOverflow` off; each
        // menu row fires that dismiss AND the action (see OverflowMenuCard),
        // so we only need to forward the sheet-toggle for each row here.
        // ──────────────────────────────────────────────────────────────────
        .overlay(alignment: .topTrailing) {
            if showOverflow {
                ZStack(alignment: .topTrailing) {
                    // Invisible scrim — catches taps outside the card.
                    Color.black.opacity(0.0001)
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .onTapGesture { showOverflow = false }

                    OverflowMenuCard(
                        theme:        theme,
                        onDismiss:    { showOverflow    = false },
                        onFihris:     { showFihris      = true  },
                        onBkm:        { showBookmarks   = true  },
                        onWird:       { showWird        = true  },
                        onHifzLog:    { showHifzLog     = true  },
                        onAzan:       { showAzan        = true  },
                        onUsageGuide: { showUsageGuide  = true  },
                        onAbout:      { showAbout       = true  },
                        onShare:      { showShare       = true  },
                        onShareDaily: { presentDailyReadingShare() }
                    )
                    .padding(.top, 52)
                    .padding(.trailing, 8)
                    .transition(
                        .opacity.combined(
                            with: .scale(scale: 0.92, anchor: .topTrailing)
                        )
                    )
                }
                .zIndex(10)
                // Force LTR *on the positioning layer only* so .topTrailing
                // resolves to the visual top-right corner. See RTL NOTE above.
                .environment(\.layoutDirection, .leftToRight)
            }
        }
        .animation(.easeOut(duration: 0.15), value: showOverflow)

        // ──────────────────────────────────────────────────────────────────
        // Daily acknowledgement pill — top-center overlay, parity with
        // Android V3 YesterdayAcknowledgementPill.  Anchored below the
        // header (top padding tuned to clear MushaFHeader at 68 pt) and
        // hit-test-transparent so taps fall through to the pager body.
        //
        // Resolution rule: `viewModel.dailyAcknowledgement` returns nil
        // when the reader has already been seen today, has already been
        // acknowledged today, or is on a true first install.  Otherwise
        // it returns `.welcomeBack` (or, in the future, `.yesterdayRead`).
        // ──────────────────────────────────────────────────────────────────
        .overlay(alignment: .top) {
            if let ack = dailyAck {
                DailyAcknowledgementPill(
                    acknowledgement: ack,
                    theme:           theme,
                    onAcknowledged:  { viewModel.markDailyAcknowledged() }
                )
                .padding(.top, 68)
                .zIndex(20)
            }
        }
        // Compute the acknowledgement ONCE on screen appear.  `.task` runs
        // once per identity per scene-active, which matches Android's
        // LaunchedEffect(prefs) — the pill never re-evaluates on swipe or
        // sheet open/close, only on cold start / scene re-entry.
        .task {
            // Stash result so subsequent renders don't re-read defaults.
            // Even if .task re-fires on scene re-entry, the pill view's
            // own `didFireAcknowledgement` guard suppresses double markup.
            dailyAck = viewModel.dailyAcknowledgement
        }

        // ──────────────────────────────────────────────────────────────────
        // Overflow-menu sheet presentations. Each `.sheet(isPresented:)` is
        // attached to the same root view; SwiftUI can present multiple sheets
        // from a single host as long as only one flag is true at a time — the
        // menu dismisses before toggling, so that invariant holds naturally.
        //
        // Navigation actions inside a sheet follow the same shape everywhere:
        //   1) dismiss the sheet
        //   2) ask the VM to jump
        // …so the pager settles on the target page after the sheet slides
        // off screen, keeping the animation crisp.
        // ──────────────────────────────────────────────────────────────────

        .sheet(isPresented: $showFihris) {
            FihrisSheet(
                surahStartPages: viewModel.surahStartPages,
                juzStartPages:   viewModel.juzStartPages,
                // Phase-1 derivation: derive the set of fully-memorized
                // page numbers from the ayah set so FihrisSheet's existing
                // "surah fully memorized" subset check still works.  Cheap
                // (≤604 predicates) and lets FihrisSheet stay untouched by
                // the storage refactor.
                memorizedPages:  derivedFullyMemorizedPages(),
                theme:           viewModel.themeColors,
                font:            quranFont(),
                onNavigate: { page in
                    showFihris = false
                    viewModel.navigateToPage(page)
                },
                onDismiss: { showFihris = false }
            )
        }

        .sheet(isPresented: $showBookmarks) {
            BookmarksSheet(
                bookmarks: viewModel.bookmarks,
                theme:     viewModel.themeColors,
                font:      quranFont(),
                onNavigate: { page in
                    showBookmarks = false
                    viewModel.navigateToPage(page)
                },
                onDelete:   { page in viewModel.deleteBookmark(page) },
                onClearAll: { viewModel.clearAllBookmarks() },
                onDismiss:  { showBookmarks = false }
            )
        }

        .sheet(isPresented: $showSearch) {
            SearchSheet(
                query:     searchQueryBinding,
                results:   viewModel.searchResults,
                isLoading: viewModel.isSearching,
                theme:     viewModel.themeColors,
                font:      quranFont(),
                // No-op — `searchQueryBinding`'s setter already routes every
                // keystroke through `viewModel.onSearchQueryChanged`, so the
                // sheet's own `.onChange(of: query)` would otherwise fire the
                // 300 ms debounce twice per character. Left wired so the
                // SearchSheet API stays explicit.
                onQueryChanged: { _ in },
                onNavigate: { page in
                    // 2026-05-03 — Android parity task #86. Was calling
                    // `clearSearch()` before navigation, which dropped the
                    // query before the destination page could highlight it.
                    // Now: capture the active query as the inline highlight
                    // FIRST, then navigate. Highlight persists across page
                    // swipes (so the reader can scan adjacent pages for the
                    // same word) and clears only via explicit `clearSearch()`
                    // — natural lifecycle for a "reading companion" highlight
                    // rather than a one-shot flash. Mirrors Android's
                    // `MushaFScreen.kt :: onNav`.
                    showSearch = false
                    viewModel.setSearchHighlight(viewModel.searchQuery)
                    viewModel.navigateToPage(page)
                },
                onDismiss: {
                    // 2026-05-03 — Android parity. Search sheet now
                    // preserves last query + results when reopened (V3
                    // changelog: "Search sheet preserves last query +
                    // results when reopened — no need to remember which
                    // word you were looking for"). Don't `clearSearch()`
                    // on dismiss; let the user reopen to the same state.
                    // Explicit clearing happens via the field's clear
                    // button (handled in SearchSheet).
                    showSearch = false
                }
            )
        }

        .sheet(isPresented: $showWird) {
            WirdSheet(
                currentPage:     viewModel.currentPage,
                userPreferences: viewModel.userPreferences,
                theme:           viewModel.themeColors,
                font:            quranFont(),
                onSet: { type, value in
                    viewModel.setWirdTarget(type, value: value)
                    showWird = false
                },
                onReset: {
                    // 2026-04-27 (pt. 4): was viewModel.resetProgress()
                    // — which ALSO wiped every bookmark.  «ابدأ ختمة
                    // جديدة» now calls cancelWird() which clears wird
                    // state + rewinds reading to page 1, but preserves
                    // bookmarks + hifz progress (matches Android).
                    viewModel.cancelWird()
                    showWird = false
                },
                onDismiss: { showWird = false }
            )
        }

        .sheet(isPresented: $showHifzLog) {
            HifzLogSheet(
                memorizedAyahs:  viewModel.memorizedAyahs,
                surahStartPages: viewModel.surahStartPages,
                juzStartPages:   viewModel.juzStartPages,
                theme:           viewModel.themeColors,
                font:            quranFont(),
                onNavigate: { page in
                    showHifzLog = false
                    viewModel.navigateToPage(page)
                },
                onBulkEntry: {
                    // Close the log sheet first so SwiftUI doesn't stack
                    // two sheets (iOS 17 crashes when you try).  The bulk
                    // picker presents after the dismiss animation settles.
                    showHifzLog = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showBulkPicker = true
                    }
                },
                onDismiss:   { showHifzLog = false },
                initialTab:  hifzLogInitialTab
            )
        }

        // ── Bulk picker — juz / surah / page-range batch توسيم ─────────────
        //   Presented AFTER the log sheet dismisses (see onBulkEntry above).
        //   The sheet's `onDismiss:` callback ALWAYS re-opens the log sheet
        //   on the heatmap tab — whether the user taps «ثبت», taps an explicit
        //   cancel, or swipes the sheet down.  Before 2026-04-23 the re-open
        //   only fired on apply; readers who dismissed without applying lost
        //   their place and had to re-open the Halaqa menu → heatmap manually
        //   to see their progress.  Nasser reported the friction directly.
        //   SwiftUI runs `onDismiss:` AFTER `showBulkPicker` has flipped to
        //   false, so the subsequent `.sheet(isPresented: $showHifzLog)`
        //   re-presentation is safe and single-shot.
        .sheet(
            isPresented: $showBulkPicker,
            onDismiss: {
                // Land on the heatmap tab regardless of *how* the picker was
                // dismissed — the garden is the entire reason the reader
                // launched the picker, so showing it back to them on close
                // is the right default.
                hifzLogInitialTab = 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showHifzLog = true
                }
            }
        ) {
            HifzBulkPickerSheet(
                initialMemorized: viewModel.memorizedAyahs,
                font:             quranFont(),
                theme:            viewModel.themeColors,
                onApply: { added, removed in
                    if !added.isEmpty {
                        viewModel.setAyahsMemorized(added,   memorized: true)
                    }
                    if !removed.isEmpty {
                        viewModel.setAyahsMemorized(removed, memorized: false)
                    }
                    // Flip the binding — the sheet's `onDismiss:` (above)
                    // handles the return to the heatmap.
                    showBulkPicker = false
                },
                onDismiss: { showBulkPicker = false }
            )
        }

        .sheet(isPresented: $showUsageGuide) {
            UsageGuideSheet(
                theme:     viewModel.themeColors,
                font:      quranFont(),
                onDismiss: { showUsageGuide = false }
            )
        }

        .sheet(isPresented: $showAbout) {
            AboutSheet(
                theme:     viewModel.themeColors,
                font:      quranFont(),
                onDismiss: { showAbout = false }
            )
        }

        // أوقات الصلاة — Azan settings sheet (port from Android, 2026-05-20).
        // Master toggle + location capture + per-prayer mode picker.  Audio
        // playback for FULL/SHORT modes is deferred to iOS v1.2 (see
        // AzanSettings header note); for v1.1 all modes behave as
        // notification + system vibration.
        .sheet(isPresented: $showAzan) {
            AzanSettingsSheet(
                theme:     viewModel.themeColors,
                font:      quranFont(),
                onDismiss: { showAzan = false }
            )
        }

        // "شارك ورتّل" — the app-share payload from ShareUtil. Hadith-framed
        // invitation, not a per-ayah share. The ayah-level share bar is a
        // separate (still-deferred) long-press action.
        //
        // We intentionally do NOT wrap UIActivityViewController in a SwiftUI
        // `.sheet { UIViewControllerRepresentable }`. That pattern triggers
        // the runtime warning
        //
        //     Adding '_UIReparentingView' as a subview of
        //     UIHostingController.view is not supported and may result in a
        //     broken view hierarchy.
        //
        // because SwiftUI's hosting controller tries to adopt the activity
        // VC's private reparenting view, which UIKit rejects. The supported
        // path is to present the activity VC directly from a live UIKit
        // view-controller — we do that from the key window's top presenter
        // when `showShare` flips to `true`. Seen by Nasser 2026-04-20 as a
        // console spam loop during the first install on iPhone 17 Pro sim.
        .onChange(of: showShare) { _, isShowing in
            guard isShowing else { return }
            // Reset immediately so the flag can flip again for a second share
            // later. The activity VC is now owned by UIKit's presentation
            // stack, not SwiftUI — resetting the flag does not dismiss it.
            showShare = false
            presentAppShare()
        }

        // ── Hifz tier-crossing celebration ─────────────────────────────────
        //   The VM sets `pendingCelebrationTier` whenever an apply raises the
        //   reader's tier above the previously-celebrated mark.  We overlay
        //   the Kuttāb-styled dialog on top of every other surface; on
        //   dismiss / share we clear the flag via `acknowledgeCelebration`
        //   so the dialog never retriggers for the same tier.
        .overlay {
            if let tier = viewModel.pendingCelebrationTier {
                HifzCelebrationDialog(
                    tier:     tier,
                    juzCount: hifzJuzCountForCelebration(),
                    theme:    viewModel.themeColors,
                    onDismiss: { viewModel.acknowledgeCelebration() }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .zIndex(100)
            }
        }
        .animation(
            .easeInOut(duration: 0.25),
            value: viewModel.pendingCelebrationTier
        )
    }

    // ── Hifz derivations used by the sheets ──────────────────────────────
    //
    // FihrisSheet still takes a `Set<Int>` of fully-memorized page numbers
    // for its gold-surah tint check.  We compute it on demand from the
    // ayah set so FihrisSheet stays untouched by the ayah-atomic refactor
    // and later surfaces can share the same cheap helper.
    private func derivedFullyMemorizedPages() -> Set<Int> {
        var out = Set<Int>()
        let ayahs = viewModel.memorizedAyahs
        for p in 1...WarattilConstants.Mushaf.totalPages {
            let keys = MetadataParser.shared.getPageAyahKeys(p)
            if keys.isEmpty { continue }
            if keys.allSatisfy({ ayahs.contains($0) }) { out.insert(p) }
        }
        return out
    }

    /// Juz count shown under the celebration headline.  The VM sets
    /// `pendingCelebrationTier` AFTER writing the new ayah set, so reading
    /// `memorizedAyahs` here picks up the just-applied data.
    private func hifzJuzCountForCelebration() -> Int {
        let ayahs = viewModel.memorizedAyahs
        var count = 0
        for j in 1...WarattilConstants.Mushaf.totalJuzaa {
            let keys = MetadataParser.shared.getJuzAyahKeys(j)
            if keys.isEmpty { continue }
            if keys.allSatisfy({ ayahs.contains($0) }) { count += 1 }
        }
        return count
    }

    // MARK: - Header info resolution

    /// Look up the surah name + juz number for the currently-displayed page
    /// from the loaded state. Falls back to Al-Fatiha / juz 1 during the
    /// pre-load frame so the header never shows an empty string.
    private func resolveHeaderInfo() -> (surahName: String, juzNumber: Int) {
        if case .loaded(let content) = viewModel.pageStates[viewModel.currentPage] {
            return (content.surahName, content.juzNumber)
        }
        // Defensive fallback — page not loaded yet.
        return (MetadataParser.shared.getSuraName(1), 1)
    }

    // MARK: - App-share presentation — UIKit direct path
    //
    // Walks up the key window's presented-VC chain to find the topmost
    // foreground controller, then presents the `UIActivityViewController`
    // from there. iPad requires a popover anchor — we pin it to the
    // centre of the presenter's view so the sheet doesn't crash in
    // regular-width idioms.

    // MARK: - Daily reading share — card rendering + activity bring-up
    //
    // Builds a DailyReadingCardData from the current view-model state, renders
    // the card to a UIImage via ImageRenderer, and hands it to
    // `ShareUtil.shareDailyReading`.  The render is gated on the main actor
    // because SwiftUI's ImageRenderer requires it (see DailyReadingShareCard
    // for the renderSnapshot signature).
    //
    // Pulling `pagesReadToday` / `dailyPagesGoal` here (not on the VM) keeps
    // the VM API surface slim — the card is the only surface that currently
    // needs those two derived values, so computing them at the call site
    // avoids adding two new computed properties to an already-busy VM.  If a
    // second caller needs them, promote them to VM then.

    private func presentDailyReadingShare() {
        // Derive today's pages-read / goal when a wird is configured; else
        // leave both nil so the card falls back to the page-in-Mushaf stat.
        var pagesReadToday: Int? = nil
        var dailyPagesGoal: Int? = nil
        if let prefs = viewModel.userPreferences, prefs.wirdStartDate != nil {
            let dailyGoal  = viewModel.wirdDailyPages(prefs)
            if let target  = viewModel.wirdTodayTargetPage(prefs) {
                let todayStart = max(target - dailyGoal + 1, 1)
                pagesReadToday = max(viewModel.currentPage - todayStart + 1, 0)
                dailyPagesGoal = dailyGoal
            }
        }

        let (surahName, juzNumber) = resolveHeaderInfo()

        let data = DailyReadingCardData(
            currentPage:    viewModel.currentPage,
            surahName:      surahName,
            juzNumber:      juzNumber,
            progressRatio:  viewModel.progressRatio,
            progressMessage: viewModel.progressMessage,
            progressColor:  viewModel.progressColor,
            pagesReadToday: pagesReadToday,
            dailyPagesGoal: dailyPagesGoal
        )

        // Main-actor render — ImageRenderer requires it, and this helper is
        // already called from SwiftUI gesture handlers so we're on the main
        // actor anyway.  Falls through silently if the renderer returns nil
        // (which it shouldn't for a 720 pt card, but quiet-fail beats
        // crashing the reader mid-share).
        //
        // Heritage lock (2026-04-29 — parity with Android V3 + Hifz garden
        // share):  the captured PNG ALWAYS uses the Heritage cream/charcoal
        // palette regardless of the user's current theme.  A reader on Dark
        // mode previously got a charcoal-on-near-black PNG that was nearly
        // unreadable inside WhatsApp's bubble.  Pinning Heritage gives every
        // share a consistent, recognisably-WARATTIL look — same rule as
        // capturableGarden in HifzLogSheet.
        Task { @MainActor in
            guard let image = DailyReadingShareCard.renderSnapshot(
                data:  data,
                theme: WarattilTheme.heritage,
                font:  quranFont()
            ) else { return }
            ShareUtil.shareDailyReading(image: image)
        }
    }

    // The "شارك ورتّل" share used to hand a plain Arabic paragraph to the
    // activity sheet — which is fine for WhatsApp/SMS but a dead letter on
    // Instagram Stories and loses all ورتّل branding on Facebook/Twitter.
    // BLUEPRINT §11.4 lifts the invite into a rendered card (see
    // AppInviteShareCard.swift) that we hand alongside the text body.
    // ShareUtil.shareAppInvite handles the fallback if the render fails.
    private func presentAppShare() {
        Task { @MainActor in
            let image = AppInviteShareCard.renderSnapshot(theme: viewModel.themeColors)
            ShareUtil.shareAppInvite(image: image)
        }
    }
}
