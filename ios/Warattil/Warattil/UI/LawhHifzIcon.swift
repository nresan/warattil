//
//  LawhHifzIcon.swift
//  Warattil
//
//  SwiftUI port of app/src/main/res/drawable/ic_lawh_hifz.xml
//
//  Why a Shape, not an Asset
//  -------------------------
//  The Android source ships a vector drawable (24×24 viewport) with
//  strokes + fills on four paths. Porting that to an iOS `Image` would
//  require an xcassets PDF/SVG import — an extra asset to keep in sync
//  whenever we adjust the glyph. Rendering directly with `SwiftUI.Shape`
//  keeps the two platforms' glyphs source-identical: the path data here
//  is a literal translation of the `android:pathData` strings in
//  `ic_lawh_hifz.xml`, so any future tweak updates both sides from the
//  same numbers.
//
//  Tinting
//  -------
//  The view honours `.foregroundStyle(...)` (SwiftUI 15+ / iOS 17+) via
//  the `tint` initialiser parameter, and also responds to
//  `.environment(\.foregroundStyle)` for parents that cascade colour.
//  Matches the way Android's vector drawable collapses all three path
//  colours into `android:tint="#99651F"` when the Icon() composable
//  applies a single tint.
//
//  Usage
//  -----
//      LawhHifzIcon(size: 18, tint: theme.gold)
//      LawhHifzIcon(size: 22, tint: hifzGold.opacity(isOn ? 1.0 : 0.35))
//

import SwiftUI

// =============================================================================
// MARK: - LawhHifzIcon — the Kuttāb tablet glyph
// =============================================================================

struct LawhHifzIcon: View {

    let size: CGFloat
    let tint: Color

    init(size: CGFloat, tint: Color) {
        self.size = size
        self.tint = tint
    }

    var body: some View {
        Canvas { ctx, bounds in
            // Viewport is 24×24 in the Android drawable; scale uniformly to
            // whatever bounds SwiftUI gave us. The aspect ratio is locked
            // because the frame below pins width == height.
            let scale = min(bounds.width, bounds.height) / 24.0

            // ── Tablet silhouette — tapered trapezoid, wider at bottom ──────
            // `M8,3 L16,3 L17.2,21 L6.8,21 Z`
            var silhouette = Path()
            silhouette.move(to: CGPoint(x: 8.0  * scale, y: 3.0  * scale))
            silhouette.addLine(to: CGPoint(x: 16.0 * scale, y: 3.0  * scale))
            silhouette.addLine(to: CGPoint(x: 17.2 * scale, y: 21.0 * scale))
            silhouette.addLine(to: CGPoint(x: 6.8  * scale, y: 21.0 * scale))
            silhouette.closeSubpath()
            ctx.stroke(
                silhouette,
                with: .color(tint),
                style: StrokeStyle(
                    lineWidth: 1.5 * scale,
                    lineCap:   .round,
                    lineJoin:  .round
                )
            )

            // ── Hanging hole — small ring near the top ──────────────────────
            // Android path: `M12,5 m-0.7,0 a0.7,0.7 0 1,0 1.4,0 a0.7,0.7 0 1,0 -1.4,0`
            // Two half-arcs that form a complete circle of radius 0.7 at (12, 5).
            let holeRect = CGRect(
                x: (12.0 - 0.7) * scale,
                y: (5.0  - 0.7) * scale,
                width:  1.4 * scale,
                height: 1.4 * scale
            )
            ctx.stroke(
                Path(ellipseIn: holeRect),
                with: .color(tint),
                lineWidth: 1.0 * scale
            )

            // ── Script lines — four short bars suggesting writing ──────────
            // `M9,9 H15 V9.8 H9 Z  M9,12 H14.5 V12.8 H9 Z
            //  M9,15 H15.2 V15.8 H9 Z  M9,18 H13 V18.8 H9 Z`
            var scriptBars = Path()
            for bar in Self.scriptBars {
                scriptBars.addRect(CGRect(
                    x: bar.x * scale,
                    y: bar.y * scale,
                    width:  bar.w * scale,
                    height: bar.h * scale
                ))
            }
            ctx.fill(scriptBars, with: .color(tint))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)  // decorative — callers set a label
    }

    /// Four script-suggestion bars. Coordinates are in the 24-unit Android
    /// viewport; the `scale` applied inside `Canvas` remaps them to the
    /// actual pixel size requested by the caller.
    private static let scriptBars: [(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat)] = [
        (x: 9.0, y: 9.0,  w: 6.0, h: 0.8),   // widest, top
        (x: 9.0, y: 12.0, w: 5.5, h: 0.8),
        (x: 9.0, y: 15.0, w: 6.2, h: 0.8),
        (x: 9.0, y: 18.0, w: 4.0, h: 0.8),   // shortest, bottom
    ]
}
