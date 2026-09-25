//
//  MushaFSheets.swift
//  Warattil
//
//  All modal sheets and dialogs presented from the MushaFScreen overflow menu
//  or icon strip, ported from the Android counterparts:
//
//    FihrisSheet       ← MushaFScreen.kt (SurahSheet / JuzSheet tabs)
//    BookmarksSheet    ← MushaFScreen.kt (BookmarkSheet)
//    SearchSheet       ← MushaFScreen.kt (SearchSheet)
//    WirdSheet         ← MushaFScreen.kt (WirdDialog)
//    HifzLogSheet      ← HifzLogSheet.kt (simplified — list of memorised surahs)
//    UsageGuideSheet   ← UsageGuideSheet.kt (six entries)
//    AboutSheet        ← AboutSheet.kt (provenance + credits + colophon)
//
//  Each sheet takes an explicit set of values + callbacks — no direct VM
//  reach-through — so the root screen retains control over presentation
//  state and the sheets stay unit-testable in isolation.
//

import SwiftUI

// =============================================================================
// Gold palette constants — mirrored from Android FIHRIS_GOLD / HIFZ_GOLD
// so the "gold" semantics of memorised surahs read the same on both sides.
// =============================================================================

private let fihrisGold   = Color(red: 0x99 / 255.0, green: 0x65 / 255.0, blue: 0x15 / 255.0)
private let fihrisGoldBg = Color(red: 0xFF / 255.0, green: 0xF8 / 255.0, blue: 0xE1 / 255.0)

// =============================================================================
// MARK: - WarattilTextFieldStyle — themed field chrome
// =============================================================================
//
// 2026-04-22: `.textFieldStyle(.roundedBorder)` (UIKit-backed `.roundedRect`)
// sources its colours from iOS system materials, which track the DEVICE's
// light/dark appearance rather than the WARATTIL theme. On a device set to
// dark mode, the search field rendered as a BLACK capsule with near-white
// system text sitting inside the app's CREAM sheet — Nasser flagged it as
// "the search form color is not visible … inconsistent with the theme."
//
// This modifier opts out of iOS system chrome (`.textFieldStyle(.plain)`)
// and paints the field in WARATTIL palette tokens:
//
//   • Fill        → `theme.bannerBg` (a subtle off-surface that still reads
//                   as "input-land" against the sheet background without
//                   going dark-opaque)
//   • Text        → `theme.text` (charcoal on heritage, parchment on dark)
//   • Placeholder → `theme.text.opacity(0.45)` (same muted tier as the
//                   "no results" label in SearchSheet)
//   • Border      → `theme.gold` at 35 % — hairline cartouche hint that
//                   keeps the field legible on every theme without
//                   shouting for attention
//   • Caret       → `theme.accent` (Mushaf green on heritage)
//
// Apply via `.warattilTextField(theme:)`. Use EVERYWHERE a `TextField`
// appears so the app never renders a system-chrome field again.
// =============================================================================

extension View {
    /// Themed text-field chrome — cream surface, charcoal body, gold hairline,
    /// accent caret. Replaces every `.textFieldStyle(.roundedBorder)` site in
    /// the codebase so fields stay legible on cream, sepia, and dark themes
    /// regardless of the device's system appearance.
    func warattilTextField(theme: ThemeColors) -> some View {
        self
            .textFieldStyle(.plain)
            .foregroundStyle(theme.text)
            .tint(theme.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(theme.bannerBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(theme.gold.opacity(0.35), lineWidth: 0.5)
            )
    }
}

// =============================================================================
// MARK: - WarattilSheetTitle — themed navigation-bar title
// =============================================================================
//
// 2026-04-22: `.navigationTitle("...")` uses `UINavigationBar`'s
// `titleTextAttributes.foregroundColor`, which defaults to
// `UIColor.label` — a dynamic system color that tracks the DEVICE's
// dark/light mode. On a device set to dark mode, the SearchSheet title
// `البحث في القرآن الكريم` rendered NEAR-WHITE on the cream sheet
// background, invisible from a couple feet away. Nasser's words:
//
//   "The white color of the text البحث في القران الكريم is not
//    visible to the user. Please use a color that matches our theme."
//
// Fix: replace `.navigationTitle(_:)` with a `ToolbarItem(placement:
// .principal)` that paints the title text in `theme.accent` (Mushaf
// green on heritage, lighter green on dark, deep brown on sepia) using
// the Amiri chrome font we already use for other sheet labels. This
// tracks the active theme — not the device.
//
// Usage (inside a NavigationStack's `.toolbar { }` block, or applied
// via `.warattilSheetTitle("...", theme: theme)`):
//
//   ToolbarItem(placement: .principal) {
//       WarattilSheetTitle(text: "البحث في القرآن الكريم", theme: theme)
//   }
//
// Keep `.navigationBarTitleDisplayMode(.inline)` on the sheet so the
// principal item anchors to the inline position (the wide/large title
// area would hide it under the sheet's top edge).
// =============================================================================

struct WarattilSheetTitle: View {
    let text:  String
    let theme: ThemeColors

    var body: some View {
        Text(text)
            .font(.warattilChrome(size: 17, weight: .semibold))
            .foregroundStyle(theme.accent)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .environment(\.layoutDirection, .rightToLeft)
    }
}

extension View {
    /// Convenience wrapper that injects a `WarattilSheetTitle` into the
    /// current `.toolbar` as the principal item AND pins the display
    /// mode to `.inline` (mandatory — the principal slot in a large-
    /// title bar is collapsed and the title won't show). Does NOT emit
    /// a `.navigationTitle(...)` so the system default color path never
    /// activates.
    func warattilSheetTitle(_ text: String, theme: ThemeColors) -> some View {
        self
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    WarattilSheetTitle(text: text, theme: theme)
                }
            }
    }
}

// =============================================================================
// MARK: - FihrisSheet — surah / juz index
// =============================================================================

/// Two-tab index: surahs (114) and juz (30). Tapping a row jumps the pager.
/// Memorised surahs get a gold tint — a visible reward for the hifz student.
struct FihrisSheet: View {

    let surahStartPages: [Int: Int]
    let juzStartPages:   [Int: Int]
    let memorizedPages:  Set<Int>
    let theme:           ThemeColors
    let font:            QuranFontInfo
    let onNavigate:      (Int) -> Void
    let onDismiss:       () -> Void

    @State private var tab: Int = 0

    /// 2026-04-22 — per-tab filter strings. Nasser: "the suras are 114 and
    /// the pages are 604, and very hard to scroll to reach the desired
    /// page, so if the user can filter to fast reach would be great."
    ///
    /// Two separate strings (not one shared) so switching tabs preserves
    /// each tab's filter context — a student halfway through typing "بقر"
    /// on the surah tab can peek at the page tab and come back to their
    /// partial query. الأجزاء (30 items) has no filter — short enough to
    /// scroll in one thumb-drag.
    @State private var surahFilter: String = ""
    @State private var pageFilter:  String = ""

    /// Surahs matching `surahFilter`. An empty filter returns all 114.
    /// Matching tries:
    ///   1. surah name substring (raw — works for most typed names)
    ///   2. Western-digit ordinal substring (e.g. "2" → Al-Baqarah)
    ///   3. Arabic-digit ordinal substring (e.g. "٢" → Al-Baqarah)
    ///
    /// Normalisation is deliberately shallow — the Uthmani name stored in
    /// `MetadataParser.shared.getSuraName(_:)` already reads cleanly for
    /// common typed queries (البقرة, الفاتحة, etc.).
    private var filteredSurahs: [Int] {
        let q = surahFilter.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Array(1...114) }
        return (1...114).filter { n in
            let name = MetadataParser.shared.getSuraName(n)
            return name.contains(q)
                || "\(n)".contains(q)
                || n.arabicDigits.contains(q)
        }
    }

    /// Pages matching `pageFilter`. Accepts both Western and Arabic
    /// digits — students transcribing a wird plan often have one or the
    /// other on hand. Empty filter returns all 604 pages.
    ///
    /// Matching is substring-based so "١٠" surfaces pages 10, 100–109,
    /// 110–119, … — gives the user a cluster to scroll through rather
    /// than forcing an exact match.
    private var filteredPages: [Int] {
        let q = pageFilter.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Array(1...WarattilConstants.Mushaf.totalPages) }
        return (1...WarattilConstants.Mushaf.totalPages).filter { p in
            "\(p)".contains(q) || p.arabicDigits.contains(q)
        }
    }

    /// Surahs whose every page is in `memorizedPages`. Computed once per
    /// appearance — the set is small (≤114 entries) so O(N) is fine.
    private var goldenSurahs: Set<Int> {
        var out: Set<Int> = []
        for s in 1...114 {
            guard let start = surahStartPages[s] else { continue }
            let end = s < 114
                ? (surahStartPages[s + 1] ?? (WarattilConstants.Mushaf.totalPages + 1)) - 1
                : WarattilConstants.Mushaf.totalPages
            guard start <= end else { continue }
            let pages = Set(start...end)
            if pages.isSubset(of: memorizedPages) { out.insert(s) }
        }
        return out
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tabs — segmented Picker was visually flat against the
                // cream background (Nasser 2026-04-21: "tabs don't look
                // like buttons"). These pill buttons carry a filled
                // accent state + ringed inactive state so the control
                // reads unambiguously as tappable.
                //
                // RTL order: السور on the right, الأجزاء in the middle,
                // الصفحات on the left. Nasser 2026-04-21 asked for a
                // فهرس الصفحات tab so the user can jump to any of the 604
                // pages directly — particularly useful for students
                // following a daily wird by page-reference.
                HStack(spacing: 8) {
                    fihrisTabButton(title: "السور",    tag: 0)
                    fihrisTabButton(title: "الأجزاء",  tag: 1)
                    fihrisTabButton(title: "الصفحات",  tag: 2)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 4)
                .environment(\.layoutDirection, .rightToLeft)

                // Filter row — shown on the السور and الصفحات tabs only.
                // الأجزاء has just 30 items and doesn't need filtering.
                // Using the tab as a switch keeps each state.binding
                // independent (typing on one tab doesn't disturb the other)
                // and keeps the keyboard numeric on the pages tab.
                filterRow

                switch tab {
                case 0:  surahList
                case 1:  juzList
                default: pageList
                }
            }
            .background(theme.background)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    WarattilSheetTitle(text: "الفهرس", theme: theme)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("إغلاق") { onDismiss() }
                        .foregroundStyle(theme.accent)
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    /// Per-tab filter TextField, placed between the tab pills and the
    /// list. Switches placeholder + keyboard by tab:
    ///   - Surah tab  → text placeholder "ابحث عن سورة…", default keyboard
    ///   - Pages tab  → numeric placeholder + `.numberPad` keyboard
    ///                  (Arabic-digit input still works via substring
    ///                   matching in `filteredPages`)
    ///   - Juz tab    → returns `EmptyView` (no filter needed for 30 items)
    @ViewBuilder
    private var filterRow: some View {
        switch tab {
        case 0:
            TextField("ابحث عن سورة…", text: $surahFilter)
                .font(.warattilChrome(size: 14))
                .warattilTextField(theme: theme)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 4)
                .environment(\.layoutDirection, .rightToLeft)
        case 2:
            TextField("رقم الصفحة (١ – ٦٠٤)", text: $pageFilter)
                .font(.warattilChrome(size: 14))
                .keyboardType(.numberPad)
                .warattilTextField(theme: theme)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 4)
                .environment(\.layoutDirection, .rightToLeft)
        default:
            EmptyView()
        }
    }

    /// Resolve the "primary surah" for a given page — the last surah whose
    /// start page is ≤ `p`. Surah start pages are monotonically increasing
    /// across 1…114 so we can break early once we overshoot.
    ///
    /// Why this helper exists
    /// ----------------------
    /// The page index shows "صفحة N — [surah name]" rows so the student
    /// can pick a page with context. For multi-surah pages we surface the
    /// surah whose text occupies the bulk of the page (which is almost
    /// always the last-started one, since new surahs typically start mid-
    /// page and fill to the bottom).
    private func primarySurah(forPage p: Int) -> Int {
        var primary = 1
        for s in 1...114 {
            guard let start = surahStartPages[s] else { continue }
            if start <= p {
                primary = s
            } else {
                break
            }
        }
        return primary
    }

    // Row ordering note (applies to surahList, juzList, HifzLogSheet list):
    //
    // The outer NavigationStack applies `.environment(\.layoutDirection,
    // .rightToLeft)`, so the FIRST child of an HStack lands on the RIGHT
    // and the LAST child on the LEFT. We pin `.rightToLeft` on each row's
    // HStack too — belt-and-braces against any List internals that might
    // otherwise render chrome LTR (Nasser's screenshot on 2026-04-21
    // showed an inconsistently-laid-out index row).
    //
    // Reading order: SURAH NAME (primary, right) → SPACER → PAGE # (secondary, left).

    private var surahList: some View {
        let surahs = filteredSurahs
        return List {
            if surahs.isEmpty {
                // No matches — surface a soft empty state in the same
                // muted tone as SearchSheet's "لم يُعثر على نتائج".
                Text("لا توجد سورة مطابقة")
                    .font(.warattilChrome(size: 14))
                    .foregroundStyle(theme.text.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
                    .listRowBackground(theme.background)
            }
            ForEach(surahs, id: \.self) { n in
                let page = surahStartPages[n] ?? 1
                let isGold = goldenSurahs.contains(n)
                HStack {
                    HStack(spacing: 6) {
                        Text("\(n.arabicDigits).")
                            .font(.warattilChrome(size: 15, weight: isGold ? .bold : .medium))
                            .foregroundStyle(isGold ? fihrisGold : theme.text)
                        Text(MetadataParser.shared.getSuraName(n))
                            .font(font.font(size: 15).weight(isGold ? .bold : .medium))
                            .foregroundStyle(isGold ? fihrisGold : theme.text)
                        if isGold {
                            // Surah fully memorised — Kuttāb tablet badge.
                            // Rendering the لوح glyph (same vector as the
                            // header button) keeps the Hifz visual language
                            // consistent across surfaces.
                            LawhHifzIcon(size: 13, tint: fihrisGold)
                        }
                    }
                    Spacer()
                    Text("ص \(page.arabicDigits)")
                        .font(.warattilChrome(size: 13))
                        .foregroundStyle(isGold ? fihrisGold : theme.accent.opacity(0.7))
                }
                .environment(\.layoutDirection, .rightToLeft)
                .padding(.vertical, 2)
                .contentShape(Rectangle())
                .onTapGesture { onNavigate(page) }
                .listRowBackground(isGold ? fihrisGoldBg : theme.background)
            }
        }
        .listStyle(.plain)
        .background(theme.background)
        .modifier(BottomFadeMask(theme: theme))
    }

    private var juzList: some View {
        List {
            ForEach(1...30, id: \.self) { n in
                let page = juzStartPages[n] ?? 1
                HStack {
                    Text("الجزء \(n.arabicDigits)")
                        .font(.warattilChrome(size: 15, weight: .medium))
                        .foregroundStyle(theme.text)
                    Spacer()
                    Text("ص \(page.arabicDigits)")
                        .font(.warattilChrome(size: 13))
                        .foregroundStyle(theme.accent.opacity(0.7))
                }
                .environment(\.layoutDirection, .rightToLeft)
                .padding(.vertical, 2)
                .contentShape(Rectangle())
                .onTapGesture { onNavigate(page) }
                .listRowBackground(theme.background)
            }
        }
        .listStyle(.plain)
        .background(theme.background)
        .modifier(BottomFadeMask(theme: theme))
    }

    /// Page index — 604 rows, one per Mushaf page. Each row shows the page
    /// number in primary type on the visual RIGHT (reading start in RTL)
    /// and the primary surah name on the visual LEFT as soft context. Tap
    /// a row to jump straight to that page.
    ///
    /// Design note
    /// -----------
    /// Nasser 2026-04-21 asked for فهرس الصفحات as a third Fihris tab so
    /// students can navigate by page reference (common in daily wird
    /// plans like "pages 45-52 today"). The list is long (604 entries)
    /// but SwiftUI's `List` already lazy-renders, so only the visible
    /// rows are materialised at any time.
    ///
    /// Layout mirrors the Juz tab: page identifier (right) · soft divider
    /// · surah name (left). Using `صفحة` rather than just the number
    /// gives the row a lexical anchor and matches the chrome convention
    /// used elsewhere ("ص N" is too terse when there are 604 of them
    /// scrolling past).
    private var pageList: some View {
        let pages = filteredPages
        return List {
            if pages.isEmpty {
                Text("لا توجد صفحة مطابقة")
                    .font(.warattilChrome(size: 14))
                    .foregroundStyle(theme.text.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
                    .listRowBackground(theme.background)
            }
            ForEach(pages, id: \.self) { p in
                let surah     = primarySurah(forPage: p)
                let surahName = MetadataParser.shared.getSuraName(surah)
                HStack {
                    // Right-anchored primary label: "صفحة N"
                    Text("صفحة \(p.arabicDigits)")
                        .font(.warattilChrome(size: 15, weight: .medium))
                        .foregroundStyle(theme.text)
                    Spacer()
                    // Left-anchored secondary label: the primary surah on
                    // that page. Rendered with the Quran font (not
                    // warattilChrome) because the surah name reads better
                    // in the Uthmani-compatible Naskh than in Amiri
                    // regular — same rule used on the Surah tab.
                    Text(surahName)
                        .font(font.font(size: 13))
                        .foregroundStyle(theme.accent.opacity(0.7))
                        .environment(\.layoutDirection, .rightToLeft)
                }
                .environment(\.layoutDirection, .rightToLeft)
                .padding(.vertical, 2)
                .contentShape(Rectangle())
                .onTapGesture { onNavigate(p) }
                .listRowBackground(theme.background)
            }
        }
        .listStyle(.plain)
        .background(theme.background)
        .modifier(BottomFadeMask(theme: theme))
    }

    // Pill tab — filled when selected, ringed when idle. Sized to
    // split the row 50/50 so the two tabs read as equal primary
    // actions. `.animation` on selection gives a gentle cross-fade
    // between states without pulling in a full transition.
    @ViewBuilder
    private func fihrisTabButton(title: String, tag: Int) -> some View {
        let isSelected = (tab == tag)
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { tab = tag }
        } label: {
            Text(title)
                .font(.warattilChrome(size: 15, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? theme.background : theme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? theme.accent : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(theme.accent.opacity(isSelected ? 0 : 0.45),
                                lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// =============================================================================
// MARK: - BookmarksSheet
// =============================================================================

struct BookmarksSheet: View {

    let bookmarks: [Bookmark]
    let theme:     ThemeColors
    let font:      QuranFontInfo
    let onNavigate: (Int) -> Void
    let onDelete:   (Int) -> Void
    let onClearAll: () -> Void
    let onDismiss:  () -> Void

    // Page number pending confirmation before deletion. Driven by the
    // trailing trash button on each row so a tap surfaces a confirm sheet
    // instead of destroying the bookmark silently.
    @State private var pendingDelete: Int? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if bookmarks.isEmpty {
                    emptyState
                } else {
                    bookmarkList
                }
            }
            .background(theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    WarattilSheetTitle(text: "إشاراتي", theme: theme)
                }
                ToolbarItem(placement: .cancellationAction) {
                    if !bookmarks.isEmpty {
                        Button("حذف الكل", role: .destructive) { onClearAll() }
                            .foregroundStyle(theme.progressLow)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("إغلاق") { onDismiss() }
                        .foregroundStyle(theme.accent)
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            Text("لا توجد إشارات مرجعية")
                .font(font.font(size: 16))
                .foregroundStyle(theme.text.opacity(0.4))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bookmarkList: some View {
        // NOTE: we use a bare HStack (with onTapGesture) instead of wrapping
        // the row in a SwiftUI Button. A Button inside a List row can swallow
        // the horizontal drag that `.swipeActions` relies on, so swipe-to-delete
        // silently stops working for the row while the toolbar's "حذف الكل"
        // (clear-all) continues to fire normally. Reported by Nasser 2026-04-20
        // — "bookmarks can be deleted all at once, not one by one".
        List {
            ForEach(bookmarks, id: \.pageNumber) { bm in
                HStack(spacing: 12) {
                    // Page-number chip — Amiri-Bold renders Eastern digits
                    // as classical Naskh, matching the rest of the chrome.
                    Text(bm.pageNumber.arabicDigits)
                        .font(.warattilChrome(size: 16, weight: .bold))
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

                    // Row body — tapping this area navigates. We scope the tap
                    // target here (not the whole row) so the trailing trash
                    // icon stays independently tappable.
                    HStack {
                        Spacer()
                        Text("صفحة \(bm.pageNumber.arabicDigits)")
                            .font(.warattilChrome(size: 15))
                            .foregroundStyle(theme.text)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { onNavigate(bm.pageNumber) }

                    // Visible per-row delete affordance. Swipe still works
                    // below (faster), but many users never discover swipe;
                    // this button makes per-bookmark delete obvious. Tap
                    // presents a confirmation so the action isn't destructive-
                    // by-accident. Reported by Nasser 2026-04-20 — "bookmarks
                    // can be deleted all at once, not one by one".
                    Button {
                        pendingDelete = bm.pageNumber
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(theme.progressLow.opacity(0.75))
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("حذف هذه الإشارة")
                }
                .padding(.vertical, 4)
                .listRowBackground(theme.background)
                // In an RTL environment SwiftUI flips the leading/trailing
                // edges automatically, so `edge: .trailing` still corresponds
                // to "the side the user swipes from" in both LTR & RTL. Using
                // `allowsFullSwipe: true` lets a quick flick delete without a
                // modal confirmation — matches the Android long-press flow.
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        onDelete(bm.pageNumber)
                    } label: {
                        Label("حذف", systemImage: "trash")
                    }
                }
            }
        }
        .confirmationDialog(
            "حذف هذه الإشارة؟",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("حذف", role: .destructive) {
                if let p = pendingDelete { onDelete(p) }
                pendingDelete = nil
            }
            Button("إلغاء", role: .cancel) { pendingDelete = nil }
        }
        .listStyle(.plain)
        .background(theme.background)
        .modifier(BottomFadeMask(theme: theme))
    }
}

// =============================================================================
// MARK: - SearchSheet
// =============================================================================

struct SearchSheet: View {

    @Binding var query: String
    let results:   [SearchResult]
    let isLoading: Bool
    let theme:     ThemeColors
    let font:      QuranFontInfo
    let onQueryChanged: (String) -> Void
    let onNavigate:     (Int) -> Void
    let onDismiss:      () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                // Result-count gold pill — parity with Android tasks #66 +
                // #72.  Sits below the field on its own line, large 28 pt
                // bold so the count reads from a glance ("how many hits did
                // my query find?") without scrolling the list.  Hidden when
                // the field is empty OR a search is in flight (the spinner
                // takes the visual slot during loading).
                if !isLoading,
                   !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    countPill
                }
                if isLoading {
                    ProgressView()
                        .tint(theme.accent)
                        .padding(.vertical, 6)
                }
                resultsList
            }
            .background(theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Principal title rendered through WarattilSheetTitle so it
                // picks up theme.accent instead of system `.label` (which
                // flips to near-white on a dark-mode device and vanishes
                // against cream). See WarattilSheetTitle comment block.
                ToolbarItem(placement: .principal) {
                    WarattilSheetTitle(
                        text: "البحث في القرآن الكريم",
                        theme: theme
                    )
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("إغلاق") { onDismiss() }
                        .foregroundStyle(theme.accent)
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var searchField: some View {
        TextField("ابحث عن كلمة أو آية...", text: $query)
            .font(font.font(size: 15))
            .warattilTextField(theme: theme)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .onChange(of: query) { _, newValue in
                onQueryChanged(newValue)
            }
            .environment(\.layoutDirection, .rightToLeft)
    }

    /// Result-count chip — verb-prefixed copy inside a faint gold pill.
    /// Renders in Amiri (warattilChrome) so the chip reads as "scholarly
    /// chrome" rather than the iOS system bold-Arabic look (Nasser
    /// 2026-05-03 — the prior `.system(size: 28, weight: .bold)` rendering
    /// of «٦ نتيجة» felt too marketing-loud against the calm Mushaf palette).
    /// Amiri's digits render cleanly without GSUB ayah-rosette substitution,
    /// so multi-digit counts like «٤٧» still display correctly.
    ///
    /// Copy follows classical Arabic count agreement (العدد والمعدود) plus
    /// a verb prefix that scales with cardinality:
    ///   • 0  → «لا توجد نتائج»     (rarely shown — empty-state handles it)
    ///   • 1  → «وردت مرة واحدة»     (singular, verb of occurrence)
    ///   • 2  → «تكررت مرتين»        (dual, verb of repetition)
    ///   • 3–10 → «تكررت N مرات»    (plural form: مرات)
    ///   • 11+ → «تكررت N مرة»      (singular tamyiiz returns past 10)
    ///
    /// 2026-05-03 — was «N نتيجة» without a verb. The verb-prefixed form
    /// reads more naturally («the word occurred 47 times») than the
    /// noun-only «47 results» which felt translation-ish.
    @ViewBuilder
    private var countPill: some View {
        let n = results.count
        let label: String = {
            switch n {
            case 0:        return "لا توجد نتائج"
            case 1:        return "وردت مرة واحدة"
            case 2:        return "تكررت مرتين"
            case 3...10:   return "تكررت \(n.arabicDigits) مرات"
            default:       return "تكررت \(n.arabicDigits) مرة"
            }
        }()
        HStack {
            Spacer(minLength: 0)
            Text(label)
                .font(.warattilChrome(size: 22, weight: .bold))
                .foregroundStyle(theme.accent)
                .lineLimit(1)
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(theme.accent.opacity(0.10))
                )
                .overlay(
                    Capsule().stroke(theme.accent.opacity(0.25), lineWidth: 1)
                )
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .environment(\.layoutDirection, .rightToLeft)
    }

    @ViewBuilder
    private var resultsList: some View {
        if results.isEmpty && !isLoading && !query.isEmpty {
            VStack {
                Spacer()
                Text("لم يُعثر على نتائج")
                    .font(font.font(size: 15))
                    .foregroundStyle(theme.text.opacity(0.45))
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            List {
                ForEach(results, id: \.self) { r in
                    // Bare row + tap gesture (same reasoning as BookmarksSheet
                    // — a Button wrapper around the whole row swallows gestures
                    // and muddles RTL layout inside the label). Reported by
                    // Nasser 2026-04-20: results were LTR and ayah-number
                    // brackets pointed outward ›N‹ instead of inward ‹N›.
                    VStack(alignment: .trailing, spacing: 4) {
                        // Row header: surah name + ayah number on the right
                        // (primary info), page number on the left (secondary).
                        // The outer NavigationStack already applies
                        // `.environment(\.layoutDirection, .rightToLeft)`, so an
                        // HStack inherits RTL ordering automatically — the
                        // first child lands on the right edge. We just have to
                        // stop re-flipping it.
                        HStack {
                            Text("\(r.surahName) ﴾\(r.ayahNumber.arabicDigits)﴿")
                                .font(font.font(size: 13).weight(.bold))
                                .foregroundStyle(theme.accent)
                            Spacer()
                            Text("ص \(r.pageNumber.arabicDigits)")
                                .font(.warattilChrome(size: 12))
                                .foregroundStyle(theme.accent.opacity(0.7))
                        }
                        // Ayah text preview — right-aligned because we're in
                        // an RTL environment where `.leading` ≡ right edge.
                        Text(String(r.text.prefix(110)))
                            .font(font.font(size: 14))
                            .foregroundStyle(theme.text)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture { onNavigate(r.pageNumber) }
                    .listRowBackground(theme.background)
                }
            }
            .listStyle(.plain)
            .background(theme.background)
        }
    }
}

// =============================================================================
// MARK: - WirdSheet  (was WirdDialog on Android)
// =============================================================================

struct WirdSheet: View {

    let currentPage:     Int
    let userPreferences: UserPreferences?
    let theme:           ThemeColors
    let font:            QuranFontInfo
    let onSet:           (ReadingTargetType, Int) -> Void
    let onReset:         () -> Void
    let onDismiss:       () -> Void

    @State private var selectedType: ReadingTargetType = .finishInDays
    @State private var valueText:    String            = "30"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("نوع الورد", selection: $selectedType) {
                        Text("بالأيام").tag(ReadingTargetType.finishInDays)
                        Text("بالصفحات").tag(ReadingTargetType.pagesPerDay)
                        Text("بالأجزاء").tag(ReadingTargetType.juzPerDay)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedType) { _, new in
                        valueText = defaultValue(for: new)
                    }

                    TextField(label(for: selectedType), text: $valueText)
                        .keyboardType(.numberPad)
                        // Themed text + caret so the field reads in
                        // WARATTIL charcoal/green rather than iOS system
                        // colours that flip with the device's dark-mode
                        // setting. The field itself stays a Form row (no
                        // `.warattilTextField` chrome — a cartouche-bordered
                        // capsule inside a grouped-table row looks wrong).
                        .foregroundStyle(theme.text)
                        .tint(theme.accent)
                        .environment(\.layoutDirection, .leftToRight)
                } header: {
                    Text("إعداد الورد اليومي")
                        .foregroundStyle(theme.accent)
                }

                if let prefs = userPreferences, prefs.wirdStartDate != nil {
                    Section {
                        Text(currentWirdLabel(prefs))
                            .font(.warattilChrome(size: 13))
                            .foregroundStyle(theme.text.opacity(0.6))
                    }
                }

                Section {
                    // 2026-04-27 (pt. 4): label flipped from destructive
                    // «إعادة ضبط (مسح الإشارات والورد)» to the positive
                    // devotional «ابدأ ختمة جديدة».  Same function on
                    // the VM side now (cancelWird, NOT resetProgress) —
                    // bookmarks + hifz progress are preserved; only wird
                    // state is cleared and reading position rewinds to
                    // page 1.  Color flipped from progressLow (red) to
                    // accent (gold) to match the positive framing.
                    Button {
                        onReset()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                            Text("ابدأ ختمة جديدة")
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(theme.accent)
                        .fontWeight(.medium)
                    }
                }
                .listRowBackground(theme.background.opacity(0.0))
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    WarattilSheetTitle(text: "الورد اليومي", theme: theme)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { onDismiss() }
                        .foregroundStyle(theme.text.opacity(0.6))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("ابدأ") {
                        let v = max(1, Int(valueText) ?? 1)
                        onSet(selectedType, v)
                    }
                    .foregroundStyle(theme.accent)
                    .fontWeight(.bold)
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func defaultValue(for type: ReadingTargetType) -> String {
        switch type {
        case .finishInDays: return "30"
        case .pagesPerDay:  return "20"
        case .juzPerDay:    return "1"
        }
    }

    private func label(for type: ReadingTargetType) -> String {
        switch type {
        case .finishInDays: return "عدد الأيام"
        case .pagesPerDay:  return "صفحات يومياً"
        case .juzPerDay:    return "أجزاء يومياً"
        }
    }

    private func currentWirdLabel(_ p: UserPreferences) -> String {
        let v = p.wirdTargetValue.arabicDigits
        switch p.wirdTargetType {
        case .finishInDays: return "الورد الحالي: ختم في \(v) يوم"
        case .pagesPerDay:  return "الورد الحالي: \(v) صفحة/يوم"
        case .juzPerDay:    return "الورد الحالي: \(v) جزء/يوم"
        }
    }
}

// =============================================================================
// MARK: - HifzLogSheet — full Android-parity stats + density heatmap
//
// Ported from app/src/main/java/com/warattil/app/ui/HifzLogSheet.kt (V3).
// The iOS Hifz surface matches the Android Phase-1 (ayah-atomic) design:
//
//   ┌──────────────────────────────────────────────┐
//   │  الإحصاء │ خريطة الحفظ                        │ ← two-tab switcher
//   │  ┌──────────────────────────────────────┐   │
//   │  │         ابدأ رحلة الحفظ               │   │ ← tier label
//   │  │         ١٢ / ٦٢٣٦ آية                 │   │ ← ayah counter (atom)
//   │  │  ██▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒      │   │ ← ayah-ratio progress
//   │  │   ١٢    ١    ١    ٠                   │   │
//   │  │   آية  صفحة سورة جزء                  │   │ ← 4-way stat chips
//   │  └──────────────────────────────────────┘   │
//   │  ┌──────────────────────────────────────┐   │
//   │  │ +  تسجيل ما تحفظه سابقاً             │   │ ← bulk-entry launcher
//   │  └──────────────────────────────────────┘   │
//   │                الأجزاء                         │
//   │  ┌──────────────────────────────────────┐   │
//   │  │ ████ ٢٣٪   الجزء الأول — الفاتحة    │   │ ← fractional juz rows
//   │  └──────────────────────────────────────┘   │
//   └──────────────────────────────────────────────┘
//
// Storage primitive is now the ayah — Phase-1's atomic unit — so every
// counter and ratio is derived through MetadataParser from the single
// ayah-key set.  Partially memorized pages and juz show fractional progress
// instead of the binary green/gold of the old page-atomic build.
//
// Heatmap tab renders a density grid (6-shade Saharan yellow → Mushaf
// Green gradient) with juz-completion flowers overlaid on the last page of
// every fully-memorized juz.  A share button rasterises the garden via
// SwiftUI's ImageRenderer and hands the UIImage to ShareUtil.shareHifzGarden.
//
// Tier formula + juz labels — byte-identical with Android
// (WarattilConstants.Hifz.hifzTierLabel / hifzTier).
// =============================================================================

struct HifzLogSheet: View {

    // ── Inputs ───────────────────────────────────────────────────────────────
    // Phase-1 ayah-atomic storage: the authoritative state is `memorizedAyahs`
    // (keyed by Hifz.ayahKey).  Page / surah / juz totals are all derived via
    // MetadataParser — this view does NOT touch UserDefaults or the DB.
    let memorizedAyahs:  Set<Int64>
    let surahStartPages: [Int: Int]
    let juzStartPages:   [Int: Int]
    let theme:           ThemeColors
    let font:            QuranFontInfo
    let onNavigate:      (Int) -> Void
    /// Fires when the reader taps the "تسجيل ما تحفظه سابقاً" launcher.
    /// MushaFScreen closes this sheet and presents HifzBulkPickerSheet.
    let onBulkEntry:     () -> Void
    let onDismiss:       () -> Void
    /// Starting tab (0 = الإحصاء, 1 = خريطة الحفظ).  After a bulk-apply,
    /// MushaFScreen re-opens the sheet with initialTab = 1 so the reader
    /// sees the effect of their تثبيت on the garden immediately instead of
    /// having to flip tabs manually.  Matches Android's `initialTab` param.
    var initialTab:      Int = 0

    // 0 = stats, 1 = heatmap. `@State` seeded once from `initialTab`.
    @State private var hifzTab: Int

    init(
        memorizedAyahs:  Set<Int64>,
        surahStartPages: [Int: Int],
        juzStartPages:   [Int: Int],
        theme:           ThemeColors,
        font:            QuranFontInfo,
        onNavigate:      @escaping (Int) -> Void,
        onBulkEntry:     @escaping () -> Void,
        onDismiss:       @escaping () -> Void,
        initialTab:      Int = 0
    ) {
        self.memorizedAyahs  = memorizedAyahs
        self.surahStartPages = surahStartPages
        self.juzStartPages   = juzStartPages
        self.theme           = theme
        self.font            = font
        self.onNavigate      = onNavigate
        self.onBulkEntry     = onBulkEntry
        self.onDismiss       = onDismiss
        self.initialTab      = initialTab
        _hifzTab = State(initialValue: max(0, min(1, initialTab)))
    }

    // ── Derived sets (all recomputed when `memorizedAyahs` changes) ──────────
    //
    // Android uses `remember(memorizedAyahs)` to cache these across
    // recompositions; SwiftUI diffs the whole `body` on each state change, so
    // computed properties are re-run automatically.  604 cheap enumerations
    // per recomputation is comfortably under the frame budget — the full pass
    // measured < 2 ms on an iPhone 11 in development.
    //
    // Note: we rely on MetadataParser.shared having been bootstrapped at app
    // launch.  Every call into `getPageAyahKeys(_:)` / `getJuzAyahKeys(_:)`
    // returns `[]` cheaply if the parser hasn't loaded yet, so partial-state
    // renders during a cold app spin-up still paint without crashing.

    /// Per-page density ratio (0…1).  Indexed by 1-based page number.
    /// Pages whose metadata isn't loaded yet fall through to 0 (EMPTY shade).
    private var pageDensities: [Double] {
        var arr = [Double](repeating: 0.0, count: WarattilConstants.Mushaf.totalPages + 1)
        for p in 1...WarattilConstants.Mushaf.totalPages {
            let keys = MetadataParser.shared.getPageAyahKeys(p)
            if keys.isEmpty { continue }
            let have = keys.reduce(0) { memorizedAyahs.contains($1) ? $0 + 1 : $0 }
            arr[p] = Double(have) / Double(keys.count)
        }
        return arr
    }

    private var fullyMemorizedPageCount: Int {
        let densities = pageDensities
        return (1...WarattilConstants.Mushaf.totalPages)
            .reduce(0) { densities[$1] >= 1.0 ? $0 + 1 : $0 }
    }

    /// Fully-memorized surahs — *every* ayah of the surah is in the user's
    /// set.  Used only by the stat-chip count; we no longer render a surah
    /// list because the per-juz rows subsume that signal.
    private var memorizedSurahSet: Set<Int> {
        var out = Set<Int>()
        for s in 1...WarattilConstants.Mushaf.totalSuwar {
            let keys = MetadataParser.shared.getSurahAyahKeys(s)
            guard !keys.isEmpty else { continue }
            if keys.allSatisfy({ memorizedAyahs.contains($0) }) { out.insert(s) }
        }
        return out
    }

    private var memorizedJuzList: [Int] {
        var out = [Int]()
        for j in 1...WarattilConstants.Mushaf.totalJuzaa {
            let keys = MetadataParser.shared.getJuzAyahKeys(j)
            guard !keys.isEmpty else { continue }
            if keys.allSatisfy({ memorizedAyahs.contains($0) }) { out.append(j) }
        }
        return out
    }

    /// Pages where a juz-completion flower should overlay — one per
    /// fully-memorized juz, placed on the juz's *last* page (per
    /// MetadataParser.getJuzLastPage).  A complete Mushaf → exactly 30
    /// flowers; mis-aligned memorization earns zero flowers by design.
    private var flowerPages: Set<Int> {
        Set(memorizedJuzList
            .map { MetadataParser.shared.getJuzLastPage($0) }
            .filter { $0 > 0 })
    }

    private var tierLabel: String {
        WarattilConstants.Hifz.hifzTierLabel(
            tier: WarattilConstants.Hifz.hifzTier(juzCount: memorizedJuzList.count)
        )
    }

    private func juzLabel(_ juzNum: Int) -> String {
        switch juzNum {
        case 1:  return "الجزء الأول — الفاتحة"
        case 27: return "جزء قَالَ فَمَا خَطْبُكُم"
        case 28: return "جزء قد سمع"
        case 29: return "جزء تبارك"
        case 30: return "جزء عمّ"
        default: return "الجزء \(juzNum.arabicDigits)"
        }
    }

    // ── Body ─────────────────────────────────────────────────────────────────

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab switcher — same pill style as FihrisSheet.
                HStack(spacing: 10) {
                    hifzTabButton(title: "الإحصاء",    tag: 0)
                    hifzTabButton(title: "خريطة الحفظ", tag: 1)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 6)

                if hifzTab == 0 {
                    statsView
                } else {
                    heatmapView
                }
            }
            .background(theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    WarattilSheetTitle(text: "لوحة الحفظ", theme: theme)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("إغلاق") { onDismiss() }
                        .foregroundStyle(theme.accent)
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    // ── Stats tab — achievement card + bulk-entry row + per-juz breakdown ────
    //
    // Mirrors HifzStatsTab in HifzLogSheet.kt.  The Android version uses a
    // LazyColumn of 520.dp fixed height; SwiftUI resolves height through the
    // sheet presenter, so a plain ScrollView gives the same behaviour without
    // hard-coding a frame.

    private var statsView: some View {
        ScrollView {
            VStack(spacing: 12) {

                // 1) Achievement card — tier + 4-way stats + progress bar.
                achievementCard

                // 2) Bulk-entry launcher row.
                bulkEntryRow

                // 3) Section heading.
                HStack {
                    Text("الأجزاء")
                        .font(.warattilChrome(size: 14, weight: .semibold))
                        .foregroundStyle(theme.text)
                    Spacer()
                }
                .padding(.horizontal, 4)
                .padding(.top, 4)

                // 4) Per-juz rows — fractional progress, not binary.
                ForEach(1...WarattilConstants.Mushaf.totalJuzaa, id: \.self) { juzNum in
                    juzRow(juzNum: juzNum)
                }
            }
            .padding(16)
        }
        .background(theme.background)
    }

    // Achievement badge — tier headline, 4-way stat chips, ayah progress bar.
    // Primary counter is ayahs (Phase-1 atomic unit), not pages.
    private var achievementCard: some View {
        let totalAyahs = memorizedAyahs.count
        let totalAyahTarget = WarattilConstants.Mushaf.totalAyahs
        let ayahRatio = Double(totalAyahs) / Double(totalAyahTarget)

        return VStack(spacing: 10) {
            Text(tierLabel)
                .font(font.font(size: 20).weight(.bold))
                .foregroundStyle(fihrisGold)
                .multilineTextAlignment(.center)

            // Ayah counter — Amiri chrome so the Eastern digits read in the
            // same Naskh face as surrounding copy.
            Text("\(totalAyahs.arabicDigits) / \(totalAyahTarget.arabicDigits) آية")
                .font(.warattilChrome(size: 14))
                .foregroundStyle(theme.text)

            // Progress bar — gold, LTR-fill (page-1 edge rightward).
            GeometryReader { geo in
                let clamped = max(0.0, min(1.0, ayahRatio))
                let fillW   = geo.size.width * CGFloat(clamped)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(theme.text.opacity(0.08))
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(fihrisGold)
                        .frame(width: fillW)
                        .animation(.easeInOut(duration: 0.25), value: clamped)
                }
            }
            .frame(height: 10)
            .environment(\.layoutDirection, .leftToRight)

            // Four stat chips — visual order (inside the RTL ancestor so
            // first child sits on the visual right): آية · صفحة · سورة · جزء.
            HStack {
                statChip(value: totalAyahs.arabicDigits,              label: "آية")
                Spacer(minLength: 0)
                statChip(value: fullyMemorizedPageCount.arabicDigits, label: "صفحة")
                Spacer(minLength: 0)
                statChip(value: memorizedSurahSet.count.arabicDigits, label: "سورة")
                Spacer(minLength: 0)
                statChip(value: memorizedJuzList.count.arabicDigits,  label: "جزء")
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(fihrisGold.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(fihrisGold.opacity(0.35), lineWidth: 1)
        )
    }

    /// Bulk-entry launcher row — for readers restoring prior memorization
    /// across whole juz / surah / page ranges.  Tapping fires `onBulkEntry`
    /// so the parent can close this sheet and present HifzBulkPickerSheet.
    private var bulkEntryRow: some View {
        Button(action: onBulkEntry) {
            HStack(alignment: .center, spacing: 10) {
                // Leading "+" glyph — on the visual RIGHT inside the RTL
                // ancestor (same side as Android's trailing Icon).
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(fihrisGold)

                VStack(alignment: .leading, spacing: 2) {
                    Text("تسجيل ما تحفظه سابقاً")
                        .font(.warattilChrome(size: 15, weight: .semibold))
                        .foregroundStyle(fihrisGold)
                    Text("جزء · سورة · نطاق صفحات")
                        .font(.warattilChrome(size: 12))
                        .foregroundStyle(theme.text.opacity(0.6))
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(fihrisGold.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(fihrisGold.opacity(0.35), lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("تسجيل ما تحفظه سابقاً")
    }

    // Stat chip — big bold digit over a small caption.
    @ViewBuilder
    private func statChip(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.warattilChrome(size: 18, weight: .bold))
                .foregroundStyle(fihrisGold)
            Text(label)
                .font(.warattilChrome(size: 11))
                .foregroundStyle(theme.text.opacity(0.6))
        }
    }

    // Per-juz row — fractional progress bar + percent readout + gold star
    // when complete.  Tapping navigates to the juz's first page.
    @ViewBuilder
    private func juzRow(juzNum: Int) -> some View {
        let startPage = juzStartPages[juzNum] ?? 1
        let juzKeys   = MetadataParser.shared.getJuzAyahKeys(juzNum)
        let haveCount = juzKeys.reduce(0) { memorizedAyahs.contains($1) ? $0 + 1 : $0 }
        let juzRatio  = juzKeys.isEmpty ? 0.0 : Double(haveCount) / Double(juzKeys.count)
        let isDone    = juzRatio >= 1.0
        let percent   = Int((juzRatio * 100.0).rounded(.down))

        Button {
            onNavigate(startPage)
        } label: {
            HStack(alignment: .center, spacing: 8) {
                // Mini progress bar (pinned LTR) + percent readout.
                HStack(spacing: 6) {
                    GeometryReader { geo in
                        let clamped = max(0.0, min(1.0, juzRatio))
                        let fillW   = geo.size.width * CGFloat(clamped)
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(theme.text.opacity(0.08))
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(isDone ? fihrisGold : theme.accent.opacity(0.6))
                                .frame(width: fillW)
                        }
                    }
                    .frame(width: 64, height: 6)

                    if !isDone && juzRatio > 0.0 {
                        Text("\(percent.arabicDigits)٪")
                            .font(.warattilChrome(size: 11))
                            .foregroundStyle(theme.text.opacity(0.55))
                    }
                }
                .environment(\.layoutDirection, .leftToRight)

                Spacer(minLength: 0)

                // Label + seal star.
                HStack(spacing: 6) {
                    Text(juzLabel(juzNum))
                        .font(font.font(size: 14)
                                .weight(isDone ? .bold : .regular))
                        .foregroundStyle(isDone ? fihrisGold : theme.text)
                        .lineLimit(1)
                    if isDone {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(fihrisGold)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isDone ? fihrisGold.opacity(0.10) : theme.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isDone ? fihrisGold.opacity(0.6) : theme.divider,
                        lineWidth: isDone ? 1 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(juzLabel(juzNum))\(isDone ? "، محفوظ" : "")")
    }

    // ── Heatmap tab — 604-cell density grid with juz-completion flowers ──
    //
    // Ported from HifzHeatmapTab in HifzLogSheet.kt.  Two layered signals:
    //
    //   1) Ground colour — Hifz.densityShade(pageDensity) maps the per-page
    //      memorization ratio to one of six shades, cooling from Saharan
    //      yellow (empty) through olive to full Mushaf Green.  Untouched
    //      pages read as desert; the garden greens from the inside out as
    //      memorization progresses.
    //
    //   2) Flower overlay — a small 5-petal gold bloom drawn on the last
    //      page of every fully-memorized juz.  A complete Mushaf earns
    //      exactly 30 flowers.  Partial / mis-aligned memorization — even
    //      hundreds of pages — earns zero flowers by design: flowers
    //      signal *juz completion*, not page count.
    //
    // Fit-to-screen:
    //   No ScrollView wraps the grid.  The grid self-sizes 20 columns ×
    //   31 rows to fit the sheet's available width/height, matching the
    //   Android behaviour after issue #18.
    //
    // Share:
    //   The capture region (grid + legend + attribution strip) is wrapped
    //   in an `ImageRenderer`-friendly container; tapping "شارك خريطة الحفظ"
    //   rasterises it and hands the UIImage to ShareUtil.shareHifzGarden.
    private var heatmapView: some View {
        // Compute once so the legend chip-count and the ImageRenderer pass
        // see the same data.
        let densities = pageDensities
        let flowers   = flowerPages
        let fullyMem  = (1...WarattilConstants.Mushaf.totalPages)
            .reduce(0) { densities[$1] >= 1.0 ? $0 + 1 : $0 }

        // ScrollView so the tier-ladder + legend + full 20×31 grid +
        // stat-chips can all render at natural size — the grid's GeometryReader
        // reads the scroll-view's constrained width (correct) and the
        // aspectRatio modifier sizes it to 20:31 (correct).  Without the
        // ScrollView the sheet compressed the grid to whatever vertical
        // space remained after the surrounding content, making it too small.
        return ScrollView {
            VStack(spacing: 10) {

                // The captured region — everything drawn here ends up in the
                // shared PNG.  On-screen render uses the LIVE theme so the
                // heatmap honours the user's chosen mode (cream/dark/sepia);
                // the off-screen ImageRenderer pass passes shareTheme =
                // WarattilTheme.heritage so the SHARED PNG is always
                // celebratory cream regardless of the user's mode.  Same
                // Heritage-lock pattern V3 Android uses.
                capturableGarden(
                    densities:  densities,
                    flowers:    flowers,
                    fullyMem:   fullyMem,
                    shareTheme: theme            // on-screen — live theme
                )
                .id("hifzGarden")

                // Share button — outside the captured region so it isn't
                // baked into the exported image.
                shareGardenButton(
                    densities: densities,
                    flowers:   flowers,
                    fullyMem:  fullyMem
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(theme.background)
    }

    /// The rasterisable garden.  Split out so both the on-screen view and
    /// the off-screen ImageRenderer snapshot instantiate identical trees.
    /// `shareTheme` is the palette used for the BAKED background and text
    /// — the on-screen call passes the live theme so the heatmap honours
    /// the user's mode; the off-screen ImageRenderer pass passes
    /// WarattilTheme.heritage so the shared PNG is always celebratory
    /// cream regardless of mode.  Same Heritage-lock pattern V3 Android
    /// uses on HifzLogSheet.
    @ViewBuilder
    private func capturableGarden(
        densities:  [Double],
        flowers:    Set<Int>,
        fullyMem:   Int,
        shareTheme: ThemeColors
    ) -> some View {
        // Tier-ladder + stat-chip metrics — same numbers the الإحصاء tab
        // shows, computed once so the captured PNG and the on-screen
        // garden agree to the digit.
        let totalAyahsCount    = memorizedAyahs.count
        let memorizedJuzCount  = memorizedJuzList.count
        let memorizedSurahNum  = memorizedSurahSet.count
        let currentTier        = WarattilConstants.Hifz.hifzTier(juzCount: memorizedJuzCount)

        VStack(spacing: 6) {
            // ── 7-tier ladder card — "هذه رحلتي مع كتاب الله" ───────────
            //   Receiver of the shared PNG sees the FULL Hifz progression
            //   (7 rungs) with the current rung highlighted, not just the
            //   sender's snapshot.  Same TierLadder shape V3 Android ships.
            VStack(spacing: 8) {
                Text("هذه رحلتي مع كتاب الله")
                    .font(.warattilChrome(size: 12))
                    .foregroundStyle(shareTheme.text.opacity(0.65))
                    .frame(maxWidth: .infinity, alignment: .center)
                tierLadder(currentTier: currentTier, shareTheme: shareTheme)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(WarattilConstants.Hifz.hifzGold.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(WarattilConstants.Hifz.hifzGold.opacity(0.35), lineWidth: 0.75)
            )
            .padding(.bottom, 4)

            // Legend row 1 — gradient swatch ramp flanked by Arabic labels.
            HStack(spacing: 0) {
                Text("بإذن الله")
                    .font(.warattilChrome(size: 11))
                    .foregroundStyle(shareTheme.text.opacity(0.7))
                Spacer(minLength: 0).frame(maxWidth: 8)
                legendSwatch(WarattilConstants.Hifz.heatmapEmpty)
                legendSwatch(WarattilConstants.Hifz.heatmapShade1)
                legendSwatch(WarattilConstants.Hifz.heatmapShade2)
                legendSwatch(WarattilConstants.Hifz.heatmapShade3)
                legendSwatch(WarattilConstants.Hifz.heatmapShade4)
                legendSwatch(WarattilConstants.Hifz.heatmapFull)
                Spacer(minLength: 0).frame(maxWidth: 8)
                Text("محفوظ")
                    .font(.warattilChrome(size: 11))
                    .foregroundStyle(shareTheme.text.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .environment(\.layoutDirection, .leftToRight)

            // Legend row 2 — flower swatch = juz completion.
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                ZStack {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(WarattilConstants.Hifz.heatmapFull)
                        .frame(width: 14, height: 14)
                    HifzFlowerGlyph(
                        petal:  WarattilConstants.Hifz.flowerPetal,
                        center: WarattilConstants.Hifz.flowerCenter
                    )
                    .frame(width: 14, height: 14)
                }
                Text("جزء مكتمل")
                    .font(.warattilChrome(size: 11))
                    .foregroundStyle(shareTheme.text.opacity(0.7))
                Spacer(minLength: 0)
            }

            // The 20×31 grid — fit-to-width, each cell a 1:1 square via
            // aspectRatio so the block stays readable at any width.  Pinned
            // LTR because a left-to-right page-order grid is easier to
            // glance at than one that starts top-right.
            GeometryReader { geo in
                let cols       = 20
                let spacing: CGFloat = 2
                let available  = geo.size.width
                let cellSize   = max(
                    1,
                    (available - CGFloat(cols - 1) * spacing) / CGFloat(cols)
                )
                VStack(spacing: spacing) {
                    let rows = (WarattilConstants.Mushaf.totalPages + cols - 1) / cols
                    ForEach(0..<rows, id: \.self) { row in
                        HStack(spacing: spacing) {
                            ForEach(0..<cols, id: \.self) { col in
                                let page = row * cols + col + 1
                                if page <= WarattilConstants.Mushaf.totalPages {
                                    heatmapCell(
                                        page:      page,
                                        cellSize:  cellSize,
                                        density:   densities[page],
                                        hasFlower: flowers.contains(page)
                                    )
                                } else {
                                    Color.clear
                                        .frame(width: cellSize, height: cellSize)
                                }
                            }
                        }
                    }
                }
                .frame(width: available, alignment: .topLeading)
            }
            .aspectRatio(
                // 20 : 31 cell grid — height scales from width.
                CGFloat(20) / CGFloat((WarattilConstants.Mushaf.totalPages + 19) / 20),
                contentMode: .fit
            )
            .environment(\.layoutDirection, .leftToRight)

            // ── 4-way summary (آية · صفحة · سورة · جزء) ──────────────
            //   Same StatChip arrangement the الإحصاء tab uses, so the
            //   in-app stats and the shared PNG read identically.
            //   Sits inside the captured region so the receiver sees
            //   the four numbers at a glance without parsing the grid.
            HStack {
                gardenStatChip(value: totalAyahsCount.arabicDigits,    label: "آية",   shareTheme: shareTheme)
                Spacer(minLength: 0)
                gardenStatChip(value: fullyMem.arabicDigits,           label: "صفحة",  shareTheme: shareTheme)
                Spacer(minLength: 0)
                gardenStatChip(value: memorizedSurahNum.arabicDigits,  label: "سورة",  shareTheme: shareTheme)
                Spacer(minLength: 0)
                gardenStatChip(value: memorizedJuzCount.arabicDigits,  label: "جزء",   shareTheme: shareTheme)
            }
            .padding(.horizontal, 4)
            .padding(.top, 10)

            // Footer: page count · flower count (when any).
            HStack(spacing: 0) {
                Text("\(fullyMem.arabicDigits) / \(WarattilConstants.Mushaf.totalPages.arabicDigits) صفحة محفوظة")
                    .font(.warattilChrome(size: 11))
                    .foregroundStyle(shareTheme.text.opacity(0.5))
                if !flowers.isEmpty {
                    Text("  ·  ")
                        .font(.warattilChrome(size: 11))
                        .foregroundStyle(shareTheme.text.opacity(0.35))
                    Text("\(flowers.count.arabicDigits) / \(WarattilConstants.Mushaf.totalJuzaa.arabicDigits) جزء مكتمل")
                        .font(.warattilChrome(size: 11))
                        .foregroundStyle(WarattilConstants.Hifz.flowerCenter)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 6)

            // Attribution strip — inside the capture so the shared PNG is
            // self-branded.  Small + subtle for on-screen readers, clear
            // enough for the receiving contact to find the app.
            HStack(spacing: 0) {
                Text("ورتّل")
                    .font(.warattilChrome(size: 12, weight: .bold))
                    .foregroundStyle(fihrisGold)
                Text("  ·  warattil.org/get")
                    .font(.system(size: 10))
                    .foregroundStyle(shareTheme.text.opacity(0.45))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
        }
        .padding(8)
        .background(shareTheme.background)
    }

    // =========================================================================
    // MARK: TierLadder — 7-rung Hifz progression
    //
    // Mirrors V3 Android's TierLadder/TierLadderRow exactly.  Each row shows
    // a marker dot, the juz-count range (Western digits — Eastern via
    // .warattilChrome doesn't pluralise multi-digit ranges cleanly), and
    // the tier name.
    //
    //   • Achieved tiers (below current):  filled green dot + medium name
    //   • Current tier:                    gold-filled dot + bold gold name
    //   • Future tiers (above current):    outline-only dot + faint name
    // =========================================================================

    private struct HifzTierRow {
        let tier:  Int
        let range: String   // Western-Arabic digits — handles multi-digit ranges cleanly
        let name:  String
    }

    private static let hifzLadder: [HifzTierRow] = [
        HifzTierRow(tier: 0, range: "٠",       name: "ابدأ رحلة الحفظ"),
        HifzTierRow(tier: 1, range: "١–٢",     name: "براعم الحفظ"),
        HifzTierRow(tier: 2, range: "٣–٦",     name: "نبتة الحفظ"),
        HifzTierRow(tier: 3, range: "٧–١٤",    name: "حافظ"),
        HifzTierRow(tier: 4, range: "١٥–٢٤",   name: "حافظ متقدم"),
        HifzTierRow(tier: 5, range: "٢٥–٢٩",   name: "شارفت على الختم"),
        HifzTierRow(tier: 6, range: "٣٠",      name: "حافظ للقرآن الكريم"),
    ]

    @ViewBuilder
    private func tierLadder(currentTier: Int, shareTheme: ThemeColors) -> some View {
        VStack(spacing: 6) {
            ForEach(Self.hifzLadder, id: \.tier) { row in
                tierLadderRow(
                    row:        row,
                    achieved:   row.tier <  currentTier,
                    current:    row.tier == currentTier,
                    shareTheme: shareTheme
                )
            }
        }
    }

    @ViewBuilder
    private func tierLadderRow(
        row:        HifzTierRow,
        achieved:   Bool,
        current:    Bool,
        shareTheme: ThemeColors
    ) -> some View {
        HStack(spacing: 10) {
            // Marker dot (12 pt circle).  Three visual states keyed off
            // (current, achieved) — see file header comment.
            let markerFill: Color = {
                if current  { return WarattilConstants.Hifz.hifzGold }
                if achieved { return WarattilConstants.Hifz.heatmapFull }
                return Color.clear
            }()
            let markerBorder: Color = {
                if current  { return WarattilConstants.Hifz.hifzGold }
                if achieved { return WarattilConstants.Hifz.heatmapFull }
                return shareTheme.text.opacity(0.30)
            }()
            ZStack {
                Circle().fill(markerFill)
                Circle().strokeBorder(markerBorder, lineWidth: 1)
            }
            .frame(width: 12, height: 12)

            // Range label — Western-Arabic digits in a system font so
            // multi-digit ranges (e.g. "١٥–٢٤") render cleanly without
            // the Uthmanic font's ayah-badge GSUB substitution.
            Text(row.range)
                .font(.system(
                    size:   current ? 13 : 12,
                    weight: current ? .bold : .medium
                ))
                .foregroundStyle(
                    current  ? WarattilConstants.Hifz.hifzGold
                  : achieved ? shareTheme.text.opacity(0.65)
                             : shareTheme.text.opacity(0.45)
                )
                .frame(minWidth: 44, alignment: .leading)

            // Tier name — Quran chrome font for visual continuity with
            // the body of the sheet.
            Text(row.name)
                .font(.warattilChrome(
                    size:   current ? 14 : 13,
                    weight: current  ? .bold
                          : achieved ? .medium
                                     : .regular
                ))
                .foregroundStyle(
                    current  ? WarattilConstants.Hifz.hifzGold
                  : achieved ? shareTheme.text.opacity(0.85)
                             : shareTheme.text.opacity(0.45)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Heritage-aware stat chip used inside the captured garden.  Distinct
    /// from the file's existing `statChip(value:label:)` (which uses live
    /// `theme.text` directly) so the captured PNG always reads against
    /// the Heritage palette regardless of the user's active mode.
    @ViewBuilder
    private func gardenStatChip(
        value: String,
        label: String,
        shareTheme: ThemeColors
    ) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.warattilChrome(size: 18, weight: .bold))
                .foregroundStyle(WarattilConstants.Hifz.hifzGold)
            Text(label)
                .font(.warattilChrome(size: 11))
                .foregroundStyle(shareTheme.text.opacity(0.6))
        }
    }

    /// Single heatmap cell — coloured background + optional flower overlay.
    /// Tapping jumps to the page.  Stroke in the heatmapFull tint when full
    /// so the transition to flower-bearing cells reads cleanly.
    @ViewBuilder
    private func heatmapCell(
        page:      Int,
        cellSize:  CGFloat,
        density:   Double,
        hasFlower: Bool
    ) -> some View {
        Button {
            onNavigate(page)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(WarattilConstants.Hifz.densityShade(density))
                    .frame(width: cellSize, height: cellSize)
                if hasFlower {
                    HifzFlowerGlyph(
                        petal:  WarattilConstants.Hifz.flowerPetal,
                        center: WarattilConstants.Hifz.flowerCenter
                    )
                    .frame(width: cellSize, height: cellSize)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("صفحة \(page.arabicDigits)\(density >= 1.0 ? "، محفوظة" : "")")
    }

    /// Small legend swatch used inside the gradient ramp row.
    @ViewBuilder
    private func legendSwatch(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color)
            .frame(width: 10, height: 10)
            .padding(.horizontal, 1)
    }

    /// Primary "share the garden" button — renders the capture region into a
    /// UIImage via SwiftUI's ImageRenderer and hands it to ShareUtil.  Pinned
    /// directly beneath the heatmap so the reader never has to hunt for a
    /// share affordance — one glance at the grid, one tap to send it.
    ///
    /// (2026-04-23) Upgraded from an outlined pill to a filled, full-width
    /// gold button at Nasser's request: the earlier outline was too easy to
    /// miss against the cream sheet background, and readers were exiting the
    /// sheet thinking the share facility didn't exist.
    @ViewBuilder
    private func shareGardenButton(
        densities: [Double],
        flowers:   Set<Int>,
        fullyMem:  Int
    ) -> some View {
        Button {
            // Off-screen ImageRenderer pass — sized to a screenshot-friendly
            // width so receiving apps show a legible garden (narrower widths
            // produce tiny cells that pixel-crush the flowers).
            //
            // shareTheme: WarattilTheme.heritage pins the captured PNG to
            // cream + charcoal regardless of the user's current theme — so
            // a reader who shares from dark mode still sends a celebratory
            // cream card, not an obsidian one.  Same Heritage-lock pattern
            // V3 Android uses on HifzLogSheet.
            let snapshotView = capturableGarden(
                densities:  densities,
                flowers:    flowers,
                fullyMem:   fullyMem,
                shareTheme: WarattilTheme.heritage
            )
            .frame(width: 720)
            .environment(\.layoutDirection, .rightToLeft)

            let renderer = ImageRenderer(content: snapshotView)
            renderer.scale = 2.0      // 2× for crisp cell borders on retina
            if let uiImage = renderer.uiImage {
                ShareUtil.shareHifzGarden(image: uiImage)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                Text("مشاركة الخريطة")
                    .font(.warattilChrome(size: 15, weight: .semibold))
            }
            .foregroundStyle(theme.background)      // cream on gold
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(fihrisGold)
            )
            .shadow(color: fihrisGold.opacity(0.25), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("مشاركة خريطة الحفظ")
    }

    // Tab pill — matches FihrisSheet.fihrisTabButton visually, tinted gold.
    @ViewBuilder
    private func hifzTabButton(title: String, tag: Int) -> some View {
        let isSelected = (hifzTab == tag)
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { hifzTab = tag }
        } label: {
            Text(title)
                .font(.warattilChrome(size: 15, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? theme.background : fihrisGold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? fihrisGold : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(fihrisGold.opacity(isSelected ? 0 : 0.45),
                                lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// =============================================================================
// MARK: - HifzFlowerGlyph — 5-petal bloom, Canvas-drawn
//
// Swift port of Android's `FlowerGlyph` (HifzLogSheet.kt, ~line 762).  Same
// geometry constants (petalDist=0.26, petalR=0.24, centerR=0.14 of minSide)
// so the iOS and Android celebrations/heatmaps render visually identical
// blooms.  Duplicated (not shared) with HifzCelebrationDialog.CelebrationFlower
// because the dialog flower takes `theme.background`-aware inset framing
// that doesn't port cleanly to a 14 pt heatmap cell.  Geometry is one-line
// and pure — keeping two copies costs nothing and spares a cross-file
// import that would otherwise have to leak CelebrationFlower out of its
// file-private scope.
// =============================================================================

private struct HifzFlowerGlyph: View {
    let petal:  Color
    let center: Color

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width  / 2
            let cy = size.height / 2
            let minSide   = min(size.width, size.height)
            let petalDist = minSide * 0.26
            let petalR    = minSide * 0.24
            let centerR   = minSide * 0.14
            for i in 0..<5 {
                let a  = -Double.pi / 2.0 + Double(i) * 2.0 * Double.pi / 5.0
                let px = cx + petalDist * CGFloat(cos(a))
                let py = cy + petalDist * CGFloat(sin(a))
                let rect = CGRect(
                    x: px - petalR, y: py - petalR,
                    width: petalR * 2, height: petalR * 2
                )
                ctx.fill(Path(ellipseIn: rect), with: .color(petal))
            }
            let centerRect = CGRect(
                x: cx - centerR, y: cy - centerR,
                width: centerR * 2, height: centerR * 2
            )
            ctx.fill(Path(ellipseIn: centerRect), with: .color(center))
        }
    }
}

// =============================================================================
// MARK: - UsageGuideSheet — «دليل الاستخدام»
// =============================================================================

struct UsageGuideSheet: View {

    let theme:     ThemeColors
    let font:      QuranFontInfo
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {

                    sectionHeading("دليل الاستخدام")
                    goldHairline
                    Text("إليك دليلاً سريعًا لأهم أدوات التطبيق وكيف تصل إليها من الشريط العلوي.")
                        .font(.warattilChrome(size: 13))
                        .foregroundStyle(theme.text.opacity(0.75))
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .environment(\.layoutDirection, .rightToLeft)
                    Spacer(minLength: 6)

                    // Icon picks mirror the Android Material set entry-for-entry
                    // (see UsageGuideSheet.kt):
                    //   Menu           → line.3.horizontal    (hamburger — same as header button)
                    //   Bookmarks      → bookmark.fill        (filled stack glyph)
                    //   Today          → calendar             (closest non-badge SF equivalent)
                    //   TrendingUp     → chart.line.uptrend.xyaxis
                    //   ic_lawh_hifz   → LawhHifzIcon (custom, same vector as Android)
                    //   ScreenRotation → rotate.right
                    guideEntry(
                        title: "الفهرس",
                        body:  "اضغط على أيقونة القائمة أعلى الصفحة ثم اختر «الفهرس» للتنقل السريع بين السور والأجزاء.",
                        icon:  "line.3.horizontal"
                    )
                    guideEntry(
                        title: "الإشارات",
                        body:  "اضغط على أيقونة الإشارة في الشريط العلوي لحفظ مكانك، واستعرض جميع إشاراتك لاحقًا من «إشاراتي» في القائمة.",
                        icon:  "bookmark.fill"
                    )
                    guideEntry(
                        title: "الورد اليومي",
                        body:  "حدِّد مقدار وردك اليومي من الصفحات أو الآيات، ويتابع التطبيق تقدّمك.",
                        icon:  "calendar"
                    )
                    guideEntry(
                        title: "شريط التقدّم",
                        body:  "الشريط أسفل الصفحة يعكس نسبة إنجاز وردك اليومي: أحمر دون ٣٠٪، برتقالي بين ٣٠ و٧٠٪، أخضر فوق ٧٠٪، وأزرق عند تجاوز الورد.",
                        icon:  "chart.line.uptrend.xyaxis"
                    )
                    guideEntryLawh(
                        title: "الحفظ",
                        body:  "اضغط على أيقونة لوح الحفظ في الشريط العلوي لتمييز الصفحة بعد إتقان حفظها، وراجع ما أتقنته من «حلقة الحفظ»."
                    )
                    guideEntry(
                        title: "أدِر الجهاز",
                        body:  "أدِر الجهاز أفقيًّا لتكبير الخط تلقائيًا لقراءة واضحة ومريحة.",
                        icon:  "rotate.right"
                    )

                    Spacer(minLength: 8)
                    goldHairline
                    Text("لمزيد من التفاصيل عن الرواية والمصادر، راجع «عن التطبيق».")
                        .font(.warattilChrome(size: 11))
                        .foregroundStyle(theme.text.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .environment(\.layoutDirection, .rightToLeft)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
            }
            .background(theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    WarattilSheetTitle(text: "دليل الاستخدام", theme: theme)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("إغلاق") { onDismiss() }
                        .foregroundStyle(theme.accent)
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .font(.warattilChrome(size: 15, weight: .bold))
            .foregroundStyle(theme.accent)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .environment(\.layoutDirection, .rightToLeft)
    }

    private var goldHairline: some View {
        HStack {
            Spacer(minLength: 0)
            Rectangle()
                .fill(theme.gold.opacity(0.35))
                .frame(height: 0.5)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40)
    }

    private func guideEntry(title: String, body: String, icon: String) -> some View {
        guideEntryRow(title: title, body: body) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(theme.accent)
        }
    }

    /// Hifz-specific variant — renders the Kuttāb tablet glyph (لوح الحفظ)
    /// inside the medallion instead of an SF Symbol. Kept separate so the
    /// other six entries don't have to plumb a custom-icon branch through
    /// their call sites.
    private func guideEntryLawh(title: String, body: String) -> some View {
        guideEntryRow(title: title, body: body) {
            LawhHifzIcon(size: 18, tint: theme.accent)
        }
    }

    /// Common layout for a Usage Guide row: gold medallion first (which
    /// renders on the RIGHT under RTL — reading-start side), followed by
    /// the title+body text column.
    ///
    /// Android's `GuideEntry` helper uses `TextAlign.Start` + `TextDirection.Rtl`,
    /// which in RTL resolves to the right edge (text hugs the side nearest the
    /// medallion, flowing leftward). SwiftUI's `HorizontalAlignment`/
    /// `TextAlignment` also flip in RTL — so to match Android's "Start" we
    /// use `.leading` here (NOT `.trailing`, which would push the text to the
    /// far-left edge of the column and leave an awkward gap beside the
    /// medallion). Earlier iterations had this inverted; fixed 2026-04-21.
    @ViewBuilder
    private func guideEntryRow<Icon: View>(
        title: String,
        body:  String,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Gold medallion — uniform 34 pt circle, subtle gold fill.
            ZStack {
                Circle()
                    .fill(theme.gold.opacity(0.10))
                    .frame(width: 34, height: 34)
                icon()
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.warattilChrome(size: 14, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                Text(body)
                    .font(.warattilChrome(size: 13))
                    .foregroundStyle(theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(4)
            }
            .environment(\.layoutDirection, .rightToLeft)
        }
        .padding(.vertical, 4)
    }
}

// =============================================================================
// MARK: - AboutSheet — «عن التطبيق»
// =============================================================================

struct AboutSheet: View {

    let theme:     ThemeColors
    let font:      QuranFontInfo
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .center, spacing: 14) {
                    // ── ١ · Basmala (FIRST) ────────────────────────────────────
                    // Mirrors AboutSheet.kt lines 74–106: the About sheet opens
                    // with the Basmala — framed by restrained floral flourishes
                    // — before the brand mark, not after it. Nasser 2026-04-22:
                    // "make the basmala upper." The logo follows below.
                    Text("❁  ❊  ❁")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.gold.opacity(0.55))
                    Text(WarattilConstants.Mushaf.basmala)
                        .font(font.font(size: 22))
                        .foregroundStyle(theme.gold)
                        .multilineTextAlignment(.center)
                        .environment(\.layoutDirection, .rightToLeft)
                    Text("❁  ❊  ❁")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.gold.opacity(0.55))

                    goldHairline

                    // ── ٢ · Warattil seal + source ayah ────────────────────────
                    // Circular logo (72 pt) with a hairline gold rim — matches
                    // AboutSheet.kt lines 117–134. Sitting between the Basmala
                    // block and the Muzzammil ayah that gives the app its name,
                    // the logo acts as the visual anchor without dominating the
                    // top of the sheet.
                    Image("WarattilLogo")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(theme.gold.opacity(0.45), lineWidth: 0.75)
                        )
                        .accessibilityLabel("شعار ورتّل")

                    // Source ayah — the "ورتِّل" tagline from سورة المزمّل :٤
                    HStack(spacing: 6) {
                        Text("﴿")
                            .font(font.font(size: 22))
                            .foregroundStyle(theme.gold)
                        Text("وَرَتِّلِ ٱلْقُرْءَانَ تَرْتِيلًا")
                            .font(font.font(size: 18))
                            .foregroundStyle(theme.text)
                            .environment(\.layoutDirection, .rightToLeft)
                        Text("﴾")
                            .font(font.font(size: 22))
                            .foregroundStyle(theme.gold)
                    }
                    Text("سورة المزمّل ـ الآية ٤")
                        .font(.warattilChrome(size: 11))
                        .foregroundStyle(theme.gold.opacity(0.75))
                        .environment(\.layoutDirection, .rightToLeft)

                    goldHairline

                    sectionHeading("الرواية والنصّ")
                    sectionBody("يُعرض القرآن الكريم في هذا التطبيق برواية حفص بن سليمان عن عاصم بن أبي النَّجود الكوفي، وهي الرواية المعتمدة في المصحف المدني الذي يطبعه مجمع الملك فهد لطباعة المصحف الشريف.")
                    sectionBody("كلّ حدود الصفحات الـ٦٠٤ مطابقة للمصحف المدني، حرفًا بحرف.")
                    // Tanzil attribution — mirrors AboutSheet.kt line 204.
                    // The digital text (rasm, tashkīl, ayah segmentation) is
                    // verified against the Tanzil project's text before
                    // shipping; naming the source here is a matter of
                    // scholarly honesty, not just credit.
                    sectionBody("وقد تَمَّ التحقّق من النصّ الرقمي عبر مشروع تنزيل (Tanzil).")

                    goldHairline

                    sectionHeading("الرسالة")
                    sectionBody("نَسأل الله أن يجعل هذا التطبيق صدقةً جاريةً لكل من شارك فيه ولكل من يقرأ به. هو مجاني للجميع، بلا إعلانات، ولا يجمع أي بيانات شخصية، ويعمل بلا إنترنت.")

                    goldHairline

                    sectionHeading("شكر وتقدير")
                    sectionBody("الحمد لله على ما أعان ويسّر. ولفضيلة علماء الأمة الذين نقلوا الرسم العثماني والضبط وعدّ الآي جزيل الشكر، ولمجمع الملك فهد لطباعة المصحف الشريف على اعتماده الذي تَستندُ إليه هذه النسخة.")
                    // Tanzil acknowledgement — mirrors AboutSheet.kt line 229.
                    // Separate body so it reads as its own beat after the
                    // primary scholarly acknowledgement above.
                    sectionBody("ولمشروع «تنزيل» على التحقق الرقمي.")

                    goldHairline

                    sectionHeading("للتواصل")
                    // Positive framing — we don't want to plant the idea that
                    // the text has errors in the reader's mind. The audience
                    // is invited to share ideas, not report bugs. Feedback
                    // from Nasser 2026-04-21.
                    sectionBody("إذا كان لديك ملاحظة أو اقتراح، فنرحِّب بمراسلتك على البريد الإلكتروني:")
                    Link("contact@warattil.org",
                         destination: URL(string: "mailto:contact@warattil.org")!)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.gold)
                        .underline()
                        .environment(\.layoutDirection, .leftToRight)

                    // Website line — parity with Android AboutSheet.kt's
                    // "للتواصل" block. Two reach-out channels under the one
                    // heading: email for feedback, website for project info.
                    // Display is the bare host for visual cleanliness; the
                    // destination carries https:// so SwiftUI's Link opens
                    // the default browser rather than any Universal Link
                    // handler that might intercept a schemeless string.
                    Spacer(minLength: 10)
                    sectionBody("وللاطّلاع على المزيد حول المشروع، موقعنا على الإنترنت:")
                    Link("www.warattil.org",
                         destination: URL(string: "https://www.warattil.org")!)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.gold)
                        .underline()
                        .environment(\.layoutDirection, .leftToRight)

                    Spacer(minLength: 12)
                    goldHairline

                    // ── المصدر المفتوح — parity with Android AboutSheet.kt.
                    // WARATTIL is a صدقة جارية: the full source of both apps
                    // is public on GitHub under the MIT licence.
                    sectionHeading("المصدر المفتوح")
                    sectionBody("ورتّل صدقةٌ جارية — الشيفرة المصدرية الكاملة للتطبيق (أندرويد وآيفون) متاحة للجميع مجانًا برخصة MIT، لمن أراد أن يتعلّم منها أو يبني عليها أو يُكمل المسيرة:")
                    Link("github.com/nresan/warattil",
                         destination: URL(string: "https://github.com/nresan/warattil")!)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.gold)
                        .underline()
                        .environment(\.layoutDirection, .leftToRight)

                    Spacer(minLength: 12)
                    goldHairline

                    // Share QR — points to warattil.org/get (UA-aware redirect).
                    // The same PNG shipped on Android (drawable-nodpi/warattil_qr.png)
                    // was ported into Assets.xcassets as "WarattilQR" 2026-04-21.
                    //
                    // 2026-04-23 — tap now shares the QR PNG via the system
                    // activity sheet (ShareUtil.shareQRCode).  Pattern:
                    //   • Tap on the image       → share the QR image
                    //   • "مشاركة الرمز" button → share the QR image (chunkier
                    //                             affordance for readers who
                    //                             don't think to tap an image)
                    //
                    // Keep image ≤140 pt so it renders cleanly at iPhone mini
                    // widths without pushing the copyright line off the first
                    // scroll card.
                    VStack(spacing: 6) {
                        Button {
                            ShareUtil.shareQRCode()
                        } label: {
                            Image("WarattilQR")
                                .resizable()
                                .interpolation(.none)   // QR modules stay crisp at any scale
                                .scaledToFit()
                                .frame(width: 140, height: 140)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("مشاركة رمز ورتّل")

                        Text("امسح أو اضغط للمشاركة")
                            .font(.warattilChrome(size: 11))
                            .foregroundStyle(theme.text.opacity(0.55))
                            .environment(\.layoutDirection, .rightToLeft)

                        // Primary affordance — filled gold pill directly below
                        // the QR, visually paired with the Hifz-garden share
                        // button so readers learn a consistent "share from
                        // any surface" vocabulary across the app.
                        Button {
                            ShareUtil.shareQRCode()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("مشاركة الرمز")
                                    .font(.warattilChrome(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(theme.background)  // cream on gold
                            .padding(.horizontal, 18)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(fihrisGold)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("مشاركة رمز ورتّل")
                        .padding(.top, 2)
                    }
                    .padding(.vertical, 6)

                    goldHairline

                    Text("ورتِّل — الإصدار ١٫١")
                        .font(.warattilChrome(size: 11))
                        .foregroundStyle(theme.text.opacity(0.45))
                    Text("© ٢٠٢٦ — مفتوح المصدر برخصة MIT")
                        .font(.warattilChrome(size: 10))
                        .foregroundStyle(theme.text.opacity(0.35))
                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
            }
            .background(theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    WarattilSheetTitle(text: "عن التطبيق", theme: theme)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("إغلاق") { onDismiss() }
                        .foregroundStyle(theme.accent)
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .font(.warattilChrome(size: 15, weight: .bold))
            .foregroundStyle(theme.accent)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .environment(\.layoutDirection, .rightToLeft)
    }

    private func sectionBody(_ text: String) -> some View {
        // For Arabic paragraphs we want the ragged edge on the LEFT (ends of
        // lines trail off on the left as the reader finishes each line going
        // right-to-left). In a `.rightToLeft` environment SwiftUI maps
        // `.leading` → the right edge, so `.leading` is what produces the
        // traditional right-aligned look. Using `.trailing` here was the bug
        // Nasser flagged 2026-04-20 — paragraphs were left-aligned (LTR-ish).
        Text(text)
            .font(.warattilChrome(size: 14))
            .foregroundStyle(theme.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
    }

    private var goldHairline: some View {
        Rectangle()
            .fill(theme.gold.opacity(0.35))
            .frame(height: 0.5)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 40)
            .padding(.vertical, 6)
    }
}

// =============================================================================
// MARK: - BottomFadeMask — cream fade at the bottom of scrolling lists
// =============================================================================
//
// Why this exists
// ---------------
// Nasser 2026-04-21: on the Fihris Juz tab the bottom row "الجزء ١٣" is
// half-clipped by the sheet edge. It reads as a layout bug — the eye can't
// tell whether the row is truncated or just below the fold. Same story on
// the Bookmarks list when the count spills past the viewport.
//
// SwiftUI's `List` doesn't expose row-snapping or a whole-row scroll anchor,
// so we can't force the last visible row to be a complete row. Instead we
// visually dissolve the bottom ~32 pt of the list into the cream background
// with a LinearGradient overlay. Partial rows still exist geometrically
// (scroll physics unchanged) but read as "there's more below" rather than
// "row got chopped."
//
// Why a ViewModifier
// ------------------
// Applied to surahList, juzList, and bookmarkList. Centralising the fade
// dimensions here keeps the three lists visually consistent and gives a
// single knob (`height`) to tune later.
//
// Why `.allowsHitTesting(false)`
// ------------------------------
// The overlay sits on top of the list's last rows. Without this flag, taps
// landing in the faded band would hit the gradient, not the underlying row,
// and the user wouldn't be able to navigate to (for example) الجزء ١٢ when
// it's partially under the fade. Disabling hit-testing lets touches pass
// straight through to the List.
//
// Why the gradient starts at opacity 0 and ends at opaque theme.background
// -----------------------------------------------------------------------
// The fade must blend with whatever sits behind the list. Using
// `theme.background` with a 0 → 1 opacity ramp produces a seamless
// transition regardless of active theme (cream, sepia, dark) — no hard-
// coded color values to keep in sync.
// =============================================================================

struct BottomFadeMask: ViewModifier {
    let theme: ThemeColors
    var height: CGFloat = 32

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            LinearGradient(
                colors: [
                    theme.background.opacity(0.0),
                    theme.background
                ],
                startPoint: .top,
                endPoint:   .bottom
            )
            .frame(height: height)
            .allowsHitTesting(false)
        }
    }
}
