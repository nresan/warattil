//
//  MushaFHeader.swift
//  Warattil
//
//  Ports app/src/main/java/com/warattil/app/ui/MushaFHeader.kt to SwiftUI.
//
//  Layout (left → right, portrait):
//    • Left cluster  — bookmark · hifz-star · "سورة X · الجزء N"
//    • Right cluster — theme-cycle · search · overflow ≡
//
//  The overflow menu carries seven items matching the Android dropdown exactly:
//    الفهرس · إشاراتي · الورد اليومي · حلقة الحفظ ·
//    دليل الاستخدام · عن التطبيق · شارك ورتّل
//
//  Header surah label (2026-05-03 — Android parity task #85):
//    The header carries «سورة X · الجزء N» on every page so a reader deep
//    inside a surah (say page 293 in al-Kahf) always knows where they are
//    without scrolling back to the surah-opening banner. The per-surah
//    name-plate inside the page body still renders on surah-start pages —
//    the header label is an always-visible secondary cue, not a replacement.
//    On multi-surah pages (604, 603 …) the header shows whichever surah
//    `surahName` resolved to (typically the first one on the page, which
//    matches user expectation: "where am I landing?").
//

import SwiftUI

// =============================================================================
// Deep gold reserved for the hifz star — matches Android HIFZ_GOLD.
// =============================================================================
private let hifzGold = Color(red: 0x99 / 255.0, green: 0x65 / 255.0, blue: 0x15 / 255.0)

// =============================================================================
// MushaFHeader — slim icon strip, pinned to the top of the screen.
// =============================================================================

struct MushaFHeader: View {

    // ── State ────────────────────────────────────────────────────────────────
    let surahName:    String
    let juzNumber:    Int
    let currentPage:  Int
    let theme:        ThemeColors
    let font:         QuranFontInfo
    let isBookmarked: Bool
    /// Per-page memorization *ratio* (0…1).  Drives the header strip's
    /// tri-state tint — empty / partial / full — via
    /// WarattilConstants.Hifz.stripAlpha.  Replaces the Phase-0 binary
    /// `isMemorized: Bool` so partially-memorized pages render as a muted
    /// gold instead of either full or dim.  Task #8 (Android) has the
    /// equivalent tri-state update.
    let memorizedRatio: Double

    // ── Callbacks ────────────────────────────────────────────────────────────
    let onBookmark:    () -> Void
    let onMemorize:    () -> Void
    let onThemeCycle:  () -> Void
    let onSearch:      () -> Void
    let onFihris:      () -> Void
    let onBkm:         () -> Void
    let onWird:        () -> Void
    let onHifzLog:     () -> Void
    let onAzan:        () -> Void   // «أوقات الصلاة» — added 2026-05-20 for Azan port
    let onUsageGuide:  () -> Void
    let onAbout:       () -> Void
    let onShare:       () -> Void
    // Tapping the ≡ button now only notifies the parent screen — the
    // overflow card is rendered as a screen-level overlay so it can pin
    // to the top-right corner of the screen (SwiftUI's own `.popover`
    // anchors to the button and extends both ways, drifting toward the
    // center of the screen; Nasser 2026-04-22 asked for it "just next to
    // the icons," i.e. hugging the right edge).
    let onMenuTap:     () -> Void

    // ── Body ─────────────────────────────────────────────────────────────────

    var body: some View {
        VStack(spacing: 0) {
            // The whole chrome strip is rendered RTL so ordering is
            // deterministic regardless of which ancestor set direction.
            // First child lands visually on the RIGHT, second on the LEFT:
            //
            //   [ menu · search · palette ]    ← right side  (rightCluster)
            //   [  juz · hifz · bookmark  ]    ← left side   (leftCluster)
            //
            // We put rightCluster FIRST so the overflow ≡ menu appears at
            // the right edge of the screen — the conventional Arabic reading
            // position for primary actions.
            HStack(alignment: .center, spacing: 0) {
                rightCluster
                Spacer(minLength: 0)
                leftCluster
            }
            .environment(\.layoutDirection, .rightToLeft)
            .padding(.horizontal, 8)
            .padding(.top,    WarattilConstants.Layout.headerTopPadding)
            .padding(.bottom, 6)

            Rectangle()
                .fill(theme.divider)
                .frame(height: WarattilConstants.Layout.dividerThickness)
        }
        .background(theme.background)
    }

    // ── Left cluster — bookmark · hifz · juz label ───────────────────────────

    private var leftCluster: some View {
        HStack(spacing: 2) {
            // Bookmark toggle
            Button(action: onBookmark) {
                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(isBookmarked ? theme.accent : theme.accent.opacity(0.5))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)

            // Memorize toggle — Kuttāb tablet glyph (لوح الحفظ), ported from
            // Android's ic_lawh_hifz vector drawable via LawhHifzIcon. Tint
            // alpha is now tri-state — empty (no ayahs memorized on this
            // page), partial (some), or full (every ayah) — matching
            // WarattilConstants.Hifz.stripAlpha.  A partially-memorized
            // page still reads as "in progress" rather than either full
            // gold or near-invisible dim, so the student sees continuous
            // momentum instead of the old 0/1 flip.
            Button(action: onMemorize) {
                LawhHifzIcon(
                    size: 18,
                    tint: hifzGold.opacity(WarattilConstants.Hifz.stripAlpha(memorizedRatio))
                )
                .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                memorizedRatio >= 1.0 ? "إلغاء تعليم الحفظ"
                    : (memorizedRatio > 0 ? "تعليم محفوظ (جزئي)" : "تعليم محفوظ")
            )

            // Compact location label «سورة X · الجزء N» — NOT rendered with
            // the Uthmanic font. The Uthmanic font ligates digits into
            // ayah-badge glyphs, which is wrong for chrome text.
            //
            // Font choice: Amiri-Regular (classical Naskh). SF Arabic — the
            // iOS default Arabic face — renders as a modern geometric
            // sans-serif that clashes with the Mushaf palette of cream /
            // charcoal / gold. Amiri matches the banner typography and
            // reads as "scholarly print" rather than "iOS chrome". Point
            // size sourced from WarattilConstants.Typography.juzLabelSize
            // (17 pt — matches Android's 17.sp anchor weight; bumped from
            // 14 on 2026-05-03 alongside this surah-name change).
            //
            // 2026-05-03 — Android parity task #85. Was «الجزء N» only;
            // now mirrors Android's «سورة X · الجزء N» on every page when
            // a surah resolves, falling back to «الجزء N» only when the
            // resolver returns an empty string (defensive — should not
            // happen with the current MetadataParser).
            if juzNumber > 0 {
                let label = surahName.isEmpty
                    ? "الجزء \(juzNumber.arabicDigits)"
                    : "سورة \(surahName) · الجزء \(juzNumber.arabicDigits)"
                Text(label)
                    .font(.warattilChrome(
                        size: WarattilConstants.Typography.juzLabelSize
                    ))
                    .foregroundStyle(theme.gold)
                    .lineLimit(1)
                    .environment(\.layoutDirection, .rightToLeft)
            }
        }
    }

    // ── Right cluster — overflow ≡ · search · palette ────────────────────────
    //
    // Children are listed in *logical* reading order (first child lands at
    // the right edge under the RTL environment we set on the parent HStack).
    // Order of priority: overflow menu > search > palette. That puts the ≡
    // button at the absolute right edge of the header — the conventional
    // primary-action slot for an Arabic reader.

    private var rightCluster: some View {
        HStack(spacing: 2) {
            // Overflow ≡ — taps delegate to the parent screen, which owns
            // the open/closed state and renders the menu card as a
            // top-right-anchored overlay. Keeping the state one level up
            // lets the overlay hug the screen edge regardless of where
            // this button sits inside the header's HStack layout.
            Button(action: onMenuTap) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(theme.accent)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)

            Button(action: onSearch) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(theme.accent)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)

            Button(action: onThemeCycle) {
                Image(systemName: "paintpalette")
                    .font(.system(size: 15))
                    .foregroundStyle(theme.accent)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
        }
    }

}

// =============================================================================
// MARK: - OverflowMenuCard — top-right-anchored dropdown
// =============================================================================
//
// Rendered as a screen-level overlay by MushaFScreen (not a SwiftUI `.popover`)
// so the card can hug the top-right corner of the screen regardless of where
// the ≡ button sits inside the header. Native `.popover` anchors to the
// button and centres the body around it, which drifts the card toward the
// middle of the screen on iPhone — the opposite of what Nasser asked for.
//
// Item order mirrors Android's overflow menu:
//   الفهرس · إشاراتي · الورد اليومي · حلقة الحفظ ·
//   دليل الاستخدام · عن التطبيق · شارك ورتّل
//
// Each row is built icon-first / text-last inside a `.rightToLeft` HStack,
// so under RTL the icon lands at the RIGHT edge and the text to its left.
// =============================================================================

struct OverflowMenuCard: View {
    let theme: ThemeColors

    let onDismiss:     () -> Void
    let onFihris:      () -> Void
    let onBkm:         () -> Void
    let onWird:        () -> Void
    let onHifzLog:     () -> Void
    let onAzan:        () -> Void   // «أوقات الصلاة» — added 2026-05-20 for Azan port
    let onUsageGuide:  () -> Void
    let onAbout:       () -> Void
    let onShare:       () -> Void
    /// "شارك قراءة اليوم" — renders a DailyReadingShareCard snapshot and
    /// hands it to the system share sheet.  Kept distinct from `onShare`
    /// (which shares the app invitation) because the payloads differ
    /// enough that bundling them into one menu item would confuse readers.
    let onShareDaily:  () -> Void

    var body: some View {
        // alignment: .leading under .rightToLeft → rows align to the RIGHT
        // edge of the card. Combined with the spacer-less row HStack below,
        // this gives the requested "icon + text both grouped on the right"
        // layout — not the prior split-edge layout.
        VStack(alignment: .leading, spacing: 0) {
            menuRow(text: "الفهرس",         icon: "book.closed",         action: onFihris)
            menuRow(text: "إشاراتي",         icon: "bookmark",            action: onBkm)
            // Wird icon (parity with Android task #57 — dropped the music-
            // stand, ic_mushaf_rihal silhouette in its place).  iOS doesn't
            // ship the custom rihal vector, so we pick the closest SF
            // Symbol: `book.pages` reads as an open Mushaf on a stand,
            // semantically right for اضبط ورد اليوم.  `calendar` (the
            // previous symbol) implied scheduling, which contradicted the
            // ungamified-no-schedule wird tone.
            menuRow(text: "الورد اليومي",    icon: "book.pages",          action: onWird)
            menuRow(text: "حلقة الحفظ",      icon: "graduationcap",       action: onHifzLog)
            // أوقات الصلاة — sits in the devotional cluster (Wird → Hifz → Azan),
            // matching the Android menu order in MushaFHeader.kt.
            menuRow(text: "أوقات الصلاة",    icon: "bell",                action: onAzan)
            menuRow(text: "شارك قراءة اليوم", icon: "chart.bar.doc.horizontal", action: onShareDaily)
            menuRow(text: "دليل الاستخدام",  icon: "questionmark.circle", action: onUsageGuide)
            menuRow(text: "عن التطبيق",      icon: "info.circle",         action: onAbout)
            menuRow(text: "شارك ورتّل",      icon: "square.and.arrow.up", action: onShare)
        }
        .padding(.vertical, 8)
        .frame(width: 240)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.background)
                .shadow(color: Color.black.opacity(0.18), radius: 16, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(theme.gold.opacity(0.25), lineWidth: 0.5)
        )
        .environment(\.layoutDirection, .rightToLeft)
    }

    /// Single menu row — Amiri chrome font, theme-tinted icon, icon + text
    /// grouped together and justified to the card's trailing edge (the RIGHT
    /// side under the card's `.rightToLeft` environment).
    ///
    /// 2026-04-22 layout fix: the earlier HStack used `Spacer(minLength: 6)`
    /// between icon and text, which under RTL pushed the icon to the
    /// right edge and the text to the left edge of the card — leaving a
    /// large empty gap in the middle and making each row read as two
    /// disconnected elements instead of one item. Nasser: "The icons and
    /// the text should be justified to the right inside the menu."
    ///
    /// Fix: remove the Spacer and use a `frame(maxWidth: .infinity,
    /// alignment: .leading)` on the HStack — under the card's RTL env,
    /// `.leading` resolves to the visual RIGHT edge. Now icon + text sit
    /// adjacent, both anchored to the right.
    ///
    /// Selecting a row dismisses the overlay first, then fires the action on
    /// the next runloop tick so any sheet it triggers opens against a clean
    /// presentation stack.
    @ViewBuilder
    private func menuRow(
        text:   String,
        icon:   String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            onDismiss()
            DispatchQueue.main.async { action() }
        } label: {
            HStack(spacing: 10) {
                // Icon first in source → leading (= RIGHT edge under RTL).
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(theme.accent)
                    .frame(width: 22, alignment: .center)
                // Text second → sits immediately to the LEFT of the icon
                // under RTL. The two stay visually glued together; no
                // Spacer so we don't split them across the card width.
                Text(text)
                    .font(.warattilChrome(size: 16))
                    .foregroundStyle(theme.text)
            }
            // Stretch the row to the full card width so the hit target
            // spans the whole row, but pin content to `.leading` — under
            // the card's RTL env this is the visual RIGHT edge, giving
            // "both icon and text justified to the right" as requested.
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
