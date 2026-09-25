package com.warattil.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.warattil.app.core.WarattilConstants.Hifz

// =============================================================================
// WirdResumeChip — «↩ تابع وردك · ص N»
//
// Calm, optional affordance for returning to the wird ribbon after a jump.
// Renders as a single-line gold-tinted chip just above the footer; only
// appears when the reader has wandered off the wird high-water mark
// (today_max_continuous_page) — see MushaFViewModel.wirdResumePage.
//
// Design rationale (locked 2026-04-27 — Nasser confirmed):
//   • Zero required action during normal sequential reading.  The chip
//     is hidden when currentPage is on or near the wird ribbon (±2
//     pages tolerance).
//   • One optional tap to return after a real jump (Friday Al-Kahf,
//     Fihris navigation, search-to-page).  Tap → navigate back to the
//     ribbon page; the engine's max_continuous stays put because
//     that's the whole point of the ribbon.
//   • Single line, plain Arabic, no jargon — readable at a glance by
//     elder users.  The «↩» prefix telegraphs "return"; the «ص N»
//     suffix tells them exactly where they're going.
//
// Usage: place above MushaFFooter inside a Column in the Scaffold's
// bottomBar slot.  When [resumePage] is null this composable renders
// NOTHING (zero height), so the footer sits flush against the page
// content during normal reading.  When non-null the chip slides into
// view above the footer.
//
// Naming canon: see project_warattil_wird_requirements memory note.
//   • «تابع وردك» = continue your wird (verb, action-oriented)
//   • «ص N»      = "p. N" — Eastern-Arabic digit
// =============================================================================

@Composable
fun WirdResumeChip(
    resumePage : Int?,
    font       : QuranFontInfo,
    theme      : ThemeColors,
    onTap      : () -> Unit
) {
    if (resumePage == null) return  // off — zero height, no tree

    // 2026-04-27 (pt. 6): the outer fillMaxWidth + Center wrapper is gone.
    // The chip is now embedded INLINE inside FooterWirdActive's Row,
    // alongside the motivation message — saves ~24dp of bottomBar
    // height and lets the chip size to its content (no full-row
    // takeover).  Returns just the pill itself; caller handles
    // alignment in its own layout context.
    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(16.dp))
            .background(Hifz.HIFZ_GOLD.copy(alpha = 0.10f))
            .border(
                width = 0.75.dp,
                color = Hifz.HIFZ_GOLD.copy(alpha = 0.45f),
                shape = RoundedCornerShape(16.dp)
            )
            .clickable(onClick = onTap)
            .padding(horizontal = 10.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text       = "↩",
            color      = Hifz.HIFZ_GOLD,
            fontSize   = 13.sp,
            fontWeight = FontWeight.Bold
        )
        Spacer(Modifier.width(5.dp))
        Text(
            text       = "تابع وردك",
            color      = Hifz.HIFZ_GOLD,
            fontSize   = 12.sp,
            fontWeight = FontWeight.SemiBold,
            fontFamily = font.family,
            style      = TextStyle(textDirection = TextDirection.Rtl)
        )
        Spacer(Modifier.width(4.dp))
        Text(
            text     = "·",
            color    = Hifz.HIFZ_GOLD.copy(alpha = 0.55f),
            fontSize = 12.sp
        )
        Spacer(Modifier.width(4.dp))
        Text(
            text       = "ص ${resumePage.toArabicDigits()}",
            color      = Hifz.HIFZ_GOLD,
            fontSize   = 12.sp,
            fontWeight = FontWeight.SemiBold,
            fontFamily = FontFamily.Default,   // page digits — kill GSUB
            style      = TextStyle(textDirection = TextDirection.Rtl)
        )
    }
}
