//
//  MushafPage.swift
//  Warattil
//
//  Domain model for a single rendered Mushaf page under the QCF per-page
//  glyph-font rendering path (introduced 2026-04-20 to match Golden Quran /
//  quran.com's pixel-identical block layout).
//
//  Data source: `page_font`, `page_line`, and `line_word` tables in
//  `quran_v3.db`, populated offline by tools/qcf/build_qcf_db.py.
//
//  The renderer draws each line by:
//    1. Looking up the line's `fontAsset` PostScript name (already registered
//       at launch by FontRegistrar).
//    2. Feeding `glyphText` through UILabel/Text with that font.
//  The PUA glyphs inside `glyphText` are meaningless outside the QCF fonts,
//  so we also keep the clean Uthmani Unicode in `MushafWord.uthmani` for
//  selection, copy, share, search, and bookmarks.
//

import Foundation

// =============================================================================
// MARK: Line type
// =============================================================================

/// Three mutually-exclusive shapes a Mushaf line can take.
enum MushafLineType: String, Equatable {
    /// Ornamental surah header (e.g. "سورة البقرة"). Rendered as a framed
    /// banner with plain Arabic text, not from the QCF fonts.
    case surahHeader = "surah-header"

    /// The basmala line that precedes ayah 1 of every surah except
    /// Al-Fatiha and At-Tawbah. Rendered from QCF_BSML.
    case basmala

    /// A regular 15-line body row of Quranic text, rendered from QCF_P###.
    case text
}

// =============================================================================
// MARK: Line
// =============================================================================

/// One rendered line on a Mushaf page.
///
/// For `surahHeader` — `surahNumber` / `surahText` are populated and the caller
/// should draw a decorative frame (glyphText is nil).
///
/// For `basmala` — `glyphText` is the three-glyph PUA sequence "ﭑﭒﭓ" and
/// `fontAsset` is `QCF_BSML`.
///
/// For `text` — `glyphText` is the per-word PUA sequence joined by spaces and
/// `fontAsset` is `QCF_P{page:03d}`. `words` holds the parallel Uthmani map.
struct MushafLine: Equatable, Identifiable {
    let page:        Int
    let lineNo:      Int
    let type:        MushafLineType

    /// PUA glyph string (for `basmala` and `text`). Nil for `surahHeader`.
    let glyphText:   String?

    /// PostScript name of the font that renders `glyphText`. Nil for
    /// `surahHeader`.
    let fontAsset:   String?

    /// 1…114, only for `surahHeader`.
    let surahNumber: Int?

    /// Plain Arabic surah title (e.g. "سورة البقرة"), only for `surahHeader`.
    let surahText:   String?

    /// "S:A-S:A" (e.g. "2:1-2:2"), only for `text`.
    let verseRange:  String?

    /// Per-word map, only populated for `text` lines.
    let words:       [MushafWord]

    /// Identifier for SwiftUI ForEach — unique within a page.
    var id: Int { lineNo }
}

// =============================================================================
// MARK: Word
// =============================================================================

/// A single word inside a `text` line. `location` is the
/// canonical "surah:ayah:word" triple (e.g. "2:1:3").
struct MushafWord: Equatable {
    let page:       Int
    let lineNo:     Int
    let pos:        Int      // 1-based within the line
    let location:   String
    let surah:      Int
    let ayah:       Int
    let wordIndex:  Int
    let glyphPua:   String   // QPC-V1 glyph
    let glyphPuaV2: String   // QPC-V2 glyph (kept for later v2 opt-in)
    let uthmani:    String   // clean Uthmani, no ayah marker
}

// =============================================================================
// MARK: Page
// =============================================================================

/// The fully-assembled page the renderer draws. A page typically has
/// 15 lines (Madinah standard); opening pages 1 and 2 are shorter.
struct MushafPage: Equatable {
    /// 1…604
    let page:      Int

    /// PostScript name of the per-page body font (`QCF_P###`). Provided here
    /// for convenience so the renderer can register it / sanity-check once
    /// per page without iterating lines.
    let bodyFontAsset: String

    /// Lines in display order (1…N from top of page).
    let lines:     [MushafLine]
}

// =============================================================================
// MARK: Ayah grouping — the bridge from rendered glyphs back to clean Unicode
//
// The renderer draws per-word PUA glyphs, but selection / copy / share MUST
// use `MushafWord.uthmani` (clean Uthmani, no ayah marker). To drive a
// context menu at the ayah level we need to know which ayahs appear on each
// line, in reading order. Usually 1–3 ayahs per line.
// =============================================================================

/// A contiguous run of `MushafWord`s on a single line that belong to the same
/// ayah. Identified by "surah:ayah" so SwiftUI `ForEach` can key on it.
struct MushafAyahGroup: Equatable, Identifiable {
    let surah: Int
    let ayah:  Int
    let words: [MushafWord]

    /// Stable identifier — unique per ayah on a line (and a line never
    /// contains the same ayah twice non-contiguously in practice, but even
    /// if it did, `ForEach` would still render distinct rows).
    var id: String { "\(surah):\(ayah)" }
}

extension MushafLine {
    /// Returns the distinct ayahs that appear on this line, in reading order.
    ///
    /// Empty for `surahHeader` / `basmala` — those lines have no per-word map.
    /// For `text` lines, adjacent words with the same (surah, ayah) are
    /// coalesced into one group. In the Uthmani script the whole-ayah marker
    /// `﴿N﴾` naturally falls inside the ayah it closes, so this grouping
    /// remains contiguous and word-ordered.
    var ayahGroups: [MushafAyahGroup] {
        guard type == .text else { return [] }
        var groups: [MushafAyahGroup] = []
        for w in words {
            if let last = groups.last,
               last.surah == w.surah, last.ayah == w.ayah {
                // Extend the trailing group.
                groups[groups.count - 1] = MushafAyahGroup(
                    surah: last.surah,
                    ayah:  last.ayah,
                    words: last.words + [w]
                )
            } else {
                groups.append(MushafAyahGroup(
                    surah: w.surah,
                    ayah:  w.ayah,
                    words: [w]
                ))
            }
        }
        return groups
    }
}
