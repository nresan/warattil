package com.warattil.app.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.widget.Toast
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.AutoStories
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.warattil.app.R
import com.warattil.app.core.ShareUtil
import com.warattil.app.core.WarattilConstants.Hifz
import com.warattil.app.data.Ayah
import com.warattil.app.data.MetadataParser

// =============================================================================
// AyahActionBar — the floating action bar shown when a user long-presses an
// ayah.
//
// v1 scope: Copy + Share only. Bookmark-per-ayah, Play, and Note will come
// back once their backing subsystems exist (per-ayah bookmarks schema, audio
// engine, notes store). A row of greyed-out buttons would add noise to a
// Mushaf page; a lean bar that does two useful things reads as "considered,"
// not "unfinished."
//
// Positioning: v1 renders the bar at the top of the content area (below the
// header strip). The selected ayah itself carries the primary visual feedback
// — a soft accent-tinted background on its text + marker spans — so the bar
// only needs a consistent, one-hand-reachable location. A float-near-text
// popup version is a possible future refinement.
//
// Share / copy format — four lines with a minimal signature. The original
// v1 format was unsigned (ajr-first, "if someone likes it they'll ask where
// it came from"); field testing on WhatsApp revealed the tradeoff: recipients
// who were moved by the ayah had no path back to the app, and the organic
// distribution theory didn't pan out. The April 2026 revision adds a single
// signature line + Play URL — enough for WhatsApp / Telegram to render a
// rich card with the app icon, no marketing copy, no hadith framing.
//
//     ﴿ {ayah text} ﴾
//     سورة {name} · الآية {n in Arabic digits}
//
//     — تطبيق ورتّل
//     {PLAY_URL}
//
// The ﴿ ﴾ Mushaf sigil still carries most of the elegance; the em-dash
// prefix on the signature reads as a quote attribution convention, not a
// CTA. The URL is pulled from [ShareUtil.PLAY_URL] so the app has exactly
// one Play Store string to maintain.
//
// BLUEPRINT §11.3 — multi-ayah range share (April 2026)
// -----------------------------------------------------
// Readers often want to share a short pericope (2–5 contiguous ayahs) rather
// than a single verse.  The action bar grows an optional plus/minus chip pair
// between the memorize toggle and Copy, and the Copy/Share actions resolve
// their payload from the range (ayah .. endAyah) rather than just the anchor.
// The chips are shown only when the caller opts in — existing single-ayah
// call sites stay on their original signature because the range parameters
// default to null / single-ayah.
//
//     ﴿ {ayah_m} m۝ {ayah_m+1} m+1۝ … {ayah_n} n۝ ﴾
//     سورة {name} · الآيات {m}–{n}
//
//     — تطبيق ورتّل
//     {PLAY_URL}
//
// The U+06DD ARABIC END OF AYAH glyph renders the trailing digit inside a
// rosette on Arabic-capable platforms (iOS, Android, Windows, modern fonts),
// which gives the receiving reader a visible boundary between ayahs without
// us re-rendering a Mushaf page into the share payload.  EN DASH (U+2013)
// separates the range numbers so the citation matches iOS exactly.
//
// Used by:
//   • MushaFScreen.kt long-press handler (this file's caller)
// =============================================================================

/**
 * Canonical single-ayah share text. Four lines: ayah + citation + blank +
 * signature + Play URL. Eastern-Arabic digits throughout.
 *
 * Kept `internal` rather than `private` so any future share surface (e.g.,
 * a multi-ayah range share) can call the exact same formatter. Divergent
 * share text between surfaces would break the "one object, many surfaces"
 * consistency the design leans on.
 */
internal fun formatAyahForShare(ayah: Ayah): String {
    val text      = ayah.text?.trim()?.stripAnnotations().orEmpty()
    val n         = ayah.ayah ?: 0
    val surahIdx  = ayah.surah ?: 1
    val surahName = MetadataParser.getSuraName(surahIdx)
    return "﴿ $text ﴾\n" +
            "سورة $surahName · الآية ${n.toArabicDigits()}\n" +
            "\n" +
            "— تطبيق ورتّل\n" +
            ShareUtil.PLAY_URL
}

/**
 * Canonical range-share formatter.  Inlines the ayah-number marker (digit +
 * U+06DD ARABIC END OF AYAH) after each ayah's text so the receiving reader
 * can see where one ayah ends and the next begins.
 *
 * @param pageAyahs  The ayahs visible on the current page — passed in rather
 *                   than fetched so the action bar never hops to the repo
 *                   while a pill is open (must be instant).  Typically the
 *                   `pageContent.ayahs` the body is already rendering.
 * @param fromAyah   Start ayah (inclusive, 1-based within the surah).
 * @param toAyah     End ayah (inclusive, 1-based within the surah).  Must
 *                   satisfy fromAyah ≤ toAyah.
 * @param surahIdx   1-based surah number — used for both the citation line
 *                   ("سورة {name} · الآيات m–n") and to filter the ayahs
 *                   list when a page spans two surahs.
 *
 * Collapses to [formatAyahForShare] when the range is a single ayah so
 * callers can treat the two modes uniformly.  Returns the empty string when
 * any ayah in the range can't be resolved from [pageAyahs] — matches the
 * conservative behaviour of the iOS `shareText(surah:from:to:)`.
 */
internal fun formatAyahRangeForShare(
    pageAyahs: List<Ayah>,
    fromAyah:  Int,
    toAyah:    Int,
    surahIdx:  Int
): String {
    if (fromAyah > toAyah) return ""
    val surahName = MetadataParser.getSuraName(surahIdx)

    // Collect bodies for each ayah in the requested (surah, n) range.  We
    // walk pageAyahs once with an index-by-n lookup so duplicate ayahs
    // (shouldn't happen but defensive) don't produce a duplicate payload.
    val byAyah = HashMap<Int, Ayah>(toAyah - fromAyah + 1)
    for (a in pageAyahs) {
        if (a.surah == surahIdx && a.ayah != null && a.ayah in fromAyah..toAyah) {
            byAyah[a.ayah] = a
        }
    }
    // Build parts: "<body> ﴿n﴾"  — ornate-paren wrapped digit closing each
    //   ayah.  We previously used U+06DD (ARABIC END OF AYAH) here on the
    //   assumption that the receiving font would compose it with the
    //   preceding digit into a rosette glyph.  In practice (WhatsApp,
    //   Telegram, SMS, iOS Mail, default Android keyboards) the receiver's
    //   system Arabic font usually lacks that OpenType composition, so the
    //   digit floats outside an empty circle — visually broken on every
    //   non-Mushaf surface.  ﴿…﴾ (U+FD3F + U+FD3E) are pre-composed bracket
    //   characters that render identically across every Arabic-capable font,
    //   no composition required.  Same convention as the OUTER block-quote
    //   already uses, kept consistent.
    //   Joined by " " (U+0020) so 2-5 ayahs read as one flowing quote when
    //   pasted into WhatsApp, not as a bulleted list.
    val parts = ArrayList<String>(toAyah - fromAyah + 1)
    for (n in fromAyah..toAyah) {
        val body = byAyah[n]?.text?.trim()?.stripAnnotations() ?: return ""
        // Single-ayah branch inside the loop is unreachable for from==to
        // because we short-circuited above; keep the marker format uniform.
        parts.add("$body ﴿${n.toArabicDigits()}﴾")
    }
    val joined   = parts.joinToString(" ")
    val citation = if (fromAyah == toAyah) {
        "سورة $surahName · الآية ${fromAyah.toArabicDigits()}"
    } else {
        // EN DASH (U+2013) — many Arabic-facing receivers treat it as the
        // correct range separator and hyphen-minus as a literal character.
        "سورة $surahName · الآيات ${fromAyah.toArabicDigits()}\u2013${toAyah.toArabicDigits()}"
    }
    return "﴿ $joined ﴾\n" +
            "$citation\n" +
            "\n" +
            "— تطبيق ورتّل\n" +
            ShareUtil.PLAY_URL
}

/** Copy the formatted ayah text to the system clipboard, with a brief toast.
 *
 *  Terminology note: the Arabic verb «نَسَخَ» in Islamic sciences names the
 *  doctrine of abrogation (الناسخ والمنسوخ) — some early rulings replaced
 *  by later revelation. A copy-to-clipboard toast that says «نُسخت الآية»
 *  invites exactly the wrong reading in a Mushaf app. We use the ن-ق-ل root
 *  instead — neutral, technology-appropriate, and safely distant from
 *  classical Quranic terminology. Also avoided: حفظ (already means hifz /
 *  memorization in this app). */
private fun copyAyahToClipboard(context: Context, text: String) {
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    clipboard.setPrimaryClip(ClipData.newPlainText("ayah", text))
    Toast.makeText(context, "نُقلت إلى الحافظة", Toast.LENGTH_SHORT).show()
}

/** Fire ACTION_SEND with the formatted ayah text. No EXTRA_SUBJECT — content
 *  shares are body-only so the receiving app's preview is the ayah itself,
 *  not an email-style subject line.
 *
 *  `internal` so any future share surface (e.g. the multi-ayah range share
 *  planned for BLUEPRINT §11.3) can reuse it — divergent share payloads
 *  would break the "one object, many surfaces" consistency goal noted on
 *  [formatAyahForShare]. */
internal fun shareAyahText(context: Context, text: String) {
    val send = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_TEXT, text)
    }
    val chooser = Intent.createChooser(send, "مشاركة الآية").apply {
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    context.startActivity(chooser)
}

/**
 * Pill-shaped floating action bar. Renders Memorize · [±] · Copy · Share ·
 * Close as icon buttons separated by thin gold hairlines. The caller decides
 * placement — typically aligned TopCenter in a Box overlay.
 *
 * Single-ayah mode
 * ----------------
 * When [onExtendForward] and [onShrinkBackward] are both null, the bar
 * renders in its classic 4-button layout (no ± chips) and both Copy / Share
 * format the single [ayah] via [formatAyahForShare].  Back-compatible with
 * every existing call site — these were the only paths available before
 * BLUEPRINT §11.3.
 *
 * Range mode
 * ----------
 * When both extend / shrink callbacks are provided, a plus/minus chip pair
 * appears between the memorize toggle and Copy.  The chips delegate the
 * actual selection mutation to the caller — this view is intentionally
 * stateless so a single selection state machine lives in MushaFScreen.
 * Copy / Share route through [formatAyahRangeForShare] using [pageAyahs] as
 * the resolution source.
 *
 * The memorize toggle continues to act on the anchor [ayah] only in range
 * mode — users would otherwise flip the memorization state of 2-5 ayahs with
 * one tap, which is easy to misfire.  Bulk memorize lives in HifzBulkPickerSheet.
 */
@Composable
fun AyahActionBar(
    ayah            : Ayah,
    isMemorized     : Boolean,
    onToggleMemorize: () -> Unit,
    theme           : ThemeColors,
    onDismiss       : () -> Unit,
    // ── Range extensions (BLUEPRINT §11.3) ──────────────────────────────────
    // `endAyah` defaults to the anchor ayah so a null-op range (single ayah)
    // still produces the correct single-ayah share text.  The ± chips are
    // gated on BOTH callbacks being provided — if a caller only wants to
    // show static extend OR shrink it can't, which is the correct invariant:
    // the pair appears together or not at all.
    endAyah         : Int                 = ayah.ayah ?: 0,
    pageAyahs       : List<Ayah>          = emptyList(),
    onExtendForward : (() -> Unit)?       = null,
    onShrinkBackward: (() -> Unit)?       = null,
    canExtendForward : Boolean            = false,
    canShrinkBackward: Boolean            = false,
    // ── Secondary sheet (Ghareeb / tafsir / etc.) ──────────────────────────
    // When provided, a "book" icon appears between Copy and Share.  Tap →
    // opens AyahMeaningsSheet for the anchor ayah.  Optional (defaults to
    // null) so existing callers don't need to wire it.
    onOpenMeanings  : (() -> Unit)?       = null,
    modifier        : Modifier            = Modifier
) {
    val context = LocalContext.current

    // Resolve the canonical share payload once per recomposition — cheap
    // (string formatting on already-loaded data).  Falls through to the
    // single-ayah formatter when endAyah == ayah.ayah, which keeps the
    // range formatter a true superset of the legacy behaviour.
    val startAyahNum = ayah.ayah ?: 0
    val surahIdx     = ayah.surah ?: 1
    val payload: String = when {
        pageAyahs.isNotEmpty() && endAyah > startAyahNum ->
            formatAyahRangeForShare(pageAyahs, startAyahNum, endAyah, surahIdx)
        else ->
            formatAyahForShare(ayah)
    }

    // Range chips appear together or not at all — visual invariant enforced
    // at the property-derivation layer rather than relying on the caller to
    // supply both flags.
    val supportsRange = onExtendForward != null && onShrinkBackward != null

    Surface(
        modifier        = modifier,
        color           = theme.background,
        contentColor    = theme.accent,
        shape           = RoundedCornerShape(24.dp),
        tonalElevation  = 4.dp,
        shadowElevation = 8.dp,
        border          = BorderStroke(1.dp, theme.gold.copy(alpha = 0.45f))
    ) {
        Row(
            modifier              = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
            verticalAlignment     = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(0.dp)
        ) {
            // Compact IconButton size — was 48 dp default, shrunk to 38 dp
            // on 2026-04-25 because adding the MenuBook icon pushed the
            // bar past 360 dp screen width and clipped the close button
            // off the left edge.  At 38 dp we fit 7 icons + the rounded
            // pill border on a 360 dp display with breathing room.  Inner
            // glyph stays at 22 dp so it doesn't shrink visually below the
            // touch-target convention.  Hairline separators were dropped
            // in the same pass — the rounded-corner pill border + button
            // padding gives enough visual structure without them.
            val btnSize = Modifier.size(38.dp)
            val iconSize = Modifier.size(22.dp)

            // ── Memorize toggle ───────────────────────────────────────────
            // First action in the pill: the Hifz toggle.  Uses the same
            // ic_lawh_hifz glyph as the header strip so a user who has
            // learned the strip's meaning recognises this action instantly.
            // Tint hops between gold-full (memorized) and a dimmed gold
            // (not yet) — mirroring the tri-state alpha scheme in
            // WarattilConstants.Hifz.stripAlpha.  We do NOT dismiss the bar
            // on toggle: users often want to verify the glyph state before
            // moving on, and a self-dismissing toggle makes that impossible.
            //
            // In range mode the toggle still acts on the ANCHOR ayah only —
            // flipping memorization across 2-5 ayahs with a single tap is
            // easy to misfire.  Bulk memorize lives in HifzBulkPickerSheet.
            IconButton(onClick = onToggleMemorize, modifier = btnSize) {
                Icon(
                    painter = painterResource(R.drawable.ic_lawh_hifz),
                    contentDescription = if (isMemorized) "إلغاء تعليم الحفظ" else "تعليم محفوظ",
                    tint = if (isMemorized) Hifz.HIFZ_GOLD
                           else            Hifz.HIFZ_GOLD.copy(alpha = Hifz.STRIP_ALPHA_EMPTY),
                    modifier = iconSize
                )
            }

            // ── Range chips (optional) ────────────────────────────────────
            // Plus/minus pair for extending the selection to a contiguous
            // multi-ayah range.  Rendered only when both callbacks are
            // provided — enforces the "pair or nothing" invariant at the
            // type level.  Disabled state: 35 % accent alpha + enabled=false
            // so the chip still reserves space (stable layout while a user
            // extends toward the page boundary) but no longer reacts.
            if (supportsRange) {
                IconButton(
                    onClick = { onShrinkBackward?.invoke() },
                    enabled = canShrinkBackward,
                    modifier = btnSize
                ) {
                    Icon(
                        Icons.Filled.Remove,
                        contentDescription = "إنقاص آية",
                        tint = if (canShrinkBackward) theme.accent
                               else                  theme.accent.copy(alpha = 0.35f),
                        modifier = iconSize
                    )
                }
                IconButton(
                    onClick = { onExtendForward?.invoke() },
                    enabled = canExtendForward,
                    modifier = btnSize
                ) {
                    Icon(
                        Icons.Filled.Add,
                        contentDescription = "أضف آية",
                        tint = if (canExtendForward) theme.accent
                               else                 theme.accent.copy(alpha = 0.35f),
                        modifier = iconSize
                    )
                }
            }

            // ── Copy ──────────────────────────────────────────────────────
            IconButton(
                onClick  = {
                    copyAyahToClipboard(context, payload)
                    onDismiss()
                },
                modifier = btnSize
            ) {
                Icon(
                    Icons.Filled.ContentCopy,
                    // ن-ق-ل root (not ن-س-خ) to avoid colliding with the
                    // classical abrogation doctrine — see the comment on
                    // copyAyahToClipboard above.
                    contentDescription = if (endAyah > startAyahNum) "نقل الآيات" else "نقل الآية",
                    tint     = theme.accent,
                    modifier = iconSize
                )
            }

            // ── Meanings sheet (Ghareeb) ────────────────────────────────────
            // Optional — only renders when [onOpenMeanings] is wired by the
            // caller.  Opens AyahMeaningsSheet anchored at this ayah.  The
            // bar itself doesn't dismiss; users typically want to glance at
            // a meaning and come back to copy / share / extend the range.
            if (onOpenMeanings != null) {
                IconButton(onClick = onOpenMeanings, modifier = btnSize) {
                    Icon(
                        // 2026-04-27: was Icons.Filled.MenuBook — Nasser
                        // reported the glyph reading as a small dense
                        // closed book in the action bar at 38dp.
                        // AutoStories is the open-pages variant of the
                        // same Material book family — same lexical
                        // meaning ("a book"), but the splayed-pages
                        // silhouette reads at a glance even at compact
                        // sizes, and matches the "open the meanings of
                        // this ayah" semantic better.
                        Icons.Filled.AutoStories,
                        contentDescription = "معاني الكلمات",
                        tint               = theme.accent,
                        modifier           = iconSize
                    )
                }
            }

            // ── Share ─────────────────────────────────────────────────────
            IconButton(
                onClick  = {
                    shareAyahText(context, payload)
                    onDismiss()
                },
                modifier = btnSize
            ) {
                Icon(
                    Icons.Filled.Share,
                    contentDescription = if (endAyah > startAyahNum) "مشاركة الآيات" else "مشاركة الآية",
                    tint     = theme.accent,
                    modifier = iconSize
                )
            }

            // ── Close ─────────────────────────────────────────────────────
            // Explicit dismiss. Without this the only ways to clear a
            // selection were (1) fire an action, (2) swipe to another page,
            // or (3) long-press a different ayah — none of which covers the
            // "I changed my mind" case. The X is rendered in a slightly
            // muted tone so it reads as a secondary affordance, not a
            // peer to the Copy / Share primaries.
            IconButton(onClick = onDismiss, modifier = btnSize) {
                Icon(
                    Icons.Filled.Close,
                    contentDescription = "إغلاق",
                    tint     = theme.accent.copy(alpha = 0.65f),
                    modifier = iconSize
                )
            }
        }
    }
}

// Hairline separator removed 2026-04-25 with the action-bar compaction —
// the rounded-corner pill border + IconButton padding gives enough visual
// structure without per-icon dividers.
