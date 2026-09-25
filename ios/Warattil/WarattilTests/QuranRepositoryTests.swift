//
//  QuranRepositoryTests.swift
//  WarattilTests
//
//  On-device smoke test for the data layer:
//    QuranDatabase (bundle copy + open) → QuranDao → QuranRepository.
//
//  Purpose: lock in that the full read path from quran_v3.db through the
//  monotonic-key range query returns the correct content for known pages.
//  This would catch any of the following regressions in future edits:
//    - Wrong SQLite column names / ordering
//    - Wrong monotonic-key formula
//    - Bundle resource copy failing
//    - MetadataParser and DB drifting apart
//
//  We do NOT test every page here — MetadataParserTests already proves the
//  604-page boundary math via JSON fixture parity. This file is the
//  end-to-end glue test.
//

import XCTest
@testable import Warattil

final class QuranRepositoryTests: XCTestCase {

    private var repo: QuranRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()

        // Reset parser state and reload from the app bundle (which we can reach
        // even from hosted tests — host app = Warattil.app). Using Bundle.main
        // here matches production behaviour exactly.
        MetadataParser.shared.__resetForTesting()
        try MetadataParser.shared.load(bundle: Bundle.main)

        // Open the database. This copies quran_v3.db from the bundle to
        // Documents on the first run; subsequent runs reuse the existing copy.
        try QuranDatabase.shared.open()

        repo = try QuranRepository()
    }

    // =========================================================================
    // Page content — the single most important read path in the app.
    // =========================================================================

    /// Page 1 is all of Al-Fatiha: surah 1, 7 ayahs, starting with "بِسْمِ ٱللَّهِ".
    func testPage1IsAlFatiha() throws {
        let content = try repo.getPageContent(pageNumber: 1)

        XCTAssertEqual(content.pageNumber, 1)
        XCTAssertEqual(content.juzNumber,  1)
        XCTAssertFalse(content.ayahs.isEmpty, "Page 1 must have ayahs")

        // Every ayah on page 1 must be from surah 1.
        for ayah in content.ayahs {
            XCTAssertEqual(ayah.surah, 1, "Page 1 ayah should be from surah 1, got \(String(describing: ayah.surah))")
        }

        // Al-Fatiha has exactly 7 ayahs.
        XCTAssertEqual(content.ayahs.count, 7, "Al-Fatiha has 7 ayahs")

        // Ayah 1 text should begin with the basmala's first word "بِسْمِ".
        let firstAyahText = content.ayahs.first?.text ?? ""
        XCTAssertTrue(
            firstAyahText.hasPrefix("بِسْمِ") || firstAyahText.hasPrefix("بِسۡمِ"),
            "Expected Al-Fatiha ayah 1 to begin with bismi, got: \(firstAyahText.prefix(20))…"
        )
    }

    /// Page 604 is the last page — end of Surah An-Nas (114), 6 ayahs.
    func testPage604IsAnNas() throws {
        let content = try repo.getPageContent(pageNumber: 604)

        XCTAssertEqual(content.pageNumber, 604)
        XCTAssertEqual(content.juzNumber,  30, "Last page must be in Juz 30")

        // An-Nas (surah 114) must appear among the ayahs on the last page.
        let surahsOnPage = Set(content.ayahs.compactMap(\.surah))
        XCTAssertTrue(surahsOnPage.contains(114), "Page 604 must contain surah 114, got \(surahsOnPage)")
    }

    // =========================================================================
    // Paging law — monotonic-key correctness via the DAO.
    //
    // This test is the whole point of the Locked Manifest architecture:
    // prove that a simple BETWEEN range query against monotonic keys
    // returns exactly the ayahs MetadataParser says belong to that page.
    // =========================================================================

    func testMonotonicKeyRangeMatchesPageBoundaries() throws {
        // Pick an interesting page — page 50 is mid-Al-Baqarah, non-trivial.
        let page = 50
        let (startKey, endKey) = MetadataParser.shared.getPageBoundaries(page)

        let content = try repo.getPageContent(pageNumber: page)

        XCTAssertFalse(content.ayahs.isEmpty, "Page \(page) must have ayahs")

        // Every returned ayah's monotonic key must fall inside the declared
        // page boundaries — the DB should not overshoot or undershoot.
        for ayah in content.ayahs {
            guard let key = ayah.monotonicKey else {
                XCTFail("Ayah missing surah/ayah on page \(page): \(ayah)")
                continue
            }
            XCTAssertTrue(
                (startKey...endKey).contains(key),
                "Ayah monotonic key \(key) outside page \(page) range [\(startKey), \(endKey)]"
            )
        }

        // First ayah's key should equal startKey (page boundary alignment).
        if let first = content.ayahs.first?.monotonicKey {
            XCTAssertEqual(first, startKey, "First ayah on page \(page) should be at startKey")
        }
    }

    // =========================================================================
    // Search — proves the diacritic-stripping LIKE query runs without error
    // and returns at least one resolvable SearchResult.
    // =========================================================================

    func testSearchReturnsResultsForCommonWord() throws {
        // "الله" is guaranteed to appear many times. We're not asserting a
        // specific count — just that search runs, returns results, and every
        // hit is a valid Mushaf page in 1…604.
        let results = try repo.searchAyahs(query: "الله")

        XCTAssertFalse(results.isEmpty, "Search for 'الله' must return hits")
        for hit in results {
            XCTAssertTrue(
                (1...604).contains(hit.pageNumber),
                "Search hit out of page range: \(hit.pageNumber)"
            )
            XCTAssertFalse(hit.surahName.isEmpty, "Search hit must have a resolved surah name")
        }
    }

    // =========================================================================
    // Index maps — built lazily, used by TOC / Juz navigation UIs.
    // =========================================================================

    func testSurahStartPagesAreMonotonicallyIncreasing() {
        let map = repo.surahStartPages
        XCTAssertEqual(map.count, 114, "Must have a start page for every surah 1–114")

        // Surah 1 starts on page 1.
        XCTAssertEqual(map[1], 1)

        // Every subsequent surah's start page must be ≥ the previous one.
        for surah in 2...114 {
            guard let cur = map[surah], let prev = map[surah - 1] else {
                XCTFail("Missing surah \(surah) in start-page map")
                continue
            }
            XCTAssertGreaterThanOrEqual(cur, prev, "Surah \(surah) starts before surah \(surah-1)")
            XCTAssertTrue((1...604).contains(cur))
        }
    }

    // =========================================================================
    // QCF per-page glyph layout — introduced 2026-04-20 (quran_v3.db).
    // These tests guard the data shape the MushafPageView renderer relies on.
    // =========================================================================

    func testMushafPage1IsFatiha() throws {
        let page = try XCTUnwrap(try repo.getMushafPage(pageNumber: 1))

        XCTAssertEqual(page.page, 1)
        XCTAssertEqual(page.bodyFontAsset, "QCF_P001.woff2")
        XCTAssertFalse(page.lines.isEmpty)

        // First line must be the Al-Fatiha surah header.
        let first = try XCTUnwrap(page.lines.first)
        XCTAssertEqual(first.type, .surahHeader)
        XCTAssertEqual(first.surahNumber, 1)

        // Every non-header line with words must reference surah 1.
        for line in page.lines where line.type == .text {
            for w in line.words {
                XCTAssertEqual(w.surah, 1, "Page 1 word not in surah 1: \(w)")
            }
        }
    }

    func testMushafPage2HasBasmala() throws {
        let page = try XCTUnwrap(try repo.getMushafPage(pageNumber: 2))
        let types = page.lines.map(\.type)
        XCTAssertTrue(types.contains(.surahHeader))
        XCTAssertTrue(types.contains(.basmala))
        XCTAssertEqual(page.bodyFontAsset, "QCF_P002.woff2")
    }

    func testMushafPage106IsAlMaidaBoundary() throws {
        let page = try XCTUnwrap(try repo.getMushafPage(pageNumber: 106))
        // Page 106 contains the tail of An-Nisa and the head of Al-Maida.
        // The Al-Maida header should appear somewhere in the middle.
        let header = page.lines.first { $0.type == .surahHeader }
        let sn = try XCTUnwrap(header?.surahNumber)
        XCTAssertEqual(sn, 5, "Page 106 header should be for Al-Maida (surah 5)")
    }

    func testMushafWordUthmaniIsClean() throws {
        // Words must never carry the trailing ayah-number marker through to
        // the clean uthmani column — otherwise copy/share would leak digits.
        let page = try XCTUnwrap(try repo.getMushafPage(pageNumber: 1))
        for line in page.lines {
            for w in line.words {
                XCTAssertFalse(
                    w.uthmani.contains("١") || w.uthmani.contains("٢") ||
                    w.uthmani.contains("٣") || w.uthmani.contains("٤") ||
                    w.uthmani.contains("٥") || w.uthmani.contains("٦") ||
                    w.uthmani.contains("٧"),
                    "uthmani leaked an Eastern digit: \(w.uthmani) at \(w.location)"
                )
                XCTAssertFalse(w.uthmani.isEmpty, "empty uthmani at \(w.location)")
            }
        }
    }

    // =========================================================================
    // QCF ayah selection — bridge from rendered PUA glyphs back to clean
    // Unicode for copy / share (task #35, context menu in MushaFPageView).
    //
    // These tests enforce three invariants the data sanity-checker verified
    // across the full DB on 2026-04-20:
    //   • every `line_word` → has a matching `ayah` row (no orphans).
    //   • on any given line, words for the same ayah are CONTIGUOUS
    //     (so our single-pass ayahGroups coalescing is correct).
    //   • per-line ayah count maxes out at 4 — menu size is always bounded.
    // =========================================================================

    func testAyahGroupsOnFatihaLineIsSingleGroup() throws {
        // Page 1, line 3 is Al-Fatiha ayah 2 ("ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَـٰلَمِينَ") —
        // 4 words, all one ayah. The context menu should offer exactly one
        // section for it.
        let page = try XCTUnwrap(try repo.getMushafPage(pageNumber: 1))
        let line3 = try XCTUnwrap(page.lines.first(where: { $0.lineNo == 3 }))
        let groups = line3.ayahGroups

        XCTAssertEqual(groups.count, 1, "Page 1 line 3 should have exactly one ayah")
        XCTAssertEqual(groups.first?.surah, 1)
        XCTAssertEqual(groups.first?.ayah,  2)
        XCTAssertEqual(groups.first?.words.count, 4)
    }

    func testAyahGroupsAreContiguousAcrossWholePage() throws {
        // Page 2 is the opening of Al-Baqara — several short ayahs on each
        // line. Ensures the single-pass grouping doesn't emit duplicate
        // groups (which would mean same (surah,ayah) was split by an
        // intervening ayah on the same line).
        let page = try XCTUnwrap(try repo.getMushafPage(pageNumber: 2))
        for line in page.lines where line.type == .text {
            var seen: Set<String> = []
            for group in line.ayahGroups {
                XCTAssertFalse(
                    seen.contains(group.id),
                    "Page 2 line \(line.lineNo) emitted duplicate ayah group \(group.id) — words not contiguous"
                )
                seen.insert(group.id)
            }
        }
    }

    func testAyahGroupsForSurahBoundaryPage() throws {
        // Page 106 contains the tail of An-Nisa (surah 4) then the head of
        // Al-Maida (surah 5). At least one text line should host words from
        // surah 4 AND surah 5 (the transition line), but the groups should
        // still be contiguous.
        let page = try XCTUnwrap(try repo.getMushafPage(pageNumber: 106))

        let allSurahsOnPage: Set<Int> = Set(
            page.lines.flatMap { $0.words.map(\.surah) }
        )
        XCTAssertTrue(allSurahsOnPage.contains(4))
        XCTAssertTrue(allSurahsOnPage.contains(5))

        // Every group is internally consistent.
        for line in page.lines where line.type == .text {
            for group in line.ayahGroups {
                for w in group.words {
                    XCTAssertEqual(w.surah, group.surah)
                    XCTAssertEqual(w.ayah,  group.ayah)
                }
            }
        }
    }

    func testAyahTextLookupReturnsFullAyahForKnownPair() throws {
        // Full-text path used by Copy / Share. Lookup of (1,1) must return
        // the basmala-form opening of Al-Fatiha; lookup of (114,6) must
        // return the last ayah of An-Nas.
        let opening = try XCTUnwrap(try repo.getAyahText(surah: 1,   ayah: 1))
        XCTAssertTrue(
            opening.hasPrefix("بِسْمِ") || opening.hasPrefix("بِسۡمِ"),
            "Al-Fatiha 1:1 should begin with bismi, got: \(opening.prefix(20))…"
        )

        let annas6 = try XCTUnwrap(try repo.getAyahText(surah: 114, ayah: 6))
        XCTAssertFalse(annas6.isEmpty, "An-Nas 114:6 must be non-empty")
    }

    func testAyahTextLookupReturnsNilForInvalidPair() throws {
        // Surah 115 doesn't exist; repo must return nil, not crash. This is
        // load-bearing: the VM's menu handler will silently skip sharing.
        XCTAssertNil(try repo.getAyahText(surah: 115, ayah: 1))
        // Ayah 10 of Al-Fatiha (which has only 7) also doesn't exist.
        XCTAssertNil(try repo.getAyahText(surah: 1, ayah: 10))
    }

    func testJuzStartPagesAreMonotonicallyIncreasing() {
        let map = repo.juzStartPages
        XCTAssertEqual(map.count, 30, "Must have a start page for every juz 1–30")
        XCTAssertEqual(map[1], 1, "Juz 1 starts on page 1")

        for juz in 2...30 {
            guard let cur = map[juz], let prev = map[juz - 1] else {
                XCTFail("Missing juz \(juz) in start-page map")
                continue
            }
            XCTAssertGreaterThan(cur, prev, "Juz \(juz) must start strictly after juz \(juz-1)")
            XCTAssertTrue((1...604).contains(cur))
        }
    }
}
