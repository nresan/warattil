package com.warattil.app.ui

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.warattil.app.R

// =============================================================================
// WARATTIL V3 — App-invite share card  (Android, 2026-04-24)
//
// Why this file exists
// --------------------
// Mirror of ios/Warattil/Warattil/UI/AppInviteShareCard.swift.  The "شارك
// ورتّل" overflow-menu item used to hand a plain Arabic paragraph to the
// system share sheet.  That text drops through WhatsApp / SMS fine but is a
// dead letter on Instagram Stories and looks like a cold link preview on
// Facebook / Twitter.  BLUEPRINT §11.4 upgrades the invite to a rendered
// card carrying:
//
//   ┌──────────────────────────────────────────────┐
//   │               ✦  ورتّل  ✦                       │
//   │         مصحف رقمي بخط عثماني كامل               │
//   │           بلا إعلانات · بلا إلهاء                │
//   │            ┌──────────────┐                  │
//   │            │   [QR code]  │                  │
//   │            └──────────────┘                  │
//   │           امسح لتحميل التطبيق                  │
//   │      ───────────  ﷺ  ───────────              │
//   │   قال النبي ﷺ: «من دلَّ على خير                 │
//   │        فله مثل أجر فاعله»                     │
//   │         ورتّل · warattil.org/get                │
//   └──────────────────────────────────────────────┘
//
// Caller renders this inside a `rememberGraphicsLayer` Box (on-screen preview
// sheet — V3's proven capture pattern from HifzLogSheet), captures to an
// Android Bitmap, and hands the bitmap to
// [com.warattil.app.core.ShareUtil.shareAppInvite].  Each destination app
// picks the subset it can render:
//   • Instagram Stories  → image only (dropped text/URL)
//   • Facebook / Twitter → image + URL (rich preview with the card)
//   • WhatsApp / Telegram → image + text (card visible, text falls in)
//   • SMS / Mail         → everything
//
// If the QR asset is somehow missing (shouldn't happen — warattil_qr.png is
// pinned at `res/drawable-nodpi/`) the card still renders with the headline,
// tagline, hadith, and attribution — graceful degradation beats a crash.
//
// Tone guardrail
// --------------
// Per product_direction: hadith framing stays on the one-time invitation
// path only.  It is NOT used on ayah-share / daily-status / garden-share
// payloads because those are recurring content and the framing would grow
// stale fast.  Keep this card the sole visual home for the hadith.
// =============================================================================

// -----------------------------------------------------------------------------
// Brand gold — matched to iOS AppInviteShareCard.swift (RGB 0.651, 0.482,
// 0.141) so the two platforms produce visually identical cards.  Not sourced
// from ThemeColors.gold because the share card is a deliberately-branded
// surface and should not flip across Heritage / Dark / Sepia themes.
// -----------------------------------------------------------------------------
private val InviteGold = Color(0xFFA67B24)

/**
 * Renders the app-invite card inside an RTL column bordered by a thin gold
 * hairline.  Pure presentation — no external state.  Caller owns the
 * `rememberGraphicsLayer` capture boilerplate exactly like
 * [DailyReadingShareCard].
 */
@Composable
fun AppInviteShareCard(
    theme: ThemeColors,
    modifier: Modifier = Modifier
) {
    val ctx        = LocalContext.current
    // Amiri for "chrome" text — wordmark, tagline, hadith body, attribution.
    val chrome     = remember(ctx) { FontFamily(Font(R.font.amiri_regular)) }
    val chromeBold = remember(ctx) { FontFamily(Font(R.font.amiri_bold)) }

    // QR decoded as ImageBitmap — not painterResource — because Compose only
    // exposes `filterQuality` on the Image(bitmap = …) overload.  We need
    // FilterQuality.None to keep the QR modules crisp at 220 dp (bilinear
    // blur smears the finder patterns and can break scanning).  Decoding
    // once inside remember() avoids re-allocating the bitmap on every
    // recomposition.  runCatching guards against a missing asset so the
    // rest of the card still renders — matches the graceful-degradation
    // contract spelled out in the file header.
    val qrBitmap = remember(ctx) {
        runCatching {
            BitmapFactory.decodeResource(ctx.resources, R.drawable.warattil_qr)
                ?.asImageBitmap()
        }.getOrNull()
    }

    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
        Column(
            modifier = modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(18.dp))
                .background(theme.background)
                .border(1.dp, InviteGold.copy(alpha = 0.35f), RoundedCornerShape(18.dp))
                .padding(horizontal = 24.dp, vertical = 26.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {

            // ── Wordmark ────────────────────────────────────────────────────
            //   Large gold "ورتّل" between two star glyphs.  This is the
            //   first visual beat — a receiver glancing at the card on
            //   Instagram Stories should identify the app in < 1 s.
            Row(
                verticalAlignment     = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                modifier              = Modifier.padding(top = 4.dp)
            ) {
                Text("✦", color = InviteGold.copy(alpha = 0.65f), fontSize = 18.sp)
                Text(
                    text       = "ورتّل",
                    color      = InviteGold,
                    fontSize   = 42.sp,
                    fontWeight = FontWeight.Bold,
                    fontFamily = chromeBold
                )
                Text("✦", color = InviteGold.copy(alpha = 0.65f), fontSize = 18.sp)
            }

            // ── Tagline ─────────────────────────────────────────────────────
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Text(
                    text       = "مصحف رقمي بخط عثماني كامل",
                    color      = theme.text.copy(alpha = 0.85f),
                    fontSize   = 17.sp,
                    fontWeight = FontWeight.Medium,
                    fontFamily = chrome
                )
                Text(
                    text       = "بلا إعلانات · بلا إلهاء",
                    color      = theme.text.copy(alpha = 0.65f),
                    fontSize   = 14.sp,
                    fontFamily = chrome
                )
            }

            // ── QR block ────────────────────────────────────────────────────
            //   The QR encodes warattil.org/get (UA-sniffing redirect →
            //   App Store on iOS, Play Store on Android).  White inset +
            //   gold border gives the code enough quiet zone to scan even
            //   when IG Stories tints the background.  interpolation=None
            //   is the Android analogue of SwiftUI's .interpolation(.none)
            //   — keeps the QR edges crisp instead of bilinearly blurred.
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp),
                modifier            = Modifier.padding(top = 6.dp)
            ) {
                if (qrBitmap != null) {
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(10.dp))
                            .background(Color.White)
                            .border(1.dp, InviteGold.copy(alpha = 0.35f), RoundedCornerShape(10.dp))
                            .padding(10.dp)
                    ) {
                        Image(
                            bitmap             = qrBitmap,
                            contentDescription = null,
                            modifier           = Modifier.size(220.dp),
                            contentScale       = ContentScale.Fit,
                            filterQuality      = FilterQuality.None
                        )
                    }
                }
                Text(
                    text       = "امسح لتحميل التطبيق",
                    color      = theme.text.copy(alpha = 0.6f),
                    fontSize   = 13.sp,
                    fontFamily = chrome
                )
            }

            // ── Divider with ﷺ glyph ───────────────────────────────────────
            //   Two thin hairlines flanking a small ﷺ.  Pure decoration —
            //   no functional role.  Uses a Row of three pieces so the
            //   hairlines stretch to fill whatever remains after the glyph.
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 30.dp, vertical = 0.dp)
                    .padding(top = 6.dp)
            ) {
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .height(1.dp)
                        .background(InviteGold.copy(alpha = 0.35f))
                )
                Text(
                    text       = "ﷺ",
                    color      = InviteGold.copy(alpha = 0.8f),
                    fontSize   = 16.sp,
                    fontFamily = chrome,
                    modifier   = Modifier.padding(horizontal = 10.dp)
                )
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .height(1.dp)
                        .background(InviteGold.copy(alpha = 0.35f))
                )
            }

            // ── Hadith ──────────────────────────────────────────────────────
            //   Kept on two lines so the card stays inside its 720 dp frame
            //   without awkward wrapping.
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Text(
                    text       = "قال النبي ﷺ:",
                    color      = theme.text.copy(alpha = 0.7f),
                    fontSize   = 13.sp,
                    fontFamily = chrome
                )
                Text(
                    text       = "«من دلَّ على خير فله مثل أجر فاعله»",
                    color      = theme.text,
                    fontSize   = 16.sp,
                    fontWeight = FontWeight.Medium,
                    fontFamily = chrome,
                    textAlign  = TextAlign.Center
                )
            }

            // ── Gold hairline ───────────────────────────────────────────────
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 40.dp, vertical = 0.dp)
                    .padding(top = 10.dp)
                    .height(1.dp)
                    .background(InviteGold.copy(alpha = 0.35f))
            )

            // ── Attribution ─────────────────────────────────────────────────
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier          = Modifier.padding(top = 4.dp)
            ) {
                Text(
                    text       = "ورتّل",
                    color      = InviteGold,
                    fontSize   = 13.sp,
                    fontWeight = FontWeight.Bold,
                    fontFamily = chromeBold
                )
                Text(
                    text       = "  ·  warattil.org/get",
                    color      = theme.text.copy(alpha = 0.5f),
                    fontSize   = 11.sp
                )
            }
        }
    }
}
