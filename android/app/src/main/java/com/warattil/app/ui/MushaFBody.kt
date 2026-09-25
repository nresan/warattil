package com.warattil.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.*
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.warattil.app.core.WarattilConstants
import com.warattil.app.core.WarattilConstants.Mushaf
import com.warattil.app.data.Ayah
import com.warattil.app.data.MetadataParser

// =============================================================================
// Font loading
// =============================================================================

data class QuranFontInfo(val family: FontFamily, val isUthmanic: Boolean)

@Composable
fun rememberQuranFont(): QuranFontInfo {
    val ctx = LocalContext.current
    return remember {
        val id = ctx.resources.getIdentifier(Mushaf.FONT_UTHMANIC, "font", ctx.packageName)
        if (id != 0) QuranFontInfo(FontFamily(Font(id)), true)
        else {
            val fb = ctx.resources.getIdentifier(Mushaf.FONT_FALLBACK, "font", ctx.packageName)
            QuranFontInfo(if (fb != 0) FontFamily(Font(fb)) else FontFamily.Serif, false)
        }
    }
}

// =============================================================================
// Utilities
// =============================================================================

/** Convert any Int to Eastern Arabic digit string (١٢٣ etc.) as a SINGLE unit.
 *  IMPORTANT: pass the complete number — never split digits before calling. */
fun Int.toArabicDigits(): String {
    val e = charArrayOf('٠','١','٢','٣','٤','٥','٦','٧','٨','٩')
    return toString().map { c -> if (c.isDigit()) e[c - '0'] else c }.joinToString("")
}

/** Strip Quranic annotation codepoints U+06D6–U+06ED so the text measurer
 *  sees clean base characters only. */
fun String.stripAnnotations(): String = buildString {
    for (c in this@stripAnnotations) if (c.code !in 0x06D6..0x06ED) append(c)
}

// ── Basmala helpers ──────────────────────────────────────────────────────────
// The canonical Basmala reduced to its 19 base letters (no diacritics, no
// spaces, Alif-wasla normalised to plain Alif).
private const val BASMALA_BASE = "بسماللهالرحمنالرحيم"

/**
 * True if this text begins with the Basmala, robust to diacritics,
 * Quranic annotations, Alif-wasla (U+0671), and TATWEEL stretch chars.
 *
 * Character classes normalised away before comparison (see
 * [isArabicBaseLetter]):
 *   • Tatweel (U+0640) — elongation glyph present in ٱلرَّحْمَـٰنِ
 *   • Harakat (U+064B..U+065F)
 *   • Dagger alef (U+0670)
 *   • Quranic marks (U+0610..U+061A, U+06D6..U+06ED)
 * Alif-wasla (U+0671) is normalised to plain Alif (U+0627).
 */
private fun String.startsWithBasmala(): Boolean {
    val clean = buildString {
        for (c in this@startsWithBasmala) {
            if (!c.isArabicBaseLetter()) continue
            append(if (c == '\u0671') '\u0627' else c)
        }
    }.trim()
    return clean.startsWith(BASMALA_BASE)
}

/** Arabic block, minus every combining mark / annotation / stretch-char.
 *
 *  The DB's Uthmani text contains:
 *    • U+0640 TATWEEL (ـ) — the stylistic elongation character. Appears in
 *      ٱلرَّحْمَـٰنِ between م and ن for visual justification. It carries no
 *      phonetic content and must be ignored for prefix matching.
 *    • U+0670 SUPERSCRIPT ALEF (ٰ) — the dagger alef, combining mark.
 *    • U+064B..U+065F — harakat (fatha, kasra, shadda, sukun…).
 *    • U+0610..U+061A — Arabic marks used in the Quran (small high jeem…).
 *    • U+06D6..U+06ED — Quranic annotation signs.
 *
 *  All of the above get filtered so the clean string is pure phonetic
 *  base letters.
 */
private fun Char.isArabicBaseLetter(): Boolean {
    val code = this.code
    if (code !in 0x0600..0x06FF) return false
    if (code in 0x0610..0x061A) return false   // Arabic marks for Quran
    if (code == 0x0640)         return false   // TATWEEL (ـ) — stretch char
    if (code in 0x064B..0x065F) return false   // harakat
    if (code == 0x0670)         return false   // superscript alef (ٰ)
    if (code in 0x06D6..0x06ED) return false   // Quranic annotations
    return true
}

/**
 * Remove the leading Basmala from an ayah text, keeping all original
 * diacritics on whatever remains. Returns the text unchanged if it does
 * not begin with Basmala.
 *
 * Used for every surah EXCEPT Al-Fatihah and At-Tawbah: the Basmala is
 * rendered as an ornamental banner by SurahBanner, so the raw ayah-1
 * text must not duplicate it.
 */
private fun String.stripBasmalaPrefix(): String {
    val rawIdxOfCleanChar = ArrayList<Int>(length)
    val cleaned           = StringBuilder(length)
    for (i in indices) {
        val c = this[i]
        if (c.isWhitespace()) continue
        if (!c.isArabicBaseLetter()) continue
        cleaned.append(if (c == '\u0671') '\u0627' else c)
        rawIdxOfCleanChar.add(i)
    }
    if (cleaned.length < BASMALA_BASE.length) return this
    if (!cleaned.startsWith(BASMALA_BASE))    return this

    // Cut at the position immediately AFTER the final base letter of the
    // Basmala (the م of الرحيم), then advance past any combining marks /
    // tatweels attached to it — otherwise the kasra sitting on that م
    // survives as an orphaned diacritic (ِ ) at the start of the remainder.
    var cutAt = rawIdxOfCleanChar[BASMALA_BASE.length - 1] + 1
    while (cutAt < length) {
        val c    = this[cutAt]
        val code = c.code
        // Stop as soon as we hit a new base letter, whitespace, or a
        // non-Arabic glyph — everything else is an attached mark we swallow.
        if (c.isArabicBaseLetter())        break
        if (c.isWhitespace())              break
        if (code !in 0x0600..0x06FF)       break
        cutAt++
    }
    return substring(cutAt).trimStart()
}

// =============================================================================
// Internal grouping — one group per Surah present on the page
// =============================================================================

internal data class SurahGroup(val surahIndex: Int, val ayahs: List<Ayah>)

internal fun buildGroups(ayahs: List<Ayah>): List<SurahGroup> = buildList {
    var cur = -1; var batch = mutableListOf<Ayah>()
    ayahs.forEach { a ->
        val s = a.surah ?: return@forEach
        if (s != cur) {
            if (batch.isNotEmpty()) add(SurahGroup(cur, batch.toList()))
            cur = s; batch = mutableListOf()
        }
        batch.add(a)
    }
    if (batch.isNotEmpty() && cur != -1) add(SurahGroup(cur, batch.toList()))
}

/**
 * Ayah list AS IT SHOULD BE DISPLAYED, given the Madinah-standard Basmala
 * rules:
 *
 *   • Al-Fatihah (1)  — unchanged. Basmala IS ayah 1 and stays inline.
 *   • At-Tawbah  (9)  — unchanged. DB already contains no Basmala.
 *   • Every other surah — if the group opens with ayah 1 and its text
 *       prepends the Basmala, strip it. If ayah 1 was JUST the Basmala
 *       (some DBs store it as a pseudo-ayah), drop the row entirely so
 *       the ornamental banner does not duplicate inside the text.
 */
internal fun SurahGroup.displayAyahs(): List<Ayah> {
    val isFatiha = surahIndex == 1
    val isTawbah = surahIndex == Mushaf.SURAH_TAWBAH
    if (isFatiha || isTawbah) return ayahs
    val first = ayahs.firstOrNull() ?: return ayahs
    if (first.ayah != 1) return ayahs
    val raw = first.text?.trim() ?: return ayahs
    if (!raw.startsWithBasmala()) return ayahs
    val stripped = raw.stripBasmalaPrefix()
    return if (stripped.isBlank())
        ayahs.drop(1)
    else
        ayahs.toMutableList().also { it[0] = first.copy(text = stripped) }
}

// =============================================================================
// Adaptive font engine
//
// Binary-search for the largest fontSize (measured in px) where the complete
// page text fits inside the available Column height.  Surah-separator heights
// are subtracted before the fit test so the text block does not collide with
// banners.
// =============================================================================

// ── Font search bounds (portrait only) ───────────────────────────────────────
// Range 22–46 sp covers every realistic Mushaf page layout.
//   • Dense pages (ayah-packed, e.g. middle of al-Baqarah) — converge near 22–26 sp
//   • Normal pages                                         — converge near 28–34 sp
//   • Sparse pages (Fatiha, end-of-surah fragments)        — cap at 46 sp, then
//     vertical-center so short text sits in the middle of the page (Ayah app style)
// Floor lowered 22f → 16f → 12f on 2026-04-27 (Nasser): the binary
// search returns MIN_SP unconditionally when even the smallest tested
// size can't fit — so a too-high floor causes content to clip.  16f
// fixed page 293 (Al-Isra → Al-Kahf transition) but page 50
// (Aal Imran 1-7 + chip visible) still clipped because the body had
// to fit 7 ayahs of dense Mushaf script in ~370dp.  12f gives the
// engine enough shrink room to fit ANY page in the Mushaf even when
// the WirdResumeChip is stealing bottomBar space.  The engine still
// prefers larger sizes — only the few densest pages drop into the
// 12-16 range, and only when the chip is visible.  Simple pages
// stay at 30-40sp.
internal const val MIN_SP          = 12f
internal const val MAX_SP          = 46f

// Opening-spread typography — pages 1 (Al-Fatiha) and 2 (start of Al-Baqarah)
// were designed to use their own font + line-height so each centered line
// holds only 2-4 words, producing the traditional diamond / rounded mushaf-
// opening silhouette you see in Madinah-printed copies and the Golden Quran.
//
//   • OPENING_SPREAD_MAX_SP  — 34sp: small enough that only a few words fit
//       per line. On typical phone widths "ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَٰلَمِينَ" lands
//       on its own line.
//   • OPENING_SPREAD_LINE_H  — 2.0× the font size for an airy, breathable
//       cadence. The tight 1.60× body rhythm crowds lines together and
//       mutes the rounded shape.
//
// ⚠️ CURRENTLY DISABLED. The previous activation caused ayah 5 on page 2
// to clip below the wird bar on a Samsung S22 (live bug in 2.2.0). Root
// cause: `adaptiveFontSp` measures line heights with LINE_H_RATIO (1.60×)
// while the render path was using 2.0× — a ~14sp-per-line underestimate
// that compounded to ~110sp of overflow on the denser of the two pages.
//
// To re-enable correctly, the adaptive engine must be told when it's
// measuring an opening spread so it uses 2.0× in the fit test too. The
// simplest shape is:
//     adaptiveFontSp(..., lineHRatio: Float = LINE_H_RATIO)
// with the PageBody branch passing OPENING_SPREAD_LINE_H on pages 1-2.
// Constants kept below so the next attempt doesn't have to re-derive them.
@Suppress("unused") internal const val OPENING_SPREAD_MAX_SP  = 34f
@Suppress("unused") internal const val OPENING_SPREAD_LINE_H  = 2.0f
internal const val LINE_H_RATIO    = 1.60f    // lineHeight = fontSize × 1.60
internal const val MARKER_RATIO    = 0.875f   // ayah-marker font = body × 0.875
internal const val BASMALA_RATIO   = 0.90f    // ornamental basmala = body × 0.90
private  const val SAFETY          = 0.97f    // +3% headroom for inter-Text padding
private  const val SEARCH_ITERATIONS = 12

// Banner chrome — everything in SurahBanner EXCEPT the ornamental Basmala line.
// Empirical sum of every vertical contribution, with a generous margin for
// Compose's includeFontPadding which adds ascender/descender padding to the
// title Text that a raw-metrics calculation underestimates:
//   outer Column padding (2+2 = 4)
//   + Box padding          (3+3 = 6)
//   + 2 × BannerDivider    (~13dp each = 26)
//   + Title at 26sp Bold   (~39dp rendered line box w/ includeFontPadding)
//   + bottom Spacer        (2)
//   + safety margin        (~13)
//   = 90. Being overly generous here only costs ~1 sp of body font; being
//   under causes the last surah to clip off page 603-style pages.
private const val BANNER_BASE_DP   = 90f

/** Basmala vertical footprint for a given ayah font size.
 *  = top padding 2dp + Text lineHeight (sp × BASMALA_RATIO × 1.40).
 *  The 1.40 multiplier covers the explicit 1.30× lineHeight we set on the
 *  Basmala Text PLUS the first-line ascender + last-line descender padding
 *  Compose adds around the Text composable. */
private fun basmalaStripDp(ayahSp: Float): Float =
    2f + (ayahSp * BASMALA_RATIO * 1.40f)

/** Total banner height (in dp) for a group whose first ayah on this page is 1. */
private fun bannerHeightDp(ayahSp: Float, hasOrnamentalBasmala: Boolean): Float =
    if (hasOrnamentalBasmala) BANNER_BASE_DP + basmalaStripDp(ayahSp)
    else                      BANNER_BASE_DP

internal fun adaptiveFontSp(
    measurer : TextMeasurer,
    groups   : List<SurahGroup>,
    font     : QuranFontInfo,
    availW   : Int,
    availH   : Int,
    density  : Density
): Float {
    // Build ONE annotated string PER group. This mirrors what the renderer
    // actually does — each group is its own AyahBlock (its own Text()) —
    // and crucially captures the per-Text first-line-ascender and last-line-
    // descender vertical padding that Compose adds around every Text.
    //
    // A previous single-string-with-\n approach undercounted that padding by
    // ~one line-height per group boundary, causing dense Juz'30 pages to
    // overflow the bottom even when the measurer reported a "fit".
    val groupTexts = groups.map { g ->
        buildAnnotatedString {
            g.displayAyahs().forEach { a ->
                val t = a.text?.trim()?.stripAnnotations() ?: return@forEach
                val n = a.ayah ?: return@forEach
                append(t)
                append(" ﴿${n.toArabicDigits()}﴾ ")
            }
        }
    }

    // Per-candidate banner footprint — depends on mid sp because the Basmala
    // font now scales with the ayah size. Larger ayahs ⇒ larger Basmala ⇒
    // taller banner ⇒ less room for text. Recompute inside the loop.
    fun sepPxAt(sp: Float): Int = with(density) {
        groups.sumOf { g ->
            if (g.ayahs.firstOrNull()?.ayah == 1) {
                val hasBas = g.surahIndex != 1 && g.surahIndex != Mushaf.SURAH_TAWBAH
                bannerHeightDp(sp, hasBas).dp.roundToPx()
            } else 0
        }
    }

    var lo = MIN_SP; var hi = MAX_SP; var best = MIN_SP
    repeat(SEARCH_ITERATIONS) {
        val mid   = (lo + hi) / 2f
        val textH = ((availH - sepPxAt(mid)).coerceAtLeast(availH / 2) * SAFETY).toInt()
        val style = TextStyle(
            fontSize      = mid.sp,
            lineHeight    = (mid * LINE_H_RATIO).sp,
            fontFamily    = font.family,
            textDirection = TextDirection.Rtl
        )
        // Sum the rendered height of EACH group — captures per-Text padding
        // that a single concatenated measurement would miss.
        val totalTextH = groupTexts.sumOf { gt ->
            if (gt.isEmpty()) 0
            else measurer.measure(
                gt, style,
                constraints = Constraints.fixedWidth(availW)
            ).size.height
        }
        if (totalTextH <= textH) { best = mid; lo = mid } else hi = mid
    }
    return best.coerceIn(MIN_SP, MAX_SP)
}

// =============================================================================
// Page content — state router
// =============================================================================

@Composable
fun PageContent(
    state           : PageUiState,
    font            : QuranFontInfo,
    theme           : ThemeColors,
    isLandscape     : Boolean             = false,
    // ── Long-press selection ─────────────────────────────────────────────
    // Set of ayah row-IDs to render with the selection highlight.  Caller
    // builds this set at the screen level from the (anchor, endAyah)
    // range so a single ayah selection is just `{ anchor.id }` and a
    // multi-ayah +/- range is the IDs of every ayah in the range.
    // Empty set = nothing highlighted.  Default empty for callers that
    // don't want the long-press action bar (e.g. preview screens).
    selectedAyahIds : Set<Int>            = emptySet(),
    // ── Search highlight (task #64, 2026-04-27) ──────────────────────────
    // Non-null when the user has tapped a search result and we want
    // every occurrence of the query painted with a gold background
    // inline in the page text.  Persists across page swipes (so the
    // user can scan adjacent pages for the same word) and clears on
    // explicit `viewModel.clearSearch()`.  Empty/null = no highlight.
    // Diacritic-aware matching: the query «الكافرون» highlights
    // «ٱلۡكَٰفِرُونَ» on the rendered page including the embedded
    // diacritics — see findHighlightRanges in SearchHighlight.kt.
    searchHighlight : String?             = null,
    onAyahLongPress : ((Ayah) -> Unit)?   = null
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(theme.background)
            .padding(horizontal = 16.dp)
    ) {
        when (state) {
            is PageUiState.Loading -> CircularProgressIndicator(
                modifier = Modifier.align(Alignment.Center), color = theme.accent
            )
            is PageUiState.Error   -> Text(
                "خطأ: ${state.message}", color = theme.progressLow,
                modifier = Modifier.align(Alignment.Center), textAlign = TextAlign.Center
            )
            is PageUiState.Success -> PageBody(
                content         = state.content,
                font            = font,
                theme           = theme,
                isLandscape     = isLandscape,
                selectedAyahIds = selectedAyahIds,
                searchHighlight = searchHighlight,
                onAyahLongPress = onAyahLongPress
            )
        }
    }
}

// =============================================================================
// Page body — adaptive font fills the available vertical space
// =============================================================================

@Composable
private fun PageBody(
    content         : com.warattil.app.data.PageContent,
    font            : QuranFontInfo,
    theme           : ThemeColors,
    isLandscape     : Boolean,
    selectedAyahIds : Set<Int>          = emptySet(),
    searchHighlight : String?           = null,
    onAyahLongPress : ((Ayah) -> Unit)? = null
) {
    val groups   = remember(content.pageNumber) { buildGroups(content.ayahs) }
    val measurer = rememberTextMeasurer()
    val density  = LocalDensity.current

    BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
        // Opening-spread treatment (pages 1 & 2) is DISABLED in this release.
        //
        // Why: the previous implementation capped the body font at
        // OPENING_SPREAD_MAX_SP (34sp) with OPENING_SPREAD_LINE_H (2.0×) and
        // centered alignment, aiming for the Madinah-Mushaf rounded
        // silhouette. In practice the adaptive engine measures lines with
        // LINE_H_RATIO = 1.60× regardless of what the render path uses, so
        // pages 1-2 rendered at 2.0× were ~14sp taller *per line* than the
        // engine expected. On page 2 (8 ayahs, dense) the cumulative ~110sp
        // overflow pushed ayah 5 below the viewport — clipped behind the
        // wird-progress bar on a Samsung S22.
        //
        // The right fix is to have the engine's measurement pass use the
        // same lineHRatio the render pass will use (i.e. pass an
        // `isOpeningSpread` flag into adaptiveFontSp so it measures with
        // 2.0× on those two pages). Deferred to a later release — until
        // then, pages 1 and 2 use the same typography as every other page.
        //
        // Target constants kept in the file (OPENING_SPREAD_MAX_SP / _LINE_H)
        // so the next attempt doesn't have to re-derive them from iOS.

        val rawSp: Float = if (isLandscape) {
            // Elderly landscape — locked at 48 sp (invariant)
            48f
        } else {
            remember(content.pageNumber, constraints.maxWidth, constraints.maxHeight) {
                adaptiveFontSp(
                    measurer, groups, font,
                    constraints.maxWidth, constraints.maxHeight, density
                )
            }
        }

        val sp: Float = rawSp
        val lineH = if (isLandscape) 72f else sp * LINE_H_RATIO

        if (isLandscape) {
            // Landscape: LazyColumn for smooth elderly-mode scrolling
            androidx.compose.foundation.lazy.LazyColumn(
                modifier = Modifier.fillMaxSize()
            ) {
                groups.forEach { group ->
                    val showBanner = group.ayahs.firstOrNull()?.ayah == 1
                    if (showBanner) {
                        item { SurahBanner(group, font, theme, isLandscape, ayahSp = sp) }
                    }
                    val display = group.displayAyahs()
                    if (display.isNotEmpty()) {
                        item {
                            AyahBlock(
                                ayahs           = display,
                                sp              = sp,
                                lineH           = lineH,
                                font            = font,
                                theme           = theme,
                                selectedAyahIds = selectedAyahIds,
                                searchHighlight = searchHighlight,
                                onAyahLongPress = onAyahLongPress
                            )
                        }
                    }
                }
            }
        } else {
            // Portrait: weight-spacer centering.
            //   Sparse page  — top & bottom spacers split the slack equally,
            //                  content sits centered vertically (Ayah-app look).
            //   Dense page   — spacers collapse to 0, content starts at y=0 and
            //                  any adaptive-engine overshoot is clipped at the
            //                  bottom only (never at the top).
            //
            // This replaces Arrangement.Center, which could push children past
            // the top edge when total content slightly exceeded the container.
            Column(
                modifier = Modifier.fillMaxSize().clipToBounds()
            ) {
                Spacer(Modifier.weight(1f))
                groups.forEach { group ->
                    val showBanner = group.ayahs.firstOrNull()?.ayah == 1
                    if (showBanner) {
                        SurahBanner(group, font, theme, isLandscape, ayahSp = sp)
                    }
                    val display = group.displayAyahs()
                    if (display.isNotEmpty()) {
                        AyahBlock(
                            ayahs           = display,
                            sp              = sp,
                            lineH           = lineH,
                            font            = font,
                            theme           = theme,
                            selectedAyahIds = selectedAyahIds,
                            searchHighlight = searchHighlight,
                            onAyahLongPress = onAyahLongPress
                        )
                    }
                }
                Spacer(Modifier.weight(1f))
            }
        }
    }
}

// =============================================================================
// Ayah text block
// =============================================================================

@Composable
private fun AyahBlock(
    ayahs    : List<Ayah>,
    sp       : Float,
    lineH    : Float,
    font     : QuranFontInfo,
    theme    : ThemeColors,
    // Opening-spread treatment: pages 1 (Al-Fatiha) and 2 (start of Al-Baqarah)
    // use centered alignment instead of justified. Each line finds its natural
    // width and the paragraph's right/left edges form the traditional rounded
    // "mushaf opening" silhouette. Only these two pages — every other page
    // stays fully justified as a proper Mushaf should.
    centered        : Boolean             = false,
    // ── Long-press selection (task #2) ───────────────────────────────────
    // Set of ayah row-IDs to highlight.  When a row's id is in the set,
    // its text and marker spans render with a soft accent-tinted
    // background — the primary visual feedback for the action bar.
    // Empty set = no ayah on this block is selected (the common case).
    // Non-empty set with a single id = single-ayah selection.  Non-empty
    // set with multiple ids = +/- range selection (extended via the
    // AyahActionBar's chips).  Caller (MushaFScreen) builds the set
    // from the (anchor, endAyah) tuple by filtering pageAyahs.
    selectedAyahIds : Set<Int>            = emptySet(),
    // ── Search highlight (task #64, 2026-04-27) ──────────────────────────
    // Non-null when the user has tapped a search result and we want
    // every occurrence of the query painted with a gold background
    // inline.  Diacritic-aware matching handles Uthmani vs Imla'i
    // orthography — see findHighlightRanges in SearchHighlight.kt.
    searchHighlight : String?             = null,
    // When non-null, long-presses on the block are routed to this callback
    // with the Ayah whose character range contains the touched offset. The
    // block itself stays stateless — selection lives in the caller.
    onAyahLongPress : ((Ayah) -> Unit)?   = null
) {
    // ── Annotated string + parallel range map ────────────────────────────
    // Each ayah contributes a contiguous [rangeStart, length) span in the
    // final AnnotatedString (text + trailing " ﴿N﴾ " marker). The
    // `ranges` list records (start, endExclusive, Ayah) so we can map a
    // touched character offset back to its ayah in O(n) — fast enough
    // for the ~15 ayahs a typical Mushaf page carries.
    //
    // Re-memoed on (ayahs, sp, selection, theme, font) so: switching pages
    // rebuilds, re-running the font engine rebuilds, toggling selection
    // rebuilds the spans to repaint the highlight, AND cycling the theme
    // rebuilds with the new SpanStyle colors.  Bug 2026-04-25: omitting
    // `theme` here meant Heritage → Dark left the body text using
    // Heritage's charcoal #1A1A1A SpanStyle on Dark's #121212 background
    // — invisible.  The Basmala (rendered separately, not via remember)
    // updated correctly, which made the bug surface-specific.
    val (annotated, ranges) = remember(ayahs, sp, selectedAyahIds, searchHighlight, theme, font) {
        val rs = mutableListOf<Triple<Int, Int, Ayah>>()
        // Search-highlight tint: warm gold, brighter than the long-press
        // selection (theme.accent at 0.14f) so the two read as distinct
        // states even when both fire on the same ayah.
        val highlightBg = WarattilConstants.Hifz.HIFZ_GOLD.copy(alpha = 0.32f)
        val built = buildAnnotatedString {
            ayahs.forEach { a ->
                val t = a.text?.trim()?.stripAnnotations() ?: return@forEach
                val n = a.ayah ?: return@forEach
                val isSelected = a.id != null && a.id in selectedAyahIds
                val bg = if (isSelected) theme.accent.copy(alpha = 0.14f)
                         else            Color.Unspecified
                val rangeStart = length

                // Compute search-highlight ranges in this ayah (in
                // ORIGINAL text coordinates, post-stripAnnotations).
                // Empty list when no highlight active or no match —
                // the common no-highlight path appends the whole text
                // in one withStyle block, same as before this feature.
                val hlRanges = if (!searchHighlight.isNullOrBlank())
                    findHighlightRanges(t, searchHighlight) else emptyList()

                if (hlRanges.isEmpty()) {
                    withStyle(SpanStyle(color = theme.text, fontFamily = font.family, background = bg)) {
                        append(t)
                    }
                } else {
                    // Walk the text in [non-highlight | highlight | …]
                    // alternating chunks.  Each chunk gets its own
                    // SpanStyle so the gold background paints exactly
                    // the matched character ranges (including embedded
                    // diacritics that fall inside the original word).
                    var cursor = 0
                    for (range in hlRanges) {
                        val s = range.first.coerceIn(0, t.length)
                        val e = (range.last + 1).coerceIn(0, t.length)
                        if (s > cursor) {
                            withStyle(SpanStyle(color = theme.text, fontFamily = font.family, background = bg)) {
                                append(t.substring(cursor, s))
                            }
                        }
                        if (e > s) {
                            withStyle(SpanStyle(
                                color      = theme.text,
                                fontFamily = font.family,
                                background = highlightBg
                            )) {
                                append(t.substring(s, e))
                            }
                        }
                        cursor = e
                    }
                    if (cursor < t.length) {
                        withStyle(SpanStyle(color = theme.text, fontFamily = font.family, background = bg)) {
                            append(t.substring(cursor))
                        }
                    }
                }

                val markerSp = sp * MARKER_RATIO
                withStyle(SpanStyle(color = theme.gold, fontSize = markerSp.sp, background = bg)) {
                    append(" ﴿")
                }
                withStyle(SpanStyle(
                    color      = theme.accent,
                    fontSize   = markerSp.sp,
                    fontWeight = FontWeight.Bold,
                    background = bg
                )) {
                    append(n.toArabicDigits())
                }
                withStyle(SpanStyle(color = theme.gold, fontSize = markerSp.sp, background = bg)) {
                    append("﴾ ")
                }

                rs.add(Triple(rangeStart, length, a))
            }
        }
        built to rs.toList()
    }

    // ── Long-press hit-testing ───────────────────────────────────────────
    // `TextLayoutResult.getOffsetForPosition(Offset)` maps touch coords to
    // a character offset; we then scan `ranges` for the matching ayah.
    // The layout result is captured via `onTextLayout` and read inside
    // the gesture lambda — it's mutable state, so a new frame always
    // sees the latest layout even if Compose recomposed the Text.
    //
    // `pointerInput(ranges)` resets the gesture detector whenever the
    // range map changes (new page, new selection). Without a key the
    // detector would hold a stale closure to the old ranges list.
    val layoutResult = remember { mutableStateOf<TextLayoutResult?>(null) }
    Text(
        text     = annotated,
        modifier = Modifier
            .fillMaxWidth()
            .then(
                if (onAyahLongPress != null) {
                    Modifier.pointerInput(ranges) {
                        detectTapGestures(onLongPress = { pos ->
                            val lr = layoutResult.value ?: return@detectTapGestures
                            val char = lr.getOffsetForPosition(pos)
                            val hit  = ranges.firstOrNull { char in it.first until it.second }
                            if (hit != null) onAyahLongPress(hit.third)
                        })
                    }
                } else Modifier
            ),
        onTextLayout = { layoutResult.value = it },
        overflow     = TextOverflow.Clip,
        style        = TextStyle(
            fontSize      = sp.sp,
            lineHeight    = lineH.sp,
            textAlign     = if (centered) TextAlign.Center else TextAlign.Justify,
            textDirection = TextDirection.Rtl,
            fontFamily    = font.family
        )
    )
}

// =============================================================================
// Surah banner — scholarly Madinah-standard Basmala rules
// =============================================================================
//
//   ┌─────────── Rule ─────────────────────────────────────────────────────┐
//   │                                                                      │
//   │  Al-Fatihah (surah 1)                                                │
//   │     • Banner: name plate ONLY — no ornamental Basmala.               │
//   │     • The Basmala is ayah 1 and is rendered INLINE by AyahBlock      │
//   │       with its own ayah marker ﴿١﴾.                                 │
//   │                                                                      │
//   │  At-Tawbah (surah 9)                                                 │
//   │     • Banner: name plate ONLY — no Basmala anywhere.                 │
//   │                                                                      │
//   │  Every other surah                                                   │
//   │     • Banner: name plate + ornamental Basmala below.                 │
//   │     • Any Basmala prefix stored in ayah 1 by the DB is stripped      │
//   │       upstream in SurahGroup.displayAyahs() so it never appears      │
//   │       inline.                                                        │
//   │                                                                      │
//   └──────────────────────────────────────────────────────────────────────┘
//
// =============================================================================

@Composable
internal fun SurahBanner(
    group      : SurahGroup,
    font       : QuranFontInfo,
    theme      : ThemeColors,
    isLandscape: Boolean,
    ayahSp     : Float = 22f    // adaptive body font size (for Basmala scale)
) {
    val surahIndex = group.surahIndex
    val name = remember(surahIndex) { MetadataParser.getSuraName(surahIndex) }

    val isFatiha = surahIndex == 1
    val isTawbah = surahIndex == Mushaf.SURAH_TAWBAH
    val showOrnamentalBasmala = !isFatiha && !isTawbah

    // Title outweighs body text so the surah name reads as the clear header:
    // 26sp portrait / 22sp landscape. Larger values are mirrored in
    // BANNER_BASE_DP so the adaptive font engine deducts enough vertical room.
    val titleSize = if (isLandscape) 22.sp else 26.sp

    // Basmala tracks the adaptive ayah size at 90%, giving clear visual
    // hierarchy without feeling undersized next to the body text. The dp
    // footprint is mirrored in adaptiveFontSp.bannerHeightDp() so the font
    // search deducts the right amount of vertical space.
    val basmalaSizeSp = ayahSp * BASMALA_RATIO

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp),          // ↓ was 6.dp
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        // Name-plate box with Deep Gold border — tighter vertical padding.
        Box(
            modifier = Modifier
                .fillMaxWidth(0.90f)
                .border(width = 1.2.dp, color = theme.gold, shape = RoundedCornerShape(4.dp))
                .background(theme.bannerBg, RoundedCornerShape(4.dp))
                .padding(horizontal = 12.dp, vertical = 3.dp),   // ↓ was 8.dp
            contentAlignment = Alignment.Center
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(0.dp) // ↓ was 2.dp
            ) {
                BannerDivider(theme)
                Text(
                    text       = "سُورَةُ $name",
                    color      = theme.gold,
                    fontSize   = titleSize,
                    fontWeight = FontWeight.Bold,
                    fontFamily = font.family,
                    textAlign  = TextAlign.Center,
                    style      = TextStyle(textDirection = TextDirection.Rtl)
                )
                BannerDivider(theme)
            }
        }

        if (showOrnamentalBasmala) {
            Text(
                text       = Mushaf.BASMALA,
                color      = theme.text.copy(alpha = 0.85f),
                fontSize   = basmalaSizeSp.sp,
                // Explicit lineHeight — prevents font-metric drift vs the
                // adaptive engine's estimate in basmalaStripDp().
                lineHeight = (basmalaSizeSp * 1.30f).sp,
                fontWeight = FontWeight.Bold,
                fontFamily = font.family,
                textAlign  = TextAlign.Center,
                style      = TextStyle(textDirection = TextDirection.Rtl),
                modifier   = Modifier.padding(top = 2.dp)        // ↓ was 4.dp
            )
        }
        Spacer(Modifier.height(2.dp))                            // ↓ was 4.dp
    }
}

@Composable
private fun BannerDivider(theme: ThemeColors) {
    Row(
        modifier          = Modifier.fillMaxWidth(0.80f),
        verticalAlignment = Alignment.CenterVertically
    ) {
        HorizontalDivider(
            modifier  = Modifier.weight(1f),
            thickness = 0.8.dp,
            color     = theme.gold.copy(alpha = 0.5f)
        )
        Text("  ✦  ", color = theme.gold, fontSize = 9.sp)
        HorizontalDivider(
            modifier  = Modifier.weight(1f),
            thickness = 0.8.dp,
            color     = theme.gold.copy(alpha = 0.5f)
        )
    }
}