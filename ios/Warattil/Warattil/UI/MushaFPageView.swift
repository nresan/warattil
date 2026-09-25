//
//  MushaFPageView.swift
//  Warattil
//
//  Android-parity Mushaf page renderer (ported from MushaFBody.kt, 2026-04-21).
//
//  HISTORY
//  -------
//  The previous implementation used a per-page QCF glyph font path (QCF_P001…
//  QCF_P604). That path depended on three SQLite tables — `page_line`,
//  `page_font`, `line_word` — which are not present in the shipped
//  `quran_v3.db` (the only tables actually bundled are `quran_text`,
//  `bookmarks`, `user_preferences`). The DAO returned nil, the view entered
//  the `.failed` state on some pages, and on other pages rendered the layout
//  against an empty line list — producing the "tofu rectangle at the ayah
//  marker" symptom Nasser reported on 2026-04-21.
//
//  WHY THIS DESIGN
//  ---------------
//  Android never used QCF for body rendering either (QCF is only referenced
//  in MushaFFooter for the page-number badge). The Mushaf body on Android is
//  rendered from the clean Uthmani text in `quran_text`, with ayah markers
//  composed INLINE as the string `" ﴿N﴾ "` where N is Eastern-Arabic digits.
//  The parens (﴿ ﴾ = U+FD3E / U+FD3F) are coloured Deep Gold; the number is
//  coloured Mushaf Green (the accent). Everything renders through a single
//  `Text` call with an `AttributedString` that splices span colours / sizes.
//
//  Porting this path 1:1 to SwiftUI:
//    (1) Eliminates the QCF-table dependency — we only need `quran_text`,
//        which every DB revision has shipped with.
//    (2) Matches Android pixel-for-pixel — the same font, the same marker
//        glyph, the same colours, the same adaptive sizing ladder.
//    (3) Sidesteps UIKit's notoriously weak Arabic justification (which
//        expands word spaces only, never kashida). The adaptive sizing
//        picks a body point size where lines naturally fill the column —
//        the traditional Madinah-Mushaf technique.
//
//  LAYOUT MODEL
//  ------------
//  One page = groups of ayahs bucketed by surah. For each group:
//    • If the group opens with ayah 1, a SurahBanner precedes it.
//        – Fatiha & Tawbah banners: name plate only.
//        – Every other surah:     name plate + ornamental Basmala.
//    • The displayed ayahs render as ONE justified / centred Text run:
//          ayah₁.text + " ﴿١﴾ " + ayah₂.text + " ﴿٢﴾ " + ... + " ﴿N﴾ "
//      with Deep-Gold parens + Mushaf-Green bold number inline.
//
//  ADAPTIVE FONT ENGINE
//  --------------------
//  Binary search 22…46 pt for the largest body size at which:
//    (available height − all banner footprints) ≥ total rendered text height
//  measured with `NSAttributedString.boundingRect(with:)` on the full content.
//  A 0.97 safety factor covers Text's first-line-ascender + last-line-descender
//  padding that UIKit adds around each `Text` composable.
//
//  Pages 1 & 2 (the illuminated "opening spread") cap at 34 pt and use a 2.0×
//  line-height and `.center` alignment — produces the characteristic rounded
//  silhouette of the Madinah-Mushaf opening.
//
//  Landscape (Elderly Reading Mode): locked at 48 pt, 72 pt line-height.
//  The whole page becomes a scrollable list so elderly users can pan through
//  text that no longer needs to fit on a single screen.
//

import SwiftUI
import UIKit

// =============================================================================
// MARK: - Sizing constants — mirror MushaFBody.kt
// =============================================================================

private enum Sizing {
    /// Binary-search bounds for the portrait adaptive font engine. 24–46 sp
    /// covers every realistic Mushaf page in practice:
    ///   • dense pages  → converge near 24–28
    ///   • normal pages → converge near 30–34
    ///   • sparse pages → cap at 46, then vertical-center via spacers
    ///
    /// 2026-04-21 — floor raised 22 → 24 (Nasser parity request: carry the
    /// pages-1-2 "elegance" to pages 3-604). The hardest-to-pack pages
    /// now read at 24 sp minimum, a meaningful step up in legibility.
    static let minBodySp: CGFloat = 24
    static let maxBodySp: CGFloat = 46

    /// Opening-spread (pages 1 & 2) — smaller cap + taller line-height produces
    /// the rounded silhouette of the Madinah-Mushaf illuminated opener.
    static let openingSpreadMaxSp:  CGFloat = 34
    static let openingSpreadLineH:  CGFloat = 2.0

    /// Standard body line-height = body × 1.70.
    ///
    /// 2026-04-21 — bumped 1.60 → 1.70 so dense pages get a fraction of
    /// the breathing room that made pages 1 & 2 feel elegant. The
    /// adaptive engine compensates by picking a slightly smaller body
    /// where necessary; net result is tighter lines on dense pages
    /// without the cramped feeling Nasser flagged.
    static let lineHRatio: CGFloat = 1.70

    /// Upper cap for the vertical-fill stretch in tier 1 of the
    /// adaptive engine. When a sparse page would otherwise leave a
    /// visible empty band top or bottom, the engine grows lineHRatio
    /// from 1.70 toward this ceiling to match the visual rhythm of
    /// denser pages. 2.20 is the highest value that still reads as
    /// "breathing room" rather than "this page is missing content" —
    /// beyond it the lines look disconnected.
    static let maxStretchRatio: CGFloat = 2.20

    /// Ayah-marker font = body × 0.875. The ﴿N﴾ glyph is visually heavier
    /// per-em than the body text, so shrinking it to ~88% matches the
    /// printed-Mushaf marker-to-body ratio.
    static let markerRatio: CGFloat = 0.875

    /// Ornamental Basmala = body × 0.95.
    ///
    /// 2026-04-21 — 0.90 → 0.95 so the Basmala reads as a proper header
    /// beat rather than a mere sub-title. Pages 1 & 2 show this effect
    /// naturally because their body sp is small; bumping the ratio gives
    /// dense pages the same visual hierarchy.
    static let basmalaRatio: CGFloat = 0.95

    /// Headroom applied to the height budget before the fit test —
    /// covers UILabel's first-line-ascender + last-line-descender padding
    /// PLUS a small margin for the ever-so-slight mismatch between the
    /// measurement paragraph style and the actual render (the render
    /// locks line-height with min/maxLineHeight absolute values, while
    /// `boundingRect` applies them as character-attribute hints that
    /// font-specific leading can marginally exceed).
    ///
    /// 2026-04-21 (rev. 2) — raised 0.93 → 0.97 after moving the fit
    /// test onto the EXACT CoreText typesetter the renderer uses. The
    /// old 0.93 margin was buffering mismatch between UIKit's
    /// `boundingRect` (measurement) and CoreText (render). With both
    /// paths now running `CTTypesetterSuggestLineBreak` on the same
    /// prepared attributed string, the mismatch is gone and the
    /// 3 % safety margin only needs to cover the banner-footprint
    /// estimate (`bannerPx`) and sub-pixel rounding. Tighter margin
    /// → larger fonts permitted → less dead space on pages that
    /// previously shrunk unnecessarily.
    static let safetyFactor: CGFloat = 0.97

    /// Absolute floor the adaptive engine is allowed to drop to when
    /// NOTHING inside the standard [minBodySp…maxBodySp] window fits.
    /// This is the "emergency shrink" path: very dense pages (e.g. long
    /// run-on ayahs in Al-Baqarah) occasionally need to go below the
    /// comfort floor to avoid clipping at the top/bottom of the page
    /// frame. 18 pt is still legible on iPhone; the trade-off is worth
    /// it against losing the first or last line of the ayah.
    static let emergencyMinBodySp: CGFloat = 18

    /// Number of binary-search iterations — 12 yields ≤ 0.006 sp resolution,
    /// well under any visible rendering difference.
    static let searchIterations: Int = 12

    /// Banner chrome height (in pt) EXCLUDING the ornamental Basmala row.
    /// Empirical sum of outer padding + borders + title line box + safety —
    /// mirrors BANNER_BASE_DP in MushaFBody.kt.
    ///
    /// 2026-04-21 rev 3 — raised 64 → 82 when the banner was redesigned
    /// toward the Golden Quran cartouche aesthetic (taller lozenge plate
    /// with double-rule border + end flourishes). Actual footprint is
    /// now plate (58) + vertical pad (4) + basmala gap (10) + safety
    /// (10) ≈ 82 pt. The extra 18 pt cost is absorbed by the vertical-
    /// fill stretch for sparse pages and handled naturally by the
    /// adaptive tier-down on dense pages.
    static let bannerBaseDp: CGFloat = 82

    /// Landscape (Elderly) — locked values, never searched.
    static let landscapeBodySp:  CGFloat = 48
    static let landscapeLineH:   CGFloat = 72

    /// Surah-banner title size. Independent of body size so the plate reads
    /// uniformly across pages of varying density.
    ///
    /// 2026-04-21 rev 3 — bumped 20 → 22 (portrait) / 17 → 19 (landscape)
    /// alongside the banner redesign toward the Golden Quran cartouche.
    /// The taller plate (58 pt) has room for a title sized closer to the
    /// printed Mushaf reference; the previous 20 pt title floated inside
    /// the plate with too much margin above and below.
    static let titleSizePortrait:  CGFloat = 22
    static let titleSizeLandscape: CGFloat = 19

    /// Explicit name-plate height. Amiri-Bold's intrinsic line height at
    /// 22 pt is ~52 pt (classical naskh carries deep ascenders/descenders
    /// to clear vowel marks). Combined with `.fixedSize(vertical: true)`
    /// this would make the box tower even taller than we need. We lock
    /// the plate to a fixed height instead — the title renders inside
    /// this box, vertically centred, and the line box is clipped so font
    /// metrics can't push the stroke outward.
    ///
    /// 2026-04-21 rev 3 — 44 / 36 → 58 / 50. The Golden Quran cartouche
    /// redesign needs vertical room for both the double-rule gold border
    /// (outer 1.5 pt + inner 0.7 pt with 3 pt inset) AND the end-
    /// flourishes flanking the title. 58 pt is the minimum where none
    /// of these elements crowd each other.
    static let bannerPlateHeightPortrait:  CGFloat = 58
    static let bannerPlateHeightLandscape: CGFloat = 50
}

// =============================================================================
// MARK: - Surah grouping & Basmala rules
// =============================================================================

/// One contiguous group of ayahs on this page that all belong to the same
/// surah. Pages can contain 1..N groups (usually 1; page 604 holds 3).
private struct SurahGroup: Identifiable {
    let surahIndex: Int
    let ayahs:      [Ayah]
    var id: Int { surahIndex }
}

private func buildGroups(from ayahs: [Ayah]) -> [SurahGroup] {
    var out: [SurahGroup] = []
    var cur = -1
    var batch: [Ayah] = []
    for a in ayahs {
        guard let s = a.surah else { continue }
        if s != cur {
            if !batch.isEmpty { out.append(SurahGroup(surahIndex: cur, ayahs: batch)) }
            cur = s
            batch = []
        }
        batch.append(a)
    }
    if !batch.isEmpty, cur != -1 {
        out.append(SurahGroup(surahIndex: cur, ayahs: batch))
    }
    return out
}

/// Ayah list AS IT SHOULD BE DISPLAYED, given Madinah-standard Basmala rules:
///   • Al-Fatiha (1)   — unchanged. Basmala IS ayah 1 and stays inline.
///   • At-Tawbah (9)   — unchanged. DB already contains no Basmala.
///   • Every other surah — if the group opens with ayah 1 and its text begins
///     with the Basmala, strip it. If ayah 1 was JUST the Basmala (some DBs
///     store it as a pseudo-ayah), drop that row entirely so the ornamental
///     banner does not duplicate inline.
private extension SurahGroup {
    func displayAyahs() -> [Ayah] {
        let isFatiha = surahIndex == 1
        let isTawbah = surahIndex == WarattilConstants.Mushaf.surahTawbah
        if isFatiha || isTawbah { return ayahs }
        guard let first = ayahs.first, first.ayah == 1 else { return ayahs }
        let raw = (first.text ?? "").trimmingCharacters(in: .whitespaces)
        guard raw.startsWithBasmala() else { return ayahs }
        let stripped = raw.stripBasmalaPrefix()
        if stripped.trimmingCharacters(in: .whitespaces).isEmpty {
            return Array(ayahs.dropFirst())
        }
        var mutated = ayahs
        mutated[0] = Ayah(
            id: first.id, surah: first.surah, ayah: first.ayah,
            text: stripped, page: first.page, juz: first.juz
        )
        return mutated
    }
}

// =============================================================================
// MARK: - Top-level page router
// =============================================================================

/// Entry point called by MushaFScreen. Accepts the ayah-based PageLoadState
/// (not MushafPageLoadState) because rendering no longer depends on the QCF
/// layout tables. The VM still populates both states in `ensureLoaded`, but
/// this view only consumes `pageStates`.
struct MushaFPageView: View {
    let state: PageLoadState
    let theme: ThemeColors
    let viewModel: MushaFViewModel

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            switch state {
            case .loading:
                ProgressView().tint(theme.accent)

            case .failed(let message):
                Text("خطأ: \(message)")
                    .foregroundStyle(theme.progressLow)
                    .multilineTextAlignment(.center)
                    .padding()

            case .loaded(let content):
                PageBody(content: content, theme: theme, viewModel: viewModel)
                    .padding(.horizontal, WarattilConstants.Layout.pageHorizontalPadding)
            }
        }
    }
}

// =============================================================================
// MARK: - Page body
// =============================================================================

private struct PageBody: View {
    let content:   PageContent
    let theme:     ThemeColors
    let viewModel: MushaFViewModel

    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass)   private var vSize

    // Long-press action-bar state. `selection` drives the floating pill's
    // visibility; `toastMessage` drives the clipboard-confirmation toast.
    // Kept local to the page so two pages in the pager don't fight over the
    // same selection.
    @State private var selection:    AyahSelection? = nil
    @State private var toastMessage: String?        = nil

    /// Drives presentation of `AyahMeaningsSheet` (Ghareeb + Tafseer tabs).
    /// Captured at open-time so dismissing the sheet doesn't disturb the
    /// long-press selection — closing the sheet returns the user to the
    /// floating action bar with the same range still highlighted.
    @State private var meaningsAyah:  AyahSelection? = nil

    var body: some View {
        let font = quranFont()
        let groups = buildGroups(from: content.ayahs)

        // iPhone in landscape reports (h: .compact, v: .compact); iPad split in
        // landscape reports (h: .regular, v: .regular). We want the elderly
        // large-reading mode ONLY on phone landscape, so trigger purely on
        // vertical = .compact (which matches "is this device in landscape").
        let isLandscape = (vSize == .compact)

        // Pages 1 & 2 use the opening-spread typography (smaller cap + taller
        // line-height + centered alignment — the rounded Mushaf-opening look).
        let isOpeningSpread = (content.pageNumber == 1 || content.pageNumber == 2)

        ZStack(alignment: .top) {
            GeometryReader { proxy in
                let size = proxy.size

                if isLandscape {
                    // Landscape: LazyColumn-equivalent, fixed 48 pt, 72 pt line.
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(groups) { group in
                                if group.ayahs.first?.ayah == 1 {
                                    SurahBanner(
                                        group: group, theme: theme, font: font,
                                        isLandscape: true, bodySp: Sizing.landscapeBodySp
                                    )
                                }
                                let display = group.displayAyahs()
                                if !display.isEmpty {
                                    AyahBlock(
                                        ayahs: display, font: font, theme: theme,
                                        bodySp: Sizing.landscapeBodySp,
                                        lineH: Sizing.landscapeLineH,
                                        centered: false,
                                        viewModel: viewModel,
                                        onSelect: { selection = $0 }
                                    )
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    // Portrait — run the adaptive engine ONCE and use the
                    // (sp, lineHRatio) pair it returns. The engine has
                    // already verified the pair fits (exact CT line-count
                    // measurement, not a prediction), so we can use both
                    // values verbatim without post-hoc clamping.
                    let sizing = adaptivePageSizing(
                        in: size,
                        groups: groups,
                        font: font,
                        theme: theme,
                        maxBodySp: isOpeningSpread
                            ? Sizing.openingSpreadMaxSp
                            : Sizing.maxBodySp,
                        baseLineHRatio: isOpeningSpread
                            ? Sizing.openingSpreadLineH
                            : Sizing.lineHRatio
                    )
                    let sp    = sizing.bodySp
                    let lineH = sp * sizing.lineHRatio

                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        ForEach(groups) { group in
                            if group.ayahs.first?.ayah == 1 {
                                SurahBanner(
                                    group: group, theme: theme, font: font,
                                    isLandscape: false, bodySp: sp
                                )
                            }
                            let display = group.displayAyahs()
                            if !display.isEmpty {
                                // `centered: false` routes through the
                                // KashidaArabicText CoreText pipeline so
                                // the opening spread (Fatihah + start of
                                // Baqarah) gets kashida-justified lines
                                // that fill the column width, matching
                                // the rest of the Mushaf. Earlier revision
                                // passed `isOpeningSpread` here and the
                                // opening pages fell through to the
                                // centered UILabel path, which left the
                                // Fatihah lines with ragged right edges.
                                // The opening-spread typography (larger
                                // cap + taller line-height) is preserved
                                // independently via `openingSpreadMaxSp`
                                // / `openingSpreadLineH` above.
                                // Nasser 2026-04-21.
                                AyahBlock(
                                    ayahs: display, font: font, theme: theme,
                                    bodySp: sp, lineH: lineH,
                                    centered: false,
                                    viewModel: viewModel,
                                    onSelect: { selection = $0 }
                                )
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(width: size.width, height: size.height, alignment: .center)
                    .clipped()
                }
            }

            // ── Floating action bar (pill) ────────────────────────────────────
            // Overlaid at the top of the content area, centred horizontally.
            // Matches AyahActionBar.kt's placement note: "v1 renders the bar
            // at the top of the content area (below the header strip)."
            if let sel = selection {
                // Max end ayah available for forward extension on this page:
                // the largest ayah number in the same surah that appears on
                // the current page content.  Bounds the "+" chip so the user
                // can't extend the selection into a surah that isn't on the
                // visible page.  If the selection's surah has no ayahs on
                // the page (shouldn't happen — the selection was created
                // from one of them) we fall back to the current end, which
                // disables the chip.
                // `Ayah.surah` and `Ayah.ayah` are both `Int?` in the data
                // model — they're nil for the page-decorator rows the
                // parser stitches in (basmala / surah-name banner).  We
                // compactMap to drop those nils before .max() so
                // `lastAyahOnPage` lands as a clean Int rather than
                // Optional<Int>; otherwise downstream comparisons like
                // `sel.endAyah < lastAyahOnPage` fail to type-check
                // (Int vs Int?).
                let lastAyahOnPage = content.ayahs
                    .filter { $0.surah == sel.surah }
                    .compactMap { $0.ayah }
                    .max() ?? sel.endAyah
                let canExtend  = sel.endAyah < lastAyahOnPage
                let canShrink  = sel.endAyah > sel.ayah
                let shareBody  = viewModel.shareText(
                    surah: sel.surah, from: sel.ayah, to: sel.endAyah
                )

                AyahActionBar(
                    theme:            theme,
                    shareText:        shareBody,
                    subject:          ShareUtil.appShareSubject,
                    // Memorize state read from the VM — @Observable tracking
                    // re-renders this bar whenever `memorizedAyahs` changes,
                    // so the glyph flips tint immediately on tap.  Range
                    // selections report the START ayah's state; toggling
                    // mutates the start ayah only so a user can't
                    // unintentionally flip memorisation across a 3-ayah
                    // block with one tap.
                    isMemorized:      viewModel.isAyahMemorized(
                                        surah: sel.surah, ayah: sel.ayah
                                      ),
                    onToggleMemorize: {
                        viewModel.toggleAyah(surah: sel.surah, ayah: sel.ayah)
                        // Intentionally do NOT dismiss the pill — mirrors
                        // Android's AyahActionBar.kt so the reader can verify
                        // the glyph state before moving on.
                    },
                    onCopy: {
                        // Range-aware copy — collapses to single-ayah when
                        // endAyah == ayah.  Toast text stays identical
                        // because the clipboard payload always reads as
                        // "one quote" regardless of how many ayahs it
                        // spans.
                        let ok = viewModel.copyAyah(
                            surah: sel.surah, from: sel.ayah, to: sel.endAyah
                        )
                        if ok { showToast("نُقلت إلى الحافظة") }
                        selection = nil
                    },
                    onDismiss: {
                        selection = nil
                    },
                    onExtendForward:   canExtend ? {
                        // Grow the range by one ayah forward.  Bounded
                        // above by lastAyahOnPage so we never silently
                        // extend into the next page (users would see a
                        // citation "الآيات m–n" with an n that isn't on
                        // screen and get confused).
                        var next = sel
                        next.endAyah = min(sel.endAyah + 1, lastAyahOnPage)
                        selection = next
                    } : nil,
                    onShrinkBackward:  canShrink ? {
                        // Shrink the range back toward the start — floor
                        // is the start ayah itself (collapse to a single
                        // ayah selection).
                        var next = sel
                        next.endAyah = max(sel.endAyah - 1, sel.ayah)
                        selection = next
                    } : nil,
                    canExtendForward:  canExtend,
                    canShrinkBackward: canShrink,
                    // Open the meanings sheet (Ghareeb default + Tafseer
                    // tabs) anchored at the selection's start ayah.
                    // Captured into `meaningsAyah` so dismissing the sheet
                    // doesn't tear down the long-press selection — when
                    // the reader returns, the floating action bar is
                    // still right where they left it.
                    onOpenMeanings: {
                        meaningsAyah = sel
                    }
                )
                .padding(.top, 8)
                .transition(
                    .move(edge: .top).combined(with: .opacity)
                )
            }

            // ── Toast near bottom ─────────────────────────────────────────────
            if let msg = toastMessage {
                VStack {
                    Spacer()
                    AyahToast(text: msg, theme: theme)
                        .padding(.bottom, 80)
                }
                .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: selection)
        .animation(.easeInOut(duration: 0.18), value: toastMessage)
        // Ayah-meanings sheet (Ghareeb default + Tafseer second tab).
        // Presented via .sheet rather than .fullScreenCover so it lands
        // as a half-height bottom sheet on iOS 16+ — closer in feel to
        // Android's ModalBottomSheet than the full-screen alternative.
        .sheet(item: $meaningsAyah) { sel in
            AyahMeaningsSheet(
                suraNumber: sel.surah,
                ayaNumber:  sel.ayah,
                theme:      theme,
                font:       quranFont(),
                onDismiss:  { meaningsAyah = nil }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
        }
    }

    /// Shows a toast that auto-dismisses after ~1.8 s — matches the Android
    /// Toast.LENGTH_SHORT duration (≈ 2 s). Replaces any in-flight toast.
    private func showToast(_ text: String) {
        toastMessage = text
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            await MainActor.run {
                if toastMessage == text { toastMessage = nil }
            }
        }
    }
}

// =============================================================================
// MARK: - Adaptive page-sizing engine
// =============================================================================
//
// ONE RULE applied to every page:
//   Pick the largest (bodySp, lineHRatio) pair for which
//       bannerFootprint + renderedLineCount × (bodySp × lineHRatio)
//     ≤ pageHeight × safetyFactor
//   holds, where `renderedLineCount` comes from the EXACT CoreText
//   typesetter the renderer uses. Overflow is impossible unless even
//   the most compact setting fails — and for a 604-page Mushaf it can't.
//
// Three-tier preference ladder (largest-quality-first):
//
//   Tier 1  (comfort):         binary search sp ∈ [24 … 46] at ratio 1.70
//   Tier 2  (emergency-sp):    sp ∈ [23 … 18] stepping by 1 at ratio 1.70
//   Tier 3  (emergency-rhythm): sp = 18 at ratio ∈ {1.60, 1.50, 1.40, 1.30, 1.25}
//
// The first pair that fits wins. Because the measurement runs the EXACT
// same `CTTypesetterSuggestLineBreak` the renderer uses on the SAME
// attributed string (rosette attachments wrapped in CTRunDelegates for
// proper advance reservation), there is no mismatch between predicted
// and rendered layout. Empty space is minimised because we always pick
// the largest pair that fits; overflow is prevented because a pair only
// wins if it actually fits.
//
// Opening spread (pages 1 & 2) pass a custom ceiling (34 sp) and base
// ratio (2.0) via the parameters; same ladder otherwise.

/// Result of the page-sizing search — both values are needed because
/// the emergency-rhythm tier adjusts the line-height ratio, not just
/// the body sp.
private struct PageSizing {
    let bodySp:     CGFloat
    let lineHRatio: CGFloat
}

private func adaptivePageSizing(
    in size:        CGSize,
    groups:         [SurahGroup],
    font:           QuranFontInfo,
    theme:          ThemeColors,
    maxBodySp:      CGFloat,
    baseLineHRatio: CGFloat
) -> PageSizing {
    guard size.width > 1, size.height > 1, !groups.isEmpty else {
        return PageSizing(bodySp: Sizing.minBodySp, lineHRatio: baseLineHRatio)
    }

    // ── Banner footprint ────────────────────────────────────────────────
    //
    // Banner height depends on body sp (the ornamental Basmala scales
    // with it). Computed fresh for each candidate sp so the budget is
    // always honest.
    func bannerPx(at sp: CGFloat) -> CGFloat {
        var total: CGFloat = 0
        for g in groups where g.ayahs.first?.ayah == 1 {
            let hasBas = g.surahIndex != 1
                      && g.surahIndex != WarattilConstants.Mushaf.surahTawbah
            total += Sizing.bannerBaseDp
            if hasBas {
                total += 10 + (sp * Sizing.basmalaRatio * 1.40)
            }
        }
        return total
    }

    /// Line count at a given body sp. Line count depends only on sp
    /// (horizontal layout); lineHRatio never changes it because
    /// justification stretches lines via kashida within a line, not
    /// by re-breaking. Factored out so the stretch pass (below) can
    /// reuse it without re-running the typesetter.
    func measuredLineCount(sp: CGFloat) -> Int {
        var lineCount = 0
        for g in groups {
            let display = g.displayAyahs()
            if display.isEmpty { continue }
            let attr = buildAyahAttributed(
                ayahs:  display,
                font:   font,
                theme:  theme,
                bodySp: sp
            )
            let wrapped = KashidaCoreTextView.wrapAttachments(in: attr)
            let lines = KashidaCoreTextView.buildLines(
                attributed: wrapped, width: size.width
            )
            lineCount += lines.count
        }
        return lineCount
    }

    /// EXACT measured body height at (sp, ratio). Builds the real
    /// rendered attributed string (with rosette NSTextAttachments),
    /// wraps the attachments in CTRunDelegates so CoreText reserves
    /// the correct advance width, breaks into lines via the same
    /// `CTTypesetterSuggestLineBreak` the renderer uses, and returns
    /// `lineCount × (sp × ratio)`.
    func measuredBodyHeight(sp: CGFloat, ratio: CGFloat) -> CGFloat {
        CGFloat(measuredLineCount(sp: sp)) * sp * ratio
    }

    /// Does (sp, ratio) fit in the page budget?
    func fits(sp: CGFloat, ratio: CGFloat) -> Bool {
        let budget = size.height * Sizing.safetyFactor
        let used   = bannerPx(at: sp) + measuredBodyHeight(sp: sp, ratio: ratio)
        return used <= budget
    }

    // ── Tier 1: binary search in the comfort window at base ratio ───────
    let hiCap = max(Sizing.minBodySp, min(maxBodySp, Sizing.maxBodySp))
    var lo: CGFloat = Sizing.minBodySp
    var hi: CGFloat = hiCap
    var bestComfort: CGFloat = 0       // 0 = "no comfort fit found yet"

    for _ in 0..<Sizing.searchIterations {
        let mid = (lo + hi) / 2
        if fits(sp: mid, ratio: baseLineHRatio) {
            bestComfort = mid
            lo = mid
        } else {
            hi = mid
        }
    }
    if bestComfort > 0 {
        let clamped = min(max(bestComfort, Sizing.minBodySp), hiCap)

        // ── Vertical-fill stretch ────────────────────────────────────
        //
        // After the binary search picks the largest sp that fits at
        // the base rhythm, sparse pages (few ayahs → short text block)
        // still leave visible empty space at the top/bottom because
        // sp is capped at `maxBodySp`. To make page heights feel
        // consistent across the 604-page Mushaf, we grow the
        // line-height ratio to soak up the remaining slack.
        //
        // The stretch is mathematically exact: we know the rendered
        // line count at `clamped` sp, and line count does NOT change
        // with ratio (kashida stretches lines horizontally, not
        // vertically). So we can solve directly for the ratio that
        // fills the budget:
        //
        //    stretched = baseRatio + slack / (lineCount × sp)
        //
        // Capped at `Sizing.maxStretchRatio` (2.20) so a page with
        // only 2–3 lines (e.g. the end of a very short surah that
        // straddles a page boundary) doesn't produce absurdly
        // over-spaced lines that look alien next to normal pages.
        let lineCount = measuredLineCount(sp: clamped)
        guard lineCount > 0 else {
            return PageSizing(bodySp: clamped, lineHRatio: baseLineHRatio)
        }

        let budget = size.height * Sizing.safetyFactor
        let used   = bannerPx(at: clamped) + CGFloat(lineCount) * clamped * baseLineHRatio
        let slack  = budget - used
        if slack > 0 {
            let extraRatio  = slack / (CGFloat(lineCount) * clamped)
            let stretched   = baseLineHRatio + extraRatio
            let cappedRatio = min(stretched, Sizing.maxStretchRatio)
            return PageSizing(bodySp: clamped, lineHRatio: cappedRatio)
        }
        return PageSizing(bodySp: clamped, lineHRatio: baseLineHRatio)
    }

    // ── Tier 2: emergency sp shrink at base ratio ───────────────────────
    //
    // Walk down sp in 1-pt steps from (minBodySp − 1) to emergencyMinBodySp
    // inclusive. First sp that fits wins.
    var sp = Sizing.minBodySp - 1
    while sp >= Sizing.emergencyMinBodySp {
        if fits(sp: sp, ratio: baseLineHRatio) {
            return PageSizing(bodySp: sp, lineHRatio: baseLineHRatio)
        }
        sp -= 1
    }

    // ── Tier 3: emergency rhythm at the sp floor ────────────────────────
    //
    // At sp = emergencyMinBodySp, tighten the line-height ratio in
    // descending order. These ratios are still legible (1.25 is the
    // minimum where Uthmani ascenders don't collide with the next
    // line's descenders for our font).
    let tightRatios: [CGFloat] = [1.60, 1.50, 1.40, 1.30, 1.25]
    for ratio in tightRatios {
        if fits(sp: Sizing.emergencyMinBodySp, ratio: ratio) {
            return PageSizing(
                bodySp:     Sizing.emergencyMinBodySp,
                lineHRatio: ratio
            )
        }
    }

    // ── Last resort: return the tightest setting. In theory unreachable
    //    on the printed Mushaf, because even the densest page (Al-Baqarah
    //    page 6) fits at 18 sp × 1.70 = 30.6 pt per line with room to
    //    spare. Fallback exists only to guarantee a total function.
    return PageSizing(
        bodySp:     Sizing.emergencyMinBodySp,
        lineHRatio: 1.25
    )
}

private func resolveUIFont(font: QuranFontInfo, size: CGFloat) -> UIFont {
    if let ps = font.postScriptName, let ui = UIFont(name: ps, size: size) {
        return ui
    }
    return UIFont.systemFont(ofSize: size)
}

// =============================================================================
// MARK: - Shared attributed-string builder
// =============================================================================
//
// Single source of truth for the Mushaf body's NSAttributedString. Used
// both by the renderer (AyahBlock.nsAttributed) AND the adaptive fit
// engine (adaptivePageSizing). Sharing this function is what makes the
// adaptive engine's predicted line count match the renderer's actual
// line count pixel-for-pixel — the engine no longer approximates the
// marker width with " ﴿N﴾ " Unicode; it builds the real rosette
// NSTextAttachment and measures against that.
//
//   • Each ayah text is concatenated with an NBSP, a rosette
//     NSTextAttachment for the ayah number, and a trailing NBSP.
//   • Every body run carries `kCTLanguageAttributeName = "ar"` so
//     CoreText's Arabic shaping path (joining-form selection + kashida
//     fallbacks) engages regardless of string-level language heuristics.
private func buildAyahAttributed(
    ayahs:           [Ayah],
    font:            QuranFontInfo,
    theme:           ThemeColors,
    bodySp:          CGFloat,
    searchHighlight: String? = nil
) -> NSAttributedString {
    let out    = NSMutableAttributedString()
    let bodyUI = resolveUIFont(font: font, size: bodySp)
    let textColor = UIColor(theme.text)
    let langKey = NSAttributedString.Key(kCTLanguageAttributeName as String)

    // NOTE: NO `.paragraphStyle` key here.
    //
    // An earlier attempt attached a paragraph style with
    // `baseWritingDirection = .rightToLeft` at this layer, intending to
    // improve CTLineCreateJustifiedLine's kashida decisions inside
    // KashidaCoreTextView. That change leaked into the CENTERED render
    // path (ArabicTextLabel, used on pages 1–2), where UILabel honored
    // the paragraph style and visibly altered glyph layout across the
    // whole Mushaf. Nasser reported it 2026-04-22: "you changed the font
    // in all the pages".
    //
    // The lesson: `buildAyahAttributed` is shared by both the
    // UILabel-based centered path AND the CoreText-based justified path.
    // Writing-direction attributes belong at the CoreText render site,
    // not at the shared attributed-string builder. If a future change
    // needs an RTL paragraph style for kashida, it should be applied
    // inside `KashidaCoreTextView` only — leaving this builder's output
    // unchanged so the centered path renders exactly as it did before.
    let bodyAttrs: [NSAttributedString.Key: Any] = [
        .font:            bodyUI,
        .foregroundColor: textColor,
        langKey:          "ar"
    ]

    // Search-highlight tint — warm gold at 32 % alpha. Brighter than the
    // long-press selection (theme.accent at 14 %) so the two read as
    // distinct states even when both fire on the same ayah. Mirrors
    // Android's `MushaFBody.kt :: highlightBg` (HIFZ_GOLD @ 0.32).
    //
    // Applying `.backgroundColor` does NOT alter glyph metrics, so the
    // adaptive-fit measurement pass (which calls `buildAyahAttributed`
    // with `searchHighlight == nil`) still produces an identical line
    // count to the rendered string — no need for an opt-out path.
    let highlightBg = UIColor(WarattilConstants.Hifz.hifzGold).withAlphaComponent(0.32)
    let hasHighlight: Bool = {
        if let q = searchHighlight?.trimmingCharacters(in: .whitespacesAndNewlines),
           !q.isEmpty { return true }
        return false
    }()
    var highlightAttrs = bodyAttrs
    highlightAttrs[.backgroundColor] = highlightBg

    for a in ayahs {
        guard let raw = a.text?.trimmingCharacters(in: .whitespaces).stripAnnotations(),
              let n = a.ayah else { continue }

        // Compute search-highlight ranges against the post-stripAnnotations
        // text. Ranges are in scalar-offset coordinates which equal UTF-16
        // offsets for BMP-only Arabic — see SearchHighlight.swift's header
        // comment for the BMP-equivalence justification.
        let ranges: [Range<Int>] = hasHighlight
            ? findHighlightRanges(text: raw, query: searchHighlight!)
            : []

        if ranges.isEmpty {
            out.append(NSAttributedString(string: raw, attributes: bodyAttrs))
        } else {
            // Walk the text in [non-highlight | highlight | …] alternating
            // chunks. Each chunk gets its own attributes so the gold
            // background paints exactly the matched character ranges
            // (including embedded diacritics that fall inside the original
            // word). Mirrors `MushaFBody.kt`'s walking loop byte-for-byte.
            //
            // We slice via `NSRange` over the NSAttributedString length —
            // safe because each range originates from a scalar walk over
            // the SAME `raw` string we're slicing here, and Quran text is
            // BMP-only so 1 scalar == 1 UTF-16 unit == 1 NSAttributedString
            // offset.
            let nsRaw = raw as NSString
            let totalLen = nsRaw.length
            var cursor = 0
            for r in ranges {
                let s = max(0, min(r.lowerBound, totalLen))
                let e = max(0, min(r.upperBound, totalLen))
                if s > cursor {
                    let chunk = nsRaw.substring(with: NSRange(location: cursor, length: s - cursor))
                    out.append(NSAttributedString(string: chunk, attributes: bodyAttrs))
                }
                if e > s {
                    let chunk = nsRaw.substring(with: NSRange(location: s, length: e - s))
                    out.append(NSAttributedString(string: chunk, attributes: highlightAttrs))
                }
                cursor = e
            }
            if cursor < totalLen {
                let chunk = nsRaw.substring(with: NSRange(location: cursor, length: totalLen - cursor))
                out.append(NSAttributedString(string: chunk, attributes: bodyAttrs))
            }
        }

        out.append(NSAttributedString(string: "\u{00A0}", attributes: bodyAttrs))

        let att = AyahRosetteRenderer.attachment(
            number:   n,
            bodySize: bodySp,
            theme:    theme
        )
        out.append(NSAttributedString(attachment: att))
        out.append(NSAttributedString(string: "\u{00A0}", attributes: bodyAttrs))
    }
    return out
}

// =============================================================================
// MARK: - Ayah block — one Text per SurahGroup, with inline coloured markers
// =============================================================================

private struct AyahBlock: View {
    let ayahs:     [Ayah]
    let font:      QuranFontInfo
    let theme:     ThemeColors
    let bodySp:    CGFloat
    let lineH:     CGFloat
    let centered:  Bool
    let viewModel: MushaFViewModel

    /// Selection callback — called when the user picks an ayah from the
    /// long-press menu. The host (PageBody) drives the floating action bar
    /// off this value.
    let onSelect:  (AyahSelection) -> Void

    /// Which ayah (if any) should the long-press menu present? Having this as
    /// state lets us defer picking until the user actually long-presses, and
    /// lets us dismiss the menu when the picker closes without side effects.
    @State private var pickerPresented: Bool = false

    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        // Rendering paths split by alignment:
        //
        //   • Centered (opening spread, pages 1 & 2) — routes through
        //     `ArabicTextLabel` with `.center`. UILabel's centered layout
        //     of short Arabic runs is pixel-perfect; no reason to rebuild.
        //
        //   • Dense body (every other page) — routes through
        //     `KashidaArabicText` with `.justified`. CoreText's
        //     `CTLineCreateJustifiedLine(line, 1.0, width)` inserts
        //     kashida/tatweel on every middle line so the glyph run
        //     touches the column's left edge — this is the printed-
        //     Madinah Mushaf silhouette Nasser wants (2026-04-22 after a
        //     back-and-forth where we briefly tried `.right` UILabel
        //     alignment and he sent back a kashida-justified reference
        //     page: "return the font used, like the attached screen").
        //     The last line is right-anchored by KashidaCoreTextView's
        //     own drawing code rather than UILabel's broken `.justified`
        //     last-line fallback.
        Group {
            if centered {
                ArabicTextLabel(
                    attributed: nsAttributed,
                    lineHeight: lineH,
                    alignment:  .center
                )
            } else {
                KashidaArabicText(
                    attributed: nsAttributed,
                    lineHeight: lineH,
                    alignment:  .justified
                )
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        // Long-press drives ayah selection. If the block has a single ayah
        // we skip the picker entirely — faster, and matches Android's
        // "long-press = select this ayah" behaviour exactly. With multiple
        // ayahs, iOS lacks the per-glyph hit-testing Android uses; a
        // confirmation dialog listing the ayahs by number is the cleanest
        // fallback that still feels native.
        .onLongPressGesture(minimumDuration: 0.35) {
            haptic.impactOccurred()
            let selectable = ayahs.compactMap { a -> AyahSelection? in
                guard let s = a.surah, let n = a.ayah else { return nil }
                return AyahSelection(surah: s, ayah: n)
            }
            if selectable.count == 1 {
                onSelect(selectable[0])
            } else if selectable.count > 1 {
                pickerPresented = true
            }
        }
        .confirmationDialog(
            "اختر آية",
            isPresented: $pickerPresented,
            titleVisibility: .visible
        ) {
            ForEach(ayahs.compactMap { a -> AyahSelection? in
                guard let s = a.surah, let n = a.ayah else { return nil }
                return AyahSelection(surah: s, ayah: n)
            }) { sel in
                Button(viewModel.ayahLabelCompact(surah: sel.surah, ayah: sel.ayah)) {
                    onSelect(sel)
                }
            }
            Button("إلغاء", role: .cancel) { }
        }
    }

    /// Thin wrapper over `buildAyahAttributed` — kept for API-locality with
    /// the rest of `AyahBlock`. The builder is module-level so the adaptive
    /// fit engine can construct the SAME attributed string for its
    /// measurement pass, guaranteeing that predicted line count = actual
    /// rendered line count.
    ///
    /// Reads `viewModel.searchHighlight` so the body re-renders whenever
    /// a search-result tap sets / clears the inline highlight. The
    /// adaptive-fit measure pass (`measuredLineCount` in `PageBody`) calls
    /// `buildAyahAttributed` without a highlight argument — line count is
    /// identical with or without the gold background, so reusing the
    /// measure-pass output for layout stays correct.
    private var nsAttributed: NSAttributedString {
        buildAyahAttributed(
            ayahs:           ayahs,
            font:            font,
            theme:           theme,
            bodySp:          bodySp,
            searchHighlight: viewModel.searchHighlight
        )
    }

}

// =============================================================================
// MARK: - Surah banner — name plate + optional ornamental Basmala
// =============================================================================
//
//   ┌──── Rule ────────────────────────────────────────────────────────────┐
//   │  Al-Fatiha (1)        Banner: name plate only (Basmala is ayah 1).   │
//   │  At-Tawbah (9)        Banner: name plate only (no Basmala).          │
//   │  Every other surah    Banner: name plate + ornamental Basmala.       │
//   └──────────────────────────────────────────────────────────────────────┘

private struct SurahBanner: View {
    let group:       SurahGroup
    let theme:       ThemeColors
    let font:        QuranFontInfo
    let isLandscape: Bool
    let bodySp:      CGFloat

    var body: some View {
        let surahIndex = group.surahIndex
        let name = MetadataParser.shared.getSuraName(surahIndex)
        let isFatiha = surahIndex == 1
        let isTawbah = surahIndex == WarattilConstants.Mushaf.surahTawbah
        let showBasmala = !isFatiha && !isTawbah

        let titleSize  = isLandscape ? Sizing.titleSizeLandscape : Sizing.titleSizePortrait
        let basmalaSp  = bodySp * Sizing.basmalaRatio

        let plateHeight = isLandscape
            ? Sizing.bannerPlateHeightLandscape
            : Sizing.bannerPlateHeightPortrait

        // Lozenge corner radius: roughly 1/3 of the plate height gives the
        // "cartouche end" silhouette — fully rounded ends would look like
        // a pill, straight-cornered would look like a plain rectangle.
        let cornerR = plateHeight / 3.2

        VStack(spacing: 0) {
            // Name-plate cartouche with double-rule Deep-Gold border and
            // drawn arabesque flourishes flanking the title. Aesthetic
            // reference is the Golden Quran (Nasser 2026-04-21).
            //
            // Layout strategy: the whole ZStack is clamped to `plateHeight`.
            // The title + flourishes sit in an HStack centred inside, and
            // the line box is clipped so Amiri's deep ascenders can't push
            // anything outside the stroked border.
            ZStack {
                // Background fill — cream bannerBg
                RoundedRectangle(cornerRadius: cornerR)
                    .fill(theme.bannerBg)

                // Outer gold stroke — primary border
                RoundedRectangle(cornerRadius: cornerR)
                    .stroke(theme.gold, lineWidth: 1.5)

                // Inner gold stroke — classic double-rule. Inset 3 pt so
                // the two strokes read as deliberately paired rather than
                // as a single thick border.
                RoundedRectangle(cornerRadius: max(cornerR - 3, 2))
                    .stroke(theme.gold.opacity(0.55), lineWidth: 0.7)
                    .padding(3)

                // Title flanked by arabesque flourishes. Mirroring the
                // right-hand flourish gives the cartouche its symmetric
                // scrollwork silhouette.
                HStack(spacing: 12) {
                    BannerFlourish(theme: theme, mirrored: false)

                    Text("سُورَةُ \(name)")
                        .font(bannerFont(size: titleSize))
                        .foregroundStyle(theme.gold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .multilineTextAlignment(.center)
                        .environment(\.layoutDirection, .rightToLeft)

                    BannerFlourish(theme: theme, mirrored: true)
                }
                .padding(.horizontal, 14)
            }
            .frame(maxWidth: .infinity)
            .frame(height: plateHeight)
            .clipped()
            .padding(.horizontal, 20) // reserve ~10% inset on each side

            if showBasmala {
                Text(WarattilConstants.Mushaf.basmala)
                    .font(font.font(size: basmalaSp).weight(.bold))
                    .foregroundStyle(theme.text.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .environment(\.layoutDirection, .rightToLeft)
                    .lineSpacing((basmalaSp * 1.30) - basmalaSp)
                    // 2 → 10 pt opens a clear gap under the plate so the
                    // Basmala reads as its own beat rather than sitting on
                    // the box's underside.
                    .padding(.top, 10)
            }
            Spacer().frame(height: 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    /// Amiri-Bold → Amiri-Regular → system-serif. Falls back silently if the
    /// classical naskh faces are not registered — banner is never blank.
    private func bannerFont(size: CGFloat) -> Font {
        if UIFont(name: "Amiri-Bold", size: size) != nil {
            return .custom("Amiri-Bold", size: size)
        }
        if UIFont(name: WarattilConstants.Mushaf.fontFallback, size: size) != nil {
            return Font.custom(WarattilConstants.Mushaf.fontFallback, size: size).weight(.bold)
        }
        return .system(size: size, weight: .bold, design: .serif)
    }
}

/// Arabesque flourish drawn at each end of the Surah banner cartouche.
///
/// The Golden Quran reference app uses custom vector art at the ends of
/// its banner — curled scrollwork with a central dot, evoking the
/// manuscript tradition of illuminated sura headings. Replicating that
/// exactly would mean committing to a full Bezier-path vector library;
/// this is a restrained approximation that captures the silhouette:
///
///   • a soft cubic curve sweeping from the outer edge inward, stroked
///     in gold and rounded at both caps so it reads as a scroll rather
///     than as an isolated line;
///   • a filled gold disc sitting on the curve's horizontal midline,
///     acting as the "anchor bead" that printed Mushafs place at the
///     centre of an end-ornament;
///
/// `mirrored = true` flips the curl left-to-right so the right-hand
/// flourish mirrors the left-hand one symmetrically. Size is deliberately
/// small (22 × 18 pt) — at the 58 pt plate height this reads as an accent
/// beside the title rather than as a competing element.
private struct BannerFlourish: View {
    let theme:    ThemeColors
    let mirrored: Bool

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            // Scroll curve — a shallow S pulled horizontally so it reads
            // as a sweep from the outer edge inward. Rounded line caps
            // soften the ends so the stroke doesn't feel clipped.
            var curl = Path()
            curl.move(to: CGPoint(x: w * 0.92, y: h * 0.50))
            curl.addCurve(
                to: CGPoint(x: w * 0.10, y: h * 0.50),
                control1: CGPoint(x: w * 0.70, y: h * 0.05),
                control2: CGPoint(x: w * 0.30, y: h * 0.95)
            )
            context.stroke(
                curl,
                with: .color(theme.gold),
                style: StrokeStyle(lineWidth: 1.0, lineCap: .round)
            )

            // Anchor bead — small filled disc on the scroll's midline.
            let r: CGFloat = 1.8
            var dot = Path()
            dot.addEllipse(in: CGRect(
                x: w * 0.50 - r,
                y: h * 0.50 - r,
                width: r * 2, height: r * 2
            ))
            context.fill(dot, with: .color(theme.gold))
        }
        .frame(width: 22, height: 18)
        .scaleEffect(x: mirrored ? -1 : 1, y: 1)
    }
}

// =============================================================================
// MARK: - Arabic text label (UIKit bridge)
// =============================================================================
//
// SwiftUI's `Text` only supports `.leading`, `.trailing`, and `.center` —
// no justified text — and cannot render `NSTextAttachment` images inline
// with glyphs. UIKit's `UILabel` does both (it internally wraps each
// attachment in a CTRunDelegate so CoreText reserves the correct advance
// width), which is why every Mushaf page on iOS flows through this
// wrapper.
//
// Alignment note: `.justified` on RTL Arabic triggers UIKit's kashida
// insertion (the tatweel ـ stretches inside letters like ب ت ح etc.) so
// middle lines fill the column edge-to-edge — matches the printed
// Madinah Mushaf and the Golden Quran app reference. The well-known
// UIKit tradeoff is that the last-line fallback for `.justified` does
// NOT honour `paragraph.baseWritingDirection` reliably on iOS 17/18, so
// a short final verse can flush visually LEFT. Nasser chose this
// tradeoff over the alternative (`.right` alignment loses kashida and
// produces short middle lines that don't touch the left margin).
//
// Full Madinah parity (kashida middle + right-anchored last line) needs
// a custom CoreText pipeline that rebuilds each line via
// `CTLineCreateJustifiedLine` with manual CTRunDelegate wrapping for
// the rosette `NSTextAttachment`s. That work is deferred.
//
// Features:
//   • `alignment` — `.justified` for dense body pages, `.center` for the
//     opening-spread (pages 1 & 2) rounded silhouette.
//   • `lineHeight` — locks line rhythm to the adaptive engine's assumption
//     (body × 1.70 normally, body × 2.0 for the opening spread).
//   • `sizeThatFits` reports intrinsic height, so SwiftUI's
//     `.fixedSize(horizontal: false, vertical: true)` makes the container
//     grow to hold the fully laid-out text block.
private struct ArabicTextLabel: UIViewRepresentable {
    let attributed: NSAttributedString
    let lineHeight: CGFloat
    let alignment:  NSTextAlignment   // .justified (dense) or .center (opening spread)

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = alignment
        label.semanticContentAttribute = .forceRightToLeft
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.textAlignment = alignment

        let paragraph = NSMutableParagraphStyle()
        // Use the caller-supplied alignment (.right for dense body pages,
        // .center for the opening spread). We used to set .justified here
        // and rely on `baseWritingDirection = .rightToLeft` to right-align
        // the last line, but UIKit's `.justified` last-line fallback
        // doesn't honour baseWritingDirection reliably on iOS 17/18 —
        // short final verses flushed LEFT instead of RIGHT. Since Arabic
        // word-space justification barely stretches anything without
        // kashida anyway (and the adaptive engine picks a body size where
        // each line naturally fills the column), `.right` produces the
        // same visual for middle lines AND deterministically right-
        // anchors the last line.
        paragraph.alignment = alignment
        paragraph.baseWritingDirection = .rightToLeft
        paragraph.lineBreakMode = .byWordWrapping
        // Minimum + maximum line height locks the line rhythm to the adaptive
        // engine's assumption. Without this, UIKit picks a smaller line
        // height and the page overshoots or leaves whitespace at the bottom.
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight

        // Overlay the paragraph style onto the entire string while keeping
        // every other per-character attribute (font, colour, attachments)
        // intact.
        let mutable = NSMutableAttributedString(attributedString: attributed)
        mutable.addAttribute(
            .paragraphStyle,
            value: paragraph,
            range: NSRange(location: 0, length: mutable.length)
        )
        label.attributedText = mutable
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UILabel,
        context: Context
    ) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width
        let fitting = uiView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        return CGSize(width: width, height: ceil(fitting.height))
    }
}

// =============================================================================
// MARK: - Kashida + right-anchored-last-line text (CoreText)
// =============================================================================
//
// WHY THIS EXISTS
// ---------------
// UIKit's `UILabel` with `NSTextAlignment.justified` + `baseWritingDirection =
// .rightToLeft` inserts kashida on middle lines (tatweel stretches letters
// like ب ت ح ل ن to fill the column edge-to-edge) but its last-line fallback
// does NOT reliably honour `baseWritingDirection` on iOS 17/18 — a short
// final verse can flush visually LEFT instead of RIGHT.
//
// Switching to `.right` alignment fixes the last-line problem but loses the
// kashida middle-line fill: middle lines become short right-aligned runs that
// don't touch the left margin, breaking the printed-Madinah-Mushaf silhouette.
//
// This view reimplements the layout pass via CoreText so we get BOTH things
// at the same time: every line except the last is justified via
// `CTLineCreateJustifiedLine` (which triggers the same kashida insertion
// UILabel uses), and the last line is drawn with its typographic origin
// pinned to the right edge of the column.
//
// LAYOUT PIPELINE
// ---------------
//  1. `wrapAttachments` — walks the attributed string and wraps every
//     `NSTextAttachment` in a `CTRunDelegate` that reports the attachment's
//     width / ascent / descent. Without this CoreText reserves zero advance
//     for attachments and the rosette ayah markers collapse to nothing.
//  2. `CTTypesetterCreateWithAttributedString` + `CTTypesetterSuggestLineBreak`
//     breaks the prepared string into `CTLine`s that fit the column width.
//  3. Each non-last line is passed through `CTLineCreateJustifiedLine(line,
//     1.0, columnWidth)`. With `justificationFactor = 1.0` CoreText fills
//     the line to the column width, inserting kashida inside Arabic runs.
//  4. The last line is drawn verbatim (unjustified) with its x-origin set
//     to `columnWidth − typographicWidth`, right-anchoring it.
//  5. For each line we walk the runs and manually draw any attachment
//     images — CoreText's `CTLineDraw` handles glyphs but not the image
//     payload of `NSTextAttachment`. The rosette image is composited
//     on top of the run's position, flipped back to screen orientation.
//
// COORDINATE SYSTEM
// -----------------
// CoreText expects a Y-up coordinate system (origin at bottom-left, y
// increases upward). UIKit's default context is Y-down. We flip the
// context once at the top of `draw(_:)` with
// `translateBy(0, height) + scaleBy(1, -1)`. Attachment images are drawn
// inside their own `saveGState/restoreGState` pair with a local flip so
// they render right-side-up even though the outer context is Y-up.
//
// RHYTHM
// ------
// All baselines are placed exactly `lineHeight` apart, anchored off the
// body font's ascent / descent so Uthmani fonts with unusual intrinsic
// metrics don't drift vertically from the `adaptiveBodySp` height
// prediction. The rhythm matches UILabel's `minimum/maximumLineHeight`
// lock, which is what the adaptive engine measures against.
//
// FALLBACK
// --------
// If anything unexpected happens (zero-width column, empty typesetter,
// CTLineCreateJustifiedLine returning nil for a given line), we draw the
// line un-justified at x=0 rather than crashing. The caller can always
// flip `AyahBlock` back to `ArabicTextLabel` with a one-line change.

import CoreText

/// SwiftUI wrapper around `KashidaCoreTextView`. Drop-in replacement for
/// `ArabicTextLabel` — same signature.
private struct KashidaArabicText: UIViewRepresentable {
    let attributed: NSAttributedString
    let lineHeight: CGFloat
    let alignment:  NSTextAlignment   // .justified (normal) or .right (plain RTL)

    func makeUIView(context: Context) -> KashidaCoreTextView {
        let v = KashidaCoreTextView()
        v.backgroundColor = .clear
        v.isOpaque = false
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return v
    }

    func updateUIView(_ view: KashidaCoreTextView, context: Context) {
        view.configure(
            attributed: attributed,
            lineHeight: lineHeight,
            alignment:  alignment
        )
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: KashidaCoreTextView,
        context: Context
    ) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width
        let h = KashidaCoreTextView.measuredHeight(
            attributed: attributed,
            lineHeight: lineHeight,
            width:      width
        )
        return CGSize(width: width, height: ceil(h))
    }
}

/// UIView subclass that owns the CoreText layout + draw pipeline.
///
/// Kept as a plain `UIView` (not `UILabel`) because we override `draw(_:)`
/// entirely — letting `UILabel` run its own layout in the background would
/// just waste cycles, and its attributedText round-trips any CTRunDelegate
/// we attach through NSCoding, which drops the delegate.
private final class KashidaCoreTextView: UIView {

    // ── Configuration ─────────────────────────────────────────────────────

    private var attributed: NSAttributedString = NSAttributedString()
    private var lineHeight: CGFloat = 0
    private var alignment:  NSTextAlignment = .justified

    /// Cache the CTRunDelegate-wrapped version keyed by the original
    /// attributed string's object identity. SwiftUI typically passes a
    /// fresh `NSAttributedString` on every update so the cache is mostly
    /// warm-for-one. Still faster than rebuilding delegates twice
    /// (measurement pass + draw pass).
    private var cachedWrapped: (source: NSAttributedString, wrapped: NSAttributedString)?

    func configure(
        attributed: NSAttributedString,
        lineHeight: CGFloat,
        alignment:  NSTextAlignment
    ) {
        var changed = false
        if self.attributed !== attributed && self.attributed != attributed {
            self.attributed = attributed
            cachedWrapped = nil
            changed = true
        }
        if self.lineHeight != lineHeight {
            self.lineHeight = lineHeight
            changed = true
        }
        if self.alignment != alignment {
            self.alignment = alignment
            changed = true
        }
        if changed {
            invalidateIntrinsicContentSize()
            setNeedsDisplay()
        }
    }

    // ── UIView hooks ──────────────────────────────────────────────────────

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let w = size.width > 0 ? size.width : bounds.width
        guard w > 1 else { return .zero }
        let h = KashidaCoreTextView.measuredHeight(
            attributed: attributed, lineHeight: lineHeight, width: w
        )
        return CGSize(width: w, height: ceil(h))
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(),
              attributed.length > 0,
              rect.width > 1 else { return }

        let wrapped = wrappedAttributedString()
        let lines   = KashidaCoreTextView.buildLines(
            attributed: wrapped, width: rect.width
        )
        guard !lines.isEmpty else { return }

        // Flip to CoreText's Y-up coordinate system.
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.translateBy(x: 0, y: rect.height)
        ctx.scaleBy(x: 1, y: -1)

        // Anchor baselines off the body font so rhythm matches the
        // adaptive engine's height prediction exactly, regardless of
        // per-line metric variation introduced by rosette attachments.
        let bodyFont = primaryFont(in: wrapped)
        let fAscent  = bodyFont.ascender
        let fDescent = abs(bodyFont.descender)
        let topLead  = max(0, (lineHeight - fAscent - fDescent) / 2)

        for (i, line) in lines.enumerated() {
            let isLast = (i == lines.count - 1)

            // Justify non-last lines; last line stays native so we can
            // right-anchor it below.
            let drawLine: CTLine = {
                if isLast { return line }
                if let j = CTLineCreateJustifiedLine(line, 1.0, Double(rect.width)) {
                    return j
                }
                return line
            }()

            // Typographic width of the line (visible, excluding trailing
            // whitespace). Needed to right-anchor the last line.
            let lineWidth = CGFloat(CTLineGetTypographicBounds(
                drawLine, nil, nil, nil
            ))

            // X origin: justified lines fill to (0…W) already; the last
            // line we manually push to the right edge to achieve RTL
            // right-anchor.
            let xOrigin: CGFloat = isLast
                ? max(0, rect.width - lineWidth)
                : 0

            // Baseline in CT (flipped) coords: first line sits just under
            // the top of the rect, each subsequent line lineHeight lower.
            let baselineY = rect.height
                - topLead - fAscent
                - CGFloat(i) * lineHeight

            ctx.textPosition = CGPoint(x: xOrigin, y: baselineY)
            CTLineDraw(drawLine, ctx)

            // CoreText renders glyphs but NOT NSTextAttachment payloads —
            // we walk the runs ourselves and composite the rosette images
            // at the positions CoreText reserved (via the CTRunDelegate).
            drawAttachments(
                in: drawLine,
                ctx: ctx,
                xOrigin: xOrigin,
                baselineY: baselineY
            )
        }

        ctx.restoreGState()
    }

    // ── Height measurement (static, reusable by SwiftUI sizeThatFits) ─────

    /// Computes total render height without touching any instance state.
    /// Used by both `KashidaArabicText.sizeThatFits` and the instance's
    /// own `sizeThatFits` so they can't disagree.
    static func measuredHeight(
        attributed: NSAttributedString,
        lineHeight: CGFloat,
        width:      CGFloat
    ) -> CGFloat {
        guard attributed.length > 0, width > 1 else { return 0 }
        let wrapped = wrapAttachments(in: attributed)
        let lines   = buildLines(attributed: wrapped, width: width)
        return CGFloat(lines.count) * lineHeight
    }

    // ── Line building ─────────────────────────────────────────────────────

    /// Break the attributed string into CTLines that each fit the column.
    /// `CTTypesetterSuggestLineBreak` returns 0 only when nothing more can
    /// be placed — we guard against that to avoid an infinite loop on
    /// pathological inputs.
    fileprivate static func buildLines(
        attributed: NSAttributedString,
        width:      CGFloat
    ) -> [CTLine] {
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        let length     = attributed.length
        var start: CFIndex = 0
        var lines: [CTLine] = []

        while start < length {
            let count = CTTypesetterSuggestLineBreak(
                typesetter, start, Double(width)
            )
            if count <= 0 { break }
            let range = CFRange(location: start, length: count)
            lines.append(CTTypesetterCreateLine(typesetter, range))
            start += count
        }
        return lines
    }

    // ── Attachment handling ───────────────────────────────────────────────

    /// Returns the attributed string with every NSTextAttachment run tagged
    /// with a CTRunDelegate that reports the attachment's width / ascent /
    /// descent. Memoised per-instance so the measurement and draw passes
    /// don't repeat work.
    private func wrappedAttributedString() -> NSAttributedString {
        if let cache = cachedWrapped, cache.source === attributed {
            return cache.wrapped
        }
        let w = KashidaCoreTextView.wrapAttachments(in: attributed)
        cachedWrapped = (attributed, w)
        return w
    }

    fileprivate static func wrapAttachments(
        in input: NSAttributedString
    ) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: input)
        let fullRange = NSRange(location: 0, length: mutable.length)

        let delegateKey = NSAttributedString.Key(kCTRunDelegateAttributeName as String)

        mutable.enumerateAttribute(
            .attachment,
            in: fullRange,
            options: []
        ) { value, range, _ in
            guard let att = value as? NSTextAttachment, att.image != nil else { return }

            let bounds = att.bounds
            // NSTextAttachment.bounds semantics: width/height are the
            // glyph's advance + height; origin.y is the distance from
            // the baseline (negative = below).
            //   ascent  = top of attachment above baseline
            //   descent = depth of attachment below baseline
            let metrics = AttachmentMetrics(
                width:   bounds.width,
                ascent:  max(0, bounds.origin.y + bounds.height),
                descent: max(0, -bounds.origin.y)
            )

            // CTRunDelegate takes a raw pointer as its refCon. We retain
            // the metrics object, hand the raw pointer to CT, and release
            // in the dealloc callback — this is the canonical bridge.
            let refCon: UnsafeMutableRawPointer =
                Unmanaged.passRetained(metrics).toOpaque()

            var callbacks = CTRunDelegateCallbacks(
                version:    kCTRunDelegateCurrentVersion,
                dealloc:    { ptr in
                    Unmanaged<AttachmentMetrics>.fromOpaque(ptr).release()
                },
                getAscent:  { ptr in
                    Unmanaged<AttachmentMetrics>.fromOpaque(ptr)
                        .takeUnretainedValue().ascent
                },
                getDescent: { ptr in
                    Unmanaged<AttachmentMetrics>.fromOpaque(ptr)
                        .takeUnretainedValue().descent
                },
                getWidth:   { ptr in
                    Unmanaged<AttachmentMetrics>.fromOpaque(ptr)
                        .takeUnretainedValue().width
                }
            )

            guard let delegate = CTRunDelegateCreate(&callbacks, refCon) else {
                // If delegate creation fails the retained metrics would
                // leak — release it back out.
                Unmanaged<AttachmentMetrics>.fromOpaque(refCon).release()
                return
            }

            mutable.addAttribute(delegateKey, value: delegate, range: range)
        }

        return mutable
    }

    /// Walk the runs of a line, find any run carrying an NSTextAttachment,
    /// and composite its image at the position CoreText reserved for the
    /// run. CoreText does NOT draw attachment images natively — without
    /// this step the rosettes would be invisible.
    private func drawAttachments(
        in line: CTLine,
        ctx: CGContext,
        xOrigin: CGFloat,
        baselineY: CGFloat
    ) {
        guard let runsRef = CTLineGetGlyphRuns(line) as? [CTRun] else { return }

        for run in runsRef {
            let attrs = CTRunGetAttributes(run) as NSDictionary
            guard let att = attrs[NSAttributedString.Key.attachment] as? NSTextAttachment,
                  let image = att.image,
                  let cg = image.cgImage else { continue }

            // Where does this run sit, horizontally, within the line?
            var pos = CGPoint.zero
            CTRunGetPositions(run, CFRange(location: 0, length: 1), &pos)

            // Attachment bounds are anchored at the baseline: origin.y is
            // negative for glyphs that hang below the baseline. We draw
            // the image in a local box whose bottom-left (in CT Y-up) is
            // at (xOrigin + pos.x + attBounds.origin.x,
            //     baselineY + attBounds.origin.y).
            let b = att.bounds
            let drawRect = CGRect(
                x:      xOrigin + pos.x + b.origin.x,
                y:      baselineY + b.origin.y,
                width:  b.width,
                height: b.height
            )

            // Our outer context is already flipped to Y-up (CoreText
            // convention) at the top of `draw(_:)`. In a Y-up context,
            // `CGContextDrawImage` renders the image right-side-up
            // directly — it's only in UIKit's default Y-down context
            // that you need a local flip to avoid upside-down output.
            //
            // An earlier revision of this function applied a SECOND
            // flip here; that double-flip effectively put us back in a
            // Y-down local context and rendered the rosette upside-down
            // on every page that routed through the CoreText path
            // (i.e. pages 3+; the opening spread on pages 1-2 uses
            // the UILabel path and wasn't affected). Nasser 2026-04-21.
            ctx.draw(cg, in: drawRect)
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    /// Primary font of the attributed string. We always build the body
    /// runs with the same font, so the attribute at index 0 is
    /// representative. Defaults to the system font if somehow absent.
    private func primaryFont(in attr: NSAttributedString) -> UIFont {
        guard attr.length > 0 else { return .systemFont(ofSize: 17) }
        if let f = attr.attribute(.font, at: 0, effectiveRange: nil) as? UIFont {
            return f
        }
        return .systemFont(ofSize: 17)
    }
}

/// Backing store for a CTRunDelegate attached to an NSTextAttachment run.
/// Held via `Unmanaged.passRetained` and released in the delegate's
/// dealloc callback.
private final class AttachmentMetrics {
    let width:   CGFloat
    let ascent:  CGFloat
    let descent: CGFloat
    init(width: CGFloat, ascent: CGFloat, descent: CGFloat) {
        self.width   = width
        self.ascent  = ascent
        self.descent = descent
    }
}
