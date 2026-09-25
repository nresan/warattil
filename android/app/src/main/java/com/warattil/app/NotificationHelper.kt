package com.warattil.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.warattil.app.azan.AzanPlaybackService
import com.warattil.app.azan.PrayerTimes

// =============================================================================
// NotificationHelper — channel registration + notification builders
// =============================================================================

object NotificationHelper {

    const val CHANNEL_WIRD   = "warattil_wird_reminder"
    const val CHANNEL_HIFZ   = "warattil_hifz_revision"
    const val CHANNEL_AZAN   = "warattil_azan_reminder"

    private const val NOTIF_ID_WIRD = 1001
    private const val NOTIF_ID_HIFZ = 1002
    const         val NOTIF_ID_AZAN = 1003   // exposed for the foreground service to re-use

    /** Call once at app start (idempotent). */
    fun createChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannels(
            listOf(
                NotificationChannel(
                    CHANNEL_WIRD,
                    "تذكير الورد اليومي",
                    NotificationManager.IMPORTANCE_DEFAULT
                ).apply { description = "تذكير يومي بالورد القرآني" },
                NotificationChannel(
                    CHANNEL_HIFZ,
                    "مراجعة الحفظ",
                    NotificationManager.IMPORTANCE_DEFAULT
                ).apply { description = "تذكير أسبوعي بمراجعة المحفوظات" },
                NotificationChannel(
                    CHANNEL_AZAN,
                    "أوقات الصلاة",
                    // HIGH so the notification heads-up briefly on lockscreen
                    // and surfaces over silent-mode policies on most OEMs;
                    // audio (when configured) plays through the foreground
                    // service, not the channel sound, so this channel is
                    // intentionally sound-less to avoid double playback.
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "تذكير بمواعيد الصلوات الخمس"
                    setSound(null, null)   // audio handled by AzanPlaybackService
                }
            )
        )
    }

    /** Wird nudge — fired at 4 PM if wird is still at 0 %. */
    fun sendWirdReminder(context: Context) {
        val intent = PendingIntent.getActivity(
            context, 0,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notif = NotificationCompat.Builder(context, CHANNEL_WIRD)
            .setSmallIcon(android.R.drawable.ic_menu_my_calendar)
            .setContentTitle("وَرَتِّلْ")
            .setContentText("وردك اليوم ينتظرك.. تقبل الله طاعتك")
            // Positive framing — invitation + dua closer, avoids the prior
            // "لم تبدأ ... بعد" accusation.
            .setStyle(NotificationCompat.BigTextStyle()
                .bigText("وردك اليوم في انتظارك — افتح التطبيق لتتلو القرآن الكريم، تقبّل الله تلاوتك."))
            .setContentIntent(intent)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()

        try {
            NotificationManagerCompat.from(context).notify(NOTIF_ID_WIRD, notif)
        } catch (_: SecurityException) { /* POST_NOTIFICATIONS not granted — no-op */ }
    }

    /** Friday Hifz revision reminder. */
    fun sendHifzRevision(context: Context, memorizedPageCount: Int) {
        if (memorizedPageCount == 0) return   // nothing memorized yet — skip
        val intent = PendingIntent.getActivity(
            context, 0,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("open_hifz_log", true)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notif = NotificationCompat.Builder(context, CHANNEL_HIFZ)
            .setSmallIcon(android.R.drawable.star_big_on)
            .setContentTitle("مراجعة الحفظ")
            // Warmer Islamic framing — greeting + barakah closer. «اليوم المبارك»
            // reads correctly whether the notification arrives exactly on Friday
            // or slightly adjacent.
            .setContentText("حيّاك الله — راجع محفوظاتك في هذا اليوم المبارك. $memorizedPageCount صفحة بفضل الله، ثبّت الله ما حفظت.")
            .setContentIntent(intent)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()

        try {
            NotificationManagerCompat.from(context).notify(NOTIF_ID_HIFZ, notif)
        } catch (_: SecurityException) { /* POST_NOTIFICATIONS not granted — no-op */ }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Azan reminder (one of five daily prayers)
    // ─────────────────────────────────────────────────────────────────────────
    //
    // The notification's job is to be the ambient ajr-reminder: visible
    // even when audio is silenced, dismissable but always present until
    // the next prayer.  Tap → open the app at today's wird ribbon page
    // (or the home page if no wird is active), compounding the loop
    // "reminder → tap → reading."
    //

    fun sendAzanReminder(context: Context, prayer: PrayerTimes.Prayer) {
        val notif = buildAzanForegroundNotif(context, prayer.arabicName)
        try {
            NotificationManagerCompat.from(context).notify(NOTIF_ID_AZAN, notif)
        } catch (_: SecurityException) { /* POST_NOTIFICATIONS not granted — no-op */ }
    }

    /** Builds the Azan notification — also reused by AzanPlaybackService for startForeground(). */
    fun buildAzanForegroundNotif(context: Context, prayerArabicName: String): Notification {
        val intent = PendingIntent.getActivity(
            context, 0,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("open_today_wird", true)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        // «إيقاف الأذان» action — sends ACTION_STOP_AZAN to AzanPlaybackService.
        // If audio is playing the service stops it and dismisses this notification.
        // If no audio was configured the service starts briefly, finds nothing to
        // stop, and exits — the notification is still dismissed cleanly.
        val stopPendingIntent = PendingIntent.getService(
            context,
            100,   // distinct request code — avoids colliding with tap intent (0)
            Intent(context, AzanPlaybackService::class.java).apply {
                action = AzanPlaybackService.ACTION_STOP_AZAN
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(context, CHANNEL_AZAN)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("حان وقت صلاة $prayerArabicName")
            .setContentText("تذكير وَرَتِّلْ — تقبل الله طاعتك")
            .setStyle(NotificationCompat.BigTextStyle()
                .bigText("حان الآن وقت صلاة $prayerArabicName، بارك الله في وقتك وتقبل صلاتك."))
            .setContentIntent(intent)
            .addAction(android.R.drawable.ic_media_pause, "إيقاف", stopPendingIntent)
            .setAutoCancel(true)
            .setOnlyAlertOnce(false)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .build()
    }
}
