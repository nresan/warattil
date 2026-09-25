package com.warattil.app.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.warattil.app.R
import kotlinx.coroutines.delay

// =============================================================================
// DailyAcknowledgementPill — once-per-day return greeting
//
// Product principle (feedback_warattil_no_debt_accounting):
//   Each day stands alone.  When the reader returns, greet them with ONE of
//   two calm modes — then fade out and get out of the way:
//
//     YesterdayRead  → «أمس: قرأت ١٢ من ١٣ صفحة» or «أمس: أتممت الورد»
//     WelcomeBack    → «أهلاً بعودتك»   (multi-day gap — no mention of days)
//
//   The welcome-back mode is the more important of the two.  A user who
//   returns after any gap — one day or many — deserves a warm greeting, not
//   an accounting of missed time.  The return itself is what we honour.
//
//   The pill is deliberately:
//     • NOT tappable            — it's not an action, it's an acknowledgement
//     • NOT dismissable         — auto-fades on its own schedule
//     • NOT persistent          — appears once per day, never sticks around
//     • NOT shareable           — wird progress is an inward-pointing fact
//                                 (product_direction — only app/ayah shares)
//     • NOT judgemental         — no "you missed", no "catch up", no streak
//
// Shown/hidden control:
//   Caller (MushaFScreen) determines WHETHER to mount this composable based
//   on [MushaFViewModel.yesterdayAcknowledgement].  Once mounted it manages
//   its own lifecycle via LaunchedEffect + AnimatedVisibility and reports
//   back through [onAcknowledged] so the ViewModel can mark the pill as
//   shown for today (mark-on-show — see VM header for rationale).
//
// Visual anchor:
//   Positioned near the top of the Mushaf page area, just below the header
//   strip.  Calm neutrally-framed text in the theme's default text tone so
//   it reads as a greeting rather than an alert or notification banner.
//   Gold hairline border echoes the rest of the app's pill vocabulary
//   (AyahActionBar, DailyReadingShareCard).
// =============================================================================

/**
 * Renders the daily-acknowledgement pill if [ack] is non-null, auto-fading
 * after a short dwell.  Produces zero layout when [ack] is null — safe to
 * leave in the overlay tree unconditionally.
 *
 * @param ack        Acknowledgement to render (YesterdayRead or WelcomeBack).
 *                   Null → no-op.
 * @param theme      Active theme colours (text / background / gold accent).
 * @param onAcknowledged Called exactly once, the moment the pill first
 *                       appears on screen.  Caller should record today's
 *                       date so subsequent same-day opens skip the pill.
 */
@Composable
fun YesterdayAcknowledgementPill(
    ack: DailyAcknowledgement?,
    theme: ThemeColors,
    onAcknowledged: () -> Unit,
    modifier: Modifier = Modifier
) {
    // ── Lifecycle guard ──────────────────────────────────────────────────────
    // `visible` flips false after the dwell so AnimatedVisibility runs the
    // fade-out transition.  `remember(ack)` keys on the ack itself so a
    // swap-in of a new ack (shouldn't happen mid-session but defensive)
    // resets the timer cleanly.
    var visible by remember(ack) { mutableStateOf(ack != null) }

    // ── Mark-on-show ─────────────────────────────────────────────────────────
    // Fire onAcknowledged once, synchronously with the first frame the pill
    // renders on.  Rationale: if the user closes the app before the fade-out
    // completes, they still shouldn't see the pill again on the next open
    // — one greeting per day is the promise, regardless of how long they
    // looked at it.
    LaunchedEffect(ack) {
        if (ack == null) return@LaunchedEffect
        onAcknowledged()
        // Dwell ≈ 5 s.  Long enough for a glance, short enough that a
        // reader who's already focused on the Mushaf body doesn't feel
        // the pill is lingering.
        delay(5_000)
        visible = false
    }

    if (ack == null) return

    // ── Body copy ────────────────────────────────────────────────────────────
    // Yesterday-read mode has a completion variant («أمس: أتممت الورد») for
    // 100 % days because «أتممت» reads better than «١٣ من ١٣».  Welcome-back
    // mode is deliberately blank on any reference to time — no "X days
    // away", no "it's been a while".  Just «أهلاً بعودتك» — the return
    // itself is the thing we honour, see file header for rationale.
    val text = when (ack) {
        is DailyAcknowledgement.YesterdayRead ->
            if (ack.pagesRead >= ack.pagesGoal)
                "أمس: أتممت الورد"
            else
                "أمس: قرأت ${ack.pagesRead.toArabicDigits()} من ${ack.pagesGoal.toArabicDigits()} صفحة"
        is DailyAcknowledgement.WelcomeBack ->
            "أهلاً بعودتك"
    }

    val ctx    = LocalContext.current
    val chrome = remember(ctx) { FontFamily(Font(R.font.amiri_regular)) }

    AnimatedVisibility(
        visible = visible,
        enter   = fadeIn(tween(durationMillis = 300)),
        exit    = fadeOut(tween(durationMillis = 400)),
        modifier = modifier
    ) {
        CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
            Surface(
                color           = theme.background,
                contentColor    = theme.text,
                shape           = RoundedCornerShape(18.dp),
                tonalElevation  = 2.dp,
                shadowElevation = 4.dp,
                border          = BorderStroke(
                    width = 1.dp,
                    color = theme.gold.copy(alpha = 0.40f)
                )
            ) {
                Text(
                    text       = text,
                    color      = theme.text.copy(alpha = 0.85f),
                    fontSize   = 13.sp,
                    fontWeight = FontWeight.Medium,
                    fontFamily = chrome,
                    modifier   = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                )
            }
        }
    }
}
