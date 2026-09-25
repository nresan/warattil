package com.warattil.app.ui

// =============================================================================
// SearchHighlight — diacritic-aware match-range finder for inline page
// highlighting after the user taps a search result.
//
// PROBLEM
// -------
// User searches for «الكافرون» (Imla'i — full alef between ك and ف, no
// diacritics).  Mushaf body text is «ٱلۡكَٰفِرُونَ» (Uthmani — alef-wasla,
// dagger alef, fathas, sukun glyph).  We want to paint a gold background
// behind THE EXACT character range of «ٱلۡكَٰفِرُونَ» on the rendered
// page — including the embedded diacritics that fall inside the matched
// region — so the reader sees the word lit up in context.
//
// APPROACH
// --------
// Walk the original text once, building (a) a normalized form (same fold
// rules as QuranRepository.normalizeForSearch / normalizeStripAlef) and
// (b) a parallel position map: `posMap[i]` = the original-text index of
// the character that produced position `i` in the normalized form.
// Stripped characters (diacritics, tatweel) contribute nothing to either.
// Folded characters (أ → ا, ٰ → ا, etc.) contribute one entry.
//
// Find normalized matches via [String.indexOf], then translate back:
// for a match at normalized [start, end), the original range is
// [posMap[start], posMap[end] OR original.length).  Using posMap[end]
// rather than posMap[end-1]+1 means trailing diacritics that fall
// inside the original word boundary get included in the highlight —
// visually correct for Arabic where diacritics belong to the letter
// they sit above/below.
//
// DUAL-FORM
// ---------
// Same Imla'i ambiguity as the search index: dagger alef sometimes
// represents a long-a written as ا in modern typing (الكافرون) and
// sometimes one written without the alef (الرحمن).  We compute BOTH
// folded and stripped variants and union the resulting ranges so a
// query like «الرحمن» highlights inside «ٱلرَّحۡمَٰنِ» correctly.
// =============================================================================

/**
 * Diacritic-aware match ranges for [query] inside [text].  Each returned
 * range is in ORIGINAL text coordinates (start inclusive, end exclusive).
 * Returns an empty list when no match exists, or when either input is
 * empty.  The rendering layer applies a SpanStyle background to each
 * range to draw the inline highlight.
 *
 * Ranges are sorted, deduplicated, and merged where they overlap.
 */
internal fun findHighlightRanges(text: String, query: String): List<IntRange> {
    if (text.isEmpty() || query.isEmpty()) return emptyList()
    val needle = normalizeQueryForHighlight(query)
    if (needle.isEmpty()) return emptyList()

    // Build both forms (with their position maps) and union the matches.
    val folded   = buildNormalizedWithMap(text, foldDagger = true)
    val stripped = buildNormalizedWithMap(text, foldDagger = false)

    val ranges = mutableListOf<IntRange>()
    collectMatches(folded.first,   folded.second,   needle, text.length, into = ranges)
    collectMatches(stripped.first, stripped.second, needle, text.length, into = ranges)

    if (ranges.isEmpty()) return ranges
    return mergeRanges(ranges)
}

private fun collectMatches(
    normalized   : String,
    posMap       : IntArray,
    needle       : String,
    originalLen  : Int,
    into         : MutableList<IntRange>
) {
    var idx = 0
    while (idx <= normalized.length - needle.length) {
        val pos = normalized.indexOf(needle, idx)
        if (pos < 0) break
        val origStart = posMap[pos]
        val origEnd   = if (pos + needle.length < posMap.size) posMap[pos + needle.length]
                        else originalLen
        if (origEnd > origStart) {
            into.add(origStart until origEnd)
        }
        idx = pos + 1   // allow overlapping matches (rare for Arabic words but cheap)
    }
}

/**
 * Walk [text] producing a normalized form + a parallel position map.
 * `foldDagger = true` folds dagger / subscript alef → ا (matches Imla'i
 * forms with full alef).  `false` strips them (matches Imla'i forms
 * without).
 */
private fun buildNormalizedWithMap(text: String, foldDagger: Boolean): Pair<String, IntArray> {
    val out = StringBuilder(text.length)
    val map = IntArray(text.length)   // upper bound — every original char produces ≤ 1 normalized char
    var mapIdx = 0

    for ((i, c) in text.withIndex()) {
        val rep = normalizeChar(c, foldDagger)
        if (rep != null) {
            out.append(rep)
            map[mapIdx++] = i
        }
    }
    return out.toString() to map.copyOf(mapIdx)
}

/**
 * Single-char normalize.  Returns the replacement char (1 char or null
 * if the char is dropped entirely).  MUST stay in lockstep with
 * QuranRepository.normalizeForSearch / normalizeStripAlef.
 */
private fun normalizeChar(c: Char, foldDagger: Boolean): Char? = when (c.code) {
    // Letter folds: Uthmani → Imla'i
    0x0622, 0x0623, 0x0625, 0x0671 -> 'ا'
    0x0656, 0x0670 -> if (foldDagger) 'ا' else null
    0x0649          -> 'ي'
    0x0640          -> null
    // Diacritic strips
    in 0x064B..0x065F -> null
    in 0x06D6..0x06ED -> null
    else            -> c
}

/** Same fold rules but without the strip-variant — query is user input,
 *  always treated as Imla'i (full alef).  In particular, if the user
 *  pastes Uthmani text with a dagger alef in their query, it folds to
 *  ا exactly like a regular alef would. */
private fun normalizeQueryForHighlight(q: String): String {
    val out = StringBuilder(q.length)
    for (c in q) {
        val rep = normalizeChar(c, foldDagger = true) ?: continue
        out.append(rep)
    }
    return out.toString()
}

/** Sort + merge overlapping/adjacent ranges so the renderer makes one
 *  span per visual highlight, not multiple stacked ones. */
private fun mergeRanges(ranges: List<IntRange>): List<IntRange> {
    if (ranges.size <= 1) return ranges.distinct()
    val sorted = ranges.sortedBy { it.first }
    val out = mutableListOf<IntRange>()
    var current = sorted[0]
    for (i in 1 until sorted.size) {
        val r = sorted[i]
        if (r.first <= current.last + 1) {
            current = current.first..maxOf(current.last, r.last)
        } else {
            out.add(current)
            current = r
        }
    }
    out.add(current)
    return out
}
