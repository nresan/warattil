//
//  DailyReadingShareCard.swift
//  Warattil
//
//  WARATTIL V2 — Daily reading status share card (2026-04-23)
//
//  Why this file exists
//  --------------------
//  Readers want to send today's reading progress to a friend/teacher/halaqa
//  group via WhatsApp, Facebook, Twitter, Instagram Stories.  Plain-text
//  payloads drop through in Instagram and lose the aesthetic everywhere else,
//  so we render a self-contained PNG (same `ImageRenderer` pattern used for
//  the Hifz garden snapshot) that carries:
//
//    ┌──────────────────────────────────────────────┐
//    │               ✦  ورد اليوم  ✦                  │
//    │         الخميس · ٢٣ أبريل ٢٠٢٦                   │
//    │                                              │
//    │     ████████████████▒▒▒▒▒▒▒▒  ٦٠٪              │
//    │                                              │
//    │          قرأت ١٢ / ٢٠ صفحة                    │
//    │        سورة البقرة · الجزء ٢                   │
//    │                                              │
//    │         شارفت على إتمام وردك                   │
//    │                                              │
//    │         ورتّل · warattil.org/get                │
//    └──────────────────────────────────────────────┘
//
//  Date policy (2026-04-29 — parity with Android V3 task #10):
//  Gregorian-only.  The Hijri secondary line was dropped on Android in
//  the V3 cycle because it cluttered the card without adding signal —
//  receivers in the WhatsApp/Instagram pipeline consistently parse the
//  Gregorian line, and the dual-calendar stack made the header crowded.
//  Mirror that on iOS so the card reads identically across platforms.
//
//  Data sources
//  ------------
//  Pulls everything from MushaFViewModel via a DailyReadingCardData struct so
//  the card itself stays pure presentation.  The view model's
//  wirdProgressRatio / wirdProgressColor / wirdProgressMessage already handle
//  the "no wird configured" fallback (Quran-completion ratio + generic tier
//  messages), so this card works in both modes.
//
//  Tone guardrail
//  --------------
//  Nasser has a standing rule: no gamification that turns ibadah into a
//  streak-counter (see feedback_warattil_copy_tone, product_direction).  The
//  headline number here is pages-read-today (a fact, not a chain), and the
//  tier message is the existing Wird vocabulary ("عزيمة وإصرار" / "شارفت على
//  إتمام وردك" / "أتممت ورد اليوم") — never "🔥 X-day streak".
//
//  Rendering flow
//  --------------
//  Caller (typically MushaFScreen or WirdSheet):
//    1) Build a `DailyReadingCardData` from the view model state.
//    2) Call `DailyReadingShareCard.renderSnapshot(data:theme:font:)` which
//       drives SwiftUI's ImageRenderer at 2× to produce a UIImage.
//    3) Hand the UIImage to `ShareUtil.shareDailyReading(image:)`.
//
//  The render helper is kept alongside the view so the capture tree and the
//  on-screen preview tree are byte-identical — same problem the Hifz garden
//  solved by splitting out `capturableGarden`.
//

import SwiftUI
import UIKit

// =============================================================================
// MARK: - DailyReadingCardData — the pure-data input
// =============================================================================

/// Everything the card needs to render.  Kept as a plain struct so the view
/// model + a test harness can both produce fixtures without pulling in the
/// whole MushaFViewModel surface.
struct DailyReadingCardData {
    /// Current page 1…604.
    let currentPage:   Int
    /// Surah name for the current page (Arabic, as returned by MetadataParser).
    let surahName:     String
    /// Juz number for the current page (1…30).
    let juzNumber:     Int
    /// Wird progress ratio — already falls back to currentPage/604 when no
    /// wird is configured.  May exceed 1.0 in the surpassed-goal tier.
    let progressRatio: Double
    /// Tier-appropriate message from `wirdProgressMessage`.
    let progressMessage: String
    /// Tiered progress colour — red / amber / green / sky-blue.
    let progressColor: Color
    /// Pages read so far today against today's wird goal.  Both nil when no
    /// wird is configured → the card falls back to "الصفحة X من ٦٠٤".
    let pagesReadToday: Int?
    let dailyPagesGoal: Int?
}

// =============================================================================
// MARK: - DailyReadingShareCard — the rendered SwiftUI view
// =============================================================================

struct DailyReadingShareCard: View {

    let data:  DailyReadingCardData
    let theme: ThemeColors
    let font:  QuranFontInfo

    /// Brand gold — matched to FihrisSheet / HifzLogSheet so the card reads
    /// as part of the same family when stacked next to a shared Hifz garden.
    private var gold: Color { Color(red: 0.651, green: 0.482, blue: 0.141) }

    var body: some View {
        VStack(spacing: 10) {

            // ── Ornate header ───────────────────────────────────────────
            // Two thin star glyphs flanking the title — cheap Kuttāb cue
            // that tells the reader this is an ورتّل artefact at a glance.
            HStack(spacing: 10) {
                Text("✦")
                    .font(.system(size: 14))
                    .foregroundStyle(gold.opacity(0.65))
                Text("ورد اليوم")
                    .font(.warattilChrome(size: 22, weight: .bold))
                    .foregroundStyle(gold)
                Text("✦")
                    .font(.system(size: 14))
                    .foregroundStyle(gold.opacity(0.65))
            }

            // Date strip — Gregorian only (Hijri dropped 2026-04-29 for
            // Android V3 parity, see file header).  Amiri chrome so Arabic
            // digits harmonise with the title.
            Text(gregorianDateLine)
                .font(.warattilChrome(size: 13))
                .foregroundStyle(theme.text.opacity(0.75))
                .padding(.bottom, 4)

            // ── Progress bar ────────────────────────────────────────────
            // Tiered colour from wirdProgressColor.  Pinned LTR so fill
            // animates left-to-right (matches the on-screen momentum bar).
            GeometryReader { geo in
                let clamped = max(0.0, min(1.0, data.progressRatio))
                let fillW   = geo.size.width * CGFloat(clamped)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(theme.text.opacity(0.10))
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(data.progressColor)
                        .frame(width: fillW)
                }
            }
            .frame(height: 12)
            .environment(\.layoutDirection, .leftToRight)
            .padding(.horizontal, 4)

            // Percentage — on the same line as an understated label; the card
            // reads calmly, not like a dashboard.
            Text(percentText)
                .font(.warattilChrome(size: 12, weight: .medium))
                .foregroundStyle(theme.text.opacity(0.6))

            // ── Main stat ───────────────────────────────────────────────
            // If wird is configured → "قرأت X / Y صفحة".  Otherwise a calm
            // page-in-Mushaf readout so the card stays meaningful.
            Text(mainStatText)
                .font(font.font(size: 20).weight(.bold))
                .foregroundStyle(theme.text)
                .multilineTextAlignment(.center)
                .padding(.top, 2)

            // Location — surah + juz.  Uthmani-face Quran font for the surah
            // name so Arabic reads consistently with the Mushaf page behind
            // the card.
            Text(locationText)
                .font(font.font(size: 16))
                .foregroundStyle(theme.text.opacity(0.8))
                .multilineTextAlignment(.center)

            // ── Tier message ────────────────────────────────────────────
            // Pulled straight from wirdProgressMessage so it matches the
            // footer message the reader sees live on the Mushaf page.
            Text(data.progressMessage)
                .font(.warattilChrome(size: 14, weight: .medium))
                .foregroundStyle(gold)
                .multilineTextAlignment(.center)
                .padding(.top, 4)

            // Gold hairline — divides the stat block from the attribution.
            Rectangle()
                .fill(gold.opacity(0.35))
                .frame(height: 0.6)
                .padding(.horizontal, 40)
                .padding(.top, 6)

            // ── Attribution ─────────────────────────────────────────────
            // ورتّل wordmark + brand URL, same pattern as capturableGarden so
            // receivers know which app produced the card.
            HStack(spacing: 0) {
                Text("ورتّل")
                    .font(.warattilChrome(size: 13, weight: .bold))
                    .foregroundStyle(gold)
                Text("  ·  warattil.org/get")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.text.opacity(0.45))
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(theme.background)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(gold.opacity(0.35), lineWidth: 1)
        )
        .environment(\.layoutDirection, .rightToLeft)
    }

    // ── Derived text ────────────────────────────────────────────────────

    /// "الخميس · ٢٣ أبريل ٢٠٢٦"
    private var gregorianDateLine: String {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale   = Locale(identifier: "ar")
        fmt.dateFormat = "EEEE · d MMMM yyyy"
        // Convert Western digits to Arabic-Indic if the formatter returns them.
        return fmt.string(from: Date()).westernToArabicDigits
    }

    private var percentText: String {
        let pct = Int((max(0.0, min(1.0, data.progressRatio)) * 100).rounded())
        return "\(pct.arabicDigits)٪"
    }

    /// Central stat — adapts to whether a wird is configured.
    private var mainStatText: String {
        if let read = data.pagesReadToday, let goal = data.dailyPagesGoal {
            return "قرأت \(read.arabicDigits) / \(goal.arabicDigits) صفحة"
        }
        // Fallback — current page in Mushaf.
        return "الصفحة \(data.currentPage.arabicDigits) من \(WarattilConstants.Mushaf.totalPages.arabicDigits)"
    }

    /// "سورة البقرة · الجزء ٢"
    private var locationText: String {
        "سورة \(data.surahName) · الجزء \(data.juzNumber.arabicDigits)"
    }
}

// =============================================================================
// MARK: - Snapshot renderer
// =============================================================================

extension DailyReadingShareCard {

    /// Rasterise the card to a UIImage ready for `ShareUtil.shareDailyReading`.
    /// Sized to 720 pt wide so receiving apps get a crisp composite even
    /// when the destination compresses (WhatsApp drops down to ~1024 px; at
    /// 720 pt × 2 scale we produce 1440 px, leaving enough headroom).
    ///
    /// The render tree is constructed identically to the on-screen tree —
    /// same data, same theme, same font — so any visual tweak flows to both
    /// preview and snapshot in a single edit.
    @MainActor
    static func renderSnapshot(
        data:  DailyReadingCardData,
        theme: ThemeColors,
        font:  QuranFontInfo
    ) -> UIImage? {
        let view = DailyReadingShareCard(data: data, theme: theme, font: font)
            .frame(width: 720)
            .environment(\.layoutDirection, .rightToLeft)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        return renderer.uiImage
    }
}

// =============================================================================
// MARK: - Digit conversion helper
// =============================================================================

/// DateFormatter with `Locale("ar")` sometimes returns Western digits on
/// certain iOS versions (FB14231108).  This strip converts any remaining
/// Western digits to Arabic-Indic so the card never mixes numeral systems.
private extension String {
    var westernToArabicDigits: String {
        // Named `table` (not `map`) because the dict would otherwise shadow
        // String.map inside the closure below — the compiler picks up the
        // local `map` as a subscriptable dict and refuses the expression.
        let table: [Character: Character] = [
            "0":"٠","1":"١","2":"٢","3":"٣","4":"٤",
            "5":"٥","6":"٦","7":"٧","8":"٨","9":"٩"
        ]
        return String(self.map { table[$0] ?? $0 })
    }
}
