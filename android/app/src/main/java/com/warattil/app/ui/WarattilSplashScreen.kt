package com.warattil.app.ui

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.warattil.app.R

// =============================================================================
// ⚠️  LOCKED TRADEMARK — DO NOT EDIT CASUALLY  ⚠️
// =============================================================================
//
// WARATTIL Android splash — the sibling of `ios/Warattil/Warattil/WarattilApp.swift`
// → `struct SplashView`. Both platforms show the SAME trademark block on
// launch:
//
//   1. Cream background (#F5F5DC — matches the Mushaf page surface).
//   2. Logo from `@drawable/splash_logo`, 200 dp, rounded-rect clip at
//      45 dp (Apple "squircle" at ≈22.37 % of the edge length — the same
//      radius iOS uses so both platforms share the icon silhouette).
//   3. A breathing animation that gently scales the logo between 0.96 ×
//      and 1.04 × over 1.4 s, mirroring the cadence of a recited breath.
//   4. The Muzzammil ayah the product is named after —
//          ﴾  وَرَتِّلِ ٱلْقُرْءَانَ تَرْتِيلًا  ﴿     (Q 73:4)
//      rendered in the pinned KFGQPC Uthmanic face, with DEEP_GOLD
//      ﴾ ﴿ brackets curving inward (﴾ on visual LEFT opens right;
//      ﴿ on visual RIGHT opens left).
//   5. Scholarly attribution "سورة المزمّل ـ الآية ٤" in Amiri, gold at
//      80 % opacity.
//
// Nasser (2026-04-22, second lock pass):
//
//     "The opening page in the iOS version is not applied to the Android
//      version. I want you to change the Android version's opening page
//      to match the iOS version."
//
// So: Android used to show the SYSTEM SplashScreen only (just the cream +
// logo drawable). That is kept as a brief cold-start bridge in
// MainActivity, but the brand-critical content — ayah + attribution —
// now lives here in Compose and renders for the full minimum-splash
// duration (4 s). Visually identical to iOS modulo font-metric
// differences.
//
// LOCK CONTRACT (do NOT edit without asking Nasser):
//   • Don't swap the ayah. "وَرَتِّلِ ٱلْقُرْءَانَ تَرْتِيلًا" is the
//     name-ayah; editing it is like editing the logo.
//   • Don't change the bracket ORDER. The glyphs curve asymmetrically;
//     flipping them makes the brackets open outward, which reads as a
//     bug. See iOS comment in SplashView for the geometry.
//   • Don't route this through `WarattilConstants.Mushaf.FONT_UTHMANIC`
//     via indirection. The splash is the trademark; pinning the font
//     name inline here makes it immune to future body-font swaps.
//     (If FONT_UTHMANIC ever changes to something other than KFGQPC,
//     the splash MUST stay on KFGQPC.)
//   • Don't remove the breathing animation — it's the only indicator
//     that the app is alive during bootstrap. Without it a stalled
//     launch reads as a frozen splash.
//   • Don't add a progress bar / "Loading..." text. If bootstrap stalls
//     long enough for the user to wonder, the correct response is an
//     error screen, not a spinner.
// =============================================================================

/** Pinned font resources — bypass WarattilConstants so a future body-font
 *  swap doesn't drag the trademark along with it. Mirrors iOS
 *  `LockedSplashFont` in `WarattilApp.swift`. */
private object LockedSplashFont {
    val uthmanic = FontFamily(Font(R.font.kfgqpc_uthmanic_script_hafs_regular))
    val chrome   = FontFamily(Font(R.font.amiri_regular))
}

/** WARATTIL gold — same hue used for ﴾ ﴿ ayah ornaments elsewhere. Hardcoded
 *  because the splash renders BEFORE the theme struct is available. */
private val SPLASH_GOLD     = Color(0xFF996515)
private val SPLASH_CREAM    = Color(0xFFF5F5DC)
private val SPLASH_CHARCOAL = Color(0xFF1A1A1A)

/**
 * The full Android trademark splash. Renders cream background, breathing
 * logo, Muzzammil ayah in gold brackets, and attribution. Sized to fill
 * the whole window — caller decides WHEN to show it (MainActivity holds
 * it for SPLASH_MIN_MS and then cross-fades into MushaFScreen).
 */
@Composable
fun WarattilSplashScreen(modifier: Modifier = Modifier) {

    // ── Breathing loop ────────────────────────────────────────────────────
    // Continuous 0.96 ↔ 1.04 scale over 1.4 s with reverse. Same cadence
    // as iOS `withAnimation(.easeInOut(duration: 1.4).repeatForever(...))`.
    val transition = rememberInfiniteTransition(label = "splashBreathe")
    val breathe by transition.animateFloat(
        initialValue = 0.96f,
        targetValue  = 1.04f,
        animationSpec = infiniteRepeatable(
            animation  = tween(durationMillis = 1400, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "breatheScale"
    )

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(SPLASH_CREAM),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(22.dp)
        ) {
            // ── Logo — circle-clipped tight around the green medallion ─────
            //
            // The source drawable `splash_logo.png` is 432×432 with a
            // circular green medallion occupying the CENTER 311 px — i.e.
            // the medallion diameter is 311/432 ≈ 72 % of the image edge.
            // The remaining 14 % on each side is transparent / padded
            // canvas the adaptive-icon splash pipeline uses as safe-zone.
            //
            // The system SplashScreen API on Stage 1 automatically
            // circle-crops that padding away (that's how adaptive icons
            // render on Android 12+). In Compose there is no such
            // automatic crop — a naive `Image(size=200.dp)` paints the
            // FULL 432 px canvas scaled to 200 dp, so the medallion
            // itself only fills ~144 dp, leaving a visible tan annulus.
            //
            // Nasser 2026-04-22 (round 3): "use the same logo as the old
            // intro; it is perfectly cropped without any unnecessary
            // border." So we replicate the system's circular mask:
            //
            //   • Wrap the Image in a 200 dp Box clipped to CircleShape.
            //   • Render the Image OVERSIZED at 278 dp via
            //     `requiredSize` — see constraint-propagation note below.
            //     Because the medallion is 72 % of the image, rendering
            //     at 278 dp makes the medallion 278 × 0.72 ≈ 200 dp —
            //     exactly filling the 200 dp circular clip edge-to-edge.
            //   • The 14 % transparent padding falls OUTSIDE the clip
            //     radius and is discarded, so the visible circle is
            //     pure green medallion — no halo, no border.
            //
            // ⚠️  Constraint-propagation gotcha (2026-04-22 round 4):
            // The outer Box's `.size(200.dp)` passes a HARD 200 × 200 dp
            // min/max constraint to children. `Modifier.size(278.dp)` on
            // the Image is a PREFERRED size that the parent is allowed
            // to override, so the Image was getting silently capped back
            // to 200 dp — meaning no oversize happened at all and the
            // medallion rendered at its natural ~144 dp inside the
            // clip, leaving the tan annulus visible. We use
            // `Modifier.requiredSize(278.dp)` here because
            // `requiredSize` ignores incoming constraints and really
            // does force the Image to 278 dp. Do not "simplify" this
            // back to `size` — the annulus returns.
            //
            // The logo asset itself is untouched; we're only masking and
            // scaling at paint time. Breathing / shadow live on the Box
            // so they drive the whole clipped composite.
            //
            // (If splash_logo.png is ever re-exported with different
            // internal padding, recompute: IMAGE_SIZE = 200 dp / (green
            // diameter / image edge). A different asset ratio will
            // otherwise reintroduce the halo.)
            Box(
                modifier = Modifier
                    .size(200.dp)
                    .scale(breathe)
                    .shadow(
                        elevation = 12.dp,
                        shape     = CircleShape,
                        clip      = false
                    )
                    .clip(CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Image(
                    painter            = painterResource(id = R.drawable.splash_logo),
                    contentDescription = null,
                    contentScale       = ContentScale.Crop,
                    modifier           = Modifier.requiredSize(278.dp)
                )
            }

            // ── Muzzammil ayah block ────────────────────────────────────
            //
            // Bracket orientation note (copied from iOS):
            //   ﴾ (U+FD3F) opens to the RIGHT  — shape ≈ "{"
            //   ﴿ (U+FD3E) opens to the LEFT   — shape ≈ "}"
            // For the curves to embrace the ayah INWARD we place ﴾ on the
            // visual LEFT and ﴿ on the visual RIGHT. Under an LTR layout-
            // direction on the Row, source order = visual order, so ﴾
            // comes first and ﴿ comes last. The inner ayah keeps RTL so
            // its words flow naturally right-to-left.
            CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
                Row(
                    verticalAlignment     = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    // Ayah size bumped 22 → 30 sp (Nasser 2026-04-22 round 5:
                    // "if you can enlarge the ayah text size it would be
                    // nice"). Brackets scaled proportionally 26 → 36 sp so
                    // the ornate glyphs stay slightly taller than the ayah
                    // body — the same visual ratio iOS uses.
                    Text(
                        text       = "﴾",
                        color      = SPLASH_GOLD,
                        fontSize   = 36.sp,
                        fontFamily = LockedSplashFont.uthmanic
                    )
                    Text(
                        text       = "وَرَتِّلِ ٱلْقُرْءَانَ تَرْتِيلًا",
                        color      = SPLASH_CHARCOAL,
                        fontSize   = 30.sp,
                        fontFamily = LockedSplashFont.uthmanic,
                        style      = TextStyle(textDirection = TextDirection.Rtl)
                    )
                    Text(
                        text       = "﴿",
                        color      = SPLASH_GOLD,
                        fontSize   = 36.sp,
                        fontFamily = LockedSplashFont.uthmanic
                    )
                }
            }

            // ── Attribution — Amiri chrome, gold @ 80 % ─────────────────
            // Reads as a scholarly citation rather than Quranic text.
            // Eastern Arabic numeral ٤ matches WARATTIL's digit style.
            Text(
                text       = "سورة المزمّل ـ الآية ٤",
                color      = SPLASH_GOLD.copy(alpha = 0.80f),
                fontSize   = 13.sp,
                fontFamily = LockedSplashFont.chrome,
                style      = TextStyle(textDirection = TextDirection.Rtl)
            )
        }
    }
}
