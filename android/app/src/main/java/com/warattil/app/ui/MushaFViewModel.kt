package com.warattil.app.ui

import android.app.Application
import android.content.Context
import android.util.Log
import android.widget.Toast
import androidx.compose.ui.graphics.Color  // Compose Color — for momentum palette
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.warattil.app.core.WarattilConstants.Hifz
import com.warattil.app.core.WarattilConstants.Mushaf
import com.warattil.app.data.Bookmark
import com.warattil.app.data.MetadataParser
import com.warattil.app.data.PageContent
import com.warattil.app.data.QuranRepository
import com.warattil.app.data.ReadingTargetType
import com.warattil.app.data.SearchResult
import com.warattil.app.data.UserPreferences
import com.warattil.app.widget.WarattilWidgetReceiver
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap

// =============================================================================
// UI State
// =============================================================================

sealed class PageUiState {
    object Loading : PageUiState()
    data class Success(val content: PageContent) : PageUiState()
    data class Error(val message: String) : PageUiState()
}

/**
 * Acknowledgement shown once on the first app open of a new day.  Two modes,
 * both designed to greet the returning reader without any debt / race /
 * catchup framing — see `feedback_warattil_no_debt_accounting`.
 *
 *   • [YesterdayRead]   — the user did read yesterday.  Render the fact
 *                          line «أمس: قرأت X من Y صفحة» or «أمس: أتممت الورد»
 *                          at full completion.
 *   • [WelcomeBack]     — the user's last reading was BEFORE yesterday
 *                          (they skipped one or many days).  Render a calm
 *                          «أهلاً بعودتك» — nothing about the gap, nothing
 *                          about what was "missed."  The return itself is
 *                          the thing we honour.
 *
 * Presence of any variant implies the pill should be shown; null means skip.
 */
sealed class DailyAcknowledgement {
    data class YesterdayRead(val pagesRead: Int, val pagesGoal: Int) : DailyAcknowledgement()
    object WelcomeBack : DailyAcknowledgement()
}

// =============================================================================
// ViewModel
// =============================================================================

class MushaFViewModel(
    application: Application,
    private val repository: QuranRepository
) : AndroidViewModel(application) {

    // ── SharedPreferences ─────────────────────────────────────────────────────
    private val prefs = application.getSharedPreferences(Hifz.PREF_FILE, Context.MODE_PRIVATE)

    // ── Page memory ───────────────────────────────────────────────────────────

    /** Mushaf page (1-based) to open at launch — persisted across restarts. */
    /**
     * Page the app opens to on cold start.
     *
     * REWORKED 2026-04-27 (pt. 5): when a wird is active, the app prefers
     * the **wird ribbon** (today_max_continuous_page — the high-water
     * mark of contiguous sequential reading) over last_read_page.
     *
     * Why: Nasser's mental model is that the app should re-open at "the
     * page I should read to move forward with my wird".  If the user
     * read up to p.16 sequentially, then casually swiped forward to
     * p.100 to look at something, then closed the app — without this
     * fix the app would re-open at p.100 (the last-swiped page).  The
     * user expects p.16 (their wird ribbon) — the natural place to
     * resume the routine.
     *
     * The fallback is last_read_page, used when no wird is active
     * (today_max_continuous_page key is absent in that case).  Both
     * values are clamped to the valid Mushaf page range.
     */
    val startPage: Int = run {
        val ribbon   = prefs.getInt("today_max_continuous_page", 0)
        val lastRead = prefs.getInt("last_read_page", 1)
        val pick = if (ribbon >= 1) ribbon else lastRead
        pick.coerceIn(1, Mushaf.TOTAL_PAGES)
    }

    private val _currentPage = MutableStateFlow(startPage)
    val currentPage: StateFlow<Int> = _currentPage.asStateFlow()

    private val pageFlows = ConcurrentHashMap<Int, MutableStateFlow<PageUiState>>()

    // ── Triple Theme ──────────────────────────────────────────────────────────

    private val _appTheme = MutableStateFlow(
        AppTheme.entries.getOrNull(prefs.getInt("app_theme", 0)) ?: AppTheme.HERITAGE
    )
    val appTheme: StateFlow<AppTheme> = _appTheme.asStateFlow()

    fun setTheme(theme: AppTheme) {
        _appTheme.value = theme
        prefs.edit().putInt("app_theme", theme.ordinal).apply()
    }

    fun cycleTheme() = setTheme(
        AppTheme.entries[((_appTheme.value.ordinal + 1) % AppTheme.entries.size)]
    )

    // ── Bookmarks ─────────────────────────────────────────────────────────────

    val bookmarks: StateFlow<List<Bookmark>> = repository
        .getBookmarksFlow()
        .stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())

    fun isBookmarked(page: Int) = bookmarks.value.any { it.pageNumber == page }

    /** Toggle — multiple bookmarks allowed (no auto-clear). */
    fun toggleBookmark(page: Int) = viewModelScope.launch {
        if (isBookmarked(page)) repository.removeBookmark(page)
        else                     repository.saveBookmark(page)
    }

    fun deleteBookmark(page: Int) = viewModelScope.launch { repository.removeBookmark(page) }
    fun clearAllBookmarks()       = viewModelScope.launch { repository.clearAllBookmarks() }

    // ── User preferences (Wird) ───────────────────────────────────────────────

    val userPreferences: StateFlow<UserPreferences?> = repository
        .getUserPreferencesFlow()
        .stateIn(viewModelScope, SharingStarted.Eagerly, null)

    /**
     * Returns the daily pages goal derived from the user's wird target type.
     */
    fun wirdDailyPages(p: UserPreferences): Int = when (p.wirdTargetType) {
        ReadingTargetType.FINISH_IN_DAYS ->
            ((Mushaf.TOTAL_PAGES - p.wirdStartPage + 1).toFloat()
                    / p.wirdTargetValue.coerceAtLeast(1).toFloat())
                .toInt().coerceAtLeast(1)
        ReadingTargetType.PAGES_PER_DAY -> p.wirdTargetValue.coerceAtLeast(1)
        ReadingTargetType.JUZ_PER_DAY   ->
            (p.wirdTargetValue * (Mushaf.TOTAL_PAGES.toFloat() / Mushaf.TOTAL_JUZAA))
                .toInt().coerceAtLeast(1)
    }

    /**
     * Page the reader needs to reach to complete the CURRENT cycle.
     *
     * REWORKED 2026-04-27 (pt. 3): under the cumulative-modulo model
     * the wird is a sequence of fixed-size cycles, each `dailyPages`
     * long, starting from `wirdStartPage`.
     *   Cycle 1: pages [wirdStartPage+1 ... wirdStartPage+dailyPages]
     *   Cycle 2: pages [wirdStartPage+dailyPages+1 ... wirdStartPage+2*dailyPages]
     *   ...
     * This function returns the LAST page of the cycle the reader is
     * currently inside (the "100%" page — reaching it shows
     * «أتممت ورد اليوم»; the next sequential page wraps to 5%).
     *
     * Returns null when no wird is configured.
     */
    fun wirdTodayTargetPage(p: UserPreferences? = userPreferences.value): Int? {
        p ?: return null
        p.wirdStartDate ?: return null
        val ppd     = wirdDailyPages(p)
        val maxCont = prefs.getInt("today_max_continuous_page", p.wirdStartPage)
            .coerceAtLeast(p.wirdStartPage)
        val pagesRead = (maxCont - p.wirdStartPage).coerceAtLeast(0)
        // Cycle index (0-based): pagesRead 1..ppd → cycle 0,
        // pagesRead ppd+1..2*ppd → cycle 1, etc.  pagesRead == 0
        // means the reader hasn't moved yet — the first cycle's goal.
        val cycleIndex = if (pagesRead == 0) 0 else (pagesRead - 1) / ppd
        return (p.wirdStartPage + (cycleIndex + 1) * ppd)
            .coerceAtMost(Mushaf.TOTAL_PAGES)
    }

    /**
     * Wird-Centric Momentum Engine — CUMULATIVE MODULO CYCLING.
     *
     * REWORKED 2026-04-27 (pt. 3) per Nasser's mental-model clarification:
     * the wird mirrors the real-world Mushaf bookmark.  Reader reads N
     * pages, places ribbon, closes book.  Comes back same day or a week
     * later — ribbon is exactly where they left it, momentum picks up
     * from there.  Cycle auto-wraps on completion.
     *
     * Formula:
     *   pagesRead   = max_continuous − wirdStartPage     (cumulative)
     *   withinCycle = ((pagesRead − 1) mod dailyPages) + 1
     *   ratio       = withinCycle / dailyPages
     *
     * Progress walks 0 → 100% across each cycle.  When the reader
     * reaches the milestone page (e.g. page 21 with start=1, target=20)
     * the bar shows 100%.  The next sequential page (22) wraps to 5%
     * (1/20) — cycle 2 begins.  Same on day 1 or day 7 of inactivity:
     * the math is page-based, not date-based, so skipping days has
     * zero effect on progress.
     *
     * Sky Blue / >100% state REMOVED — Nasser's directive 2026-04-27.
     * The maximum visible state is 100% «أتممت ورد اليوم»; the next
     * page advances to a fresh cycle.  Display-side ratio is therefore
     * always in [0, 1.0].
     *
     * Falls back to whole-Quran completion ratio when no wird is set.
     */
    fun wirdProgressRatio(currentPage: Int, p: UserPreferences?): Float {
        if (p?.wirdStartDate == null) {
            // No wird set — fall back to Quran-completion ratio.
            return (currentPage.toFloat() / Mushaf.TOTAL_PAGES.toFloat())
                .coerceIn(0f, 1f)
        }
        val dailyPages = wirdDailyPages(p)
        // max_continuous = high-water mark of CONTIGUOUS forward reading
        // since wirdStartPage.  Sequential swipes advance it; jumps to
        // Al-Kahf, Fihris, search-to-page do not.  See onPageChanged.
        val maxCont = prefs.getInt("today_max_continuous_page", p.wirdStartPage)
            .coerceAtLeast(p.wirdStartPage)
        val pagesRead = (maxCont - p.wirdStartPage).coerceAtLeast(0)
        if (pagesRead == 0) return 0f

        // Modulo-with-snap-to-100% — the (pagesRead-1) % D + 1 form
        // ensures the milestone page reads as exactly 100%, not 0%
        // (a naive `pagesRead % D` would jump 95% → 0% across the
        // boundary; this form jumps 95% → 100% → 5% across two
        // pages, giving the reader a moment to see "completed!"
        // before the next cycle begins).
        val withinCycle = ((pagesRead - 1) % dailyPages) + 1
        return (withinCycle.toFloat() / dailyPages.toFloat())
            .coerceIn(0f, 1f)
    }

    /**
     * Three-tier color mapping (Sky Blue removed 2026-04-27).
     *
     * Because [wirdProgressRatio] now caps at 1.0f, the engine never
     * enters a "beyond goal" state — completion is always exactly
     * 100%, and the next page begins a new cycle at low single
     * digits.  We keep the 30-70-100 thresholds for the Red/Amber/
     * Green progression within each cycle.
     */
    fun wirdProgressColor(ratio: Float): Color = when {
        ratio >= 0.70f -> Color(0xFF1B5E20)  // Mushaf Green — approaching / at goal
        ratio >= 0.30f -> Color(0xFFFFA000)  // Amber — steady progress
        else           -> Color(0xFFD32F2F)  // Red — just beginning a cycle
    }

    /**
     * Returns the page the reader should "return to" to resume their wird,
     * or null when they're already on it (or have no wird configured).
     *
     * The wird ribbon = today_max_continuous_page (the high-water mark of
     * contiguous forward reading from today's anchor).  Sequential swipes
     * advance it; jumps to Al-Kahf, Fihris navigation, search-to-page DO
     * NOT advance it.  This function tells the UI whether the reader has
     * wandered off that ribbon and where to send them back.
     *
     * Tolerance: ±2 pages.  Verifying a verse one page back doesn't trip
     * the chip; a real jump (Al-Kahf, Fihris, search) does.  See
     * project_warattil_wird_requirements memory for the full semantic.
     *
     * Returns null when:
     *   • No wird is active (nothing to resume)
     *   • Reader is on the wird page (currentPage == max_continuous)
     *   • Reader is within tolerance of the wird page (|diff| ≤ 2)
     */
    fun wirdResumePage(currentPage: Int, p: UserPreferences?): Int? {
        if (p?.wirdStartDate == null) return null
        // The wird ribbon = max_continuous since wirdStartPage.  In the
        // cumulative-modulo model this never resets per day — it's the
        // overall sequential high-water mark.
        val maxCont = prefs.getInt("today_max_continuous_page", p.wirdStartPage)
            .coerceAtLeast(p.wirdStartPage)
        // Show the chip when the reader has clearly stepped off the
        // wird ribbon — more than 2 pages away in either direction.
        // Within ±2 they're verifying / hovering, which is normal
        // reading behaviour and shouldn't trigger a "return" prompt.
        return if (kotlin.math.abs(currentPage - maxCont) > 2) maxCont else null
    }

    /**
     * Returns the single momentum message for the footer.
     *
     * REWORKED 2026-04-27 (pt. 3): Sky Blue Duaa rotation REMOVED — see
     * [wirdProgressRatio] for the new cumulative-modulo cycling.
     * The maximum visible state is exactly 100% «أتممت ورد اليوم»;
     * the next sequential page begins a fresh cycle at low single
     * digits (Red tier).  No "beyond goal" celebration — that was
     * tied to the old per-day target arithmetic that this refactor
     * deletes.  No need for `currentPage` anymore.
     *
     * Tier boundaries (within each cycle):
     *   ratio == 1.0  → Green  → "أتممت ورد اليوم"
     *   ratio ≥ 0.70  → Green  → "شارفت على إتمام وردك"
     *   ratio ≥ 0.30  → Amber  → "عزيمة وإصرار"
     *   else          → Red    → "ابدأ وردك اليوم"
     */
    fun wirdProgressMessage(
        ratio : Float,
        p     : UserPreferences?,
        @Suppress("UNUSED_PARAMETER") currentPage: Int = 0
    ): String {
        // ── No wird active — track Quran completion instead ───────────────────
        if (p?.wirdStartDate == null) {
            return when {
                ratio >= 1.0f  -> "ختمة جديدة مباركة"
                ratio >= 0.70f -> "شارفت على الختم"
                ratio >= 0.30f -> "عزيمة وإصرار"
                else           -> "بداية مباركة"
            }
        }
        // Use a tight epsilon for the "exactly 100%" case — withinCycle
        // / dailyPages is exact when the user lands on a milestone, but
        // float comparisons are safer with a small slack.
        return when {
            ratio >= 0.999f -> "أتممت ورد اليوم"
            ratio >= 0.70f  -> "شارفت على إتمام وردك"
            ratio >= 0.30f  -> "عزيمة وإصرار"
            else            -> "ابدأ وردك اليوم"
        }
    }

    // =========================================================================
    // Yesterday acknowledgement  («أمس» pill)
    //
    // Product principle (feedback_warattil_no_debt_accounting):
    //   Each day stands alone.  Yesterday's unfinished wird is NOT a debt
    //   against today.  When the user comes back after a day of reading, we
    //   greet them once with a calm fact-line acknowledging what they read,
    //   then get out of the way.  No streak, no catchup prompt, no guilt.
    //
    // Why the logic is this small:
    //   The wird engine already derives today's pages-read from (currentPage,
    //   wirdStartDate, wirdStartPage, target) — no persistent daily counter.
    //   We can apply the same derivation to yesterday's date and yesterday's
    //   last_read_page snapshot (which is whatever `last_read_page` holds
    //   right now, since the user hasn't navigated today yet).
    //
    // When the pill is shown:
    //   • A wird is configured (wirdStartDate != null)
    //   • last_read_date == yesterday (the user did read yesterday, and has
    //     NOT yet bumped any page today)
    //   • last_acknowledged_date != today (not already shown today)
    //   • computed pagesRead > 0
    //
    // Mark-on-show semantics (see MushaFScreen integration):
    //   We mark the acknowledgement as done the moment the pill appears,
    //   not on fade-out.  Users who close the app mid-animation still get
    //   credit for having seen it — avoids the pill reappearing across
    //   rapid open/close cycles, which would feel naggy.
    // =========================================================================

    /** Arabic-agnostic day key in the device's default timezone (YYYY-MM-DD).
     *  Used to answer "same day?" / "was yesterday?" without caring about
     *  the user's preferred date-format locale. */
    private fun todayDateKey(): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())

    private fun yesterdayDateKey(): String {
        val c = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, -1) }
        return SimpleDateFormat("yyyy-MM-dd", Locale.US).format(c.time)
    }

    /** Timestamp corresponding to the start of yesterday (local midnight).
     *  Used only to compute the `daysElapsed` index relative to wirdStartDate
     *  when the user's wird was set mid-day some time ago. */
    private fun yesterdayStartTimestamp(): Long {
        val c = Calendar.getInstance().apply {
            add(Calendar.DAY_OF_YEAR, -1)
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0);     set(Calendar.MILLISECOND, 0)
        }
        return c.timeInMillis
    }

    /**
     * Returns the acknowledgement to show on this app open, or null if the
     * pill should be skipped.
     *
     * Decision tree:
     *   1. No last_read_date → null          (first-ever open — nothing to greet)
     *   2. last_read_date == today → null    (already read today — no greeting)
     *   3. last_ack_date == today → null     (already greeted once today)
     *   4. last_read_date == yesterday AND a wird is configured AND yesterday's
     *      pages-read > 0 → [DailyAcknowledgement.YesterdayRead]
     *   5. Otherwise (multi-day gap, or read yesterday without a wird set):
     *      [DailyAcknowledgement.WelcomeBack]
     *
     * The WelcomeBack branch honours Nasser's standing principle: a user
     * returning after any gap of days deserves a warm greeting, NOT an
     * accounting of missed days.  The return itself is the thing we honour.
     */
    fun yesterdayAcknowledgement(): DailyAcknowledgement? {
        val today     = todayDateKey()
        val yesterday = yesterdayDateKey()
        val lastRead  = prefs.getString("last_read_date", null) ?: return null
        val lastAck   = prefs.getString("last_acknowledged_date", null)

        if (lastRead == today) return null   // already read today — no new-day greeting
        if (lastAck  == today) return null   // already greeted once today

        // 2026-04-27 (pt. 3): the YesterdayRead variant («أمس قرأت X من
        // Y صفحة») was tied to the per-day anchor reset that this
        // refactor deletes.  Under the cumulative-modulo wird, there's
        // no "yesterday's progress" to recap — the wird is one
        // continuous bookmarked plan that doesn't reset per day.
        // Fall through to WelcomeBack for any return after one or
        // more days, regardless of whether the previous read was
        // yesterday or last week.
        @Suppress("UNUSED_VARIABLE") val _yesterday = yesterday  // kept for diff visibility
        return DailyAcknowledgement.WelcomeBack
    }

    /** Called by the pill composable on first render so subsequent same-day
     *  re-opens skip the pill.  Mark-on-show (not mark-on-fade-out) — see
     *  header comment for rationale. */
    fun markYesterdayAcknowledged() {
        prefs.edit().putString("last_acknowledged_date", todayDateKey()).apply()
    }

    // Note (2026-04-27 pt. 3): the WIRD_DUAA_LIST companion object held a
    // rotation of "goal-surpassed" Duaa phrases for the Sky Blue tier.
    // Removed alongside the Sky Blue state itself — the cumulative-modulo
    // model never emits ratio > 1.0, so the rotation has no caller.
    // Phrases are not lost; they live in git history if a future feature
    // wants a "completed N cycles" celebration screen.

    fun setWirdTarget(type: ReadingTargetType, value: Int, startPage: Int = _currentPage.value) =
        viewModelScope.launch {
            // Diagnostic try/catch added 2026-04-26: a user reported wird
            // saving silently failing.  Wrapping the Room write so any
            // exception surfaces as a Toast (instead of vanishing inside
            // the coroutine) — also logs via Log.e for adb logcat retrieval.
            // Once we've confirmed the root cause, the Toast can stay as a
            // user-facing safety net.
            try {
                val updated = (repository.getUserPreferences() ?: UserPreferences()).copy(
                    wirdTargetType = type, wirdTargetValue = value,
                    wirdStartDate  = System.currentTimeMillis(), wirdStartPage = startPage,
                    wirdLastCompletedPage = 0
                )
                repository.saveUserPreferences(updated)
                // Seed today's anchor + max-continuous so the very first
                // wirdProgressRatio call after setup measures against the
                // starting page.  Also seed last_read_date so the new wird
                // doesn't trigger a spurious «أمس» / welcome-back greeting
                // on its first day.
                // 2026-04-27 (pt. 3): the today_anchor_page key is no
                // longer referenced (the cumulative-modulo model uses
                // p.wirdStartPage as the cycle anchor instead).  Kept
                // off the write set so it doesn't pollute SharedPrefs;
                // any leftover value from earlier installs is harmless
                // (no read site).
                prefs.edit()
                    .putInt("today_max_continuous_page", startPage)
                    .putString("last_read_date", todayDateKey())
                    .apply()
                // Success confirmation — added 2026-04-27 because users
                // reported the dialog dismissing with no visible effect
                // (the StateFlow update is async; the footer takes a beat
                // to flip from FooterNoWird → FooterWirdActive).  A 1s
                // Toast bridges that perception gap.
                Toast.makeText(
                    getApplication(),
                    "تم ضبط الورد · بدأت رحلة جديدة",
                    Toast.LENGTH_SHORT
                ).show()
            } catch (e: Throwable) {
                Log.e("Warattil/Wird", "setWirdTarget failed", e)
                Toast.makeText(
                    getApplication(),
                    "تعذّر حفظ الورد — أعد المحاولة",
                    Toast.LENGTH_LONG
                ).show()
            }
        }

    /**
     * Stop the wird ONLY — clears wirdStartDate + today's anchor/max-
     * continuous SharedPrefs, nothing else.  The reader's bookmarks,
     * lastReadPage, hifz progress, and theme choice are all preserved.
     *
     * Why this exists separate from [resetProgress]: «إيقاف الورد» (the
     * destructive-tinted button in WirdDialog) used to call resetProgress
     * — which ALSO deleted every bookmark and kicked the reader back to
     * page 1.  A user who tapped «إيقاف الورد» expecting "stop the daily
     * plan" instead lost their bookmarks AND their reading position
     * (Nasser, 2026-04-27).  Split into a focused [cancelWird] that does
     * exactly what its label promises; [resetProgress] is reserved for
     * an explicit factory-reset action which we do NOT currently expose.
     */
    fun cancelWird() = viewModelScope.launch {
        try {
            val updated = (repository.getUserPreferences() ?: UserPreferences()).copy(
                wirdStartDate         = null,
                wirdLastCompletedPage = 0,
                // 2026-04-27 (pt. 5): «ابدأ ختمة جديدة» (the renamed
                // button) implies STARTING at page 1 — Nasser feedback
                // that resetting the wird should also rewind reading
                // position so the new khatma begins at the Mushaf's
                // first page, exactly as opening a fresh physical
                // Mushaf would.  Bookmarks + hifz progress are NOT
                // touched (those are the bug we fixed earlier — see
                // feedback_warattil_cancel_wird_vs_reset memory note).
                lastReadPage          = 1
                // wirdTargetType / wirdTargetValue intentionally retained
                // so re-enabling later via the dialog pre-fills the
                // reader's last choice instead of dropping back to default.
            )
            repository.saveUserPreferences(updated)
            // Clear today's per-day state — there is no "today's wird"
            // when there's no wird at all.  Reset last_read_page in
            // SharedPrefs to 1 so a subsequent app restart also opens
            // at page 1 (the wird-ribbon-aware startup logic falls
            // through to last_read_page when there's no wird).
            prefs.edit()
                .remove("today_anchor_page")
                .remove("today_max_continuous_page")
                .putInt("last_read_page", 1)
                .apply()
            // Navigate the live pager to page 1 so the user SEES the
            // reset happen — same pattern resetProgress uses.
            _navigationEvent.tryEmit(1)
            // Toast reframed positively (Nasser 2026-04-27 pt. 4): the
            // button label reads «ابدأ ختمة جديدة» so the confirmation
            // should match the devotional framing.  The technical action
            // is unchanged — wird state cleared, bookmarks + position
            // preserved.
            Toast.makeText(
                getApplication(),
                "بداية ختمة جديدة بإذن الله",
                Toast.LENGTH_SHORT
            ).show()
        } catch (e: Throwable) {
            Log.e("Warattil/Wird", "cancelWird failed", e)
            Toast.makeText(
                getApplication(),
                "تعذّر إيقاف الورد — أعد المحاولة",
                Toast.LENGTH_LONG
            ).show()
        }
    }

    fun resetProgress() = viewModelScope.launch {
        repository.clearAllBookmarks()
        val reset = (repository.getUserPreferences() ?: UserPreferences()).copy(
            lastReadPage = 1, wirdStartDate = null, wirdLastCompletedPage = 0
        )
        repository.saveUserPreferences(reset)
        // Clear the whole per-day state tuple — no wird → no anchor, no
        // stale last_read_date leftover from a previous plan.
        prefs.edit()
            .putInt("last_read_page", 1)
            .remove("today_anchor_page")
            .remove("today_max_continuous_page")
            .remove("last_read_date")
            .remove("last_acknowledged_date")
            .apply()
        _navigationEvent.tryEmit(1)
    }

    // ── Live search (300 ms debounce) ─────────────────────────────────────────

    private val _searchQuery   = MutableStateFlow("")
    /** Public read of the last search query — used by the SearchSheet
     *  composable to pre-populate its field on re-open so the reader
     *  remembers which word their results came from (Nasser, 2026-04-27). */
    val searchQuery: StateFlow<String> = _searchQuery.asStateFlow()

    /**
     * Active search-highlight term, or null when no highlight should
     * render.  Set when the user taps a search result so the page they
     * land on highlights every occurrence of the query inline.  Persists
     * across page swipes (user might want to scan adjacent pages for
     * the same word) and clears only on explicit [clearSearch] /
     * [setSearchHighlight] (null) — natural lifecycle for a "reading
     * companion" highlight rather than a one-shot flash.
     */
    private val _searchHighlight = MutableStateFlow<String?>(null)
    val searchHighlight: StateFlow<String?> = _searchHighlight.asStateFlow()

    /** Sets (or clears, with null) the inline page-highlight query. */
    fun setSearchHighlight(q: String?) {
        _searchHighlight.value = q?.takeIf { it.isNotBlank() }
    }
    private val _searchResults = MutableStateFlow<List<SearchResult>>(emptyList())
    val searchResults: StateFlow<List<SearchResult>> = _searchResults.asStateFlow()

    private val _isSearching = MutableStateFlow(false)
    val isSearching: StateFlow<Boolean> = _isSearching.asStateFlow()

    // Total count of substring occurrences across all matched ayahs (NOT
    // ayah count — an ayah containing the term twice contributes 2).
    // Updates on every search result.  Renders as "X مرة" / "مرتان" /
    // "X مرات" near the search input — Nasser 2026-04-25.
    private val _searchOccurrences = MutableStateFlow(0)
    val searchOccurrences: StateFlow<Int> = _searchOccurrences.asStateFlow()

    fun onSearchQueryChanged(q: String) { _searchQuery.value = q }
    fun clearSearch() {
        _searchQuery.value = ""
        _searchResults.value = emptyList()
        _searchOccurrences.value = 0
        _searchHighlight.value = null   // also drop any inline highlight
    }

    // =========================================================================
    // Hifz — ayah-atomic memorization store  (Phase 1)
    //
    //   _memorizedAyahs is the authoritative source of truth.  A page /
    //   surah / juz is "memorized" iff every ayah it contains is in this
    //   set.  See WarattilConstants.Hifz for the key helpers.
    //
    //   Persistence strategy:
    //     • Primary:     Hifz.PREF_AYAH_SET      (StringSet<Long-as-string>)
    //     • Worker fast: Hifz.PREF_PAGE_COUNT    (Int — fully-memorized pages)
    //     • Migration:   Hifz.PREF_LEGACY_PAGES  (read once, then removed)
    //
    //   The mirror is written on every save so HifzRevisionWorker can produce
    //   a page count without loading MetadataParser from its cold-start
    //   process.  The ViewModel always treats _memorizedAyahs.value as the
    //   truth and regenerates the mirror deterministically.
    // =========================================================================

    private val _memorizedAyahs = MutableStateFlow<Set<Long>>(loadMemorizedAyahs())
    val memorizedAyahs: StateFlow<Set<Long>> = _memorizedAyahs.asStateFlow()

    // ── Tier-crossing events ──────────────────────────────────────────────
    //   Emits the NEW tier (1..6) whenever the user crosses upward from a
    //   previously-celebrated tier.  SharedFlow (not StateFlow) because a
    //   celebration should fire exactly once per crossing — late subscribers
    //   on a recomposition must NOT re-receive the event, and we don't want
    //   it to survive process death (PREF_LAST_TIER does that job).  The
    //   buffer (1) lets the ViewModel emit during save even if no collector
    //   is momentarily attached (e.g. bulk apply completes while the user
    //   has briefly backgrounded the app); the collector will see it the
    //   next time it attaches — which is fine, the celebration is still
    //   timely.
    private val _tierCelebration = MutableSharedFlow<Int>(
        replay           = 0,
        extraBufferCapacity = 1,
        onBufferOverflow    = kotlinx.coroutines.channels.BufferOverflow.DROP_OLDEST
    )
    val tierCelebration: SharedFlow<Int> = _tierCelebration.asSharedFlow()

    /**
     * One-time load that also performs the legacy→ayah migration.  Run from
     * the constructor of [_memorizedAyahs] so no caller ever sees the old
     * page-set shape.
     */
    private fun loadMemorizedAyahs(): Set<Long> {
        // ── Modern path — key exists (even if empty) ──────────────────────
        val stored = prefs.getStringSet(Hifz.PREF_AYAH_SET, null)
        if (stored != null) {
            return stored.mapNotNullTo(HashSet(stored.size)) { it.toLongOrNull() }
        }

        // ── Migration path — expand legacy page-set to ayah-set ───────────
        val legacy = prefs.getStringSet(Hifz.PREF_LEGACY_PAGES, null).orEmpty()
        if (legacy.isEmpty()) {
            // No legacy either — seed the key so we never fall into this
            // branch again (avoids re-checking on every launch).
            prefs.edit()
                .putStringSet(Hifz.PREF_AYAH_SET, emptySet())
                .putInt(Hifz.PREF_PAGE_COUNT, 0)
                .apply()
            return emptySet()
        }

        val expanded = HashSet<Long>(legacy.size * 12)
        for (token in legacy) {
            val page = token.toIntOrNull() ?: continue
            if (page !in 1..Mushaf.TOTAL_PAGES) continue
            expanded.addAll(MetadataParser.getPageAyahKeys(page))
        }
        // Persist the migrated set, mirror the page count, and remove the
        // legacy key so the next cold start hits the fast path.
        prefs.edit()
            .putStringSet(Hifz.PREF_AYAH_SET, expanded.map { it.toString() }.toSet())
            .putInt(Hifz.PREF_PAGE_COUNT, legacy.mapNotNull { it.toIntOrNull() }.size)
            .remove(Hifz.PREF_LEGACY_PAGES)
            .apply()
        return expanded
    }

    /** Persists the current ayah-set + the fully-memorized page count mirror,
     *  and fires a tier-crossing event if the user has just entered a higher
     *  hifz tier for the first time. */
    private fun saveMemorizedAyahs(set: Set<Long>) {
        _memorizedAyahs.value = set
        val fullyMemorizedPages = countFullyMemorizedPages(set)
        val fullyMemorizedJuz   = countFullyMemorizedJuz(set)
        val currentTier         = Hifz.hifzTier(fullyMemorizedJuz)
        val lastCelebratedTier  = prefs.getInt(Hifz.PREF_LAST_TIER, 0)

        val editor = prefs.edit()
            .putStringSet(Hifz.PREF_AYAH_SET, set.map { it.toString() }.toSet())
            .putInt(Hifz.PREF_PAGE_COUNT, fullyMemorizedPages)
        if (currentTier > lastCelebratedTier) {
            // Lock in the higher tier BEFORE emitting so that if the consumer
            // collects from a different coroutine and immediately re-reads
            // prefs, it sees the updated value.  Also: write-first means a
            // crash between save and emit doesn't re-fire the celebration.
            editor.putInt(Hifz.PREF_LAST_TIER, currentTier)
        }
        editor.apply()

        if (currentTier > lastCelebratedTier) {
            _tierCelebration.tryEmit(currentTier)
        }
    }

    /** Walks all 604 pages — O(604 × avg ayahs/page) ≈ 6236 set lookups.  Fast. */
    private fun countFullyMemorizedPages(set: Set<Long>): Int {
        if (set.isEmpty()) return 0
        var count = 0
        for (page in 1..Mushaf.TOTAL_PAGES) {
            val keys = MetadataParser.getPageAyahKeys(page)
            if (keys.isNotEmpty() && keys.all { it in set }) count++
        }
        return count
    }

    /** Count of juz for which every ayah is in [set].  Drives tier state. */
    private fun countFullyMemorizedJuz(set: Set<Long>): Int {
        if (set.isEmpty()) return 0
        var count = 0
        for (j in 1..Mushaf.TOTAL_JUZAA) {
            val keys = MetadataParser.getJuzAyahKeys(j)
            if (keys.isNotEmpty() && keys.all { it in set }) count++
        }
        return count
    }

    // ── Public query helpers ──────────────────────────────────────────────

    fun isAyahMemorized(sura: Int, aya: Int): Boolean =
        Hifz.ayahKey(sura, aya) in _memorizedAyahs.value

    /** True iff every ayah on [page] is in the memorized set. */
    fun isPageMemorized(page: Int): Boolean {
        val keys = MetadataParser.getPageAyahKeys(page)
        if (keys.isEmpty()) return false
        val set = _memorizedAyahs.value
        return keys.all { it in set }
    }

    /** 0 .. 1 fraction of ayahs on [page] that are memorized. */
    fun pageMemorizationRatio(page: Int): Float {
        val keys = MetadataParser.getPageAyahKeys(page)
        if (keys.isEmpty()) return 0f
        val set = _memorizedAyahs.value
        val hit = keys.count { it in set }
        return hit.toFloat() / keys.size.toFloat()
    }

    // ── Public mutation actions ───────────────────────────────────────────

    /** Toggle a single ayah's membership. */
    fun toggleAyah(sura: Int, aya: Int) {
        val key = Hifz.ayahKey(sura, aya)
        val next = _memorizedAyahs.value.toHashSet()
        if (!next.add(key)) next.remove(key)
        saveMemorizedAyahs(next)
    }

    /**
     * Toggle a whole page.  If the page is fully memorized, *remove* every
     * ayah on it.  Otherwise *complete* the page (add the ayahs that
     * aren't already memorized).  This matches the MushaFHeader strip-tap
     * semantics: one gesture, result depends on current density.
     */
    fun togglePage(page: Int) {
        val keys = MetadataParser.getPageAyahKeys(page)
        if (keys.isEmpty()) return
        val set = _memorizedAyahs.value
        val allMemorized = keys.all { it in set }
        val next = set.toHashSet()
        if (allMemorized) next.removeAll(keys.toSet())
        else              next.addAll(keys)
        saveMemorizedAyahs(next)
    }

    /** Complete-or-clear at surah granularity. */
    fun toggleSurah(sura: Int) {
        val keys = MetadataParser.getSurahAyahKeys(sura)
        if (keys.isEmpty()) return
        val set = _memorizedAyahs.value
        val allMemorized = keys.all { it in set }
        val next = set.toHashSet()
        if (allMemorized) next.removeAll(keys.toSet())
        else              next.addAll(keys)
        saveMemorizedAyahs(next)
    }

    /** Complete-or-clear at juz granularity. */
    fun toggleJuz(juz: Int) {
        val keys = MetadataParser.getJuzAyahKeys(juz)
        if (keys.isEmpty()) return
        val set = _memorizedAyahs.value
        val allMemorized = keys.all { it in set }
        val next = set.toHashSet()
        if (allMemorized) next.removeAll(keys.toSet())
        else              next.addAll(keys)
        saveMemorizedAyahs(next)
    }

    /**
     * Low-level bulk set/clear.  Used by the HifzBulkPickerSheet to apply a
     * multi-select decision (e.g., "mark these 7 juz memorized") in a single
     * SharedPreferences write.
     */
    fun setAyahsMemorized(keys: Collection<Long>, memorized: Boolean) {
        if (keys.isEmpty()) return
        val next = _memorizedAyahs.value.toHashSet()
        if (memorized) next.addAll(keys) else next.removeAll(keys.toSet())
        saveMemorizedAyahs(next)
    }

    /**
     * Mark a closed `fromPage..toPage` range as memorized / unmemorized in
     * one pass.  Useful for seeding an existing-hifz user ("I already know
     * the first 300 pages") without iterating page-by-page at the UI layer.
     */
    fun setPagesRangeMemorized(fromPage: Int, toPage: Int, memorized: Boolean) {
        val a = fromPage.coerceIn(1, Mushaf.TOTAL_PAGES)
        val b = toPage.coerceIn(1, Mushaf.TOTAL_PAGES)
        val lo = minOf(a, b)
        val hi = maxOf(a, b)
        val keys = ArrayList<Long>(256)
        for (p in lo..hi) keys.addAll(MetadataParser.getPageAyahKeys(p))
        setAyahsMemorized(keys, memorized)
    }

    // ── Fihris ────────────────────────────────────────────────────────────────

    val surahStartPages: Map<Int, Int> by lazy { repository.surahStartPages }
    val juzStartPages  : Map<Int, Int> by lazy { repository.juzStartPages   }

    // ── Navigation events ─────────────────────────────────────────────────────

    private val _navigationEvent = MutableSharedFlow<Int>(extraBufferCapacity = 1)
    val navigationEvent: SharedFlow<Int> = _navigationEvent

    // ── Init ──────────────────────────────────────────────────────────────────

    init {
        // Pre-warm pages around the opening page
        for (offset in -2..5) {
            val p = startPage + offset
            if (p in 1..Mushaf.TOTAL_PAGES) getPageFlow(p)
        }
        // Live search with 300 ms debounce
        viewModelScope.launch {
            _searchQuery.debounce(300L).distinctUntilChanged().collect { q ->
                if (q.isBlank()) {
                    _searchResults.value = emptyList()
                    _searchOccurrences.value = 0
                    _isSearching.value = false
                    return@collect
                }
                _isSearching.value = true
                try {
                    val results = repository.searchAyahs(q.trim())
                    _searchResults.value = results
                    // Occurrence count = total substring hits across all
                    // returned ayahs, using the SAME normalization as the
                    // SQL query (strip diacritics, alif-wasla → alif) so
                    // the displayed number matches what's actually being
                    // matched.  An ayah with the term twice contributes 2.
                    //
                    // NOTE: bounded by the DAO's `LIMIT 100` — for very
                    // common terms (e.g. "الله") the displayed count
                    // reflects occurrences in the first 100 matching
                    // ayahs, not the whole Mushaf.  Acceptable for V3
                    // because the result list itself is also capped.
                    // Removing the cap would require either a separate
                    // aggregate COUNT query or a SUM(LENGTH(...) -
                    // LENGTH(REPLACE(...))) trick — deferred.
                    val needle = normalizeForSearch(q.trim())
                    var total = 0
                    for (r in results) {
                        total += countOccurrences(normalizeForSearch(r.text), needle)
                    }
                    _searchOccurrences.value = total
                } finally {
                    _isSearching.value = false
                }
            }
        }
    }

    // ── Search-side normalization & counting ─────────────────────────────────
    //   MUST mirror QuranRepository.normalizeForSearch — used here ONLY
    //   for the occurrence count beside the search field so the count
    //   agrees with what the repository actually matched.  Any change to
    //   the fold rules in the repository must be applied here too.

    private fun normalizeForSearch(s: String): String {
        if (s.isEmpty()) return s
        val out = StringBuilder(s.length)
        for (c in s) {
            when (c.code) {
                // Letter folds: Uthmani → Imla'i
                0x0622, 0x0623, 0x0625, 0x0671 -> out.append('ا')   // آ أ إ ٱ → ا
                0x0656, 0x0670                 -> out.append('ا')   // subscript / dagger alef → ا
                0x0649                         -> out.append('ي')   // alef-maqsura ى → ي
                0x0640                         -> Unit              // tatweel ـ → strip
                // Diacritic marks
                in 0x064B..0x065F              -> Unit              // tashkeel + extras
                in 0x06D6..0x06ED              -> Unit              // recitation marks
                else                           -> out.append(c)
            }
        }
        return out.toString()
    }

    /** Non-overlapping substring occurrence count. */
    private fun countOccurrences(haystack: String, needle: String): Int {
        if (needle.isEmpty()) return 0
        var count = 0
        var idx = 0
        while (true) {
            idx = haystack.indexOf(needle, idx)
            if (idx == -1) break
            count++
            idx += needle.length
        }
        return count
    }

    // ── Page access ───────────────────────────────────────────────────────────

    fun getPageFlow(pageNumber: Int): StateFlow<PageUiState> {
        if (pageNumber !in 1..Mushaf.TOTAL_PAGES)
            return MutableStateFlow(PageUiState.Error("صفحة غير صالحة: $pageNumber"))
        return pageFlows.computeIfAbsent(pageNumber) { pNum ->
            MutableStateFlow<PageUiState>(PageUiState.Loading).also { flow ->
                viewModelScope.launch {
                    runCatching { repository.getPageContent(pNum) }
                        .onSuccess { flow.value = PageUiState.Success(it) }
                        .onFailure { flow.value = PageUiState.Error(it.message ?: "خطأ $pNum") }
                }
            }
        }
    }

    // ── Navigation ────────────────────────────────────────────────────────────

    fun onPageChanged(pagerIndex: Int) {
        val page = pagerIndex + 1
        _currentPage.value = page

        // ── Sequential-counter update (`today_max_continuous_page`) ─────────
        //
        // REWORKED 2026-04-27 (pt. 3): under the cumulative-modulo wird
        // model, max_continuous is a SINGLE high-water mark since
        // wirdStartPage that NEVER resets per calendar day.  Skipping
        // days has zero effect — the bookmark stays exactly where the
        // reader left it, no matter how long they're away.  See
        // wirdProgressRatio + project_warattil_wird_requirements memory.
        //
        // The counter advances only when the new page equals
        // (current max_continuous + 1) — true sequential reading.
        // Non-sequential navigation — Fihris jump to Al-Kahf, search-
        // result tap, bookmark hop — leaves it untouched.  Returning
        // to the point right after max_continuous resumes the count
        // naturally.
        //
        // Note: `last_read_date` is still stamped so the welcome-back
        // pill («أهلاً بعودتك») can detect a multi-day absence — but
        // that's purely a returning-reader greeting, NOT a wird-state
        // reset.  The wird ribbon is page-based; the pill is the
        // only thing that's date-aware.
        val today      = todayDateKey()
        val currentMax = prefs.getInt("today_max_continuous_page", page)
        val newMax = if (page == currentMax + 1) page else currentMax

        prefs.edit()
            .putInt("last_read_page", page)
            .putString("last_read_date", today)
            .putInt("today_max_continuous_page", newMax)
            .apply()

        // Widget ratio snapshot — reads the freshly-committed max_continuous.
        val ratio = wirdProgressRatio(page, userPreferences.value)
        prefs.edit().putFloat("widget_wird_ratio", ratio).apply()
        // Pre-warm neighbouring pages in the swipe direction
        for (offset in -2..2) { val adj = page + offset; if (adj in 1..Mushaf.TOTAL_PAGES) getPageFlow(adj) }
        // ── Async: resolve surah name + juz, then refresh the widget ─────────
        //   The widget needs three derived values (page, surah, juz) so we
        //   round-trip through the repository to guarantee a consistent tuple
        //   (same paging law as the Mushaf body).
        viewModelScope.launch {
            runCatching { repository.getPageContent(page) }
                .onSuccess { content ->
                    prefs.edit()
                        .putString("last_read_surah", content.surahName)
                        .putInt("last_read_juz", content.juzNumber)
                        .apply()
                }
            WarattilWidgetReceiver.updateAll(getApplication())
        }
    }

    fun navigateToPage(page: Int) {
        if (page in 1..Mushaf.TOTAL_PAGES) {
            _currentPage.value = page
            _navigationEvent.tryEmit(page)
            for (offset in -2..2) { val p = page + offset; if (p in 1..Mushaf.TOTAL_PAGES) getPageFlow(p) }
        }
    }

    // ── Factory ───────────────────────────────────────────────────────────────

    class Factory(private val application: Application, private val repository: QuranRepository)
        : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T =
            MushaFViewModel(application, repository) as T
    }
}
