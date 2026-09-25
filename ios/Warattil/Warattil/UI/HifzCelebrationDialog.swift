//
//  HifzCelebrationDialog.swift
//  Warattil
//
//  Ports app/src/main/java/com/warattil/app/ui/HifzCelebrationDialog.kt to SwiftUI.
//
//  PURPOSE
//  -------
//  Fired from MushaFScreen when MushaFViewModel sets `pendingCelebrationTier`
//  (i.e. the user has crossed upward into a previously-uncelebrated hifz
//  tier).  Purpose: acknowledge the milestone — not congratulate in
//  marketing terms, but name it in the scholarly register
//  (براعم الحفظ / نبتة الحفظ / حافظ / شارفت على الختم / حافظ للقرآن الكريم)
//  and point at the next milestone so the reader knows where the journey
//  continues.
//
//  AESTHETIC — KUTTĀB
//  ------------------
//    • Gold border + Heritage cream background (matches Warattil's brand)
//    • Single large bloom glyph over a Mushaf-Green disc — same visual
//      vocabulary the user already associates with juz completion on the
//      heatmap, so the two surfaces read as one piece.
//    • No "you earned X!" language — phrasing is Quranic in register
//      ("بارك الله فيك", "سدّد الله خطاك").
//
//  ACTIONS
//  -------
//    • الحمد لله — primary, dismisses (clears pendingCelebrationTier).
//    • شارك فرحتك — secondary, captures the card content via ImageRenderer
//      and shares the rendered PNG via ShareUtil.shareHifzMilestone.
//      Earlier this fell through to shareAppInvite — which sent generic
//      invite copy instead of the actual milestone card; with image
//      capture the receiver sees the rendered celebration.  Mirrors V3
//      Android refactor (2026-04-27).
//
//  HERITAGE LOCK
//  -------------
//  All colours inside `CelebrationCardContent` are pinned to
//  WarattilTheme.heritage so the captured PNG looks celebratory regardless
//  of the user's active theme.  The dialog's outer chrome (backdrop +
//  buttons) still honours the live `theme` so the in-app overlay feels
//  native to dark / sepia modes — only the captured card is fixed to
//  Heritage.  Same lock pattern as V3 Android's HifzCelebrationDialog.kt.
//

import SwiftUI
import UIKit

struct HifzCelebrationDialog: View {

    // Inputs
    let tier:     Int              // 1…6 — tier 0 is never celebrated
    let juzCount: Int              // total fully-memorized juz at crossing time
    let theme:    ThemeColors      // live theme (drives outer chrome only)
    let onDismiss: () -> Void

    // Convenience accessors — mirrors the Android derivation exactly.
    private var tierLabel: String { WarattilConstants.Hifz.hifzTierLabel(tier: tier) }
    private var nextJuz:   Int?   { WarattilConstants.Hifz.nextTierJuzThreshold(currentTier: tier) }
    private var nextLabel: String? {
        guard let _ = nextJuz else { return nil }
        return WarattilConstants.Hifz.hifzTierLabel(tier: tier + 1)
    }

    /// Tier-specific honorific line — landing gravity is intentional.
    /// Tier 6 (khatma) carries the heaviest du'a; lower tiers are warm.
    private var honorific: String {
        switch tier {
        case 6:  return "بارك الله لك في حفظك · اللهم اجعل القرآن ربيع قلبه"
        case 5:  return "شارفتَ على الختم · اللهم يسّر وأتمّ"
        case 4:  return "بارك الله فيك · سدّد الله خطاك"
        case 3:  return "بارك الله فيك · ثبّت الله حفظك"
        case 2:  return "نبتة طيبة بإذن الله · ثبّت الله خطاك"
        case 1:  return "بدايةٌ مباركة · جعل الله لك في كل آية أجراً"
        default: return "بارك الله فيك"
        }
    }

    // =========================================================================
    // Body
    //
    // Backdrop + card.  The card visual is delegated to CelebrationCardContent
    // (Heritage-locked) so the SAME view tree feeds both the on-screen render
    // and the off-screen ImageRenderer snapshot — guaranteeing the receiver
    // sees exactly what the user saw, with no theme drift.
    // =========================================================================
    var body: some View {
        ZStack {
            // ── Backdrop — dims the Mushaf behind the card.  Tap anywhere
            //    outside the card to dismiss, matching AlertDialog's
            //    dismissOnOutsideTouch semantics.
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            // ── Card + buttons.  Heritage-locked card sits above the
            //    button row; both share the same gold-bordered rounded
            //    container so the captured image and the live overlay
            //    visually agree.
            VStack(spacing: 14) {
                CelebrationCardContent(
                    tier:      tier,
                    juzCount:  juzCount,
                    tierLabel: tierLabel,
                    honorific: honorific,
                    nextJuz:   nextJuz,
                    nextLabel: nextLabel
                )

                // Actions row — outside the captured region so they
                // don't appear in the shared PNG.  Spans full card width.
                HStack(spacing: 10) {
                    Button {
                        captureAndShare()
                    } label: {
                        Text("شارك فرحتك")
                            .font(.warattilChrome(size: 14, weight: .semibold))
                            .foregroundStyle(WarattilConstants.Hifz.hifzGold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(
                                        WarattilConstants.Hifz.hifzGold.opacity(0.6),
                                        lineWidth: 1
                                    )
                            )
                    }

                    Button(action: onDismiss) {
                        Text("الحمد لله")
                            .font(.warattilChrome(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(WarattilConstants.Hifz.hifzGold)
                            )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .environment(\.layoutDirection, .rightToLeft)
            .frame(maxWidth: 340)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(theme.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(WarattilConstants.Hifz.hifzGold.opacity(0.55), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.22), radius: 16, x: 0, y: 6)
            .padding(.horizontal, 24)
        }
    }

    // =========================================================================
    // MARK: Snapshot capture
    //
    // ImageRenderer (iOS 16+) renders a SwiftUI view to a UIImage off-screen.
    // We rebuild a fresh CelebrationCardContent inside the renderer so the
    // captured image carries the Heritage-locked palette regardless of the
    // user's current theme — same view definition as the on-screen render
    // means no aesthetic drift between what they see and what they share.
    //
    // Scale = main screen scale so the PNG looks crisp on the recipient's
    // device.  Renderer can return nil if the view tree fails to lay out;
    // we fall back to a quiet no-op (matches the iOS QR / daily share
    // paths' "quiet-fail beats crashing" behaviour).
    // =========================================================================
    @MainActor
    private func captureAndShare() {
        let renderer = ImageRenderer(
            content: CelebrationCardContent(
                tier:      tier,
                juzCount:  juzCount,
                tierLabel: tierLabel,
                honorific: honorific,
                nextJuz:   nextJuz,
                nextLabel: nextLabel
            )
            .environment(\.layoutDirection, .rightToLeft)
            .frame(width: 340)   // Pinned width matches on-screen card
        )
        renderer.scale = UIScreen.main.scale

        let image = renderer.uiImage
        ShareUtil.shareHifzMilestone(image: image)
    }
}

// =============================================================================
// MARK: - CelebrationCardContent — Heritage-locked captured region
//
// All colours pinned to WarattilTheme.heritage.  Background is painted on
// THIS view's outermost background modifier so the rendered PNG ships
// with a baked cream backdrop instead of transparency (which would let
// dark-mode WhatsApp / Telegram bubbles bleed through and ruin the
// celebratory tone).  Same fix pattern as V3's garden-share + celebration
// share PNG bake-in.
//
// Includes the "ورتّل · warattil.org/get" attribution strip at the bottom
// so receivers (Instagram-only flows that drop the caption text) still
// know where the image came from.
// =============================================================================

private struct CelebrationCardContent: View {
    let tier:      Int
    let juzCount:  Int
    let tierLabel: String
    let honorific: String
    let nextJuz:   Int?
    let nextLabel: String?

    // Heritage palette — locked so the captured PNG always looks
    // celebratory regardless of the user's active theme.
    private var shareTheme: ThemeColors { WarattilTheme.heritage }

    var body: some View {
        VStack(spacing: 12) {
            // Title (Arabic — crossing line, not the tier label).
            Text("مبارك! بلغتَ مرحلةً جديدة")
                .font(.warattilChrome(size: 16, weight: .bold))
                .foregroundStyle(WarattilConstants.Hifz.hifzGold)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            // Bloom hero — same visual vocabulary as the heatmap
            // juz-completion flower, scaled up for dialog impact.
            ZStack {
                Circle()
                    .fill(WarattilConstants.Hifz.heatmapFull)
                Circle()
                    .strokeBorder(WarattilConstants.Hifz.hifzGold, lineWidth: 1.5)
                CelebrationFlower(
                    petal:  WarattilConstants.Hifz.flowerPetal,
                    center: WarattilConstants.Hifz.flowerCenter
                )
                .frame(width: 68, height: 68)
            }
            .frame(width: 86, height: 86)

            // Tier name — the hero of this dialog.
            Text(tierLabel)
                .font(.warattilChrome(size: 22, weight: .bold))
                .foregroundStyle(WarattilConstants.Hifz.hifzGold)
                .multilineTextAlignment(.center)

            // Juz milestone — factual, Eastern-Arabic digits.
            Text("\(juzCount.arabicDigits) من \(30.arabicDigits) جزءاً بإذن الله")
                .font(.warattilChrome(size: 13))
                .foregroundStyle(shareTheme.text.opacity(0.75))
                .multilineTextAlignment(.center)

            // Honorific / du'a line.
            Text(honorific)
                .font(.warattilChrome(size: 13))
                .foregroundStyle(shareTheme.text.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 4)

            // Next-goal pointer (omitted for khatma / tier 6).
            if let nextJuz, let nextLabel {
                nextGoalBox(nextLabel: nextLabel, nextJuz: nextJuz)
                    .padding(.top, 2)
            }

            // ── Attribution strip — captured into the PNG
            //   Self-branding so a receiver who drops the caption text
            //   (Instagram Stories) still knows where the image came
            //   from.  Subtle so it doesn't compete with the milestone
            //   visually.
            Spacer().frame(height: 2)
            HStack(spacing: 0) {
                Text("ورتّل")
                    .font(.warattilChrome(size: 11, weight: .bold))
                    .foregroundStyle(WarattilConstants.Hifz.hifzGold)
                Text("  ·  warattil.org/get")
                    .font(.system(size: 10))
                    .foregroundStyle(shareTheme.text.opacity(0.45))
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .background(
            // Heritage cream baked into the captured layer — see file
            // header for why this MUST be on the inner content, not on
            // the outer dialog modifier.
            RoundedRectangle(cornerRadius: 12)
                .fill(shareTheme.background)
        )
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    /// Gold-tinted pill box pointing at the next milestone.  Omitted when
    /// `tier == 6` (the user has reached full hafiz — no next goal).
    private func nextGoalBox(nextLabel: String, nextJuz: Int) -> some View {
        VStack(spacing: 2) {
            Text("المرحلة القادمة")
                .font(.warattilChrome(size: 11))
                .foregroundStyle(shareTheme.text.opacity(0.55))
            Text("\(nextLabel) · عند \(nextJuz.arabicDigits) جزءاً")
                .font(.warattilChrome(size: 13, weight: .semibold))
                .foregroundStyle(WarattilConstants.Hifz.hifzGold)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(WarattilConstants.Hifz.hifzGold.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(WarattilConstants.Hifz.hifzGold.opacity(0.4), lineWidth: 0.75)
        )
    }
}

// =============================================================================
// MARK: CelebrationFlower — larger variant of the heatmap bloom glyph
//
// Same 5-petal geometry as the heatmap's juz-completion flower so the
// celebration and the garden read as a matched pair.  Self-contained so
// the dialog has no dependency on HifzLogSheet internals.
// =============================================================================

private struct CelebrationFlower: View {
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
