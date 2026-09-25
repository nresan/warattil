package com.warattil.app.azan

import android.app.Service
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.os.IBinder
import android.util.Log
import com.warattil.app.NotificationHelper

// =============================================================================
// AzanPlaybackService — foreground service that plays the user's uploaded
// azan audio file when a prayer alarm fires.
//
// Foreground service (mediaPlayback type) is required on modern Android
// to play audio reliably from a background-triggered alarm — broadcast
// receivers only have a ~10-second execution window, which is fine for a
// short Takbīr clip but not for a 2-minute full Azan.
//
// The notification displayed by the service is the same one AzanReceiver
// posted moments earlier (same channel + ID), so the user sees a single
// reminder card, not two.  When playback completes, the service stops
// itself; the notification remains until the user dismisses it or taps it.
// =============================================================================

class AzanPlaybackService : Service() {

    private var player: MediaPlayer? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Stop command fired from the notification action button — silence
        // playback and dismiss the notification entirely.
        if (intent?.action == ACTION_STOP_AZAN) {
            safeStop(removeNotification = true)
            return START_NOT_STICKY
        }

        val uriStr     = intent?.getStringExtra(EXTRA_AUDIO_URI)
        val prayerName = intent?.getStringExtra(EXTRA_PRAYER_NAME) ?: "أوقات الصلاة"

        if (uriStr.isNullOrBlank()) {
            stopSelf()
            return START_NOT_STICKY
        }

        // Take over the same notification AzanReceiver posted so the user
        // sees one card, not two — startForeground reuses the ID.
        startForeground(
            NotificationHelper.NOTIF_ID_AZAN,
            NotificationHelper.buildAzanForegroundNotif(this, prayerName)
        )

        try {
            player = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                setDataSource(this@AzanPlaybackService, Uri.parse(uriStr))
                setOnCompletionListener {
                    safeStop()
                }
                setOnErrorListener { _, what, extra ->
                    Log.w("AzanPlayback", "MediaPlayer error what=$what extra=$extra")
                    safeStop()
                    true
                }
                prepare()
                start()
            }
        } catch (t: Throwable) {
            Log.w("AzanPlayback", "Failed to start audio: ${t.message}")
            safeStop()
        }

        return START_NOT_STICKY
    }

    private fun safeStop(removeNotification: Boolean = false) {
        try {
            player?.apply {
                if (isPlaying) stop()
                release()
            }
        } catch (_: Throwable) { /* best-effort cleanup */ }
        player = null
        if (removeNotification) {
            // User tapped «إيقاف» — dismiss the notification completely.
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            // Playback ended naturally — keep the notification as an ambient
            // prayer reminder until the user dismisses it manually.
            stopForeground(STOP_FOREGROUND_DETACH)
        }
        stopSelf()
    }

    override fun onDestroy() {
        safeStop()
        super.onDestroy()
    }

    companion object {
        const val EXTRA_AUDIO_URI    = "audio_uri"
        const val EXTRA_PRAYER_NAME  = "prayer_name"
        const val ACTION_STOP_AZAN   = "com.warattil.app.STOP_AZAN"
    }
}
