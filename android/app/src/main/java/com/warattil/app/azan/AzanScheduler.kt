package com.warattil.app.azan

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import java.util.Calendar

// =============================================================================
// AzanScheduler — AlarmManager-based one-shot alarms for the five daily
// prayer reminders.
//
// Why AlarmManager (not WorkManager) — WorkManager periodic work has a
// 15-minute minimum interval and no exact-time guarantee.  Prayer timing
// needs to be precise to the minute, otherwise the reminder is meaningless
// when ٱللَّـه's appointment came and went five minutes ago.  AlarmManager
// `setExactAndAllowWhileIdle` is the correct primitive.
//
// Each prayer is a separate one-shot alarm with a stable request code.
// When an alarm fires, AzanReceiver re-schedules that same prayer for
// the next day — so we always have exactly five future alarms queued.
//
// Permission note: SCHEDULE_EXACT_ALARM is declared in the manifest.  When the
// user grants it (or on devices where it is auto-granted), canScheduleExactAlarms()
// returns true and we use setExactAndAllowWhileIdle().  If not granted, we fall
// back to am.set() — slightly less precise but still functional.
// USE_EXACT_ALARM was removed: it is restricted to calendar/alarm-clock apps by
// Play Store policy and WARATTIL does not qualify.
// =============================================================================

object AzanScheduler {

    private const val TAG = "AzanScheduler"

    const val ACTION_AZAN         = "com.warattil.app.azan.ACTION_AZAN"
    const val EXTRA_PRAYER        = "prayer"
    /** True → AzanReceiver should just refresh the widget and exit, without
     *  firing notification / audio / vibration.  Used by the T+20min post-
     *  prayer refresh so the widget can flip from "count-up since prayer"
     *  to "count-down to next prayer" at the right moment. */
    const val EXTRA_REFRESH_ONLY  = "refresh_only"

    /** SharedPreferences keys recording the most recently fired prayer
     *  so the widget can decide if we're in the 20-minute post-prayer
     *  grace window. */
    const val PREF_LAST_FIRED_PRAYER = "azan_last_fired_prayer"
    const val PREF_LAST_FIRED_TIME   = "azan_last_fired_time"
    const val POST_PRAYER_WINDOW_MS  = 20L * 60L * 1000L  // 20 minutes

    // Stable request codes so cancelling / replacing the same prayer's alarm
    // works correctly (PendingIntent identity must match what was scheduled).
    //
    // Note: a previous version of this scheduler also queued T-30 / T-15 / T-5
    // "widget tick" alarms (request codes 3000-3099) to keep the home-screen
    // countdown fresh.  Those were dropped on 2026-05-16 when the widget
    // switched to an embedded Android Chronometer (live-ticking via the
    // system widget host, no app-side refresh needed).  See WarattilWidget.kt
    // and project_warattil_azan.md.
    private fun requestCode(p: PrayerTimes.Prayer) = 2000 + p.ordinal

    /**
     * Schedule (or replace) one prayer's alarm for the next time it should
     * fire — today if it's still in the future, otherwise tomorrow.
     */
    fun scheduleNext(ctx: Context, prayer: PrayerTimes.Prayer) {
        if (!AzanSettings.isEnabled(ctx)) return
        val loc = AzanSettings.getLocation(ctx) ?: return

        val now = Calendar.getInstance()
        val target = nextOccurrence(prayer, loc.first, loc.second, now)
        val triggerAtMillis = target.timeInMillis

        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = pendingIntentFor(ctx, prayer)

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !am.canScheduleExactAlarms()) {
                // Fallback to inexact when the user has revoked exact-alarm
                // permission on Android 12+.  Better to nudge a minute or two
                // late than to silently no-op.
                am.set(AlarmManager.RTC_WAKEUP, triggerAtMillis, pi)
            } else {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pi)
            }
            Log.d(TAG, "Scheduled ${prayer.arabicName} for $target")
        } catch (se: SecurityException) {
            Log.w(TAG, "Cannot schedule exact alarm: ${se.message}")
        }
    }

    /** Schedule all five prayers. Used on first-enable, on boot, on settings change. */
    fun scheduleAll(ctx: Context) {
        PrayerTimes.Prayer.ORDER.forEach { scheduleNext(ctx, it) }
    }

    /** Cancel all pending Azan alarms (used when the user disables the feature). */
    fun cancelAll(ctx: Context) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        PrayerTimes.Prayer.ORDER.forEach { p ->
            am.cancel(pendingIntentFor(ctx, p))
        }
        // Also drop any pending POST_PRAYER refresh.
        am.cancel(postPrayerRefreshPendingIntent(ctx))
    }

    /**
     * Schedule (or replace) the one-shot AlarmManager alarm that fires
     * AzanReceiver with `EXTRA_REFRESH_ONLY=true` to flip the widget from
     * POST_PRAYER (count-up) back to BEFORE_PRAYER (count-down) at the end
     * of the 20-minute post-prayer grace window.
     *
     * Idempotent — uses the shared request code [POST_PRAYER_REFRESH_REQUEST_CODE]
     * with `FLAG_UPDATE_CURRENT`, so calling it repeatedly only ever leaves one
     * pending refresh.  Called from two places:
     *   1. AzanReceiver, immediately after a prayer fires (at T+20min from now)
     *   2. WarattilWidget.buildAzanChronometerState, on every render while we
     *      are inside the post-prayer window, with the *original* fire time
     *      + 20min as the target.  This is the belt-and-suspenders that
     *      survives a force-stop / Doze-kill that would otherwise drop the
     *      original alarm and leave the widget stuck on POST_PRAYER forever.
     *
     * [triggerAtMillis] is a wall-clock millis value (System.currentTimeMillis
     * basis).  If already past, AlarmManager fires it immediately on the next
     * service tick — which is exactly what we want for the late-recovery case.
     */
    fun scheduleRefreshAt(ctx: Context, triggerAtMillis: Long) {
        val pi = postPrayerRefreshPendingIntent(ctx)
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !am.canScheduleExactAlarms()) {
                am.set(AlarmManager.RTC_WAKEUP, triggerAtMillis, pi)
            } else {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pi)
            }
        } catch (se: SecurityException) {
            Log.w(TAG, "Cannot schedule post-prayer refresh: ${se.message}")
        }
    }

    /** PendingIntent identity for the T+20 post-prayer refresh alarm. */
    private fun postPrayerRefreshPendingIntent(ctx: Context): PendingIntent {
        val refreshIntent = Intent(ctx, AzanReceiver::class.java).apply {
            action = ACTION_AZAN
            putExtra(EXTRA_REFRESH_ONLY, true)
        }
        return PendingIntent.getBroadcast(
            ctx,
            POST_PRAYER_REFRESH_REQUEST_CODE,
            refreshIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    /** Shared request code for the single post-prayer refresh alarm. */
    private const val POST_PRAYER_REFRESH_REQUEST_CODE = 4000

    /**
     * Compute the next [prayer] occurrence after [now], using today's prayer
     * times if it hasn't passed yet, tomorrow's otherwise.
     */
    private fun nextOccurrence(
        prayer: PrayerTimes.Prayer,
        lat: Double,
        lng: Double,
        now: Calendar
    ): Calendar {
        val todayTimes = PrayerTimes.compute(now, lat, lng)
        val today      = atMinute(now, todayTimes.forPrayer(prayer))
        if (today.timeInMillis > now.timeInMillis) return today

        // Otherwise compute tomorrow's times
        val tomorrow = (now.clone() as Calendar).apply { add(Calendar.DAY_OF_YEAR, 1) }
        val tomorrowTimes = PrayerTimes.compute(tomorrow, lat, lng)
        return atMinute(tomorrow, tomorrowTimes.forPrayer(prayer))
    }

    /** Build a Calendar at the given minutes-since-local-midnight on the same day as [base]. */
    private fun atMinute(base: Calendar, minutesSinceMidnight: Int): Calendar {
        return (base.clone() as Calendar).apply {
            set(Calendar.HOUR_OF_DAY, minutesSinceMidnight / 60)
            set(Calendar.MINUTE,      minutesSinceMidnight % 60)
            set(Calendar.SECOND,      0)
            set(Calendar.MILLISECOND, 0)
        }
    }

    private fun pendingIntentFor(ctx: Context, prayer: PrayerTimes.Prayer): PendingIntent {
        val intent = Intent(ctx, AzanReceiver::class.java).apply {
            action = ACTION_AZAN
            putExtra(EXTRA_PRAYER, prayer.name)
        }
        return PendingIntent.getBroadcast(
            ctx,
            requestCode(prayer),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}
