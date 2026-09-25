package com.warattil.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.warattil.app.data.UserPreferences

// =============================================================================
// MushaFFooter — two-mode footer
//
// MODE A — wird active (prefs.wirdStartDate != null):
//   ┌────────────────────────────────────────────────────────────────┐
//   │                      أتممت ورد اليوم                           │ ← motivation line (tier colour)
//   │  ⟨ ٢ ⟩  ٨٠٪  ░░░░░░░████████████████████   ورد اليوم           │ ← unified row (RTL, bar fills R→L)
//   └────────────────────────────────────────────────────────────────┘
//
// MODE B — no wird configured (prefs.wirdStartDate == null):
//   ┌────────────────────────────────────────────────────────────────┐
//   │  ⟨ ٢ ⟩         اضبط ورد اليوم — اضغط للبدء                     │ ← single tappable row, page badge + invite
//   └────────────────────────────────────────────────────────────────┘
//
// Why two modes (Nasser feedback 2026-04-25):
//   When no wird is set, the engine falls back to a Quran-completion
//   ratio (currentPage / 604), but the bar's chip still says "ورد اليوم"
//   and the tier message reads as if there's a real plan in progress —
//   creating a phantom-plan illusion.  Replacing the bar with an
//   explicit «اضبط ورد اليوم» tappable line removes the ambiguity:
//   the reader sees at a glance that no plan is set and has a one-tap
//   path to start one.  Non-catalog: not a new menu surface, just a
//   clearer state for an existing slot.
//
// Design intent for MODE A (mirrors Ayah / Golden-Quran reference apps):
//   • The chip label "ورد اليوم" anchors the RIGHT side (the logical start in RTL).
//   • The progress bar fills from right → left: as the user's wird % grows,
//     the coloured portion extends from the right-hand edge toward the left.
//     This is automatic once the row is inside LayoutDirection.Rtl because
//     LinearProgressIndicator honours LocalLayoutDirection.
//   • The percentage label sits to the VISUAL LEFT of the bar — that is the
//     "leading edge" of progress in RTL, so the number always reads right
//     next to where the filled portion currently ends.
//   • The OrnatePageBadge anchors the far-LEFT (the logical end in RTL).
//
// Momentum law (30-40-30-Beyond):
//   ratio < 0.30  → Red     ·  ratio < 0.70  → Amber
//   ratio ≤ 1.0   → Green   ·  ratio > 1.0   → Sky Blue
//
// Page number uses FontFamily.Default — the KFGQPC Uthmanic font applies
// OpenType GSUB digit→ayah-badge substitution, which caps at ~2 digits per
// glyph and therefore mangles page numbers ≥100. Plain font renders cleanly.
// =============================================================================

@Composable
fun MushaFFooter(
    currentPage    : Int,
    wirdRatio      : Float,
    wirdColor      : androidx.compose.ui.graphics.Color,
    wirdMessage    : String,
    font           : QuranFontInfo,
    theme          : ThemeColors,
    prefs          : UserPreferences?,
    wirdTarget     : Int?,
    // ── WirdResumeChip integration (2026-04-27 pt. 6) ────────────────────
    // The chip used to live in its own row above the footer; merged INTO
    // the footer's first row alongside the motivation message to claw
    // back ~24dp of bottomBar height — body content gets more room.
    // resumePage non-null = chip visible (reader has wandered off the
    // wird ribbon).  onWirdResumeTap navigates back to the ribbon.
    wirdResumePage : Int?         = null,
    onWirdResumeTap: () -> Unit   = {},
    // Tap target for the "no wird" state's «اضبط ورد اليوم» line.
    // Should open WirdDialog from the parent screen.
    onWirdSetClick : () -> Unit = {}
) {
    val wirdActive = prefs?.wirdStartDate != null

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(theme.background)
            .navigationBarsPadding()
            .padding(start = 14.dp, end = 14.dp, top = 4.dp, bottom = 6.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        if (wirdActive) {
            // ── MODE A: wird active ─────────────────────────────────────────
            FooterWirdActive(
                currentPage     = currentPage,
                wirdRatio       = wirdRatio,
                wirdColor       = wirdColor,
                wirdMessage     = wirdMessage,
                font            = font,
                theme           = theme,
                resumePage      = wirdResumePage,
                onResumeTap     = onWirdResumeTap
            )
        } else {
            // ── MODE B: no wird configured ──────────────────────────────────
            //   wirdRatio + wirdMessage already fall back to whole-Quran
            //   completion when no wird is set (see wirdProgressRatio
            //   and wirdProgressMessage in MushaFViewModel) — so the same
            //   variables drive the calm "reading progress" strip below.
            FooterNoWird(
                currentPage  = currentPage,
                quranRatio   = wirdRatio,
                quranColor   = wirdColor,
                quranMessage = wirdMessage,
                font         = font,
                theme        = theme
            )
        }
    }
}

// =============================================================================
// MODE A — wird-active footer (existing layout)
// =============================================================================

@Composable
private fun FooterWirdActive(
    currentPage : Int,
    wirdRatio   : Float,
    wirdColor   : androidx.compose.ui.graphics.Color,
    wirdMessage : String,
    font        : QuranFontInfo,
    theme       : ThemeColors,
    resumePage  : Int?            = null,
    onResumeTap : () -> Unit      = {}
) {
    // 2026-04-27 (pt. 3): cap at 100% — the cumulative-modulo wird
    // engine never emits ratio > 1.0 (Sky Blue state removed), so a
    // 1.5f ceiling here would just dead-code the upper range.
    val pctLabel = "${(wirdRatio.coerceIn(0f, 1f) * 100).toInt()}٪"

    // ── Top row: motivation message + (optional) wird-resume chip ──────
    //   Single row to claw back vertical space (Nasser 2026-04-27 pt. 6).
    //   When the reader is off the wird ribbon the chip joins the message
    //   on the same line; otherwise the message takes the full row.
    //   In RTL the message centers, the chip floats on the visual-LEFT
    //   (the leading edge of the row's free space).
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
        Row(
            modifier              = Modifier.fillMaxWidth(),
            verticalAlignment     = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Center
        ) {
            Text(
                text       = wirdMessage,
                color      = wirdColor,
                fontSize   = 13.sp,
                fontWeight = FontWeight.Medium,
                fontFamily = font.family,
                textAlign  = TextAlign.Center,
                maxLines   = 1,
                style      = TextStyle(textDirection = TextDirection.Rtl)
            )
            if (resumePage != null) {
                Spacer(Modifier.width(10.dp))
                WirdResumeChip(
                    resumePage = resumePage,
                    font       = font,
                    theme      = theme,
                    onTap      = onResumeTap
                )
            }
        }
    }

    Spacer(Modifier.height(5.dp))

    // ── Unified row (RTL): chip · bar · % · page badge ──────────────────
    // Logical order below translates to this visual order (right → left):
    //   [chip "ورد اليوم"] [bar (fills R→L)] [% label] [page badge]
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
        Row(
            modifier              = Modifier.fillMaxWidth().height(32.dp),
            verticalAlignment     = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text       = "ورد اليوم",
                color      = theme.text.copy(alpha = 0.55f),
                fontSize   = 11.sp,
                fontFamily = font.family,
                maxLines   = 1,
                style      = TextStyle(textDirection = TextDirection.Rtl)
            )
            LinearProgressIndicator(
                progress   = { wirdRatio.coerceIn(0f, 1f) },
                modifier   = Modifier
                    .weight(1f)
                    .height(12.dp)
                    .clip(RoundedCornerShape(6.dp)),
                color      = wirdColor,
                trackColor = theme.text.copy(alpha = 0.09f)
            )
            Text(
                text       = pctLabel,
                color      = wirdColor,
                fontSize   = 13.sp,
                fontWeight = FontWeight.Bold,
                fontFamily = FontFamily.Default,
                maxLines   = 1
            )
            OrnatePageBadge(pageNumber = currentPage, theme = theme)
        }
    }
}

// =============================================================================
// MODE B — no-wird footer (2026-04-27 pt. 4)
//
// REWRITTEN per Nasser's feedback: the previous tappable invite line
// «ابدأ ورداً يومياً» duplicated the «الورد اليومي» menu item — readers
// reported the redundancy as catalog-noise.  The new MODE B is a calm,
// non-tappable progress strip showing where the reader stands in the
// whole Mushaf — same visual chrome as MODE A but with a different
// chip label («تقدم القراءة») and the no-wird Quran-completion message
// pipeline.  Setting up a wird is now ONLY accessible from the menu —
// one path, no duplication.
//
// onWirdSetClick is no longer called but kept on the parameter list so
// existing call sites compile without modification (it's a defaulted
// no-op now).
// =============================================================================

@Composable
private fun FooterNoWird(
    currentPage    : Int,
    quranRatio     : Float,
    quranColor     : androidx.compose.ui.graphics.Color,
    quranMessage   : String,
    font           : QuranFontInfo,
    theme          : ThemeColors
) {
    val pctLabel = "${(quranRatio.coerceIn(0f, 1f) * 100).toInt()}٪"

    Text(
        text       = quranMessage,
        color      = quranColor,
        fontSize   = 13.sp,
        fontWeight = FontWeight.Medium,
        fontFamily = font.family,
        textAlign  = TextAlign.Center,
        maxLines   = 1,
        style      = TextStyle(textDirection = TextDirection.Rtl),
        modifier   = Modifier.fillMaxWidth()
    )

    Spacer(Modifier.height(5.dp))

    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
        Row(
            modifier              = Modifier.fillMaxWidth().height(32.dp),
            verticalAlignment     = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text       = "تقدم القراءة",
                color      = theme.text.copy(alpha = 0.55f),
                fontSize   = 11.sp,
                fontFamily = font.family,
                maxLines   = 1,
                style      = TextStyle(textDirection = TextDirection.Rtl)
            )
            LinearProgressIndicator(
                progress   = { quranRatio.coerceIn(0f, 1f) },
                modifier   = Modifier
                    .weight(1f)
                    .height(12.dp)
                    .clip(RoundedCornerShape(6.dp)),
                color      = quranColor,
                trackColor = theme.text.copy(alpha = 0.09f)
            )
            Text(
                text       = pctLabel,
                color      = quranColor,
                fontSize   = 13.sp,
                fontWeight = FontWeight.Bold,
                fontFamily = FontFamily.Default,
                maxLines   = 1
            )
            OrnatePageBadge(pageNumber = currentPage, theme = theme)
        }
    }
}

// =============================================================================
// OrnatePageBadge — Deep Gold double-ring circle with the current page number.
// Rendered at a fixed 36 dp so three-digit numbers (٥٥٧ etc.) still read clean.
// =============================================================================

@Composable
private fun OrnatePageBadge(
    pageNumber: Int,
    theme     : ThemeColors
) {
    Box(
        modifier = Modifier
            .size(34.dp)
            .clip(CircleShape)
            .background(theme.gold.copy(alpha = 0.10f))
            .border(width = 1.2.dp, color = theme.gold.copy(alpha = 0.55f), shape = CircleShape),
        contentAlignment = Alignment.Center
    ) {
        // Inner hairline ring — sits 3dp inside the outer border
        Box(
            modifier = Modifier
                .size(28.dp)
                .clip(CircleShape)
                .border(width = 0.6.dp, color = theme.gold.copy(alpha = 0.35f), shape = CircleShape)
        )
        // FontFamily.Default — avoids the Uthmanic digit→ayah-badge glyph bug.
        Text(
            text       = pageNumber.toArabicDigits(),
            color      = theme.gold,
            fontSize   = 13.sp,
            fontWeight = FontWeight.Bold,
            fontFamily = FontFamily.Default,
            maxLines   = 1
        )
    }
}

// =============================================================================
// Landscape momentum strip — 5dp bar pinned at bottom edge (unchanged)
// =============================================================================

@Composable
fun LandscapeMomentumStrip(
    wirdRatio : Float,
    wirdColor : androidx.compose.ui.graphics.Color,
    modifier  : Modifier = Modifier
) {
    LinearProgressIndicator(
        progress   = { wirdRatio.coerceIn(0f, 1f) },
        modifier   = modifier
            .fillMaxWidth()
            .height(5.dp),
        color      = wirdColor,
        trackColor = androidx.compose.ui.graphics.Color.Transparent
    )
}
