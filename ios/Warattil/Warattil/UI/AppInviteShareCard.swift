//
//  AppInviteShareCard.swift
//  Warattil
//
//  WARATTIL V2 — App-invite share card (2026-04-23)
//
//  Why this file exists
//  --------------------
//  The "شارك ورتّل" overflow-menu item used to hand a plain Arabic paragraph
//  to the system share sheet.  That text drops through WhatsApp / SMS just
//  fine but is a dead letter on Instagram Stories, and on Facebook / Twitter
//  it produces a link preview of the App Store listing with no branding
//  context from ورتّل.  BLUEPRINT §11.4 lifts the invite into a rendered
//  card carrying:
//
//    ┌──────────────────────────────────────────────┐
//    │                                              │
//    │               ✦  ورتّل  ✦                       │
//    │         مصحف رقمي بخط عثماني كامل               │
//    │           بلا إعلانات · بلا إلهاء                │
//    │                                              │
//    │            ┌──────────────┐                  │
//    │            │              │                  │
//    │            │   [QR code]  │                  │
//    │            │              │                  │
//    │            └──────────────┘                  │
//    │           امسح لتحميل التطبيق                  │
//    │                                              │
//    │      ───────────  ﷺ  ───────────              │
//    │   قال النبي ﷺ: «من دلَّ على خير                 │
//    │        فله مثل أجر فاعله»                     │
//    │                                              │
//    │         ورتّل · warattil.org/get                │
//    └──────────────────────────────────────────────┘
//
//  Caller hands the rendered UIImage to `ShareUtil.shareAppInvite(image:)`
//  alongside the existing textual invite.  Each destination app picks the
//  subset it can render:
//    • Instagram Stories  → image only (dropped text/URL)
//    • Facebook / Twitter → image + URL (rich preview with the card)
//    • WhatsApp / Telegram → image + text (card visible, text falls in)
//    • SMS / Mail         → everything
//
//  The card is self-contained — no network fetch, QR PNG bundled in the asset
//  catalogue as "WarattilQR" (same asset AboutSheet uses).  If the asset is
//  missing `renderSnapshot` returns nil and ShareUtil falls back to the
//  text-only share path.
//
//  Tone guardrail
//  --------------
//  Per product_direction: hadith framing stays on the one-time invitation
//  path only.  It is *not* used on ayah-share / daily-status / garden-share
//  payloads because those are recurring content and the framing would grow
//  stale fast.  Keep this card the sole visual home for the hadith.
//

import SwiftUI
import UIKit

// =============================================================================
// MARK: - AppInviteShareCard
// =============================================================================

struct AppInviteShareCard: View {

    let theme: ThemeColors

    /// Brand gold — matched to DailyReadingShareCard / FihrisSheet so the
    /// family of shared cards reads consistently when a reader posts two
    /// of them back-to-back (e.g. daily-status + app-invite on Stories).
    private var gold: Color { Color(red: 0.651, green: 0.482, blue: 0.141) }

    var body: some View {
        VStack(spacing: 14) {

            // ── Wordmark + tagline ───────────────────────────────────────
            HStack(spacing: 12) {
                Text("✦")
                    .font(.system(size: 18))
                    .foregroundStyle(gold.opacity(0.65))
                Text("ورتّل")
                    .font(.warattilChrome(size: 42, weight: .bold))
                    .foregroundStyle(gold)
                Text("✦")
                    .font(.system(size: 18))
                    .foregroundStyle(gold.opacity(0.65))
            }
            .padding(.top, 4)

            VStack(spacing: 4) {
                Text("مصحف رقمي بخط عثماني كامل")
                    .font(.warattilChrome(size: 17, weight: .medium))
                    .foregroundStyle(theme.text.opacity(0.85))
                Text("بلا إعلانات · بلا إلهاء")
                    .font(.warattilChrome(size: 14))
                    .foregroundStyle(theme.text.opacity(0.65))
            }

            // ── QR block ─────────────────────────────────────────────────
            // The QR encodes `brandRedirectURL` (warattil.org/get) which
            // UA-sniffs to App Store on iOS and Play Store on Android.  The
            // white inset + gold border gives the code enough contrast and
            // quiet zone to scan reliably even when IG Stories tints the
            // background.  No-op if the asset is missing.
            if let qrImage = UIImage(named: "WarattilQR") {
                VStack(spacing: 8) {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220, height: 220)
                        .padding(10)
                        .background(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(gold.opacity(0.35), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Text("امسح لتحميل التطبيق")
                        .font(.warattilChrome(size: 13))
                        .foregroundStyle(theme.text.opacity(0.6))
                }
                .padding(.top, 6)
            }

            // ── Divider + hadith ─────────────────────────────────────────
            // Hairline split by a small ﷺ glyph.  Pure decoration — no
            // functional role — so it's drawn once and flanked by two
            // rectangles to avoid coupling the divider to any external
            // layout constant.
            HStack(spacing: 10) {
                Rectangle()
                    .fill(gold.opacity(0.35))
                    .frame(height: 0.6)
                Text("ﷺ")
                    .font(.warattilChrome(size: 16))
                    .foregroundStyle(gold.opacity(0.8))
                Rectangle()
                    .fill(gold.opacity(0.35))
                    .frame(height: 0.6)
            }
            .padding(.horizontal, 30)
            .padding(.top, 6)

            // Hadith body — kept on two lines to stay inside the 720 pt
            // frame without wrapping awkwardly at narrow fallback widths.
            VStack(spacing: 4) {
                Text("قال النبي ﷺ:")
                    .font(.warattilChrome(size: 13))
                    .foregroundStyle(theme.text.opacity(0.7))
                Text("«من دلَّ على خير فله مثل أجر فاعله»")
                    .font(.warattilChrome(size: 16, weight: .medium))
                    .foregroundStyle(theme.text)
                    .multilineTextAlignment(.center)
            }

            // ── Attribution ─────────────────────────────────────────────
            Rectangle()
                .fill(gold.opacity(0.35))
                .frame(height: 0.6)
                .padding(.horizontal, 40)
                .padding(.top, 10)

            HStack(spacing: 0) {
                Text("ورتّل")
                    .font(.warattilChrome(size: 13, weight: .bold))
                    .foregroundStyle(gold)
                Text("  ·  warattil.org/get")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.text.opacity(0.5))
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 26)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(theme.background)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(gold.opacity(0.35), lineWidth: 1)
        )
        .environment(\.layoutDirection, .rightToLeft)
    }
}

// =============================================================================
// MARK: - Snapshot renderer
// =============================================================================

extension AppInviteShareCard {

    /// Rasterise the invite card to a UIImage for ShareUtil.shareAppInvite.
    /// Sized 720 pt × 2× scale → 1440 px-wide output, which fits Instagram
    /// Stories (1080 px) with headroom after iOS compression, and Twitter's
    /// 1024×512 crop zone when posted as a link-preview image.
    ///
    /// Returns nil if the underlying ImageRenderer fails — ShareUtil
    /// interprets nil as "fall back to text-only invite" rather than
    /// crashing the reader.
    @MainActor
    static func renderSnapshot(theme: ThemeColors) -> UIImage? {
        let view = AppInviteShareCard(theme: theme)
            .frame(width: 720)
            .environment(\.layoutDirection, .rightToLeft)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        return renderer.uiImage
    }
}
