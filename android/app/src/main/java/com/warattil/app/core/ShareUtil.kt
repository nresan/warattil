package com.warattil.app.core

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import androidx.core.content.FileProvider
import java.io.File
import java.io.FileOutputStream

// =============================================================================
// ShareUtil — fires the Android share-sheet across every share surface in
// the app.  Framed around the hadith "من دلَّ على خير فله مثل أجر فاعله"
// (on the one-time app-invite path) rather than growth-marketing language.
//
// Called from:
//   • MushaFHeader overflow "شارك ورتّل" item             → shareAppInvite
//   • Overflow "شارك قراءة اليوم" item                     → shareDailyReading
//   • AboutSheet QR tap                                  → shareQrCode
//   • HifzLogSheet heatmap "مشاركة الخريطة" button        → shareHifzGarden
//   • AyahActionBar (single ayah or multi-ayah range)    → shareAyahText
//
// Design notes (all image-share paths):
//   • Activity items are a multi-part list: [imageUri, text].  Each
//     destination app picks the subset it renders best —
//        Instagram Stories  → image only (drops text)
//        Facebook / Twitter → image + URL (synthesised rich preview card)
//        WhatsApp / Telegram → image + text (URL embedded inline in text)
//        Mail / Messages    → everything
//   • The rendered PNG already carries the "ورتّل · warattil.org/get"
//     wordmark so even the image-only destinations are self-identifying.
//   • FileProvider authority is applicationId-qualified (see manifest)
//     so the V2 and V3 APKs can coexist without colliding.
//   • All cache files overwrite on each call; the system wipes cacheDir
//     under memory pressure so no manual cleanup is required.
//   • FLAG_GRANT_READ_URI_PERMISSION is mandatory for the receiving app to
//     actually read the image from our FileProvider.
//
// Mirror file: ios/Warattil/Warattil/Core/ShareUtil.swift.  Keep payload
// strings, URLs, and chooser titles byte-identical between the two so a
// user who shares the same surface from iOS and Android receives the same
// message.
// =============================================================================

object ShareUtil {

    /** Canonical share URL — branded short link on Nasser's own domain.
     *
     *  The server at warattil.org/get does a UA-sniffing 302 redirect:
     *    • iOS User-Agents   → https://apps.apple.com/app/id6766103481
     *    • Android UAs       → https://play.google.com/store/apps/details?id=com.warattil.warattilmushaf
     *    • everything else   → Play Store (desktop browsers fall through to Android listing)
     *
     *  Why the redirect instead of the raw Play URL:
     *    • Short — fits on one line in WhatsApp / Telegram previews.
     *    • Branded — "warattil.org" carries trust; shorteners like bit.ly
     *      look like spam and create a third-party failure dependency.
     *    • Platform-aware — iPhone users land on the App Store, not the
     *      wrong store + manual hunt.
     *
     *  Lockstep asset: res/drawable-nodpi/warattil_qr.png encodes this
     *  SAME URL and is rendered in the About sheet — if PLAY_URL changes,
     *  the QR must be regenerated in the same commit. */
    const val PLAY_URL = "https://warattil.org/get"

    // -------------------------------------------------------------------------
    // MARK: App-invite share — "شارك ورتّل"
    //
    //   Text-only fallback (if the rendered AppInviteShareCard bitmap is
    //   null) + image-augmented primary path.  Carries the hadith framing
    //   — this is the one-time invitation path where the framing belongs.
    //   Recurring-content paths (ayah, daily, garden, QR) keep a short
    //   caption so the framing doesn't grow stale.
    // -------------------------------------------------------------------------

    /** Arabic share text.  Leading line names the app so recipients who have
     *  never seen Warattil understand what they're being invited to try. */
    internal val APP_SHARE_TEXT = """
        ورتّل — مصحف رقمي بخط عثماني كامل، بلا إعلانات ولا إلهاء.
        اقرأ، احفظ، وتابع وردك اليومي.

        قال النبي ﷺ: «من دلَّ على خير فله مثل أجر فاعله»

        $PLAY_URL
    """.trimIndent()

    private const val APP_SHARE_SUBJECT = "ورتّل — مصحف رقمي"
    private const val APP_SHARE_CHOOSER = "شارك ورتّل"

    /**
     * Text-only invite — kept for callers that don't supply an image or
     * when the rendered card bitmap is null.  Use [shareAppInvite] by
     * default so Instagram Stories / Facebook / Twitter get the rendered
     * card.
     */
    fun shareApp(context: Context) {
        val sendIntent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_SUBJECT, APP_SHARE_SUBJECT)
            putExtra(Intent.EXTRA_TEXT,    APP_SHARE_TEXT)
        }
        val chooser = Intent.createChooser(sendIntent, APP_SHARE_CHOOSER).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(chooser)
    }

    /**
     * App-invite share with a rendered [AppInviteShareCard] bitmap.  When
     * [bitmap] is null (render failed — shouldn't happen for a 380 dp card)
     * the path falls back to the text-only intent so the user never hits a
     * silent dead-end.
     *
     *   Instagram Stories   → image only
     *   Facebook / Twitter  → image + URL (rich preview with the card)
     *   WhatsApp / Telegram → image + body text
     *   SMS / Mail          → everything
     */
    fun shareAppInvite(context: Context, bitmap: Bitmap?) {
        if (bitmap == null) { shareApp(context); return }
        sendImage(
            context     = context,
            bitmap      = bitmap,
            fileName    = "warattil_invite.png",
            subject     = APP_SHARE_SUBJECT,
            text        = APP_SHARE_TEXT,
            chooserTitle = APP_SHARE_CHOOSER
        )
    }

    // -------------------------------------------------------------------------
    // MARK: Hifz garden share
    //
    //   The HifzLogSheet renders the heatmap inside a graphicsLayer and
    //   captures it to a Bitmap on the reader's "مشاركة الخريطة" tap.  We
    //   hand it to the share chooser alongside a brief caption + brand URL.
    // -------------------------------------------------------------------------

    private const val GARDEN_SHARE_SUBJECT = "خريطة حفظي في ورتّل"

    /** Body for garden-image share.  Short — the image is the message.  */
    private val GARDEN_SHARE_TEXT = """
        هذه خريطة حفظي في ورتّل.
        $PLAY_URL
    """.trimIndent()

    /**
     * Save [bitmap] to cacheDir/shared_images/ and present the system share
     * chooser with [image + text] activity items.  File is overwritten on
     * each call — we only ever need the most recent snapshot in flight.
     */
    fun shareHifzGarden(context: Context, bitmap: Bitmap) {
        sendImage(
            context      = context,
            bitmap       = bitmap,
            fileName     = "warattil_garden.png",
            subject      = GARDEN_SHARE_SUBJECT,
            text         = GARDEN_SHARE_TEXT,
            chooserTitle = "شارك خريطة الحفظ"
        )
    }

    // -------------------------------------------------------------------------
    // MARK: Daily reading status share
    //
    //   Caller renders DailyReadingShareCard into a graphicsLayer, captures
    //   a Bitmap, and hands it here.  Accompanying caption is intentionally
    //   terse — the card IS the message.
    // -------------------------------------------------------------------------

    private const val DAILY_SHARE_SUBJECT = "ورد اليوم · ورتّل"

    private val DAILY_SHARE_TEXT = """
        ورد اليوم مع ورتّل.
        $PLAY_URL
    """.trimIndent()

    fun shareDailyReading(context: Context, bitmap: Bitmap) {
        sendImage(
            context      = context,
            bitmap       = bitmap,
            fileName     = "warattil_daily.png",
            subject      = DAILY_SHARE_SUBJECT,
            text         = DAILY_SHARE_TEXT,
            chooserTitle = "شارك ورد اليوم"
        )
    }

    // -------------------------------------------------------------------------
    // MARK: Hifz milestone (tier-crossing) share
    //
    //   Caller renders HifzCelebrationDialog's content into a graphicsLayer,
    //   captures a Bitmap, and hands it here.  Earlier the dialog's "شارك
    //   فرحتك" button fell through to the App-Invite text share — which
    //   sent the wrong message (a generic invite, not the milestone card).
    //   With image capture the receiver sees the actual celebration card.
    // -------------------------------------------------------------------------

    private const val MILESTONE_SHARE_SUBJECT = "مرحلة جديدة في حفظي · ورتّل"

    private val MILESTONE_SHARE_TEXT = """
        بفضل الله، بلغتُ مرحلةً جديدة في رحلة حفظ القرآن.
        $PLAY_URL
    """.trimIndent()

    fun shareHifzMilestone(context: Context, bitmap: Bitmap) {
        sendImage(
            context      = context,
            bitmap       = bitmap,
            fileName     = "warattil_milestone.png",
            subject      = MILESTONE_SHARE_SUBJECT,
            text         = MILESTONE_SHARE_TEXT,
            chooserTitle = "شارك فرحتك"
        )
    }

    // -------------------------------------------------------------------------
    // MARK: QR code share
    //
    //   Some readers want to DM the QR to a friend so the friend can scan
    //   directly instead of copy-pasting a URL.  Caller passes the decoded
    //   warattil_qr bitmap (loaded from res/drawable-nodpi/warattil_qr.png)
    //   and we present a share chooser with it.
    // -------------------------------------------------------------------------

    private const val QR_SHARE_SUBJECT = "رمز ورتّل"

    private val QR_SHARE_TEXT = """
        امسح الرمز لتحميل تطبيق ورتّل.
        $PLAY_URL
    """.trimIndent()

    /**
     * Share the bundled QR PNG.  Caller supplies the decoded bitmap (loaded
     * via BitmapFactory.decodeResource so we don't need to know which dpi
     * bucket the resource resolved to).  Quiet-fail on null bitmap matches
     * the iOS implementation's behaviour — beats crashing the reader.
     */
    fun shareQrCode(context: Context, bitmap: Bitmap?) {
        if (bitmap == null) return
        sendImage(
            context      = context,
            bitmap       = bitmap,
            fileName     = "warattil_qr.png",
            subject      = QR_SHARE_SUBJECT,
            text         = QR_SHARE_TEXT,
            chooserTitle = "شارك رمز ورتّل"
        )
    }

    // -------------------------------------------------------------------------
    // MARK: Shared PNG-share helper
    //
    //   Single place that (a) writes the bitmap to cacheDir/shared_images/
    //   under [fileName], (b) wraps it with the FileProvider-derived URI,
    //   (c) builds the ACTION_SEND intent with image + text, (d) fires the
    //   chooser with the provided title.
    //
    //   Adding a new share surface is a one-liner into this helper; no
    //   copy-paste of the FileProvider boilerplate each time.
    // -------------------------------------------------------------------------

    private fun sendImage(
        context     : Context,
        bitmap      : Bitmap,
        fileName    : String,
        subject     : String,
        text        : String,
        chooserTitle: String
    ) {
        val dir = File(context.cacheDir, "shared_images").apply { mkdirs() }
        val file = File(dir, fileName)

        FileOutputStream(file).use { out ->
            // Lossless PNG — these cards are flat UI, PNG compresses them
            // to tiny files (typically < 100 KB) while keeping edges crisp.
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        }

        val authority = "${context.packageName}.fileprovider"
        val uri = FileProvider.getUriForFile(context, authority, file)

        val sendIntent = Intent(Intent.ACTION_SEND).apply {
            type = "image/png"
            putExtra(Intent.EXTRA_STREAM,  uri)
            putExtra(Intent.EXTRA_SUBJECT, subject)
            putExtra(Intent.EXTRA_TEXT,    text)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val chooser = Intent.createChooser(sendIntent, chooserTitle).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(chooser)
    }
}
