//
//  AyahMeaningsSheet.swift
//  Warattil
//
//  Ports app/src/main/java/com/warattil/app/ui/AyahMeaningsSheet.kt to Swift.
//
//  WARATTIL — per-ayah meanings sheet (iOS port, 2026-04-27)
//
//  Opened from the AyahActionBar's "📖" book icon.  Scoped to the currently
//  selected ayah; closing the sheet doesn't dismiss the long-press selection.
//
//  Two tabs (RTL — right-most is shown first):
//
//    1. معاني الكلمات  (default — right side)
//         KFGQPC «الميسر في غريب القرآن» — rare-word dictionary keyed by
//         ayah.  Roughly ~5,000 ayat have entries; the rest are "plain"
//         and show the empty-state.
//
//    2. التفسير الميسر  (left side, secondary)
//         KFGQPC «التفسير الميسر» — the canonical condensed Sunni tafseer
//         produced by King Fahd Complex.  Plain explanatory prose that
//         often inlines short Quran quotations marked up in the source
//         with `<span class="aya">…</span>`.  We render those quoted
//         runs gold-tinted + bold so the Quran fragments visually
//         distinguish themselves from the scholarly gloss — same approach
//         Golden Quran takes.
//
//  Tab order rationale (locked feedback memory feedback_warattil_meanings_tab_order):
//  users typically tap 📖 to ask "what does THIS WORD mean?" — a quick scan
//  of a couple of rare-word glosses.  Reading the full tafseer is the rarer
//  mode.  So Ghareeb is the default landing tab; Tafseer is one swipe away.
//
//  Loading model
//  -------------
//  Both tabs kick off their lookups inside an `.onAppear { Task { … } }` so
//  the sheet renders an empty/loading state for a frame, then populates.
//  Subsequent opens are instant (singletons cache after first parse).
//

import SwiftUI

// =============================================================================
// MARK: - AyahMeaningsSheet — sheet entry point
// =============================================================================

struct AyahMeaningsSheet: View {

    let suraNumber: Int
    let ayaNumber:  Int
    let theme:      ThemeColors
    let font:       QuranFontInfo
    let onDismiss:  () -> Void

    /// Logical tab index — 0 = Ghareeb (default, right side in RTL), 1 = Tafseer.
    @State private var selectedTab: Int = 0

    /// nil → still loading; `.empty` payload renders the empty-state.
    @State private var ghareebEntries: [GhareebEntry]? = nil
    @State private var tafseerText:    String?         = nil

    private var surahName: String {
        MetadataParser.shared.getSuraName(suraNumber)
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Drag handle (purely visual; SwiftUI ModalPresentation already
            //    provides one but it floats above our content; this echoes the
            //    Android ModalBottomSheet handle for visual parity).
            Capsule()
                .fill(theme.gold.opacity(0.35))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 16)

            // ── Header — "سورة {name} ﴿n﴾" gold-tinted ────────────────────────
            Text("سورة \(surahName) ﴿\(ayaNumber.toArabicDigits())﴾")
                .font(font.font(size: 17).weight(.bold))
                .foregroundStyle(WarattilConstants.Hifz.hifzGold)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            Divider().background(theme.gold.opacity(0.30))

            // ── Tab strip ────────────────────────────────────────────────────
            MeaningsTabStrip(
                selectedTab: $selectedTab,
                theme:       theme,
                font:        font
            )

            Divider().background(theme.gold.opacity(0.18))

            // ── Tab content — TabView + .page style for swipeable pages.
            //   We use `.tabViewStyle(.page(indexDisplayMode: .never))` so
            //   the dot indicator below doesn't show (we drive selection
            //   from the custom strip above).  `.environment(\.layoutDirection,
            //   .rightToLeft)` is set on the host (presentMeaningsSheet)
            //   but the swipe direction reverses naturally with it.
            TabView(selection: $selectedTab) {
                GhareebTab(
                    entries: ghareebEntries,
                    theme:   theme,
                    font:    font
                )
                .tag(0)

                TafseerTab(
                    text:  tafseerText,
                    theme: theme,
                    font:  font
                )
                .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(minHeight: 240, idealHeight: 360, maxHeight: 480)

            Spacer(minLength: 20)
        }
        .background(theme.background.ignoresSafeArea())
        .environment(\.layoutDirection, .rightToLeft)
        .task(id: AyahKey(sura: suraNumber, aya: ayaNumber)) {
            // Parallel fetch — both lookups are synchronous singleton parses
            // but we hop off the main actor via Task.detached to keep the
            // first sheet-open frame snappy.
            async let g: [GhareebEntry] = await fetchGhareeb(sura: suraNumber, aya: ayaNumber)
            async let t: String         = await fetchTafseer(sura: suraNumber, aya: ayaNumber)
            ghareebEntries = await g
            tafseerText    = await t
        }
    }

    private func fetchGhareeb(sura: Int, aya: Int) async -> [GhareebEntry] {
        await Task.detached(priority: .userInitiated) {
            GhareebLookup.entries(sura: sura, aya: aya)
        }.value
    }

    private func fetchTafseer(sura: Int, aya: Int) async -> String {
        await Task.detached(priority: .userInitiated) {
            TafseerLookup.text(sura: sura, aya: aya) ?? ""
        }.value
    }
}

// =============================================================================
// MARK: - Tab strip — custom 2-pill selector (RTL aware)
//
// Two equal-width tabs, label centered, active tab underlined in gold and
// rendered in the accent colour, inactive tabs in muted body colour.
// Smaller and quieter than SwiftUI's default `Picker(.segmented)`, and
// retains custom font (the segmented picker forces SF Pro Arabic).
// =============================================================================

private struct MeaningsTabStrip: View {
    @Binding var selectedTab: Int
    let theme: ThemeColors
    let font:  QuranFontInfo

    var body: some View {
        HStack(spacing: 0) {
            // RTL: the FIRST pill in this Row appears on the RIGHT.  We
            // render Ghareeb first (right side, default tab 0) and Tafseer
            // second (left side, tab 1) — see file-header rationale.
            TabPill(
                label:    "معاني الكلمات",
                selected: selectedTab == 0,
                onTap:    { withAnimation { selectedTab = 0 } },
                theme:    theme,
                font:     font
            )
            TabPill(
                label:    "التفسير الميسر",
                selected: selectedTab == 1,
                onTap:    { withAnimation { selectedTab = 1 } },
                theme:    theme,
                font:     font
            )
        }
        .padding(.horizontal, 16)
    }
}

private struct TabPill: View {
    let label:    String
    let selected: Bool
    let onTap:    () -> Void
    let theme:    ThemeColors
    let font:     QuranFontInfo

    var body: some View {
        VStack(spacing: 6) {
            Text(label)
                .font(font.font(size: 14).weight(selected ? .bold : .medium))
                .foregroundStyle(
                    selected
                        ? WarattilConstants.Hifz.hifzGold
                        : theme.text.opacity(0.55)
                )
                .multilineTextAlignment(.center)

            // Active-tab underline — gold hairline of half the pill width,
            // transparent placeholder when inactive so the row height
            // doesn't jump on selection change.
            Rectangle()
                .fill(selected
                      ? WarattilConstants.Hifz.hifzGold
                      : theme.gold.opacity(0))
                .frame(height: 2)
                .frame(maxWidth: 100)
                .clipShape(Capsule())
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// =============================================================================
// MARK: - Tafseer tab — mixed-font prose with inlined Quran fragments
// =============================================================================

private struct TafseerTab: View {
    let text:  String?
    let theme: ThemeColors
    let font:  QuranFontInfo

    var body: some View {
        Group {
            if text == nil {
                centeredHint("جاري التحميل…", color: theme.text.opacity(0.5))
            } else if text!.isEmpty {
                centeredHint("لا يوجد تفسير لهذه الآية", color: theme.text.opacity(0.5))
            } else {
                ScrollView {
                    // Prose renders in Amiri (.warattilChrome) — KFGQPC's
                    // tafseer source itself documents that the prose is
                    // meant to be in Uthman Taha Naskh while the Quran
                    // quotes are in Hafs Uthmanic.  Using Hafs Uthmanic
                    // for the prose makes commas «،» and periods «.»
                    // render as ornate Mushaf-style dot-circles, which
                    // users (Nasser, 2026-04-27) reported as confusing
                    // visual noise.  Amiri is a classical Naskh that
                    // renders standard Arabic punctuation cleanly.  The
                    // <span class="aya"> Quran fragments still use
                    // font (Hafs Uthmanic) inside buildTafseerAttributed.
                    Text(buildTafseerAttributed(text!, font: font))
                        .font(.warattilChrome(size: 17))
                        .foregroundStyle(theme.text)
                        .multilineTextAlignment(.trailing)
                        .lineSpacing(7)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .environment(\.layoutDirection, .rightToLeft)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
                .environment(\.layoutDirection, .rightToLeft)
            }
        }
    }

    @ViewBuilder
    private func centeredHint(_ text: String, color: Color) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.warattilChrome(size: 13))
                .foregroundStyle(color)
            Spacer()
        }
    }
}

/// Walks the KFGQPC tafseer source and emits an `AttributedString` that
/// renders inlined Quran fragments (wrapped in `<span class="aya">…</span>`)
/// in a gold-tinted bold style, while the surrounding prose uses the body
/// colour.  Same trick as Android's buildTafseerAttributed.
///
/// The matcher tolerates both `'aya'` and `"aya"` quoting (different KFGQPC
/// distributions have used both) and arbitrary whitespace inside the tag.
/// Anything that doesn't match falls through as plain prose, so a
/// malformed source string degrades gracefully rather than dropping content.
private func buildTafseerAttributed(
    _ text: String,
    font: QuranFontInfo
) -> AttributedString {
    var out = AttributedString()

    // NSRegularExpression because the equivalent Swift Regex literal needs
    // iOS 16+ and we want belt-and-braces compatibility.  This regex is
    // fast enough for ~6 KB strings (the longest tafseer entry).
    let pattern = #"<span\s+class=['"]aya['"]\s*>(.*?)</span>"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
    else {
        out.append(AttributedString(text))
        return out
    }

    let nsText = text as NSString
    let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))

    var cursor = 0
    for match in matches {
        // Append the prose run BEFORE this match — left UNSTYLED so the
        // outer Text's .warattilChrome (Amiri) carries through.  Adding
        // a font attribute here would override the prose font and bring
        // back the Mushaf-style punctuation glyphs we're trying to escape.
        if match.range.location > cursor {
            let prose = nsText.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            out.append(AttributedString(prose))
        }
        // Append the quoted Quran fragment in the highlighted style.
        // Hafs Uthmanic on the quote span so quoted ayah fragments
        // visually match the Mushaf body the reader is looking at —
        // surrounding prose stays in Amiri.
        let inner = nsText.substring(with: match.range(at: 1))
        var styled = AttributedString(inner)
        styled.foregroundColor = WarattilConstants.Hifz.hifzGold
        styled.font = font.font(size: 17).weight(.semibold)
        out.append(styled)
        cursor = match.range.location + match.range.length
    }
    // Append any remaining prose tail
    if cursor < nsText.length {
        let tail = nsText.substring(from: cursor)
        out.append(AttributedString(tail))
    }
    return out
}

// =============================================================================
// MARK: - Ghareeb tab — ordered (phrase, meaning) cards
// =============================================================================

private struct GhareebTab: View {
    let entries: [GhareebEntry]?
    let theme:   ThemeColors
    let font:    QuranFontInfo

    var body: some View {
        Group {
            if entries == nil {
                centeredHint("جاري التحميل…", color: theme.text.opacity(0.5))
            } else if entries!.isEmpty {
                centeredHint("لا توجد كلمات غريبة في هذه الآية", color: theme.text.opacity(0.5))
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(entries!.enumerated()), id: \.offset) { _, entry in
                            MeaningCard(entry: entry, theme: theme, font: font)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    @ViewBuilder
    private func centeredHint(_ text: String, color: Color) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.warattilChrome(size: 13))
                .foregroundStyle(color)
            Spacer()
        }
    }
}

private struct MeaningCard: View {
    let entry: GhareebEntry
    let theme: ThemeColors
    let font:  QuranFontInfo

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            // The Quranic phrase — Uthmani body font so it visually matches
            // the same glyphs the reader sees on the Mushaf page.
            Text("﴿\(entry.phrase)﴾")
                .font(font.font(size: 17).weight(.bold))
                .foregroundStyle(WarattilConstants.Hifz.hifzGold)
                .multilineTextAlignment(.trailing)
                .environment(\.layoutDirection, .rightToLeft)

            // The meaning — Amiri prose so commas «،» and periods «.»
            // render cleanly instead of as Mushaf-style decorative
            // dot-circles (the glyphs Hafs Uthmanic draws for those
            // code points are intended for Quran typesetting only).
            Text(entry.meaning)
                .font(.warattilChrome(size: 15))
                .foregroundStyle(theme.text)
                .multilineTextAlignment(.trailing)
                .lineSpacing(3)
                .environment(\.layoutDirection, .rightToLeft)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .environment(\.layoutDirection, .rightToLeft)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(WarattilConstants.Hifz.hifzGold.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(WarattilConstants.Hifz.hifzGold.opacity(0.30), lineWidth: 0.6)
        )
    }
}
