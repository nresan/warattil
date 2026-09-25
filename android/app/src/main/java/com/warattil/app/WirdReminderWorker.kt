package com.warattil.app

import android.content.Context
import androidx.work.*
import java.util.Calendar
import java.util.concurrent.TimeUnit

// =============================================================================
// WirdReminderWorker
//
// Fires daily at 16:00 (4 PM) local time.
// Checks if the user has read any pages today; if wird ratio is still 0 %,
// sends a gentle nudge notification.
// =============================================================================

class WirdReminderWorker(
    private val ctx: Context,
    params         : WorkerParameters
) : CoroutineWorker(ctx, params) {

    override suspend fun doWork(): Result {
        val prefs = ctx.getSharedPreferences("warattil_prefs", Context.MODE_PRIVATE)
        val ratio = prefs.getFloat("widget_wird_ratio", 0f)
        // Only nudge if the user hasn't started their wird today (ratio == 0)
        if (ratio <= 0f) {
            NotificationHelper.sendWirdReminder(ctx)
        }
        return Result.success()
    }

    companion object {
        const val WORK_NAME = "warattil_wird_reminder"
        private const val FIRE_HOUR   = 16
        private const val FIRE_MINUTE = 0

        fun schedule(context: Context) {
            val request = PeriodicWorkRequestBuilder<WirdReminderWorker>(1, TimeUnit.DAYS)
                .setInitialDelay(initialDelayMs(), TimeUnit.MILLISECONDS)
                .setConstraints(Constraints.NONE)
                .build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                request
            )
        }

        /** Milliseconds until the next occurrence of FIRE_HOUR:FIRE_MINUTE today or tomorrow. */
        private fun initialDelayMs(): Long {
            val now    = Calendar.getInstance()
            val target = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, FIRE_HOUR)
                set(Calendar.MINUTE,      FIRE_MINUTE)
                set(Calendar.SECOND,      0)
                set(Calendar.MILLISECOND, 0)
            }
            if (target.timeInMillis <= now.timeInMillis) {
                target.add(Calendar.DAY_OF_YEAR, 1)
            }
            return (target.timeInMillis - now.timeInMillis).coerceAtLeast(0L)
        }
    }
}
