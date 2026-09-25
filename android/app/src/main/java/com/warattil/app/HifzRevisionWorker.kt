package com.warattil.app

import android.content.Context
import androidx.work.*
import com.warattil.app.core.WarattilConstants.Hifz
import java.util.Calendar
import java.util.concurrent.TimeUnit

// =============================================================================
// HifzRevisionWorker
//
// Fires every Friday at 08:00 local time.
//
// Reads the *fully-memorized page count* from SharedPreferences as a single
// Int mirror written by MushaFViewModel every time the ayah-set is saved.
// This is the cold-path primitive: the worker must not load MetadataParser
// just to count pages from the authoritative Set<Long> of ayah keys.
//
// Phase-1 storage layout (see WarattilConstants.Hifz):
//   • memorized_ayahs        → StringSet<Long-as-string>   — authoritative
//   • memorized_pages_count  → Int                         — worker-friendly
//   • memorized_pages        → (legacy, one-shot migrated out on app start)
// =============================================================================

class HifzRevisionWorker(
    private val ctx: Context,
    params         : WorkerParameters
) : CoroutineWorker(ctx, params) {

    override suspend fun doWork(): Result {
        val prefs = ctx.getSharedPreferences(Hifz.PREF_FILE, Context.MODE_PRIVATE)
        val memorizedCount = prefs.getInt(Hifz.PREF_PAGE_COUNT, 0)
        NotificationHelper.sendHifzRevision(ctx, memorizedCount)
        return Result.success()
    }

    companion object {
        const val WORK_NAME   = "warattil_hifz_revision"
        private const val FIRE_HOUR   = 8
        private const val FIRE_MINUTE = 0

        fun schedule(context: Context) {
            val request = PeriodicWorkRequestBuilder<HifzRevisionWorker>(7, TimeUnit.DAYS)
                .setInitialDelay(initialDelayToFridayMs(), TimeUnit.MILLISECONDS)
                .setConstraints(Constraints.NONE)
                .build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                request
            )
        }

        /** Milliseconds until the next Friday at FIRE_HOUR:FIRE_MINUTE. */
        private fun initialDelayToFridayMs(): Long {
            val now = Calendar.getInstance()
            val target = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, FIRE_HOUR)
                set(Calendar.MINUTE,      FIRE_MINUTE)
                set(Calendar.SECOND,      0)
                set(Calendar.MILLISECOND, 0)
            }
            // Advance to the next Friday (Calendar.FRIDAY == 6)
            while (target.get(Calendar.DAY_OF_WEEK) != Calendar.FRIDAY
                || target.timeInMillis <= now.timeInMillis) {
                target.add(Calendar.DAY_OF_YEAR, 1)
            }
            return (target.timeInMillis - now.timeInMillis).coerceAtLeast(0L)
        }
    }
}
