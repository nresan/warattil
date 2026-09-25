//
//  MushaFFooter.swift
//  Warattil
//
//  Port of app/src/main/java/com/warattil/app/ui/MushaFFooter.kt.
//
//  LAYOUT
//  ------
//  Structure (rendered on screen, one unified row under the motivation line):
//
//    ┌───────────────────────────────────────────────────────────────────┐
//    │                      اتممت ورد اليوم                              │ ← motivation (tier colour)
//    │  ⟨ ٢ ⟩  ٨٠٪  ░░░░░░████████████████████   ورد اليوم                │ ← unified row (RTL, bar fills R→L)
//    └───────────────────────────────────────────────────────────────────┘
//
//  Layout semantics (mirrors Ayah / Golden-Quran reference apps):
//    • The chip label "ورد اليوم" anchors the logical START — visual RIGHT
//      in RTL.
//    • The bar fills right→left: as the user swipes forward through the
//      Mushaf the coloured portion grows from the chip edge (visual
//      RIGHT in RTL) toward the percentage. SwiftUI LinearProgressIndicator
//      equivalent here is a hand-rolled ZStack because we need explicit
//      fill-direction control. The fill is anchored to `.leading` inside
//      the RTL environment — which resolves to the VISUAL RIGHT edge,
//      matching Android's RTL LinearProgressIndicator. (Using `.trailing`
//      looks correct in LTR but is exactly wrong in RTL: it anchors at
//      the visual LEFT and fills rightward, which reads as "going
//      backward" as the user swipes forward.)
//    • The percentage label sits to the VISUAL LEFT of the bar (the
//      "leading edge" of progress in RTL) so the number always reads
//      right next to where the filled portion currently ends. It grows
//      live with the swipe because the ratio changes with the page.
//    • The OrnatePageBadge anchors the visual LEFT (logical end in RTL).
//
//  MOMENTUM LAW (unchanged — 30-40-30-Beyond):
//    ratio < 0.30 → Red     ·  ratio < 0.70 → Amber
//    ratio ≤ 1.0  → Green   ·  ratio > 1.0  → Sky Blue
//
//  PAGE BADGE
//  ----------
//  Android uses FontFamily.Default for the page number because the KFGQPC
//  Uthmanic font applies an OpenType GSUB digit→ayah-badge substitution
//  that caps at ~2 digits per glyph and mangles page numbers ≥100. On iOS
//  we don't ship KFGQPC for UI chrome, but we keep the system font here
//  for visual parity and three-digit clarity (pages run to ٦٠٤).
//

import SwiftUI

struct MushaFFooter: View {
    let currentPage:   Int
    let progressRatio: Double
    let progressColor: Color
    let progressMsg:   String
    let theme:         ThemeColors
    let font:          QuranFontInfo
    // ── WirdResumeChip integration (parity with Android pt. 6) ────────
    // Non-null `wirdResumePage` = chip visible (reader has wandered off
    // the wird ribbon).  Embedded INLINE in the message row so the
    // bottomBar height stays compact — same pattern as Android.
    var wirdResumePage: Int?       = nil
    var onWirdResumeTap: () -> Void = {}

    /// Percent label — capped at 100% (cumulative-modulo engine never
    /// emits ratio > 1.0; Sky Blue removed 2026-04-27 pt. 3).
    private var pctLabel: String {
        let clamped = max(0.0, min(1.0, progressRatio))
        return "\(Int(clamped * 100).toArabicDigits())٪"
    }

    var body: some View {
        VStack(spacing: 5) {
            // Subtle top divider — separates the footer from the Mushaf body.
            Rectangle()
                .fill(theme.divider)
                .frame(height: WarattilConstants.Layout.dividerThickness)

            // ── Top row: motivation message + (optional) WirdResumeChip ──
            //   Single row to claw back vertical space (parity with Android
            //   pt. 6).  When the reader is off the wird ribbon the chip
            //   joins the message on the same line; otherwise the message
            //   takes the full row.
            HStack(spacing: 10) {
                Text(progressMsg)
                    .font(font.font(size: 13).weight(.medium))
                    .foregroundStyle(progressColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                if let page = wirdResumePage {
                    WirdResumeChip(
                        resumePage: page,
                        theme:      theme,
                        onTap:      onWirdResumeTap
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .environment(\.layoutDirection, .rightToLeft)

            // ── Unified row: chip · bar · % · page badge ───────────────────
            // The whole row is forced RTL so the HStack's logical ordering
            // (chip → bar → pct → badge) renders as
            //     [badge] [pct] [bar →left-fill] [chip]
            // i.e. chip on RIGHT, badge on LEFT — matching Android.
            HStack(spacing: 8) {

                // 1) Chip label — "ورد اليوم" (logical start, visual RIGHT)
                Text("ورد اليوم")
                    .font(font.font(size: 11))
                    .foregroundStyle(theme.text.opacity(0.55))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                // 2) Momentum bar — takes remaining width. Fill grows from
                //    the RIGHT edge (visual right in RTL = logical start).
                MomentumBar(
                    ratio: progressRatio,
                    color: progressColor,
                    theme: theme
                )
                .frame(height: WarattilConstants.Layout.progressBarHeight)
                .frame(maxWidth: .infinity)

                // 3) Percentage — sits on the VISUAL LEFT of the bar (the
                //    leading edge in RTL). Grows live as the user swipes.
                Text(pctLabel)
                    .font(.warattilChrome(size: 12, weight: .bold))
                    .foregroundStyle(progressColor)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    // Use LTR for the label itself so the percent sign lands
                    // to the right of the digits (the Arabic "٪" glyph reads
                    // right-to-left but the digit run is visually LTR).
                    .environment(\.layoutDirection, .leftToRight)

                // 4) Ornate page badge — double-ring gold disc with Eastern
                //    digits. Visual LEFT anchor (logical end in RTL).
                OrnatePageBadge(pageNumber: currentPage, theme: theme)
            }
            .frame(height: 32)
            .environment(\.layoutDirection, .rightToLeft)
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .background(theme.background)
    }
}

// =============================================================================
// MARK: - MomentumBar — RTL-filling rounded bar
// =============================================================================
//
// SwiftUI's `ProgressView` and `LinearProgressIndicator` honour the
// environment layout direction on iOS 17+, but the fill anchor is not
// reliable across iOS 17.0 → 17.4 (some iPhone 15 builds showed the bar
// filling LTR even inside an RTL environment). A hand-rolled GeometryReader
// variant sidesteps the OS bug and lets us control the fill anchor
// explicitly.
// =============================================================================

private struct MomentumBar: View {
    let ratio: Double
    let color: Color
    let theme: ThemeColors

    var body: some View {
        GeometryReader { geo in
            let clamped = max(0, min(1, ratio))
            let fillW   = geo.size.width * CGFloat(clamped)

            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: WarattilConstants.Layout.progressBarRadius)
                    .fill(theme.text.opacity(0.09))

                // Fill — anchored to `.leading`, which inside this RTL
                // parent resolves to the VISUAL RIGHT edge. As the ratio
                // grows with each forward swipe, the fill extends from
                // the right edge toward the left — same direction as
                // Arabic reading, matching Android.
                RoundedRectangle(cornerRadius: WarattilConstants.Layout.progressBarRadius)
                    .fill(color)
                    .frame(width: fillW)
                    .animation(.easeInOut(duration: 0.25), value: clamped)
            }
        }
    }
}

// =============================================================================
// MARK: - OrnatePageBadge — double-ring Deep-Gold circle with page number
// =============================================================================
//
// Port of OrnatePageBadge in MushaFFooter.kt — 34 dp outer disc with a
// 28 dp inner hairline ring. Numbers run 1…604 so the badge is sized to
// fit three Eastern-Arabic digits comfortably.
// =============================================================================

private struct OrnatePageBadge: View {
    let pageNumber: Int
    let theme:      ThemeColors

    var body: some View {
        ZStack {
            // Outer disc — faded gold fill + crisp gold border
            Circle()
                .fill(theme.gold.opacity(0.10))
            Circle()
                .strokeBorder(theme.gold.opacity(0.55), lineWidth: 1.2)

            // Inner hairline ring — sits 3 pt inside the outer border
            Circle()
                .strokeBorder(theme.gold.opacity(0.35), lineWidth: 0.6)
                .padding(3)

            // Page number — Amiri-Bold. SF Arabic (the iOS default) renders
            // digits as modern geometric sans-serif that clashes with the
            // Mushaf palette; Amiri's classical Naskh reads as "scholarly
            // print seal" and matches the banner typography. Bold ensures
            // the digit stays legible at 14 pt against the gold ring.
            // The point size is bumped +1 pt over the old SF setting (14
            // vs 13) because Amiri's x-height is tighter than SF, so the
            // optical weight at 13 pt felt smaller than the SF original.
            // Avoids the Uthmanic digit→ayah-badge ligature that would
            // mangle 3-digit page numbers (pages run to ٦٠٤).
            // Nasser 2026-04-21.
            Text(pageNumber.toArabicDigits())
                .font(.warattilChrome(size: 13, weight: .bold))
                .foregroundStyle(theme.gold)
                .lineLimit(1)
        }
        .frame(width: 34, height: 34)
    }
}
