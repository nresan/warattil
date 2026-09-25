//
//  SearchHighlight.swift
//  Warattil
//
//  Diacritic-aware match-range finder for inline page highlighting after the
//  user taps a search result.
//
//  Ports app/src/main/java/com/warattil/app/ui/SearchHighlight.kt (V3, 2026-05).
//
// =============================================================================
// PROBLEM
// =============================================================================
//  User searches for «الكافرون» (Imla'i — full alef between ك and ف, no
//  diacritics). Mushaf body text is «ٱلۡكَٰفِرُونَ» (Uthmani — alef-wasla,
//  dagger alef, fathas, sukun glyph). We want to paint a gold background
//  behind THE EXACT character range of «ٱلۡكَٰفِرُونَ» on the rendered page
//  — including the embedded diacritics that fall inside the matched region —
//  so the reader sees the word lit up in context.
//
// =============================================================================
// APPROACH
// =============================================================================
//  Walk the original text once, building (a) a normalized form (same fold
//  rules as `QuranRepository.normalizeForSearch` / `normalizeStripAlef`)
//  and (b) a parallel position map: `posMap[i]` = the original-text index
//  of the character that produced position `i` in the normalized form.
//  Stripped characters (diacritics, tatweel) contribute nothing to either.
//  Folded characters (أ → ا, ٰ → ا, etc.) contribute one entry.
//
//  Find normalized matches via `String.range(of:)`, then translate back:
//  for a match at normalized [start, end), the original range is
//  [posMap[start], posMap[end] OR original.length). Using `posMap[end]`
//  rather than `posMap[end-1]+1` means trailing diacritics that fall
//  inside the original word boundary get included in the highlight —
//  visually correct for Arabic where diacritics belong to the letter
//  they sit above/below.
//
// =============================================================================
// DUAL-FORM
// =============================================================================
//  Same Imla'i ambiguity as the search index: dagger alef sometimes
//  represents a long-a written as ا in modern typing (الكافرون) and
//  sometimes one written without the alef (الرحمن). We compute BOTH
//  folded and stripped variants and union the resulting ranges so a
//  query like «الرحمن» highlights inside «ٱلرَّحۡمَٰنِ» correctly.
//
// =============================================================================
// SWIFT NOTES
// =============================================================================
//  • Ranges are returned as `Range<Int>` over the original String's
//    UTF-16-equivalent character offsets (Swift `Character` indices).
//    Because the rendering layer (buildAyahAttributed) operates on
//    `NSAttributedString`, which is UTF-16-indexed, we walk the original
//    text by `unicodeScalars` and emit scalar offsets — these match the
//    NSAttributedString offsets used downstream IF the string contains
//    no characters outside the BMP. Quran text fits this constraint
//    (every Arabic letter + diacritic is BMP), so scalar offset == UTF-16
//    offset. Mirror Android's IntRange semantics by emitting ranges as
//    [start ..< end) over scalar offsets.
//

import Foundation

// =============================================================================
// MARK: - Public API
// =============================================================================

/// Diacritic-aware match ranges for `query` inside `text`. Each returned
/// range is in ORIGINAL text coordinates (start inclusive, end exclusive)
/// over Unicode-scalar offsets, which match `NSAttributedString` UTF-16
/// offsets for BMP-only text (Quranic Arabic qualifies).
///
/// Returns an empty array when no match exists, or when either input is
/// empty. Ranges are sorted, deduplicated, and merged where they overlap.
///
/// The rendering layer (`buildAyahAttributed`) applies a gold background
/// `NSAttributedString` attribute to each range to draw the inline highlight.
internal func findHighlightRanges(text: String, query: String) -> [Range<Int>] {
    if text.isEmpty || query.isEmpty { return [] }
    let needle = normalizeQueryForHighlight(query)
    if needle.isEmpty { return [] }

    // Build both forms (with their position maps) and union the matches.
    let folded   = buildNormalizedWithMap(text, foldDagger: true)
    let stripped = buildNormalizedWithMap(text, foldDagger: false)

    var ranges: [Range<Int>] = []
    collectMatches(
        normalized: folded.normalized,
        posMap:     folded.map,
        needle:     needle,
        originalLen: text.unicodeScalars.count,
        into:       &ranges
    )
    collectMatches(
        normalized: stripped.normalized,
        posMap:     stripped.map,
        needle:     needle,
        originalLen: text.unicodeScalars.count,
        into:       &ranges
    )

    if ranges.isEmpty { return ranges }
    return mergeRanges(ranges)
}

// =============================================================================
// MARK: - Internal helpers
// =============================================================================

private func collectMatches(
    normalized:   String,
    posMap:       [Int],
    needle:       String,
    originalLen:  Int,
    into:         inout [Range<Int>]
) {
    guard !normalized.isEmpty, normalized.count >= needle.count else { return }

    // Walk `normalized` by Character (== Unicode scalar for ASCII/BMP-only
    // arabic content). Convert to a scalar-indexed Array<Character> once so
    // index arithmetic stays O(1) per step.
    let normChars = Array(normalized)
    let needleChars = Array(needle)
    if needleChars.isEmpty { return }

    var idx = 0
    let limit = normChars.count - needleChars.count
    while idx <= limit {
        // Substring match at scalar offset `idx`.
        var matched = true
        for k in 0..<needleChars.count {
            if normChars[idx + k] != needleChars[k] { matched = false; break }
        }
        if matched {
            let origStart = posMap[idx]
            let origEnd: Int = (idx + needleChars.count) < posMap.count
                ? posMap[idx + needleChars.count]
                : originalLen
            if origEnd > origStart {
                into.append(origStart ..< origEnd)
            }
            idx += 1                  // allow overlapping matches (rare for Arabic, cheap)
        } else {
            idx += 1
        }
    }
}

/// Walks `text` producing a normalized form + a parallel position map.
/// `foldDagger == true` folds dagger / subscript alef → ا (matches Imla'i
/// forms with full alef). `false` strips them (matches Imla'i forms
/// without).
private func buildNormalizedWithMap(
    _ text: String,
    foldDagger: Bool
) -> (normalized: String, map: [Int]) {
    var out = String()
    out.reserveCapacity(text.unicodeScalars.count)
    var map = [Int]()
    map.reserveCapacity(text.unicodeScalars.count)

    // Iterate by Unicode scalar — matches the NSAttributedString offset
    // basis used by the renderer. Quran text is BMP-only, so 1 scalar = 1
    // UTF-16 code unit = 1 Character.
    for (i, scalar) in text.unicodeScalars.enumerated() {
        if let rep = normalizeChar(scalar, foldDagger: foldDagger) {
            out.unicodeScalars.append(rep)
            map.append(i)
        }
    }
    return (out, map)
}

/// Single-character normalize. Returns the replacement scalar, or `nil`
/// if the char is dropped entirely. MUST stay in lockstep with
/// `QuranRepository.normalizeForSearch` / `normalizeStripAlef`.
///
/// The rules below mirror `SearchHighlight.kt`'s `normalizeChar` byte-for-byte.
private func normalizeChar(
    _ s: Unicode.Scalar,
    foldDagger: Bool
) -> Unicode.Scalar? {
    let code = s.value
    switch code {
    // Letter folds: Uthmani → Imla'i (alef family)
    case 0x0622, 0x0623, 0x0625, 0x0671:
        return Unicode.Scalar(0x0627)        // ا
    // Dagger alef + subscript alef — fold or strip per `foldDagger`
    case 0x0656, 0x0670:
        return foldDagger ? Unicode.Scalar(0x0627) : nil
    // Alef-maqsura → ya
    case 0x0649:
        return Unicode.Scalar(0x064A)        // ي
    // Tatweel — strip
    case 0x0640:
        return nil
    // Diacritic strips: standard tashkeel + recitation/pause marks
    case 0x064B...0x065F:
        return nil
    case 0x06D6...0x06ED:
        return nil
    default:
        return s
    }
}

/// Same fold rules but without the strip-variant — query is user input,
/// always treated as Imla'i (full alef). In particular, if the user
/// pastes Uthmani text with a dagger alef in their query, it folds to
/// ا exactly like a regular alef would.
private func normalizeQueryForHighlight(_ q: String) -> String {
    var out = String()
    out.reserveCapacity(q.unicodeScalars.count)
    for s in q.unicodeScalars {
        if let rep = normalizeChar(s, foldDagger: true) {
            out.unicodeScalars.append(rep)
        }
    }
    return out
}

/// Sort + merge overlapping/adjacent ranges so the renderer makes one
/// span per visual highlight, not multiple stacked ones.
private func mergeRanges(_ ranges: [Range<Int>]) -> [Range<Int>] {
    if ranges.count <= 1 { return Array(Set(ranges)) }
    let sorted = ranges.sorted { $0.lowerBound < $1.lowerBound }
    var out: [Range<Int>] = []
    var current = sorted[0]
    for i in 1..<sorted.count {
        let r = sorted[i]
        // Adjacent counts as overlap (Android: r.first <= current.last + 1)
        if r.lowerBound <= current.upperBound {
            current = current.lowerBound ..< max(current.upperBound, r.upperBound)
        } else {
            out.append(current)
            current = r
        }
    }
    out.append(current)
    return out
}
