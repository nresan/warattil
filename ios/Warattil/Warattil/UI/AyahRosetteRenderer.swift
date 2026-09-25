//
//  AyahRosetteRenderer.swift
//  Warattil
//
//  Produces the decorative ayah-marker rosette used in the Mushaf body.
//
//  WHY THIS EXISTS
//  ---------------
//  Android renders `﴿N﴾` as a single decorative glyph because the KFGQPC
//  Uthmanic Script HAFS font carries an OpenType substitution that collapses
//  the three-character sequence into a rosette ligature. iOS CoreText does
//  not apply the same substitution — the same Unicode lands on the page as
//  three flat characters (U+FD3E, Eastern digit, U+FD3F). The visual gap
//  between platforms is exactly what Nasser flagged 2026-04-21 as "the font
//  for the ayah number is not suitable".
//
//  Rather than fight the font engine, we pre-render the rosette as a
//  UIImage and splice it into the text stream via `NSTextAttachment`. The
//  result is pixel-identical across devices, renders inside the justified
//  UILabel's layout pass, and gives us full control over geometry, colour,
//  and digit typography.
//
//  DESIGN
//  ------
//  Revised 2026-04-21 after Nasser compared against the Android KFGQPC
//  rendering: the Android font's rosette ligature is a floral, scallop-
//  edged seal — not a pointy starburst. The iOS marker now mirrors that
//  silhouette.
//
//  • Outer silhouette: 12 scalloped lobes traced with quadratic curves
//    (r(θ) = R × (1 + 0.10·cos(12θ))) — reads as a soft flower, not
//    spokes. Filled with faded gold so it sits under the body line
//    without competing with the glyphs.
//  • Gold ring: solid theme.gold disc punched through by an inner cream
//    disc, producing a crisp hairline frame.
//  • Hairline decoration: a 0.4 pt gold tracery ring just inside the
//    main gold ring — echoes the Madinah Mushaf's double-rule outline.
//  • Digit: Eastern-Arabic, Amiri-Bold, rendered in theme.gold (NOT
//    Mushaf Green). Earlier iteration used accent-green which over-
//    contrasted against the cream disc and read as modern/Material;
//    gold-on-cream keeps the classical printed-Mushaf palette.
//
//  CACHING
//  -------
//  Rendering on every layout pass costs ~2 ms per marker; at ~8 markers
//  per page × 60 fps scroll that stacks up. We memoise by
//  (number, size-bucket, theme-fingerprint) so only unique combinations
//  pay the render cost once.
//

import UIKit
import SwiftUI

enum AyahRosetteRenderer {

    /// Render the rosette at the given body font size.
    ///
    /// - Parameters:
    ///   - number:   The ayah number to draw inside the disc (Latin 0-9;
    ///               converted to Eastern Arabic internally).
    ///   - bodySize: The BODY font point size. The rosette is sized at
    ///               1.55× bodySize diameter to match printed-Mushaf
    ///               marker-to-body proportions.
    ///   - theme:    Active ThemeColors (palette follows theme switching).
    /// - Returns:    A UIImage ready to hand to NSTextAttachment.
    static func image(
        number:   Int,
        bodySize: CGFloat,
        theme:    ThemeColors
    ) -> UIImage {
        // NSCache wants NSObject keys — use a plain NSString so Swift's
        // bridging is trivial and no unsafe casts are needed.
        let sizeBucket = Int((bodySize * 2).rounded())   // 0.5-pt buckets
        let key = "\(number)|\(sizeBucket)|\(themeFingerprint(theme))" as NSString
        if let hit = cache.object(forKey: key) {
            return hit
        }

        let img = draw(number: number, bodySize: bodySize, theme: theme)
        cache.setObject(img, forKey: key)
        return img
    }

    // ── Private ─────────────────────────────────────────────────────────────

    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 2048   // ≈ 6 surahs × 286 ayah max + headroom
        return c
    }()

    /// Stable-ish identifier for the theme — good enough for cache keying.
    /// Uses the background colour's description string because the three
    /// shipped themes (cream / sepia / night) have distinct background
    /// colours. If we ever add a theme that reuses the same background
    /// but differs in accent or gold, widen this to include those too.
    private static func themeFingerprint(_ t: ThemeColors) -> String {
        "\(t.background.description)|\(t.gold.description)|\(t.accent.description)"
    }

    /// Actual Core Graphics draw pass. Called once per unique cache key.
    ///
    /// DESIGN (2026-04-21, revision 3 — simplicity pass)
    /// -------------------------------------------------
    /// Nasser flagged that the previous floral halo + hairline tracery
    /// rendering still didn't match Android's KFGQPC font glyph. The
    /// KFGQPC glyph is fundamentally simple: a single gold-ringed disc
    /// with a subtle outer floral edge and the digit inside. No faint
    /// halo, no double-rule ring, no heavy decoration — it reads as
    /// a printed Mushaf seal, not as a Material Design badge.
    ///
    /// This revision strips every non-essential decoration and
    /// matches KFGQPC:
    ///   1. Single scalloped outer edge (8 gentle lobes, amp = 0.035) —
    ///      subtle floral breath, not a starburst or chrysanthemum.
    ///   2. One solid gold ring.
    ///   3. Cream interior.
    ///   4. Eastern-Arabic digit, gold, Amiri-Bold.
    ///
    /// The diameter multiplier was also reduced (1.55 → 1.42) so the
    /// marker sits more integrated with the body line — the old 1.55
    /// multiplier made the marker feel oversized compared to the
    /// Android glyph, which reads at ~1.3× body x-height.
    private static func draw(
        number:   Int,
        bodySize: CGFloat,
        theme:    ThemeColors
    ) -> UIImage {
        let dia  = max(bodySize * 1.42, 11)
        let size = CGSize(width: dia, height: dia)

        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.opaque = false
        fmt.scale  = UIScreen.main.scale

        return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
            let center = CGPoint(x: dia / 2, y: dia / 2)

            // ── Radii ────────────────────────────────────────────────────
            // The scalloped outer boundary oscillates between `rOuter`
            // (lobe peaks) and `rOuter × (1 − 2·amp)`. amp = 0.035 gives
            // a breath of flower-edge without reading as "spiky".
            let rOuter = dia / 2 - 0.5
            let rInner = rOuter * 0.78       // cream disc radius; the
                                             // ring width is (rOuter − rInner)
                                             // ≈ 22 % of the outer radius,
                                             // matching KFGQPC's printed
                                             // proportion.

            // ── Colours ──────────────────────────────────────────────────
            let gold  = UIColor(theme.gold)
            let cream = UIColor(theme.background)

            // 1. Scalloped gold disc — 8 gentle lobes. The whole shape
            //    is filled as a single gold silhouette, then the cream
            //    interior is punched through in step 2 to leave a
            //    uniform-width ring.
            let petals      = 8
            let amp: CGFloat = 0.035
            let samples     = 240
            let silhouette  = UIBezierPath()
            for i in 0...samples {
                let theta = CGFloat(i) / CGFloat(samples) * 2 * .pi - .pi / 2
                let r     = rOuter * (1 - amp + amp * cos(CGFloat(petals) * theta))
                let p = CGPoint(
                    x: center.x + r * cos(theta),
                    y: center.y + r * sin(theta)
                )
                if i == 0 { silhouette.move(to: p) } else { silhouette.addLine(to: p) }
            }
            silhouette.close()
            gold.setFill()
            silhouette.fill()

            // 2. Cream disc punches the centre out of the gold
            //    silhouette — leaves a clean gold ring whose outer
            //    edge follows the scalloped silhouette above.
            cream.setFill()
            UIBezierPath(
                arcCenter: center, radius: rInner,
                startAngle: 0, endAngle: 2 * .pi, clockwise: true
            ).fill()

            // 3. Digit. Amiri-Bold renders Eastern digits with the
            //    traditional Madinah-Mushaf numeral forms; fall back
            //    to system bold if the font isn't registered.
            let digits   = number.arabicDigits

            // Font size scales DOWN as the numeral grows wider so 2-
            // and 3-digit markers keep breathing room inside the
            // cream disc. A single 0.66× multiplier was correct for
            // 1-digit numbers but left late-Baqarah markers
            // (ayahs 283-286) visibly cramped against the inner rim
            // of the ring. Nasser 2026-04-21.
            //
            // • 1 digit  → 0.66× body — unchanged (well-proportioned).
            // • 2 digits → 0.58× body — small reduction, mostly
            //   imperceptible but prevents crowding on pages with
            //   ayahs 10-99.
            // • 3+ digits → 0.46× body — real breathing room; matches
            //   the visual density of the 1-digit marker so markers
            //   read as a family across the page.
            let digitCountScale: CGFloat = {
                switch digits.count {
                case 1:  return 1.00
                case 2:  return 0.88
                default: return 0.70
                }
            }()
            let fontSize = bodySize * 0.66 * digitCountScale
            let numFont: UIFont = {
                if let amiri = UIFont(name: "Amiri-Bold", size: fontSize) {
                    return amiri
                }
                return .systemFont(ofSize: fontSize, weight: .bold)
            }()
            let attrs: [NSAttributedString.Key: Any] = [
                .font:            numFont,
                .foregroundColor: gold
            ]
            let str = NSAttributedString(string: digits, attributes: attrs)
            let textSize = str.size()
            // Nudge a touch upward — Amiri's Eastern digits have no
            // ascender above their baseline, so the typographic centre
            // sits a hair below the visual centre of the cream disc.
            str.draw(at: CGPoint(
                x: center.x - textSize.width  / 2,
                y: center.y - textSize.height / 2 - bodySize * 0.03
            ))
        }
    }

    /// Build an NSTextAttachment sized and vertically-positioned so the
    /// rosette reads as if it were an in-line glyph on the body text line.
    static func attachment(
        number:   Int,
        bodySize: CGFloat,
        theme:    ThemeColors
    ) -> NSTextAttachment {
        let img = image(number: number, bodySize: bodySize, theme: theme)
        let att = NSTextAttachment()
        att.image = img
        let h = img.size.height
        // Attachment `bounds.y` is measured from the line's baseline:
        // negative values push the attachment DOWN, pinning part of it
        // below the baseline. We want the rosette's visual centre to sit
        // on the x-height midpoint (~0.25 × bodySize above baseline),
        // so the bottom edge lands at ≈ 0.25×bodySize − h/2.
        att.bounds = CGRect(
            x: 0,
            y: bodySize * 0.25 - h / 2,
            width: img.size.width,
            height: h
        )
        return att
    }
}
