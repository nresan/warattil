package com.warattil.app.widget

import android.content.Context
import android.widget.RemoteViews
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalSize
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.AndroidRemoteViews
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.ContentScale
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxHeight
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextAlign
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.warattil.app.MainActivity
import com.warattil.app.R
import com.warattil.app.azan.AzanScheduler
import com.warattil.app.azan.AzanSettings
import com.warattil.app.azan.PrayerTimes
import java.util.Calendar

// =============================================================================
// WarattilWidget — Heritage-Cream home-screen presence.
//
// HYBRID design (locked 2026-05-19, after a long iteration cycle):
//   - The reading state — logo + page/surah/juz + wird progress + daily
//     du'aa — is ALWAYS visible.  This is the widget's identity even
//     when Azan isn't configured.
//   - The next-prayer countdown line is ADDED only when Azan is enabled
//     AND a location is captured.  Renders as a single 18sp gold
//     centered chronometer between the upper band and the progress bar.
//   - No tap-to-enable prompt; no prayer-focused replacement layout.
//     If the user hasn't set up Azan, the widget still serves its
//     reading-state purpose without nagging.
//
//   Layout (Azan disabled — natural ~120dp):
//   ┌─────────────────────────────────────────────────────┐
//   │  [Logo 56dp]   صفحة ٥٥٧                             │
//   │                سورة الحديد                          │
//   │                الجزء ٢٧                             │
//   │  ███████████████░░░░░░░░░░░░░░░░░░░░░░  ٤٢٪          │
//   │  ربّ زدني علماً ونفعاً                                │
//   └─────────────────────────────────────────────────────┘
//
//   Layout (Azan enabled — adds the countdown line — ~150dp):
//   ┌─────────────────────────────────────────────────────┐
//   │  [Logo 56dp]   صفحة ٥٥٧                             │
//   │                سورة الحديد                          │
//   │                الجزء ٢٧                             │
//   │         الظهر بعد ٠١:٣٩:١٥                          │   ← 18sp gold, only when Azan on
//   │  ███████████████░░░░░░░░░░░░░░░░░░░░░░  ٤٢٪          │
//   │  ربّ زدني علماً ونفعاً                                │
//   └─────────────────────────────────────────────────────┘
//
//   Iteration history (preserved for posterity):
//     • pt.5 — chronometer inline at trailing edge of upper Row at 22sp.
//       Glance's Spacer(defaultWeight()) inside a Row failed to push
//       the AndroidRemoteViews to the trailing edge; chronometer
//       collapsed to zero width and disappeared.
//     • pt.6 — full pivot to prayer-focused widget (two prayer panels,
//       no reading state).  Worked when Azan was set up but became a
//       useless "tap to enable" prompt when it wasn't, and lost the
//       reading state entirely even for users who had it set up.
//     • pt.7 (CURRENT) — hybrid.  Reading state always.  Countdown is
//       additive.  No fallback prompts, no all-or-nothing.
//
//   Invariants:
//     • Heritage Cream background (#F5F5DC)
//     • Mushaf Green accents (#1B5E20)
//     • All digits rendered as Eastern-Arabic numerals (٠-٩)
//     • 30-40-30 wird progress colour law: <30% Red, 30-70% Amber,
//       ≥70% Green
//
//   SharedPreferences inputs (written by MushaFViewModel.onPageChanged):
//     last_read_page     Int    — current Mushaf page (1-604)
//     last_read_surah    String — Arabic surah name
//     last_read_juz      Int    — juz number (1-30)
//     widget_wird_ratio  Float  — daily wird completion ratio
// =============================================================================

class WarattilWidget : GlanceAppWidget() {

    override val sizeMode: SizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val prefs     = context.getSharedPreferences("warattil_prefs", Context.MODE_PRIVATE)
        val page      = prefs.getInt("last_read_page", 1).coerceIn(1, 604)
        val surahName = prefs.getString("last_read_surah", "") ?: ""
        val juz       = prefs.getInt("last_read_juz", 1).coerceIn(1, 30)
        val ratio     = prefs.getFloat("widget_wird_ratio", 0f)

        // Resolve next-prayer countdown only if Azan is set up.
        // Returns null when feature is off or no location — in that case the
        // chronometer Row is simply not rendered (no fallback prompt, no
        // empty space).
        val azanState = buildAzanChronometerState(context)

        provideContent { WidgetContent(context, page, surahName, juz, ratio, azanState) }
    }

    // --------------------------------------------------------------------- //
    //  Root content
    // --------------------------------------------------------------------- //

    @Composable
    private fun WidgetContent(
        context  : Context,
        page     : Int,
        surahName: String,
        juz      : Int,
        ratio    : Float,
        azanState: AzanChronometerState?
    ) {
        val barColor = progressColor(ratio)
        val pageStr  = toArabicDigits(page)
        val juzStr   = toArabicDigits(juz)
        val pctStr   = "${(ratio.coerceIn(0f, 1.5f) * 100).toInt()}٪"

        Box(
            modifier = GlanceModifier
                .fillMaxSize()
                .background(ColorProvider(CREAM))
                .cornerRadius(14.dp)
                .clickable(actionStartActivity<MainActivity>())
                .padding(horizontal = 12.dp, vertical = 10.dp)
        ) {
            Column(modifier = GlanceModifier.fillMaxWidth()) {

                // ── Upper band: logo + page/surah/juz column ─────────────
                Row(
                    modifier          = GlanceModifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Image(
                        provider           = ImageProvider(R.mipmap.ic_launcher),
                        contentDescription = null,
                        modifier           = GlanceModifier.size(56.dp).cornerRadius(12.dp),
                        contentScale       = ContentScale.Fit
                    )
                    Spacer(GlanceModifier.width(12.dp))
                    Column(
                        modifier          = GlanceModifier.defaultWeight(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text     = "صفحة $pageStr",
                            style    = TextStyle(
                                color      = ColorProvider(CHARCOAL),
                                fontSize   = 17.sp,
                                fontWeight = FontWeight.Bold
                            ),
                            maxLines = 1
                        )
                        if (surahName.isNotBlank()) {
                            Text(
                                text     = "سورة $surahName",
                                style    = TextStyle(
                                    color      = ColorProvider(MUSHAF_GREEN),
                                    fontSize   = 13.sp,
                                    fontWeight = FontWeight.Medium
                                ),
                                maxLines = 1
                            )
                        }
                        Text(
                            text     = "الجزء $juzStr",
                            style    = TextStyle(
                                color    = ColorProvider(CHARCOAL_SOFT),
                                fontSize = 11.sp
                            ),
                            maxLines = 1
                        )
                    }
                }

                // ── Optional Azan countdown line (only when Azan enabled) ──
                // Stays on its OWN row for rendering reliability — Glance's
                // Spacer-weight inside a Row doesn't reliably push
                // AndroidRemoteViews, so we don't try to inline it.
                if (azanState != null) {
                    Spacer(GlanceModifier.height(4.dp))
                    Box(
                        modifier         = GlanceModifier.fillMaxWidth(),
                        contentAlignment = Alignment.Center
                    ) {
                        AndroidRemoteViews(
                            remoteViews = buildAzanChronometerRemoteViews(context, azanState)
                        )
                    }
                    Spacer(GlanceModifier.height(4.dp))
                } else {
                    Spacer(GlanceModifier.height(8.dp))
                }

                // ── Wird progress bar + % label ───────────────────────────
                MomentumRow(ratio = ratio, barColor = barColor, pctStr = pctStr)

                // ── Daily ma'thūr du'aa — bottom anchor ────────────────────
                Spacer(GlanceModifier.height(8.dp))
                Text(
                    text     = DailyDuaa.forToday(),
                    style    = TextStyle(
                        color      = ColorProvider(AZAN_GOLD),
                        fontSize   = 11.sp,
                        fontWeight = FontWeight.Normal,
                        textAlign  = TextAlign.Center
                    ),
                    maxLines = 2,
                    modifier = GlanceModifier.fillMaxWidth()
                )
            }
        }
    }

    // --------------------------------------------------------------------- //
    //  Momentum bar
    //
    //  Fixes the broken 50/50 defaultWeight rendering by computing the
    //  filled / empty widths in real Dp from the current widget size.
    //
    //  Quantisation law (matches project directive):
    //      ratio100 = (clampedRatio * 100).toInt()
    //      fillDp   = barTotal * (ratio100 / 100f)
    //      emptyDp  = barTotal - fillDp
    // --------------------------------------------------------------------- //

    @Composable
    private fun MomentumRow(ratio: Float, barColor: Color, pctStr: String) {
        val clamped  = ratio.coerceIn(0f, 1f)
        val ratio100 = (clamped * 100).toInt().coerceIn(0, 100)
        val overGoal = ratio > 1f

        val totalWidth = LocalSize.current.width
        val barTotalDp = (totalWidth - 24.dp - 44.dp).coerceAtLeast(60.dp)
        val fillDp     = if (overGoal) barTotalDp else barTotalDp * (ratio100 / 100f)
        val emptyDp    = barTotalDp - fillDp

        Row(
            modifier          = GlanceModifier.fillMaxWidth().height(14.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(modifier = GlanceModifier.width(barTotalDp).height(8.dp)) {
                if (fillDp > 0.dp) {
                    Box(
                        modifier = GlanceModifier
                            .width(fillDp)
                            .fillMaxHeight()
                            .background(ColorProvider(barColor))
                            .cornerRadius(4.dp)
                    ) {}
                }
                if (emptyDp > 0.dp) {
                    Box(
                        modifier = GlanceModifier
                            .width(emptyDp)
                            .fillMaxHeight()
                            .background(ColorProvider(TRACK))
                            .cornerRadius(4.dp)
                    ) {}
                }
            }

            Spacer(GlanceModifier.width(6.dp))

            Text(
                text     = pctStr,
                style    = TextStyle(
                    color      = ColorProvider(barColor),
                    fontSize   = 10.sp,
                    fontWeight = FontWeight.Bold,
                    textAlign  = TextAlign.End
                ),
                maxLines = 1,
                modifier = GlanceModifier.defaultWeight()
            )
        }
    }

    // --------------------------------------------------------------------- //
    //  Helpers
    // --------------------------------------------------------------------- //

    private fun progressColor(ratio: Float): Color = when {
        ratio >= 0.70f -> Color(0xFF1B5E20)
        ratio >= 0.30f -> Color(0xFFFFA000)
        else           -> Color(0xFFD32F2F)
    }

    private fun toArabicDigits(n: Int): String {
        val e = charArrayOf('٠','١','٢','٣','٤','٥','٦','٧','٨','٩')
        return n.toString().map { c -> if (c.isDigit()) e[c - '0'] else c }.joinToString("")
    }

    companion object {
        private val CREAM         = Color(0xFFF5F5DC)
        private val CHARCOAL      = Color(0xFF1A1A1A)
        private val CHARCOAL_SOFT = Color(0xFF556055)
        private val MUSHAF_GREEN  = Color(0xFF1B5E20)
        private val AZAN_GOLD     = Color(0xFF996515)
        private val TRACK         = Color(0x22000000)

        /**
         * State passed from provideGlance into the Composable describing how
         * the optional Azan chronometer line should be configured.
         *
         *   - BEFORE_PRAYER counts DOWN to the next prayer's fire time.
         *     Format «الفجر بعد %s».  baseMillis = future fire time.
         *   - POST_PRAYER counts UP from the moment of fire for 20 min.
         *     Format «الفجر قبل %s».  baseMillis = past fire time.
         *     At T+20min the AlarmManager-scheduled refresh swaps back
         *     to BEFORE_PRAYER for the next upcoming prayer.
         *
         * Null when Azan is disabled or no location is set — in that case
         * the WidgetContent simply omits the chronometer Row and the
         * widget reads as pure reading state.
         */
        data class AzanChronometerState(
            val prayerName: String,
            val baseMillis: Long,
            val phase     : Phase
        )

        enum class Phase { BEFORE_PRAYER, POST_PRAYER }

        /**
         * Compute the chronometer state, or null if Azan isn't enabled or
         * we don't have a location.  If a prayer fired within the last
         * 20 minutes, returns POST_PRAYER; otherwise BEFORE_PRAYER for
         * the next upcoming prayer.
         *
         * Side effect: while inside the post-prayer window, re-schedules
         * the T+20 widget-refresh alarm at `lastFiredTime + WINDOW`.
         * Belt-and-suspenders against force-stop / Doze drop of the
         * original alarm.
         */
        fun buildAzanChronometerState(context: Context): AzanChronometerState? {
            if (!AzanSettings.isEnabled(context)) return null
            val loc = AzanSettings.getLocation(context) ?: return null

            val prefs = context.getSharedPreferences("warattil_prefs", Context.MODE_PRIVATE)
            val lastFiredTime = prefs.getLong(AzanScheduler.PREF_LAST_FIRED_TIME, 0L)
            val lastFiredName = prefs.getString(AzanScheduler.PREF_LAST_FIRED_PRAYER, null)
            val nowMs         = System.currentTimeMillis()

            if (lastFiredTime > 0L && lastFiredName != null &&
                nowMs - lastFiredTime < AzanScheduler.POST_PRAYER_WINDOW_MS
            ) {
                val prayer = runCatching { PrayerTimes.Prayer.valueOf(lastFiredName) }.getOrNull()
                if (prayer != null) {
                    AzanScheduler.scheduleRefreshAt(
                        context,
                        lastFiredTime + AzanScheduler.POST_PRAYER_WINDOW_MS
                    )
                    return AzanChronometerState(
                        prayerName  = prayer.arabicName,
                        baseMillis  = lastFiredTime,
                        phase       = Phase.POST_PRAYER
                    )
                }
            }

            // Defensive cleanup: stale post-prayer prefs (window expired)
            // get cleared so subsequent reads don't reanimate POST_PRAYER.
            if (lastFiredTime > 0L && nowMs - lastFiredTime >= AzanScheduler.POST_PRAYER_WINDOW_MS) {
                prefs.edit()
                    .remove(AzanScheduler.PREF_LAST_FIRED_TIME)
                    .remove(AzanScheduler.PREF_LAST_FIRED_PRAYER)
                    .apply()
            }

            val now    = Calendar.getInstance()
            val next   = PrayerTimes.nextAfter(now, loc.first, loc.second)
            val target = now.timeInMillis + next.minutesUntil * 60_000L
            return AzanChronometerState(
                prayerName  = next.prayer.arabicName,
                baseMillis  = target,
                phase       = Phase.BEFORE_PRAYER
            )
        }

        /**
         * Build the RemoteViews holding the live-ticking Chronometer line
         * with the prayer-name prefix and BEFORE/POST format string.
         */
        fun buildAzanChronometerRemoteViews(
            context: Context,
            state  : AzanChronometerState
        ): RemoteViews {
            val nowMs               = System.currentTimeMillis()
            val nowElapsed          = android.os.SystemClock.elapsedRealtime()
            val baseElapsedRealtime = nowElapsed + (state.baseMillis - nowMs)

            val rv = RemoteViews(context.packageName, R.layout.widget_azan_chronometer)
            when (state.phase) {
                Phase.BEFORE_PRAYER -> {
                    rv.setChronometer(
                        R.id.azan_chronometer,
                        baseElapsedRealtime,
                        "${state.prayerName} بعد %s",
                        true
                    )
                    rv.setChronometerCountDown(R.id.azan_chronometer, true)
                }
                Phase.POST_PRAYER -> {
                    rv.setChronometer(
                        R.id.azan_chronometer,
                        baseElapsedRealtime,
                        "${state.prayerName} قبل %s",
                        true
                    )
                    rv.setChronometerCountDown(R.id.azan_chronometer, false)
                }
            }
            return rv
        }
    }
}
