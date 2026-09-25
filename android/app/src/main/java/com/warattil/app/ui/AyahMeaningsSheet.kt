package com.warattil.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.warattil.app.R
import com.warattil.app.core.WarattilConstants.Hifz
import com.warattil.app.data.GhareebEntry
import com.warattil.app.data.GhareebLookup
import com.warattil.app.data.MetadataParser
import com.warattil.app.data.TafseerLookup
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// =============================================================================
// AyahMeaningsSheet — vertical secondary sheet for an ayah's reading aids.
//
// Opened from the AyahActionBar's "📖" book icon — that pill stays scoped
// to the currently selected ayah, so this sheet always corresponds to
// exactly one ayah.
//
// Two tabs (RTL — right-most is shown first):
//
//   1. معاني الكلمات  (default — right side)
//        KFGQPC «الميسر في غريب القرآن» — rare-word dictionary keyed by
//        ayah.  Roughly ~5,000 ayat have entries; the rest are "plain"
//        and show the empty-state.
//
//   2. التفسير الميسر  (left side, secondary)
//        KFGQPC «التفسير الميسر» — the canonical condensed Sunni tafseer
//        produced by King Fahd Complex.  Plain explanatory prose that
//        often inlines short Quran quotations marked up in the source
//        with `<span class="aya">…</span>`.  We render those quoted
//        runs gold-tinted + bold so the Quran fragments visually
//        distinguish themselves from the scholarly gloss — the same
//        approach Golden Quran takes.
//
// Tab order rationale (per Nasser 2026-04-27): users typically tap 📖
// to ask "what does THIS WORD mean?" — a quick scan of one or two
// rare-word glosses.  Reading the full tafseer is the rarer mode.
// So Ghareeb is the default landing tab, Tafseer is one swipe away
// for the times the reader wants the broader explanation.
//
// Earlier iterations (2026-04-25) included «قريباً» placeholders for
// English / أسباب النزول / إعراب; those were removed per the non-catalog
// principle.  The two tabs we ship are real shipping content.
//
// Loading model: each tab loads its own asset asynchronously on first
// open.  Singletons (TafseerLookup + GhareebLookup) cache after the
// first parse, so subsequent ayah taps are instant.
// =============================================================================

@OptIn(ExperimentalMaterial3Api::class, androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
fun AyahMeaningsSheet(
    suraNumber : Int,
    ayaNumber  : Int,
    font       : QuranFontInfo,
    theme      : ThemeColors,
    onDismiss  : () -> Unit
) {
    val context = LocalContext.current
    val scope   = rememberCoroutineScope()

    // ── Prose font ────────────────────────────────────────────────────────
    // KFGQPC's tafseer source itself documents:
    //   "The Tafseer text in Uthman Taha Naskh font and the Aya in Uthmanic
    //    Hafs font."
    // Rendering the prose in font.family (Hafs Uthmanic) makes commas «،» and
    // periods «.» display as decorative dot-circles — the Mushaf font's
    // glyphs for those code points are stylised for Quran typesetting, not
    // running prose.  Amiri is a classical Naskh that renders standard
    // Arabic punctuation cleanly; we already bundle it for chrome text
    // elsewhere in the app, and using it here matches KFGQPC's design
    // intent (a Naskh face for prose, Hafs for inline Quran fragments).
    val proseFont = remember(context) { FontFamily(Font(R.font.amiri_regular)) }

    // ── Async lookups — kicked off in parallel so the user lands on tab 0
    //    (Tafseer) without waiting for the Ghareeb parse, and switching
    //    to tab 1 finds the data already loaded.
    var tafseerText by remember(suraNumber, ayaNumber) {
        mutableStateOf<String?>(null)   // null → loading
    }
    var ghareebEntries by remember(suraNumber, ayaNumber) {
        mutableStateOf<List<GhareebEntry>?>(null)
    }
    LaunchedEffect(suraNumber, ayaNumber) {
        val t = withContext(Dispatchers.IO) {
            TafseerLookup.textFor(context, suraNumber, ayaNumber)
        }
        tafseerText = t ?: ""
    }
    LaunchedEffect(suraNumber, ayaNumber) {
        val g = withContext(Dispatchers.IO) {
            GhareebLookup.entriesFor(context, suraNumber, ayaNumber)
        }
        ghareebEntries = g
    }

    val surahName = remember(suraNumber) { MetadataParser.getSuraName(suraNumber) }

    // Tab 0 = Ghareeb (default — right-most tab in RTL, the user's
    // most common reason for tapping 📖), tab 1 = Tafseer (left side,
    // one swipe away when the reader wants the broader explanation).
    val pagerState = rememberPagerState(initialPage = 0, pageCount = { 2 })

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor   = theme.background
    ) {
        CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
            Column(
                modifier = Modifier.fillMaxWidth()
            ) {
                // ── Header ───────────────────────────────────────────────────
                Row(
                    modifier              = Modifier
                        .fillMaxWidth()
                        .padding(top = 4.dp, bottom = 12.dp, start = 16.dp, end = 16.dp),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment     = Alignment.CenterVertically
                ) {
                    Text(
                        text       = "سورة $surahName ﴿${ayaNumber.toArabicDigits()}﴾",
                        color      = Hifz.HIFZ_GOLD,
                        fontSize   = 17.sp,
                        fontWeight = FontWeight.Bold,
                        fontFamily = font.family,
                        textAlign  = TextAlign.Center,
                        style      = TextStyle(textDirection = TextDirection.Rtl)
                    )
                }

                HorizontalDivider(color = theme.gold.copy(alpha = 0.30f))

                // ── Tab strip ────────────────────────────────────────────────
                //   Two tabs, gold-underlined for the active one.  Custom
                //   strip (not Material3 TabRow) because TabRow's defaults
                //   bleed the wrong colors and don't honor RTL ordering
                //   intuitively for two tabs.
                MeaningsTabStrip(
                    selectedTab = pagerState.currentPage,
                    onTabSelected = { idx ->
                        scope.launch { pagerState.animateScrollToPage(idx) }
                    },
                    font  = font,
                    theme = theme
                )

                HorizontalDivider(color = theme.gold.copy(alpha = 0.18f))

                // ── Pager ────────────────────────────────────────────────────
                //   Both tabs are bounded-height so a long tafseer or a
                //   long ghareeb list scrolls inside the sheet rather than
                //   pushing the tab strip off-screen.
                HorizontalPager(
                    state    = pagerState,
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = 240.dp, max = 480.dp)
                ) { page ->
                    when (page) {
                        0 -> GhareebTab(
                            entries   = ghareebEntries,
                            font      = font,
                            proseFont = proseFont,
                            theme     = theme
                        )
                        1 -> TafseerTab(
                            text      = tafseerText,
                            font      = font,
                            proseFont = proseFont,
                            theme     = theme
                        )
                    }
                }

                Spacer(Modifier.height(20.dp))
            }
        }
    }
}

// =============================================================================
// Tab strip — custom 2-tab horizontal selector, RTL aware.
//
// Implements the visual pattern Golden Quran uses: two equal-width tabs,
// label centered, active tab underlined in gold and rendered in the
// accent color, inactive tabs in muted body color.  Smaller and quieter
// than Material3's default TabRow, which is overkill for 2 tabs and
// imports its own LinearProgressIndicator-style indicator we don't need.
// =============================================================================

@Composable
private fun MeaningsTabStrip(
    selectedTab : Int,
    onTabSelected: (Int) -> Unit,
    font  : QuranFontInfo,
    theme : ThemeColors
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
    ) {
        // RTL: the FIRST TabPill in this Row appears on the RIGHT.  We
        // render Ghareeb first (right side, default tab 0) and Tafseer
        // second (left side, tab 1) — see file-header rationale.
        TabPill(
            label    = "معاني الكلمات",
            selected = selectedTab == 0,
            onClick  = { onTabSelected(0) },
            font     = font,
            theme    = theme,
            modifier = Modifier.weight(1f)
        )
        TabPill(
            label    = "التفسير الميسر",
            selected = selectedTab == 1,
            onClick  = { onTabSelected(1) },
            font     = font,
            theme    = theme,
            modifier = Modifier.weight(1f)
        )
    }
}

@Composable
private fun TabPill(
    label    : String,
    selected : Boolean,
    onClick  : () -> Unit,
    font     : QuranFontInfo,
    theme    : ThemeColors,
    modifier : Modifier = Modifier
) {
    Column(
        modifier              = modifier
            .clickable(onClick = onClick)
            .padding(vertical = 12.dp),
        horizontalAlignment   = Alignment.CenterHorizontally,
        verticalArrangement   = Arrangement.spacedBy(6.dp)
    ) {
        Text(
            text       = label,
            color      = if (selected) Hifz.HIFZ_GOLD else theme.text.copy(alpha = 0.55f),
            fontSize   = 14.sp,
            fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium,
            fontFamily = font.family,
            textAlign  = TextAlign.Center,
            style      = TextStyle(textDirection = TextDirection.Rtl)
        )
        // Active-tab underline — full-width gold hairline; inactive tabs
        // get a transparent placeholder so the row height doesn't jump
        // when selection changes.
        Box(
            modifier = Modifier
                .fillMaxWidth(0.5f)
                .height(2.dp)
                .background(
                    color = if (selected) Hifz.HIFZ_GOLD else theme.gold.copy(alpha = 0f),
                    shape = RoundedCornerShape(1.dp)
                )
        )
    }
}

// =============================================================================
// Tafseer tab — renders the mixed-font tafseer prose.
//
// The KFGQPC source embeds <span class="aya">…</span> around quoted Quran
// fragments.  We walk the text for those tags and emit an AnnotatedString
// where the quoted runs use a slightly larger gold-tinted style and the
// surrounding prose uses the regular body color.  Both runs share the
// same fontFamily — there's no font swap, just colour + weight + size —
// because the active body font already renders both Quran and prose
// glyphs (Hafs Uthmanic v2.0 covers everything in the source).
// =============================================================================

@Composable
private fun TafseerTab(
    text      : String?,
    font      : QuranFontInfo,
    proseFont : FontFamily,
    theme     : ThemeColors
) {
    when {
        text == null -> {
            // Loading
            Box(
                modifier         = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text       = "جاري التحميل…",
                    color      = theme.text.copy(alpha = 0.5f),
                    fontSize   = 13.sp,
                    fontFamily = proseFont
                )
            }
        }
        text.isBlank() -> {
            Box(
                modifier         = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text       = "لا يوجد تفسير لهذه الآية",
                    color      = theme.text.copy(alpha = 0.5f),
                    fontSize   = 13.sp,
                    fontFamily = proseFont,
                    style      = TextStyle(textDirection = TextDirection.Rtl)
                )
            }
        }
        else -> {
            // Use a vertical-scroll Column rather than LazyColumn — the
            // tafseer is ONE block of prose with inline annotations, so
            // a LazyColumn with a single item adds layout overhead with
            // no virtualisation benefit.
            //
            // Prose font is Amiri (Naskh) — see proseFont definition for
            // why.  The inline Quran-quote spans use the active body font
            // (Uthmani Hafs) so quoted ayah fragments still look like
            // Quran while the surrounding scholarly prose reads cleanly.
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp, vertical = 12.dp)
            ) {
                Text(
                    text       = buildTafseerAttributed(text, font.family),
                    color      = theme.text,
                    fontSize   = 17.sp,
                    fontFamily = proseFont,
                    lineHeight = 26.sp,
                    style      = TextStyle(
                        textDirection = TextDirection.Rtl,
                        textAlign     = TextAlign.Justify
                    ),
                    modifier   = Modifier.fillMaxWidth()
                )
                Spacer(Modifier.height(8.dp))
            }
        }
    }
}

/**
 * Walks the KFGQPC tafseer source string and emits an AnnotatedString that
 * renders inlined Quran fragments (wrapped in `<span class="aya">…</span>`)
 * in a gold-tinted style at a slightly larger size, while the surrounding
 * prose uses the normal body color.
 *
 * The matcher is intentionally lenient on quote style ("aya" vs 'aya') —
 * different KFGQPC distributions have used both — and tolerates whitespace
 * around the attribute.  Anything that doesn't match falls through as plain
 * prose, so a malformed source string degrades gracefully rather than
 * dropping content.
 */
private val TAFSEER_SPAN_RX = Regex(
    pattern = """<span\s+class=['"]aya['"]\s*>(.*?)</span>""",
    options = setOf(RegexOption.DOT_MATCHES_ALL)
)

internal fun buildTafseerAttributed(
    text: String,
    quranFont: FontFamily
): AnnotatedString =
    buildAnnotatedString {
        var cursor = 0
        TAFSEER_SPAN_RX.findAll(text).forEach { match ->
            // Append the prose run BEFORE this match (no inline style — the
            // outer Text supplies the prose font + colour)
            if (match.range.first > cursor) {
                append(text.substring(cursor, match.range.first))
            }
            // Append the quoted Quran fragment in the highlighted style.
            // We force the Hafs Uthmanic font on the quote span so the
            // glyphs match the Mushaf body the reader is looking at —
            // the surrounding prose stays in Amiri.
            val inner = match.groupValues[1]
            withStyle(
                SpanStyle(
                    color      = Hifz.HIFZ_GOLD,
                    fontWeight = FontWeight.SemiBold,
                    fontFamily = quranFont
                )
            ) {
                append(inner)
            }
            cursor = match.range.last + 1
        }
        // Append any remaining prose tail
        if (cursor < text.length) {
            append(text.substring(cursor))
        }
    }

// =============================================================================
// Ghareeb tab — lifted unchanged from the original single-section sheet.
//
//   • null  → loading (initial frame)
//   • empty → "لا توجد كلمات غريبة في هذه الآية"
//   • populated → ordered list of (phrase, meaning) cards
// =============================================================================

@Composable
private fun GhareebTab(
    entries   : List<GhareebEntry>?,
    font      : QuranFontInfo,
    proseFont : FontFamily,
    theme     : ThemeColors
) {
    when {
        entries == null -> {
            Box(
                modifier         = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text       = "جاري التحميل…",
                    color      = theme.text.copy(alpha = 0.5f),
                    fontSize   = 13.sp,
                    fontFamily = proseFont
                )
            }
        }
        entries.isEmpty() -> {
            Box(
                modifier         = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text       = "لا توجد كلمات غريبة في هذه الآية",
                    color      = theme.text.copy(alpha = 0.5f),
                    fontSize   = 13.sp,
                    fontFamily = proseFont,
                    style      = TextStyle(textDirection = TextDirection.Rtl)
                )
            }
        }
        else -> {
            LazyColumn(
                modifier            = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
                contentPadding      = PaddingValues(vertical = 12.dp)
            ) {
                items(entries) { entry ->
                    MeaningCard(entry, font, proseFont, theme)
                }
            }
        }
    }
}

@Composable
private fun MeaningCard(
    entry     : GhareebEntry,
    font      : QuranFontInfo,
    proseFont : FontFamily,
    theme     : ThemeColors
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(
                color = Hifz.HIFZ_GOLD.copy(alpha = 0.05f),
                shape = RoundedCornerShape(10.dp)
            )
            .border(
                width = 0.6.dp,
                color = Hifz.HIFZ_GOLD.copy(alpha = 0.30f),
                shape = RoundedCornerShape(10.dp)
            )
            .padding(horizontal = 12.dp, vertical = 10.dp)
    ) {
        // The Quranic phrase — Uthmani body font so it visually matches
        // the same glyphs the reader is looking at on the Mushaf page.
        Text(
            text       = "﴿${entry.phrase}﴾",
            color      = Hifz.HIFZ_GOLD,
            fontSize   = 17.sp,
            fontWeight = FontWeight.Bold,
            fontFamily = font.family,
            style      = TextStyle(textDirection = TextDirection.Rtl)
        )
        Spacer(Modifier.height(4.dp))
        // The meaning — Naskh prose font (Amiri) so commas «،» and
        // periods «.» render as proper punctuation rather than as
        // Mushaf-style decorative dot-circles.  Slightly larger
        // (14sp → 15sp) for elder-friendly legibility.
        Text(
            text       = entry.meaning,
            color      = theme.text,
            fontSize   = 15.sp,
            fontFamily = proseFont,
            lineHeight = 23.sp,
            style      = TextStyle(textDirection = TextDirection.Rtl)
        )
    }
}
