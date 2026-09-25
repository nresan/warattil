package com.warattil.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.warattil.app.R
import com.warattil.app.core.WarattilConstants.Hifz
import com.warattil.app.core.WarattilConstants.Typography

// =============================================================================
// MushaFHeader — slim icon strip with compact location label.
//
// The header carries a «سورة X · الجزء N» label so a reader deep inside a
// surah (say, page 293 in al-Kahf) always knows where they are without
// scrolling back to the surah-opening banner.  The per-surah title-plate
// inside the page body (SurahBanner()) still renders on surah-start pages
// — the header label is an always-visible secondary cue, not a replacement.
//
// Layout (visual, left → right):
//   • Left cluster  — bookmark · hifz star · سورة X · الجزء N
//   • Right cluster — theme-cycle · search · overflow ⋮
//
// On multi-surah pages (604, 603, …) the header label shows whichever
// surah `surahName` resolved to — typically the first one on the page,
// which matches user expectation ("where am I landing?").
//
// The overflow is anchored at the far right so its menu opens away from
// the cluster rather than across it.
//
// Edge-to-edge: .statusBarsPadding() pushes the icon row below the system
// clock / camera punch-hole (targetSdk 35 enforces edge-to-edge layout).
// =============================================================================

@Composable
fun MushaFHeader(
    surahName     : String,
    juzNum        : Int,
    currentPage   : Int,
    font          : QuranFontInfo,
    theme         : ThemeColors,
    isBookmarked  : Boolean,
    // 0 .. 1 density of ayah-level memorization on the current page.  The
    // top-strip glyph hops across three alpha tiers (empty / partial / full)
    // driven by Hifz.stripAlpha — so a partially memorized page reads as
    // "in progress" even before it is fully complete.
    pageMemorizationRatio : Float,
    // Callbacks
    onBookmark    : () -> Unit,
    onMemorize    : () -> Unit,       // toggles memorized-state for current page
    onDarkMode    : () -> Unit,       // cycles theme (Heritage → Dark → Sepia)
    onSearch      : () -> Unit,
    onMore        : () -> Unit,
    menuExpanded  : Boolean,
    onMenuDismiss : () -> Unit,
    onFihris      : () -> Unit,
    onWird        : () -> Unit,
    onBkm         : () -> Unit,
    onHifzLog     : () -> Unit,
    onAzanSettings: () -> Unit,       // opens the «أوقات الصلاة» prayer-reminder sheet
    onUsageGuide  : () -> Unit,       // opens the six-entry «دليل الاستخدام» sheet
    onAbout       : () -> Unit,
    onShareDaily  : () -> Unit,       // captures DailyReadingShareCard → share chooser
    onShare       : () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(theme.background)
            .statusBarsPadding()                    // ← clears system clock / camera
            .padding(top = 4.dp, bottom = 4.dp)
    ) {
        Row(
            modifier              = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp),
            verticalAlignment     = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            // ── Left cluster — bookmark · hifz · juz label ───────────────────
            Row(
                verticalAlignment     = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                IconButton(onClick = onBookmark, modifier = Modifier.size(30.dp)) {
                    Icon(
                        imageVector = if (isBookmarked) Icons.Filled.Bookmark
                                      else              Icons.Filled.BookmarkBorder,
                        contentDescription = null,
                        tint     = if (isBookmarked) theme.accent
                                   else              theme.accent.copy(alpha = 0.5f),
                        modifier = Modifier.size(18.dp)
                    )
                }
                IconButton(onClick = onMemorize, modifier = Modifier.size(30.dp)) {
                    // Top-strip memorize toggle — uses the same لوح glyph as
                    // the menu entry.  Three-tier alpha driven by
                    // Hifz.stripAlpha(ratio): EMPTY (0.30) for untouched,
                    // PARTIAL (0.60) while any ayah on the page is memorized,
                    // FULL (1.00) when every ayah is in the set.
                    Icon(
                        painter            = painterResource(R.drawable.ic_lawh_hifz),
                        contentDescription = null,
                        tint     = Hifz.HIFZ_GOLD.copy(alpha = Hifz.stripAlpha(pageMemorizationRatio)),
                        modifier = Modifier.size(18.dp)
                    )
                }
                if (juzNum > 0) {
                    // Compact location label: «سورة X · الجزء N» — always
                    // visible so a reader mid-surah knows where they are
                    // without scrolling back to the opening banner (user
                    // feedback 2026-04-24).  On multi-surah pages we show
                    // whichever surah surahName resolved to (typically the
                    // first).  FontFamily.Default — the Uthmanic font
                    // mangles digits via ayah-badge glyph substitution,
                    // so we keep the whole label in the chrome font.
                    val label = if (surahName.isNotEmpty())
                        "سورة $surahName · الجزء ${juzNum.toArabicDigits()}"
                    else
                        "الجزء ${juzNum.toArabicDigits()}"
                    Text(
                        text       = label,
                        color      = theme.gold,
                        fontSize   = Typography.JUZ_LABEL_SIZE,
                        fontFamily = FontFamily.Default,
                        maxLines   = 1,
                        style      = TextStyle(textDirection = TextDirection.Rtl)
                    )
                }
            }

            // ── Right cluster — palette · search · overflow ⋮ ─────────────────
            Row(
                verticalAlignment     = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                IconButton(onClick = onDarkMode, modifier = Modifier.size(30.dp)) {
                    Icon(
                        Icons.Default.Palette, null,
                        tint = theme.accent, modifier = Modifier.size(16.dp)
                    )
                }
                IconButton(onClick = onSearch, modifier = Modifier.size(30.dp)) {
                    Icon(
                        Icons.Default.Search, null,
                        tint = theme.accent, modifier = Modifier.size(18.dp)
                    )
                }
                // Overflow ☰ (hamburger) anchored to the far right — its
                // dropdown opens downward from this Box.  Balanced menu:
                // 190-dp-wide panel with 20-sp Medium items on 10-dp vertical
                // padding — legible without feeling oversized.
                Box {
                    IconButton(onClick = onMore, modifier = Modifier.size(40.dp)) {
                        Icon(
                            Icons.Default.Menu, null,
                            tint = theme.accent, modifier = Modifier.size(26.dp)
                        )
                    }
                    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
                        DropdownMenu(
                            expanded         = menuExpanded,
                            onDismissRequest = onMenuDismiss,
                            modifier         = Modifier
                                .background(theme.background)
                                .width(220.dp)
                        ) {
                            val itemPad = PaddingValues(horizontal = 16.dp, vertical = 10.dp)
                            // All items share theme.accent (Mushaf Green) — one
                            // voice, no visual hierarchy by colour.  Leading
                            // icons echo real UI affordances / section themes.
                            DropdownMenuItem(
                                text        = {
                                    Text(
                                        "الفهرس",
                                        color      = theme.accent,
                                        fontFamily = font.family,
                                        fontSize   = 20.sp,
                                        fontWeight = FontWeight.Medium
                                    )
                                },
                                leadingIcon = {
                                    Icon(
                                        Icons.Default.MenuBook, null,
                                        tint = theme.gold, modifier = Modifier.size(22.dp)
                                    )
                                },
                                onClick        = onFihris,
                                contentPadding = itemPad
                            )
                            DropdownMenuItem(
                                text        = {
                                    Text(
                                        "إشاراتي",
                                        color      = theme.accent,
                                        fontFamily = font.family,
                                        fontSize   = 20.sp,
                                        fontWeight = FontWeight.Medium
                                    )
                                },
                                leadingIcon = {
                                    Icon(
                                        Icons.Default.Bookmarks, null,
                                        tint = theme.gold, modifier = Modifier.size(22.dp)
                                    )
                                },
                                onClick        = onBkm,
                                contentPadding = itemPad
                            )
                            DropdownMenuItem(
                                text        = {
                                    // 2026-04-27 (pt. 2): reverted to
                                    // «الورد اليومي» — the verb form
                                    // «اضبط ورد اليوم» read as "set
                                    // today's reading" (a one-day action)
                                    // but the function is a long-term
                                    // plan to finish the Quran by N
                                    // days/pages/juz.  «الورد اليومي»
                                    // names the feature itself: the
                                    // daily routine.  See cancel-wird
                                    // memory note for the full semantic.
                                    Text(
                                        "الورد اليومي",
                                        color      = theme.accent,
                                        fontFamily = font.family,
                                        fontSize   = 20.sp,
                                        fontWeight = FontWeight.Medium
                                    )
                                },
                                leadingIcon = {
                                    // ic_mushaf_rihal — open Mushaf on a
                                    // wooden rihal stand.  Replaces the
                                    // generic Icons.Default.Today
                                    // (calendar) icon, which read as
                                    // "schedule something for later"
                                    // instead of "configure today's Quran
                                    // reading."  Drawn in the same kuttāb
                                    // visual register as ic_lawh_dawaah_qalam
                                    // (the «حلقة الحفظ» glyph) so the menu
                                    // strip reads as one matched set.
                                    Icon(
                                        painter            = painterResource(R.drawable.ic_mushaf_rihal),
                                        contentDescription = null,
                                        tint               = theme.gold,
                                        modifier           = Modifier.size(22.dp)
                                    )
                                },
                                onClick        = onWird,
                                contentPadding = itemPad
                            )
                            DropdownMenuItem(
                                text        = {
                                    Text(
                                        "حلقة الحفظ",
                                        color      = theme.accent,
                                        fontFamily = font.family,
                                        fontSize   = 20.sp,
                                        fontWeight = FontWeight.Medium
                                    )
                                },
                                leadingIcon = {
                                    // Kuttāb workstation — tablet + reed qalam
                                    // + inkpot (ic_lawh_dawaah_qalam).  Evokes
                                    // the study circle (الحلقة) rather than a
                                    // single tablet.
                                    Icon(
                                        painter            = painterResource(R.drawable.ic_lawh_dawaah_qalam),
                                        contentDescription = null,
                                        tint               = theme.gold,
                                        modifier           = Modifier.size(22.dp)
                                    )
                                },
                                onClick        = onHifzLog,
                                contentPadding = itemPad
                            )
                            // ── أوقات الصلاة — prayer-reminder configuration ─────
                            // Sits inside the devotional cluster (Wird → Hifz →
                            // Azan): three ongoing devotional surfaces the user
                            // configures once and that then run quietly in the
                            // background.  The clock glyph (Schedule) reads as
                            // "scheduled reminder" without overpromising audio.
                            DropdownMenuItem(
                                text        = {
                                    Text(
                                        "أوقات الصلاة",
                                        color      = theme.accent,
                                        fontFamily = font.family,
                                        fontSize   = 20.sp,
                                        fontWeight = FontWeight.Medium
                                    )
                                },
                                leadingIcon = {
                                    Icon(
                                        Icons.Default.Schedule, null,
                                        tint = theme.gold, modifier = Modifier.size(22.dp)
                                    )
                                },
                                onClick        = onAzanSettings,
                                contentPadding = itemPad
                            )
                            // ── دليل الاستخدام — how-to / reference sheet ─────
                            // Positioned between the functional trio (فهرس،
                            // إشارات، ورد، حفظ) and the identity items
                            // (عن التطبيق، شارك ورتّل): it's the hinge
                            // between "what can I do here" and "who made
                            // this". Help-outline glyph is universally
                            // read — its "?" reads left-to-right but the
                            // semantic never needs mirroring.
                            DropdownMenuItem(
                                text        = {
                                    Text(
                                        "دليل الاستخدام",
                                        color      = theme.accent,
                                        fontFamily = font.family,
                                        fontSize   = 20.sp,
                                        fontWeight = FontWeight.Medium
                                    )
                                },
                                leadingIcon = {
                                    Icon(
                                        Icons.Default.HelpOutline, null,
                                        tint = theme.gold, modifier = Modifier.size(22.dp)
                                    )
                                },
                                onClick        = onUsageGuide,
                                contentPadding = itemPad
                            )
                            DropdownMenuItem(
                                text        = {
                                    Text(
                                        "عن التطبيق",
                                        color      = theme.accent,
                                        fontFamily = font.family,
                                        fontSize   = 20.sp,
                                        fontWeight = FontWeight.Medium
                                    )
                                },
                                leadingIcon = {
                                    Icon(
                                        Icons.Default.Info, null,
                                        tint = theme.gold, modifier = Modifier.size(22.dp)
                                    )
                                },
                                onClick        = onAbout,
                                contentPadding = itemPad
                            )
                            // ── شارك قراءة اليوم — daily-reading status card ──
                            // Penultimate item in the menu: captures the
                            // DailyReadingShareCard to a bitmap and fires the
                            // share chooser with image + caption + URL.  The
                            // Insights glyph reads as a "stats / progress"
                            // cue without looking like growth-marketing chrome.
                            DropdownMenuItem(
                                text        = {
                                    Text(
                                        "شارك قراءة اليوم",
                                        color      = theme.accent,
                                        fontFamily = font.family,
                                        fontSize   = 20.sp,
                                        fontWeight = FontWeight.Medium
                                    )
                                },
                                leadingIcon = {
                                    Icon(
                                        Icons.Default.Insights, null,
                                        tint = theme.gold, modifier = Modifier.size(22.dp)
                                    )
                                },
                                onClick        = onShareDaily,
                                contentPadding = itemPad
                            )
                            // ── شارك ورتّل — hadith-framed invitation CTA ──
                            // Last item in the menu: a gentle "exit point"
                            // for users who want to invite others.  Material
                            // Share icon is universally read; gold tint keeps
                            // it consistent with the rest of the leading icons.
                            DropdownMenuItem(
                                text        = {
                                    Text(
                                        "شارك ورتّل",
                                        color      = theme.accent,
                                        fontFamily = font.family,
                                        fontSize   = 20.sp,
                                        fontWeight = FontWeight.Medium
                                    )
                                },
                                leadingIcon = {
                                    Icon(
                                        Icons.Default.Share, null,
                                        tint = theme.gold, modifier = Modifier.size(22.dp)
                                    )
                                },
                                onClick        = onShare,
                                contentPadding = itemPad
                            )
                        }
                    }
                }
            }
        }
    }
}

// =============================================================================
// Compact landscape header strip (28 dp tall) — mirrors the portrait
// cluster layout: palette · search · overflow on the right.
// =============================================================================

@Composable
fun LandscapeHeaderStrip(
    surahName     : String,
    juzNum        : Int,
    currentPage   : Int,
    font          : QuranFontInfo,
    theme         : ThemeColors,
    isBookmarked  : Boolean,
    pageMemorizationRatio : Float,
    onBookmark    : () -> Unit,
    onMemorize    : () -> Unit,
    onThemeCycle  : () -> Unit,
    onSearch      : () -> Unit,
    onMore        : () -> Unit,
    menuExpanded  : Boolean,
    onMenuDismiss : () -> Unit,
    onFihris      : () -> Unit,
    onWird        : () -> Unit,
    onBkm         : () -> Unit,
    onHifzLog     : () -> Unit,
    onAzanSettings: () -> Unit,
    onUsageGuide  : () -> Unit,
    onAbout       : () -> Unit,
    onShareDaily  : () -> Unit,
    onShare       : () -> Unit,
    modifier      : Modifier = Modifier
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .statusBarsPadding()
            .height(28.dp)
            .background(theme.background.copy(alpha = 0.95f))
            .padding(horizontal = 10.dp),
        verticalAlignment     = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        // Left cluster — bookmark · hifz
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBookmark, modifier = Modifier.size(24.dp)) {
                Icon(
                    if (isBookmarked) Icons.Filled.Bookmark else Icons.Filled.BookmarkBorder,
                    null, tint = theme.accent, modifier = Modifier.size(14.dp)
                )
            }
            IconButton(onClick = onMemorize, modifier = Modifier.size(24.dp)) {
                // Same tri-state alpha treatment as the portrait header —
                // see MushaFHeader.kt's portrait cluster for rationale.
                Icon(
                    painter            = painterResource(R.drawable.ic_lawh_hifz),
                    contentDescription = null,
                    tint     = Hifz.HIFZ_GOLD.copy(alpha = Hifz.stripAlpha(pageMemorizationRatio)),
                    modifier = Modifier.size(14.dp)
                )
            }
        }

        Text(
            "$surahName  ·  الجزء ${juzNum.toArabicDigits()}  ·  ${currentPage.toArabicDigits()}",
            color      = theme.text,
            fontSize   = 10.sp,
            fontFamily = FontFamily.Default,
            maxLines   = 1,
            style      = TextStyle(textDirection = TextDirection.Rtl),
            modifier   = Modifier.weight(1f),
            textAlign  = TextAlign.Center
        )

        // Right cluster — palette · search · overflow ⋮
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onThemeCycle, modifier = Modifier.size(24.dp)) {
                Icon(Icons.Default.Palette, null, tint = theme.accent, modifier = Modifier.size(13.dp))
            }
            IconButton(onClick = onSearch, modifier = Modifier.size(24.dp)) {
                Icon(Icons.Default.Search, null, tint = theme.accent, modifier = Modifier.size(14.dp))
            }
            Box {
                IconButton(onClick = onMore, modifier = Modifier.size(28.dp)) {
                    Icon(Icons.Default.Menu, null, tint = theme.accent, modifier = Modifier.size(20.dp))
                }
                CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
                    DropdownMenu(
                        expanded         = menuExpanded,
                        onDismissRequest = onMenuDismiss,
                        modifier         = Modifier
                            .background(theme.background)
                            .width(220.dp)
                    ) {
                        val itemPad = PaddingValues(horizontal = 16.dp, vertical = 10.dp)
                        DropdownMenuItem(
                            text        = { Text("الفهرس",       color = theme.accent, fontFamily = font.family, fontSize = 20.sp, fontWeight = FontWeight.Medium) },
                            leadingIcon = { Icon(Icons.Default.MenuBook,  null, tint = theme.gold, modifier = Modifier.size(22.dp)) },
                            onClick = onFihris, contentPadding = itemPad
                        )
                        DropdownMenuItem(
                            text        = { Text("إشاراتي",      color = theme.accent, fontFamily = font.family, fontSize = 20.sp, fontWeight = FontWeight.Medium) },
                            leadingIcon = { Icon(Icons.Default.Bookmarks, null, tint = theme.gold, modifier = Modifier.size(22.dp)) },
                            onClick = onBkm, contentPadding = itemPad
                        )
                        DropdownMenuItem(
                            text        = { Text("الورد اليومي", color = theme.accent, fontFamily = font.family, fontSize = 20.sp, fontWeight = FontWeight.Medium) },
                            leadingIcon = {
                                Icon(
                                    painter            = painterResource(R.drawable.ic_mushaf_rihal),
                                    contentDescription = null,
                                    tint               = theme.gold,
                                    modifier           = Modifier.size(22.dp)
                                )
                            },
                            onClick = onWird, contentPadding = itemPad
                        )
                        DropdownMenuItem(
                            text        = { Text("حلقة الحفظ",   color = theme.accent, fontFamily = font.family, fontSize = 20.sp, fontWeight = FontWeight.Medium) },
                            leadingIcon = {
                                Icon(
                                    painter            = painterResource(R.drawable.ic_lawh_dawaah_qalam),
                                    contentDescription = null,
                                    tint               = theme.gold,
                                    modifier           = Modifier.size(22.dp)
                                )
                            },
                            onClick = onHifzLog, contentPadding = itemPad
                        )
                        DropdownMenuItem(
                            text        = { Text("أوقات الصلاة", color = theme.accent, fontFamily = font.family, fontSize = 20.sp, fontWeight = FontWeight.Medium) },
                            leadingIcon = { Icon(Icons.Default.Schedule, null, tint = theme.gold, modifier = Modifier.size(22.dp)) },
                            onClick = onAzanSettings, contentPadding = itemPad
                        )
                        DropdownMenuItem(
                            text        = { Text("دليل الاستخدام", color = theme.accent, fontFamily = font.family, fontSize = 20.sp, fontWeight = FontWeight.Medium) },
                            leadingIcon = { Icon(Icons.Default.HelpOutline, null, tint = theme.gold, modifier = Modifier.size(22.dp)) },
                            onClick = onUsageGuide, contentPadding = itemPad
                        )
                        DropdownMenuItem(
                            text        = { Text("عن التطبيق",   color = theme.accent, fontFamily = font.family, fontSize = 20.sp, fontWeight = FontWeight.Medium) },
                            leadingIcon = { Icon(Icons.Default.Info,      null, tint = theme.gold, modifier = Modifier.size(22.dp)) },
                            onClick = onAbout, contentPadding = itemPad
                        )
                        DropdownMenuItem(
                            text        = { Text("شارك قراءة اليوم", color = theme.accent, fontFamily = font.family, fontSize = 20.sp, fontWeight = FontWeight.Medium) },
                            leadingIcon = { Icon(Icons.Default.Insights,  null, tint = theme.gold, modifier = Modifier.size(22.dp)) },
                            onClick = onShareDaily, contentPadding = itemPad
                        )
                        DropdownMenuItem(
                            text        = { Text("شارك ورتّل",   color = theme.accent, fontFamily = font.family, fontSize = 20.sp, fontWeight = FontWeight.Medium) },
                            leadingIcon = { Icon(Icons.Default.Share,     null, tint = theme.gold, modifier = Modifier.size(22.dp)) },
                            onClick = onShare, contentPadding = itemPad
                        )
                    }
                }
            }
        }
    }
}
