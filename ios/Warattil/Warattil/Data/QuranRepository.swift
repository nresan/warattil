//
//
//  QuranRepository.swift
//  Warattil
//
//  Ports app/src/main/java/com/warattil/app/data/QuranRepository.kt to Swift.
//
//  PAGING LAW (non-negotiable invariant, preserved from Android):
//    Page boundaries are derived EXCLUSIVELY from MetadataParser.
//    The database `page` column is NEVER used for boundary determination.
//    Range queries use monotonic key: sura * 10000 + aya.
//
//  Threading model:
//    - All DAO calls are serialised on QuranDatabase.shared.queue.
//    - Public API is expressed as `throws` sync methods AND `async throws`
//      wrappers. Android returns Flow<T>; on iOS we will wrap these in
//      @Published properties at the ViewModel layer once that's ported.
//

import Foundation

// =============================================================================
// Result types — direct ports of the Kotlin data classes.
// =============================================================================

struct PageContent: Equatable, Hashable, Sendable {
    let pageNumber: Int
    let ayahs:      [Ayah]
    let surahName:  String
    let juzNumber:  Int
}

/// A single search hit, fully resolved to a Mushaf page number.
///
/// The page is determined via [MetadataParser] (monotonic key law), NOT the
/// database `page` column.
struct SearchResult: Equatable, Hashable, Sendable {
    let pageNumber:  Int
    let surahNumber: Int
    let surahName:   String
    let ayahNumber:  Int
    let text:        String
}

// =============================================================================
// Repository
// =============================================================================

final class QuranRepository {

    private let dao: QuranDao
    private let queue: DispatchQueue

    /// Construct with an open DAO. In production use:
    ///     try QuranDatabase.shared.open()
    ///     let repo = try QuranRepository()
    ///
    /// The test-friendly convenience initialiser wires directly to
    /// `QuranDatabase.shared`.
    init() throws {
        self.dao   = try QuranDatabase.shared.quranDao()
        self.queue = QuranDatabase.shared.queue
    }

    /// Test-only injection point — pass a DAO backed by a fixture DB.
    init(dao: QuranDao, queue: DispatchQueue) {
        self.dao   = dao
        self.queue = queue
    }

    // -------------------------------------------------------------------------
    // Index maps — built ONCE lazily from MetadataParser (fast, in-memory).
    //
    // Kotlin uses `by lazy`. Swift's closest match is a `lazy var` inside the
    // class; however `lazy var` can't be accessed from a `let self`, so we
    // emulate it with a backing private var + computed property.
    // -------------------------------------------------------------------------

    private var _surahStartPages: [Int: Int]?
    private var _juzStartPages:   [Int: Int]?

    /// Maps surah index (1–114) → the first Mushaf page that surah appears on.
    /// Computed by scanning all 604 pages for the monotonic key of ayah 1 of
    /// each surah. O(604 × 114) MetadataParser lookups on first access, cached.
    var surahStartPages: [Int: Int] {
        if let cached = _surahStartPages { return cached }
        var map: [Int: Int] = [:]
        for surah in 1...114 {
            let firstKey = surah * 10000 + 1
            map[surah] = findPageForKey(firstKey)
        }
        _surahStartPages = map
        return map
    }

    /// Maps juz number (1–30) → the first Mushaf page of that Juz.
    var juzStartPages: [Int: Int] {
        if let cached = _juzStartPages { return cached }
        var map: [Int: Int] = [:]
        for juz in 1...30 {
            let (juzStartKey, _) = MetadataParser.shared.getJuzBoundaries(juz)
            map[juz] = findPageForKey(juzStartKey)
        }
        _juzStartPages = map
        return map
    }

    // -------------------------------------------------------------------------
    // Public API — Page Content
    // -------------------------------------------------------------------------

    /// Fetches the full content for a given Mushaf `pageNumber` (1-indexed).
    ///
    /// Precondition: `pageNumber` in 1...604. Violations trap with
    /// `preconditionFailure`, matching Kotlin's `require { }`.
    func getPageContent(pageNumber: Int) throws -> PageContent {
        precondition(
            (1...WarattilConstants.Mushaf.totalPages).contains(pageNumber),
            "Invalid Mushaf page: \(pageNumber). Must be in range 1–604."
        )
        return try queue.sync { try _getPageContentOnQueue(pageNumber: pageNumber) }
    }

    /// Async variant for use from SwiftUI / ViewModels.
    ///
    /// IMPORTANT: calls the on-queue helper directly from `queue.async` —
    /// NEVER re-enters `queue.sync`. Re-entering a serial GCD queue is a
    /// detected deadlock on Apple platforms and traps with EXC_BREAKPOINT.
    func getPageContent(pageNumber: Int) async throws -> PageContent {
        precondition(
            (1...WarattilConstants.Mushaf.totalPages).contains(pageNumber),
            "Invalid Mushaf page: \(pageNumber). Must be in range 1–604."
        )
        return try await withCheckedThrowingContinuation { cont in
            queue.async {
                do    { cont.resume(returning: try self._getPageContentOnQueue(pageNumber: pageNumber)) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    /// Inner worker — assumes the caller is already executing on `queue`.
    /// Must NOT wrap with `queue.sync` (would reentrantly deadlock when
    /// invoked from the async variant's `queue.async` dispatch).
    private func _getPageContentOnQueue(pageNumber: Int) throws -> PageContent {
        let (startKey, endKey) = MetadataParser.shared.getPageBoundaries(pageNumber)
        let ayahs     = try dao.getAyahsByMonotonicRange(startKey: startKey, endKey: endKey)
        let surahName = MetadataParser.shared.getSuraName(ayahs.first?.surah ?? 1)
        let juzNumber = resolveJuzForPage(pageNumber)

        return PageContent(
            pageNumber: pageNumber,
            ayahs:      ayahs,
            surahName:  surahName,
            juzNumber:  juzNumber
        )
    }

    // -------------------------------------------------------------------------
    // Public API — QCF Page Rendering
    //
    // Feeds MushafPageView the per-page QCF glyph layout (page_font / page_line /
    // line_word tables in quran_v3.db). Page boundaries are still governed by
    // MetadataParser — this path only provides the visual rendering data.
    // -------------------------------------------------------------------------

    /// Blocking fetch of the QCF layout for a page. Falls back to `nil` if the
    /// page hasn't been imported (not expected for 1…604 in a shipped DB).
    func getMushafPage(pageNumber: Int) throws -> MushafPage? {
        precondition(
            (1...WarattilConstants.Mushaf.totalPages).contains(pageNumber),
            "Invalid Mushaf page: \(pageNumber). Must be in range 1–604."
        )
        return try queue.sync { try dao.getMushafPage(page: pageNumber) }
    }

    /// Async variant — same reentrancy rules as `getPageContent(pageNumber:) async`.
    func getMushafPage(pageNumber: Int) async throws -> MushafPage? {
        precondition(
            (1...WarattilConstants.Mushaf.totalPages).contains(pageNumber),
            "Invalid Mushaf page: \(pageNumber). Must be in range 1–604."
        )
        return try await withCheckedThrowingContinuation { cont in
            queue.async {
                do    { cont.resume(returning: try self.dao.getMushafPage(page: pageNumber)) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    // -------------------------------------------------------------------------
    // Public API — Single ayah lookup (for copy / share)
    //
    // When the user long-presses a line, the rendered PUA glyphs MUST NOT be
    // what gets copied. We resolve the selected (surah, ayah) back to the
    // clean Uthmani text row in `quran_text`. O(1) via the composite PK.
    // -------------------------------------------------------------------------

    /// Returns the full clean Uthmani text for a single ayah, or nil if not
    /// found. Blocking variant — use from queues or from already-background
    /// contexts. The typical caller is `MushaFViewModel.ayahText(surah:ayah:)`
    /// which falls back to this when the ayah isn't cached in a loaded page.
    func getAyahText(surah: Int, ayah: Int) throws -> String? {
        try queue.sync { try dao.getAyahText(surah: surah, ayah: ayah) }
    }

    // -------------------------------------------------------------------------
    // Public API — Search
    //
    // Architecture (parity with Android QuranRepository.kt — 2026-04-27 pt. 4):
    // normalization runs in Swift against an in-memory cache, NOT in SQL.  The
    // previous SQL strip chain blew SQLite's parser stack at 45 nested
    // REPLACEs (the bundled SQLite has a fixed yyparse() stack that overflows
    // around ~30+).
    //
    // The Swift path:
    //   1. First search triggers a one-time fetch of all 6,236 ayahs
    //      (~1.5 MB read), each paired with TWO normalized variants
    //      (folded vs stripped — see SearchEntry doc).
    //   2. Subsequent searches scan the cache with a simple `contains`
    //      check on each variant.  ~6k strings × ~150 chars is well
    //      under 50 ms on iPhone.
    //   3. Cache lives for the process lifetime; the Quran content
    //      doesn't change inside a session.
    //
    // Net result is faster than the SQL path AND covers KFGQPC v2.0's
    // full annotation glyph inventory without parser-stack risk.
    // -------------------------------------------------------------------------

    /// Snapshot of one ayah with two pre-normalized variants — see
    /// `normalizeForSearch` for the fold rules and `normalizeStripAlef`
    /// for the strip variant.
    ///
    /// Why dual-form: the dagger alef (U+0670) is ambiguous in Imla'i.
    /// In some words it represents a long-a that IS written as a full
    /// alef in modern spelling (الكافرون → ٱلۡكَٰفِرُونَ).  In other
    /// words the same glyph represents a long-a that's NOT written as
    /// a full alef in modern spelling (الرحمن → ٱلرَّحۡمَٰنِ).  No single-
    /// pass normalization can satisfy both — folding the dagger alef
    /// to ا finds الكافرون but breaks الرحمن; stripping it does the
    /// opposite.  Indexing BOTH variants and OR-ing the match covers
    /// both spelling conventions at the cost of a second pass per
    /// ayah.  Memory remains <4 MB total.
    private struct SearchEntry {
        let ayah:         Ayah
        let foldedText:   String   // dagger/subscript alef → ا (Imla'i with alef)
        let strippedText: String   // dagger/subscript alef removed (Imla'i without alef)
    }

    /// Lazily-built in-memory search index.  `nil` = not loaded yet.
    /// Always accessed on `queue`, so a plain stored property is sufficient
    /// — no `@Volatile` / lock needed since the GCD serial queue gives us
    /// the exclusion guarantee for free.
    private var searchCache: [SearchEntry]?

    /// Builds (or returns) the in-memory cache.  Caller must already be on
    /// `queue` — same reentrancy rules as `_getPageContentOnQueue`.
    private func ensureSearchCacheOnQueue() throws -> [SearchEntry] {
        if let cached = searchCache { return cached }
        let all = try dao.getAllAyahsForSearch()
        let built: [SearchEntry] = all.map { a in
            let raw = a.text ?? ""
            return SearchEntry(
                ayah:         a,
                foldedText:   Self.normalizeForSearch(raw),
                strippedText: Self.normalizeStripAlef(raw)
            )
        }
        searchCache = built
        return built
    }

    /// Diacritic-tolerant full-text search over the Quran text.
    ///
    /// Mirrors Android `searchAyahs` exactly: empty query → empty result;
    /// each hit is resolved to its correct Mushaf page via MetadataParser
    /// (NOT the DB page column).  Returns up to 100 results.
    func searchAyahs(query: String) throws -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return try queue.sync { try _searchAyahsOnQueue(trimmed: trimmed) }
    }

    /// Async variant — see `getPageContent(pageNumber:) async` for the
    /// reentrancy rationale. Calls the on-queue helper directly from
    /// `queue.async`, NEVER re-entering `queue.sync`.
    func searchAyahs(query: String) async throws -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return try await withCheckedThrowingContinuation { cont in
            queue.async {
                do    { cont.resume(returning: try self._searchAyahsOnQueue(trimmed: trimmed)) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    /// Inner worker — assumes the caller is already executing on `queue`.
    /// Match if EITHER form contains the needle — covers both Imla'i
    /// conventions for dagger-alef'd words.
    private func _searchAyahsOnQueue(trimmed: String) throws -> [SearchResult] {
        let needle = Self.normalizeForSearch(trimmed)
        guard !needle.isEmpty else { return [] }
        let cache = try ensureSearchCacheOnQueue()

        var results: [SearchResult] = []
        results.reserveCapacity(min(100, cache.count))
        for entry in cache {
            if results.count >= 100 { break }
            let hit = entry.foldedText.contains(needle) ||
                      entry.strippedText.contains(needle)
            guard hit else { continue }
            guard let surah = entry.ayah.surah,
                  let aya   = entry.ayah.ayah,
                  let text  = entry.ayah.text else { continue }
            let key  = surah * 10000 + aya
            results.append(
                SearchResult(
                    pageNumber:  findPageForKey(key),
                    surahNumber: surah,
                    surahName:   MetadataParser.shared.getSuraName(surah),
                    ayahNumber:  aya,
                    text:        text
                )
            )
        }
        return results
    }

    // -------------------------------------------------------------------------
    // Search normalization — direct port of Android QuranRepository.kt
    //
    // Bridges KFGQPC's **Uthmani** Mushaf orthography to the **Imla'i**
    // (modern) spelling that users type on their keyboards.  Tanzil ships
    // Imla'i (matches what users type), KFGQPC ships Uthmani (uses different
    // glyphs for the same sounds — dagger alef, alef-wasla, alef-maqsura,
    // etc).  Both indexed text and user query run through this so they
    // meet in a common normalized form.
    //
    // Folds applied (Uthmani → Imla'i / forgiving):
    //   • Alef variants  أ إ آ ٱ ٰ ٖ → ا
    //   • Alef-maqsura  ى → ي
    //   • Tatweel       ـ → ∅
    //
    // Marks dropped entirely (don't change letter identity):
    //   • 0x064B–0x065F  tashkeel + extras
    //   • 0x06D6–0x06ED  recitation pause + small-high-marks
    // -------------------------------------------------------------------------

    /// Folded variant — dagger / subscript alef collapse to ا.  Finds
    /// الكافرون when the user types it with a full alef.
    fileprivate static func normalizeForSearch(_ s: String) -> String {
        guard !s.isEmpty else { return s }
        var out = String()
        out.reserveCapacity(s.count)
        for scalar in s.unicodeScalars {
            let v = scalar.value
            switch v {
            // ── Letter folds: Uthmani → Imla'i ──────────────────────
            case 0x0622, 0x0623, 0x0625, 0x0671: out.append("ا")   // آ أ إ ٱ → ا
            case 0x0656, 0x0670:                 out.append("ا")   // subscript / dagger alef → ا
            case 0x0649:                         out.append("ي")   // alef-maqsura ى → ي
            case 0x0640:                         break              // tatweel ـ → strip
            // ── Diacritic marks: drop entirely ──────────────────────
            case 0x064B...0x065F:                break              // tashkeel + extra vowels
            case 0x06D6...0x06ED:                break              // recitation marks (incl. 06E1 sukun)
            default:                             out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    /// Strip-alef variant — dagger / subscript alefs are DROPPED rather
    /// than folded.  Finds الرحمن (no alef between م and ن in modern
    /// spelling) against KFGQPC's ٱلرَّحۡمَٰنِ (dagger alef present).
    fileprivate static func normalizeStripAlef(_ s: String) -> String {
        guard !s.isEmpty else { return s }
        var out = String()
        out.reserveCapacity(s.count)
        for scalar in s.unicodeScalars {
            let v = scalar.value
            switch v {
            // Same letter folds EXCEPT 0656 / 0670 — those are stripped here
            case 0x0622, 0x0623, 0x0625, 0x0671: out.append("ا")   // آ أ إ ٱ → ا
            case 0x0656, 0x0670:                 break              // dagger / subscript alef → drop
            case 0x0649:                         out.append("ي")   // alef-maqsura ى → ي
            case 0x0640:                         break              // tatweel ـ → strip
            case 0x064B...0x065F:                break              // tashkeel + extras
            case 0x06D6...0x06ED:                break              // recitation marks
            default:                             out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    // -------------------------------------------------------------------------
    // Public API — Bookmark / Preferences  (delegate to QuranDao)
    //
    // Android returns Flow<>; we return current snapshots here. A Combine /
    // AsyncStream wrapper will be added at the ViewModel layer so the UI can
    // observe changes — that's a UI concern, not a repo concern.
    // -------------------------------------------------------------------------

    func getAllBookmarks() throws -> [Bookmark] {
        try queue.sync { try dao.getAllBookmarks() }
    }

    func saveBookmark(pageNumber: Int) throws {
        try queue.sync { try dao.insertBookmark(Bookmark(pageNumber: pageNumber)) }
    }

    func removeBookmark(pageNumber: Int) throws {
        try queue.sync { try dao.deleteBookmark(Bookmark(pageNumber: pageNumber)) }
    }

    func clearAllBookmarks() throws {
        try queue.sync { try dao.deleteAllBookmarks() }
    }

    func getUserPreferences() throws -> UserPreferences? {
        try queue.sync { try dao.getUserPreferencesValue() }
    }

    func saveUserPreferences(_ prefs: UserPreferences) throws {
        try queue.sync { try dao.saveUserPreferences(prefs) }
    }

    // -------------------------------------------------------------------------
    // Private helpers — mirror Android exactly
    // -------------------------------------------------------------------------

    /// Returns the 1-indexed Mushaf page that contains `targetKey`.
    /// Scans all 604 pages once; MetadataParser boundaries are in-memory.
    private func findPageForKey(_ targetKey: Int) -> Int {
        for page in 1...WarattilConstants.Mushaf.totalPages {
            let (start, end) = MetadataParser.shared.getPageBoundaries(page)
            if (start...end).contains(targetKey) { return page }
        }
        return 1
    }

    private func resolveJuzForPage(_ pageNumber: Int) -> Int {
        let (pageStartKey, _) = MetadataParser.shared.getPageBoundaries(pageNumber)
        var resolved = 1
        for juz in 1...30 {
            let (juzKey, _) = MetadataParser.shared.getJuzBoundaries(juz)
            if juzKey <= pageStartKey { resolved = juz } else { break }
        }
        return resolved
    }
}
