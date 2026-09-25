package com.warattil.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
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
import com.warattil.app.core.WarattilConstants.Mushaf
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// =============================================================================
// WARATTIL V3 — Daily reading status share card  (Android, 2026-04-24)
//
// Why this file exists
// --------------------
// Mirror of ios/Warattil/Warattil/UI/DailyReadingShareCard.swift.  Readers want
// to post today's reading progress to WhatsApp / Telegram / Instagram Stories /
// Facebook / Twitter.  Plain-text payloads drop through IG and look like spam
// on Twitter, so we render a self-contained PNG that carries the pages-read
// number, location in the Mushaf, the Wird-engine tier message, and the
// "ورتّل · warattil.org/get" brand strip.
//
//   ┌──────────────────────────────────────────────┐
//   │               ✦  ورد اليوم  ✦                  │
//   │         الجمعة ٢٤ أبريل ٢٠٢٦                    │
//   │                                              │
//   │     ████████████████▒▒▒▒▒▒▒▒  ٦٠٪              │
//   │                                              │
//   │          قرأت ١٢ / ٢٠ صفحة                    │
//   │        سورة البقرة · الجزء ٢                   │
//   │                                              │
//   │         شارفت على إتمام وردك                   │
//   │         ─────────────────                    │
//   │         ورتّل · warattil.org/get                │
//   └──────────────────────────────────────────────┘
//
// Tone guardrail
// --------------
// Nasser's standing copy rule (feedback_warattil_copy_tone / product_direction)
// forbids streak / gamification framing.  The headline number is
// pages-read-today (a fact, not a chain) and the tier message is the existing
// Wird vocabulary.  NEVER add "🔥 X-day streak" or similar.
//
// Rendering contract
// ------------------
// This file ships the pure-presentation composable [DailyReadingShareCard]
// and its input struct [DailyReadingCardData].  The caller (MushaFScreen)
// mounts the card inside a [rememberGraphicsLayer] Box on a preview sheet,
// taps share, calls `graphicsLayer.toImageBitmap().asAndroidBitmap()`, and
// hands the bitmap to [com.warattil.app.core.ShareUtil.shareDailyReading].
// Mirroring V3's HifzLogSheet on-screen-capture pattern keeps one proven
// approach to bitmap capture across all share surfaces in the app.
// =============================================================================

/**
 * Pure-data input for [DailyReadingShareCard].  Built at the call site from
 * the ViewModel's Wird-engine helpers — the card itself has no ViewModel
 * coupling so a test harness / preview can build a fixture without a running
 * repository.
 *
 * @property currentPage      Current Mushaf page (1 .. 604).
 * @property surahName        Arabic surah name for the current page.
 * @property juzNumber        Juz number for the current page (1 .. 30).
 * @property progressRatio    Wird progress ratio — already falls back to
 *                            currentPage/604 when no wird is configured.  May
 *                            exceed 1.0 in the surpassed-goal tier.
 * @property progressMessage  Tier-appropriate message from
 *                            [MushaFViewModel.wirdProgressMessage].
 * @property progressColor    Tiered progress colour — red / amber / green /
 *                            sky-blue from [MushaFViewModel.wirdProgressColor].
 * @property pagesReadToday   Pages read so far today against today's wird
 *                            goal.  Null when no wird is configured — the
 *                            main stat falls back to "الصفحة X من ٦٠٤".
 * @property dailyPagesGoal   Today's wird goal.  Null when no wird set.
 */
data class DailyReadingCardData(
    val currentPage:     Int,
    val surahName:       String,
    val juzNumber:       Int,
    val progressRatio:   Float,
    val progressMessage: String,
    val progressColor:   Color,
    val pagesReadToday:  Int?,
    val dailyPagesGoal:  Int?
)

// -----------------------------------------------------------------------------
// Brand gold — matched to iOS DailyReadingShareCard.swift exactly (RGB 0.651,
// 0.482, 0.141) so the two platforms produce visually identical cards.  Not
// sourced from ThemeColors.gold because the share card is a deliberately-
// branded surface and should not flip to Heritage's Deep Gold (#996515) or
// Dark's lower-saturation gold — one card aesthetic across all three themes.
// -----------------------------------------------------------------------------
private val ShareGold = Color(0xFFA67B24)

/**
 * Renders the daily-reading share card inside an RTL column bordered by a
 * thin gold hairline.  Pure presentation — no Wird-engine calls.  Caller is
 * responsible for capturing the composed tree via `rememberGraphicsLayer()`
 * and handing the resulting Bitmap to
 * [com.warattil.app.core.ShareUtil.shareDailyReading].
 */
@Composable
fun DailyReadingShareCard(
    data:  DailyReadingCardData,
    theme: ThemeColors,
    font:  QuranFontInfo,
    modifier: Modifier = Modifier
) {
    val ctx      = LocalContext.current
    // Amiri for "chrome" text (title, dates, percentage, tier msg, attribution)
    // so Arabic digits inside these strings harmonise with the body.  Matches
    // iOS's .warattilChrome(...).
    val chrome      = remember(ctx) { FontFamily(Font(R.font.amiri_regular)) }
    val chromeBold  = remember(ctx) { FontFamily(Font(R.font.amiri_bold)) }

    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
        Column(
            modifier = modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(18.dp))
                .background(theme.background)
                .border(1.dp, ShareGold.copy(alpha = 0.35f), RoundedCornerShape(18.dp))
                .padding(horizontal = 24.dp, vertical = 22.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {

            // ── Ornate header ───────────────────────────────────────────────
            //   Two thin star glyphs flanking the title — a cheap Kuttāb cue
            //   that tells the reader this is a ورتّل artefact at a glance.
            Row(
                verticalAlignment     = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Text("✦", color = ShareGold.copy(alpha = 0.65f), fontSize = 14.sp)
                Text(
                    text       = "ورد اليوم",
                    color      = ShareGold,
                    fontSize   = 22.sp,
                    fontWeight = FontWeight.Bold,
                    fontFamily = chromeBold
                )
                Text("✦", color = ShareGold.copy(alpha = 0.65f), fontSize = 14.sp)
            }

            // ── Date strip ──────────────────────────────────────────────────
            //   Gregorian only, per Nasser's call (2026-04-24): most users are
            //   more familiar with Gregorian, and showing Hijri alongside was
            //   adding friction (plus the Hijri line was rendering the
            //   Gregorian month name — ICU quirk).  Keep a single calendar
            //   line rather than build a two-calendar toggle that would
            //   violate the non-catalog principle.
            Text(
                text       = gregorianDateLine(),
                color      = theme.text.copy(alpha = 0.75f),
                fontSize   = 13.sp,
                fontFamily = chrome,
                modifier   = Modifier.padding(bottom = 4.dp)
            )

            // ── Progress bar ────────────────────────────────────────────────
            //   Tiered colour from wirdProgressColor.  Pinned LTR so the fill
            //   animates left-to-right — matches the live momentum bar on the
            //   Mushaf footer (MushaFFooter.kt).
            CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
                BoxWithConstraints(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 4.dp)
                        .height(12.dp)
                        .clip(RoundedCornerShape(6.dp))
                        .background(theme.text.copy(alpha = 0.10f))
                ) {
                    val clamped = data.progressRatio.coerceIn(0f, 1f)
                    val fillDp  = maxWidth * clamped
                    Box(
                        modifier = Modifier
                            .width(fillDp)
                            .height(12.dp)
                            .clip(RoundedCornerShape(6.dp))
                            .background(data.progressColor)
                    )
                }
            }

            // ── Percentage ──────────────────────────────────────────────────
            //   Understated, on its own line — the card reads calmly, not
            //   like a dashboard.
            Text(
                text       = percentText(data.progressRatio),
                color      = theme.text.copy(alpha = 0.6f),
                fontSize   = 12.sp,
                fontWeight = FontWeight.Medium,
                fontFamily = chrome
            )

            // ── Main stat ───────────────────────────────────────────────────
            //   Wird configured → "قرأت X / Y صفحة".  Otherwise a calm
            //   page-in-Mushaf readout so the card stays meaningful for
            //   readers who haven't set a wird.
            //
            //   Uses Amiri chrome (NOT the Uthmanic body font) because the
            //   Uthmanic font's GSUB digit→ayah-badge substitution caps at
            //   2 digits per glyph, and the no-wird fallback "الصفحة X من
            //   ٦٠٤" renders the 3-digit ٦٠٤ as a 2-digit rosette + stray
            //   digit (Nasser 2026-04-25).  Same root cause as #20 and
            //   the footer page badge.  Amiri renders Arabic-Indic digits
            //   cleanly and reads handsomely on the share card.
            Text(
                text       = mainStatText(data),
                color      = theme.text,
                fontSize   = 20.sp,
                fontWeight = FontWeight.Bold,
                fontFamily = chrome,
                textAlign  = TextAlign.Center,
                modifier   = Modifier.padding(top = 2.dp)
            )

            // ── Location — surah + juz ──────────────────────────────────────
            //   Uthmani-face Quran font so the surah name reads consistently
            //   with the Mushaf page underneath the card.
            Text(
                text       = "سورة ${data.surahName} · الجزء ${data.juzNumber.toArabicDigits()}",
                color      = theme.text.copy(alpha = 0.8f),
                fontSize   = 16.sp,
                fontFamily = font.family,
                textAlign  = TextAlign.Center
            )

            // ── Tier message ────────────────────────────────────────────────
            //   Pulled straight from wirdProgressMessage so it matches the
            //   footer message the reader sees live on the Mushaf page.
            Text(
                text       = data.progressMessage,
                color      = ShareGold,
                fontSize   = 14.sp,
                fontWeight = FontWeight.Medium,
                fontFamily = chrome,
                textAlign  = TextAlign.Center,
                modifier   = Modifier.padding(top = 4.dp)
            )

            // ── Gold hairline ───────────────────────────────────────────────
            //   Separates the stat block from the attribution strip.
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 40.dp, vertical = 0.dp)
                    .padding(top = 6.dp)
                    .height(1.dp)
                    .background(ShareGold.copy(alpha = 0.35f))
            )

            // ── Attribution ─────────────────────────────────────────────────
            //   ورتّل wordmark + brand URL — same pattern as HifzLogSheet's
            //   capturable-garden footer so a receiver who sees the image
            //   alone (Instagram Stories drops text + URL) still knows the
            //   source.
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier          = Modifier.padding(top = 2.dp)
            ) {
                Text(
                    text       = "ورتّل",
                    color      = ShareGold,
                    fontSize   = 13.sp,
                    fontWeight = FontWeight.Bold,
                    fontFamily = chromeBold
                )
                Text(
                    text       = "  ·  warattil.org/get",
                    color      = theme.text.copy(alpha = 0.45f),
                    fontSize   = 11.sp
                )
            }
        }
    }
}

// =============================================================================
// Derived-text helpers — isolated at file scope so they're easy to audit
// against their iOS mirrors in DailyReadingShareCard.swift.
// =============================================================================

/** "الجمعة ٢٤ أبريل ٢٠٢٦" — localised Arabic Gregorian date strip.
 *  No separator between weekday and date: the middle-dot "·" (U+00B7)
 *  renders almost identically to the Arabic-Indic zero "٠" (U+0660)
 *  in Amiri and most Arabic fonts, which made earlier screenshots read
 *  "٢٤٠ أبريل" instead of "٢٤ · أبريل".  Plain space avoids the
 *  ambiguity and reads naturally in Arabic convention. */
private fun gregorianDateLine(): String {
    val fmt = SimpleDateFormat("EEEE d MMMM yyyy", Locale("ar"))
    // Force Arabic-Indic digits even on Android versions where the ar locale
    // occasionally emits Western digits — mirrors the westernToArabicDigits
    // helper on iOS (FB14231108).
    return fmt.format(Date()).westernToArabicDigits()
}

/** "٦٠٪" — Arabic-Indic percent with the Arabic percent sign "٪". */
private fun percentText(ratio: Float): String {
    val pct = (ratio.coerceIn(0f, 1f) * 100f).toInt()
    return "${pct.toArabicDigits()}٪"
}

/** Adapts to whether a wird is configured. */
private fun mainStatText(data: DailyReadingCardData): String {
    val read = data.pagesReadToday
    val goal = data.dailyPagesGoal
    return if (read != null && goal != null) {
        "قرأت ${read.toArabicDigits()} / ${goal.toArabicDigits()} صفحة"
    } else {
        "الصفحة ${data.currentPage.toArabicDigits()} من ${Mushaf.TOTAL_PAGES.toArabicDigits()}"
    }
}

/** Fallback digit normaliser — SimpleDateFormat with Locale("ar") sometimes
 *  emits Western digits; this maps them to Arabic-Indic so the card never
 *  mixes numeral systems. */
private fun String.westernToArabicDigits(): String {
    val table = charArrayOf('٠','١','٢','٣','٤','٥','٦','٧','٨','٩')
    return buildString(length) {
        for (c in this@westernToArabicDigits) {
            if (c in '0'..'9') append(table[c - '0']) else append(c)
        }
    }
}
