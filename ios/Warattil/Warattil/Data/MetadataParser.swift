//
//  MetadataParser.swift
//  Warattil
//
//  Ports app/src/main/java/com/warattil/app/data/MetadataParser.kt to Swift.
//  The parsing logic and the output shape must match Android 1:1 — every
//  call to getPageBoundaries / getJuzBoundaries / getSuraName must return
//  the same value on both platforms for the same input.
//
//  Why this matters: the Android app uses these boundaries to run
//  `WHERE monotonic_key BETWEEN startKey AND endKey` against quran_v2.db.
//  iOS uses the same DB and the same formula. Drift here = off-by-one bugs
//  on specific pages, which are the hardest kind of bug to notice.
//

import Foundation

public final class MetadataParser: NSObject {

    // -------------------------------------------------------------------------
    // Singleton — matches the `object MetadataParser` pattern in Kotlin.
    // -------------------------------------------------------------------------
    public static let shared = MetadataParser()

    // Parse state
    private(set) public var suras: [SuraMetadata] = []
    private(set) public var pages: [PageMetadata] = []
    private(set) public var juzs:  [JuzMetadata]  = []

    // Lookup maps built at load time for O(1) access. The Kotlin reference
    // uses linear .find() scans on every call — cheap for n ≤ 604 but
    // unnecessary. Behaviour is identical.
    private var suraByIndex: [Int: SuraMetadata] = [:]
    private var pageByIndex: [Int: PageMetadata] = [:]
    private var juzByIndex:  [Int: JuzMetadata]  = [:]

    private var loaded = false

    // Temporary collector used during SAX parsing
    private var collectingSuras: [SuraMetadata] = []
    private var collectingPages: [PageMetadata] = []
    private var collectingJuzs:  [JuzMetadata]  = []

    // -------------------------------------------------------------------------
    // Load & parse. Idempotent — second call is a no-op, matching Kotlin.
    // Throws on I/O or XML error so the caller fails loud.
    // -------------------------------------------------------------------------
    public func load(bundle: Bundle = .main, resourceName: String = "quran_metadata", resourceExtension: String = "xml") throws {
        if loaded { return }

        guard let url = bundle.url(forResource: resourceName, withExtension: resourceExtension) else {
            throw MetadataError.resourceMissing("\(resourceName).\(resourceExtension) not found in bundle")
        }

        let data = try Data(contentsOf: url)
        try loadFromData(data)
    }

    /// Exposed for unit tests — lets us feed the XML directly without a
    /// bundle lookup.
    public func loadFromData(_ data: Data) throws {
        if loaded { return }

        collectingSuras.removeAll()
        collectingPages.removeAll()
        collectingJuzs.removeAll()

        let parser = XMLParser(data: data)
        parser.delegate = self

        guard parser.parse() else {
            if let err = parser.parserError {
                throw MetadataError.xmlParse(err.localizedDescription)
            }
            throw MetadataError.xmlParse("Unknown XML parser failure")
        }

        // Promote collectors to the live store + build index maps.
        suras = collectingSuras
        pages = collectingPages
        juzs  = collectingJuzs

        suraByIndex = Dictionary(uniqueKeysWithValues: suras.map { ($0.index, $0) })
        pageByIndex = Dictionary(uniqueKeysWithValues: pages.map { ($0.index, $0) })
        juzByIndex  = Dictionary(uniqueKeysWithValues: juzs.map  { ($0.index, $0) })

        loaded = true
    }

    /// Test-only: wipe state so a fresh load can be performed.
    public func __resetForTesting() {
        suras.removeAll()
        pages.removeAll()
        juzs.removeAll()
        suraByIndex.removeAll()
        pageByIndex.removeAll()
        juzByIndex.removeAll()
        loaded = false
    }

    // -------------------------------------------------------------------------
    // Public API — exact port of the Kotlin surface.
    //
    // A page's boundary is the monotonic range of ayah keys that page covers.
    // A page must end exactly one ayah before the next page starts. If the
    // next page starts at ayah 1 of a new surah, the current page ends at the
    // last ayah of the previous surah. The final page ends at 114:6 — the
    // last ayah of An-Nas.
    // -------------------------------------------------------------------------

    public func getPageBoundaries(_ pageIndex: Int) -> (startKey: Int, endKey: Int) {
        guard let currentPage = pageByIndex[pageIndex] else {
            return (0, 0)
        }
        let nextPage = pageByIndex[pageIndex + 1]

        let startKey = currentPage.sura * 10000 + currentPage.aya
        let endKey: Int

        if let next = nextPage {
            if next.aya > 1 {
                endKey = next.sura * 10000 + (next.aya - 1)
            } else {
                // Next page begins at ayah 1 of a new surah → this page ends at
                // the last ayah of the previous surah.
                let prevSuraIndex = next.sura - 1
                if let prevSura = suraByIndex[prevSuraIndex] {
                    endKey = prevSuraIndex * 10000 + prevSura.ayas
                } else {
                    endKey = startKey  // fallback — matches Kotlin
                }
            }
        } else {
            // Last page of the Mushaf ends at Sura 114, Aya 6 (An-Nas).
            endKey = 114 * 10000 + 6
        }

        return (startKey, endKey)
    }

    public func getJuzBoundaries(_ juzIndex: Int) -> (startKey: Int, endKey: Int) {
        guard let currentJuz = juzByIndex[juzIndex] else {
            return (0, 0)
        }
        let nextJuz = juzByIndex[juzIndex + 1]

        let startKey = currentJuz.sura * 10000 + currentJuz.aya
        let endKey: Int

        if let next = nextJuz {
            if next.aya > 1 {
                endKey = next.sura * 10000 + (next.aya - 1)
            } else {
                let prevSuraIndex = next.sura - 1
                if let prevSura = suraByIndex[prevSuraIndex] {
                    endKey = prevSuraIndex * 10000 + prevSura.ayas
                } else {
                    endKey = startKey
                }
            }
        } else {
            endKey = 114 * 10000 + 6
        }

        return (startKey, endKey)
    }

    public func getSuraName(_ index: Int) -> String {
        suraByIndex[index]?.name ?? ""
    }

    public func getSuras() -> [SuraMetadata] {
        suras
    }

    // =========================================================================
    // Phase 1 Hifz — ayah-key enumeration helpers
    //
    // Mirror the Android MetadataParser extension methods that drive every
    // V3 Hifz surface:
    //   • page / surah / juz density ratios (heatmap + tier stats)
    //   • bulk picker tile highlight state (isOn iff all unit keys ∈ set)
    //   • flower placement (one per fully-memorized juz, on its last page)
    //   • togglePage / toggleSurah / toggleJuz batch mutations
    //
    // Ayah keys follow the monotonic-key formula  sura * 10000 + aya  and
    // are returned as Int64 to match Hifz.ayahKey / the UserDefaults
    // string-set wire format.  Order within the returned array is reading
    // order (low → high surah, low → high aya) which is the same order
    // Android returns; callers that rely on ordering (e.g. juz-last-page
    // probes) get identical results cross-platform.
    // =========================================================================

    /// All ayah keys on [page].  Walks (sura, aya) pairs across any surah
    /// boundary the page straddles, using each surah's `ayas` count to know
    /// when to roll over to the next surah.  Returns [] if metadata is not
    /// loaded yet or the page index is out of range.
    public func getPageAyahKeys(_ page: Int) -> [Int64] {
        guard pageByIndex[page] != nil else { return [] }
        let (startKey, endKey) = getPageBoundaries(page)
        return expandAyahKeys(startKey: startKey, endKey: endKey)
    }

    /// All ayah keys in [surah] (1..114).  Trivial: 1 .. surah.ayas, all
    /// prefixed with the surah index.
    public func getSurahAyahKeys(_ surah: Int) -> [Int64] {
        guard let s = suraByIndex[surah] else { return [] }
        var out = [Int64]()
        out.reserveCapacity(s.ayas)
        for a in 1...s.ayas {
            out.append(Int64(surah) * 10000 + Int64(a))
        }
        return out
    }

    /// All ayah keys in [juz] (1..30).  Uses the same boundary-walk as
    /// getPageAyahKeys — a juz routinely straddles several surahs.
    public func getJuzAyahKeys(_ juz: Int) -> [Int64] {
        guard juzByIndex[juz] != nil else { return [] }
        let (startKey, endKey) = getJuzBoundaries(juz)
        return expandAyahKeys(startKey: startKey, endKey: endKey)
    }

    /// Last page (1..604) of [juz] — the page whose ayah range CONTAINS the
    /// juz's final ayah.  Used to place the juz-completion flower glyph.
    /// A scan ascending through pages: the last page whose startKey ≤ the
    /// juz's endKey is the page containing the final ayah of that juz.
    /// Returns 0 if metadata is not loaded or the juz index is invalid.
    public func getJuzLastPage(_ juz: Int) -> Int {
        guard juzByIndex[juz] != nil else { return 0 }
        let (_, endKey) = getJuzBoundaries(juz)
        if endKey == 0 { return 0 }
        var lastMatch = 0
        // pages are loaded in ascending order; pageByIndex lookup is O(1).
        for p in 1...WarattilConstants.Mushaf.totalPages {
            guard let pm = pageByIndex[p] else { continue }
            let pageStartKey = pm.sura * 10000 + pm.aya
            if pageStartKey <= endKey {
                lastMatch = p
            } else {
                break   // pages are monotonically increasing — done
            }
        }
        return lastMatch
    }

    /// Shared boundary-walker used by getPageAyahKeys and getJuzAyahKeys.
    /// Expands the monotonic [startKey, endKey] range into an ordered list
    /// of ayah keys, correctly rolling over surah boundaries.  Pre-sizes
    /// the output array based on an estimate so short pages don't thrash
    /// the heap.
    private func expandAyahKeys(startKey: Int, endKey: Int) -> [Int64] {
        if startKey == 0 || endKey == 0 { return [] }
        let startSura = startKey / 10000
        let startAya  = startKey % 10000
        let endSura   = endKey   / 10000
        let endAya    = endKey   % 10000
        var out = [Int64]()
        out.reserveCapacity(max(8, endKey - startKey + 1))

        if startSura == endSura {
            if startAya <= endAya {
                for a in startAya...endAya {
                    out.append(Int64(startSura) * 10000 + Int64(a))
                }
            }
            return out
        }

        // Multi-surah range: [startSura:startAya .. startSura.ayas], then
        // any full middle suras, then [endSura:1 .. endSura:endAya].
        if let s = suraByIndex[startSura], startAya <= s.ayas {
            for a in startAya...s.ayas {
                out.append(Int64(startSura) * 10000 + Int64(a))
            }
        }
        if startSura + 1 <= endSura - 1 {
            for sNum in (startSura + 1)...(endSura - 1) {
                guard let s = suraByIndex[sNum] else { continue }
                for a in 1...s.ayas {
                    out.append(Int64(sNum) * 10000 + Int64(a))
                }
            }
        }
        if endAya >= 1 {
            for a in 1...endAya {
                out.append(Int64(endSura) * 10000 + Int64(a))
            }
        }
        return out
    }
}

// =============================================================================
// XMLParserDelegate — SAX-style handling matching the Kotlin XmlPullParser.
// =============================================================================

extension MetadataParser: XMLParserDelegate {

    public func parser(_ parser: XMLParser,
                       didStartElement elementName: String,
                       namespaceURI: String?,
                       qualifiedName qName: String?,
                       attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "sura":
            guard let indexStr = attributeDict["index"],
                  let name = attributeDict["name"],
                  let ayasStr = attributeDict["ayas"],
                  let startStr = attributeDict["start"],
                  let index = Int(indexStr),
                  let ayas = Int(ayasStr),
                  let start = Int(startStr) else { return }
            collectingSuras.append(
                SuraMetadata(index: index, name: name, ayas: ayas, start: start)
            )

        case "page":
            guard let indexStr = attributeDict["index"],
                  let suraStr = attributeDict["sura"],
                  let ayaStr = attributeDict["aya"],
                  let index = Int(indexStr),
                  let sura = Int(suraStr),
                  let aya = Int(ayaStr) else { return }
            collectingPages.append(
                PageMetadata(index: index, sura: sura, aya: aya)
            )

        case "juz":
            guard let indexStr = attributeDict["index"],
                  let suraStr = attributeDict["sura"],
                  let ayaStr = attributeDict["aya"],
                  let index = Int(indexStr),
                  let sura = Int(suraStr),
                  let aya = Int(ayaStr) else { return }
            collectingJuzs.append(
                JuzMetadata(index: index, sura: sura, aya: aya)
            )

        default:
            break
        }
    }
}

public enum MetadataError: Error, Equatable {
    case resourceMissing(String)
    case xmlParse(String)
}
