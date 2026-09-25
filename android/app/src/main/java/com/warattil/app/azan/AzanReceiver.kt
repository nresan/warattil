package com.warattil.app.azan

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import androidx.core.content.edit
import com.warattil.app.NotificationHelper
import com.warattil.app.widget.WarattilWidgetReceiver

// =============================================================================
// AzanReceiver — fires when an AlarmManager alarm for a prayer time triggers.
//
// Responsibilities (always, in this order):
//   1. Post the visual notification (the always-on ajr-reminder surface)
//   2. Vibrate the device once (so a pocketed phone is still felt)
//   3. If the user picked FULL or SHORT for this prayer, start the
//      AzanPlaybackService to play their uploaded audio file.
//   4. Re-schedule the SAME prayer for the next day so the daily cycle
//      continues without external intervention.
//
// The receiver runs in the app's main process briefly (~10s window granted
// to BroadcastReceivers after onReceive returns).  Audio playback longer
// than that needs the foreground service — that's why AzanPlaybackService
// exists rather than playing MediaPlayer directly here.
// =============================================================================

class AzanReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != AzanScheduler.ACTION_AZAN) return

        // Lightweight branch: T+20min post-prayer alarm just refreshes the
        // widget (so the chronometer can flip from "count-up since prayer"
        // to "count-down to next prayer").  No notification, no audio, no
        // vibration.  Exit early.
        if (intent.getBooleanExtra(AzanScheduler.EXTRA_REFRESH_ONLY, false)) {
            WarattilWidgetReceiver.updateAll(context)
            return
        }

        val prayerName = intent.getStringExtra(AzanScheduler.EXTRA_PRAYER) ?: return
        val prayer     = runCatching { PrayerTimes.Prayer.valueOf(prayerName) }.getOrNull() ?: return

        Log.d("AzanReceiver", "Firing for ${prayer.arabicName}")

        // Record this prayer fire so the widget knows we're inside the 20-min
        // post-prayer grace window (chronometer counts UP from this moment
        // with "الظهر قبل %s" format until T+20min refresh swaps it back).
        context.getSharedPreferences("warattil_prefs", Context.MODE_PRIVATE).edit {
            putString(AzanScheduler.PREF_LAST_FIRED_PRAYER, prayer.name)
            putLong  (AzanScheduler.PREF_LAST_FIRED_TIME,   System.currentTimeMillis())
        }

        // 1) Notification — ALWAYS shown
        NotificationHelper.sendAzanReminder(context, prayer)

        // 2) Vibration — ALWAYS fires (the audio is additive)
        vibrate(context)

        // 3) Audio playback — only if user uploaded a file and picked FULL or SHORT
        val uri = AzanSettings.resolveAudioFor(context, prayer)
        if (uri != null) {
            val svc = Intent(context, AzanPlaybackService::class.java).apply {
                putExtra(AzanPlaybackService.EXTRA_AUDIO_URI, uri)
                putExtra(AzanPlaybackService.EXTRA_PRAYER_NAME, prayer.arabicName)
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(svc)
                } else {
                    context.startService(svc)
                }
            } catch (t: Throwable) {
                // Service start can fail under aggressive OEM background limits
                // — the notification + vibration still landed, so we degrade
                // gracefully rather than crash.
                Log.w("AzanReceiver", "Could not start playback service: ${t.message}")
            }
        }

        // 4) Reschedule THIS prayer for tomorrow so the daily cycle continues
        AzanScheduler.scheduleNext(context, prayer)

        // 5) Refresh placed widgets so the chronometer immediately flips
        //    into POST_PRAYER mode (count-up from this prayer's fire time).
        WarattilWidgetReceiver.updateAll(context)

        // 6) Schedule a one-shot refresh at T+20min — at that point the grace
        //    window expires and we want the widget to flip back to
        //    BEFORE_PRAYER for the next upcoming prayer.  Belt-and-suspenders:
        //    WarattilWidget.buildAzanChronometerState also re-schedules this
        //    same alarm on every render while inside the window, so a
        //    force-stop or Doze-kill that drops this alarm gets recovered the
        //    next time the widget renders for any reason.
        AzanScheduler.scheduleRefreshAt(
            context,
            System.currentTimeMillis() + AzanScheduler.POST_PRAYER_WINDOW_MS
        )
    }

    private fun vibrate(context: Context) {
        @Suppress("DEPRECATION")
        val vibrator: Vibrator? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)
                ?.defaultVibrator
        } else {
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
        if (vibrator?.hasVibrator() != true) return

        // Pattern: short-pause-short (a gentle "alert" feel, not an alarm shake).
        val pattern = longArrayOf(0, 250, 200, 250)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createWaveform(pattern, -1))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(pattern, -1)
        }
    }
}
