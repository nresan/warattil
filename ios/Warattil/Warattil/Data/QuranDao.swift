//
//  QuranDao.swift
//  Warattil
//
//  Ports app/src/main/java/com/warattil/app/data/QuranDao.kt to Swift.
//
//  Query surface matches Android 1:1. Naming preserved (`getAyahsBy…`,
//  `insertBookmark`, etc.) so any future ViewModel port can read both files
//  side-by-side with identical call sites.
//
//  All public methods are synchronous and expect to be called inside the
//  shared serial DB queue: `QuranDatabase.shared.queue.async { dao.… }`.
//  The queue-dispatch lives one layer up (in QuranRepository) so the DAO
//  stays flat and unit-testable.
//

import Foundation
import SQLite3

final class QuranDao {

    // Non-owning — QuranDatabase owns the handle's lifetime.
    private let db: OpaquePointer
    private let queue: DispatchQueue

    init(db: OpaquePointer, queue: DispatchQueue) {
        self.db = db
        self.queue = queue
    }

    // =========================================================================
    // MARK: Ayah reads
    //
    // The ONLY query the main reading surface uses is `getAyahsByMonotonicRange`.
    // The other helpers are kept for parity with the Android DAO (search UI,
    // etc.) but should never be used to compute page boundaries.
    // =========================================================================

    /// Matches Kotlin:
    ///   @Query("SELECT * FROM quran_text
    ///           WHERE (sura * 10000 + aya) BETWEEN :startKey AND :endKey
    ///           ORDER BY (sura * 10000 + aya) ASC")
    func getAyahsByMonotonicRange(startKey: Int, endKey: Int) throws -> [Ayah] {
        let sql = """
            SELECT id, sura, aya, text, page, juz
            FROM quran_text
            WHERE (sura * 10000 + aya) BETWEEN ? AND ?
            ORDER BY (sura * 10000 + aya) ASC;
        """
        return try withStatement(sql) { stmt in
            sqlite3_bind_int(stmt, 1, Int32(startKey))
            sqlite3_bind_int(stmt, 2, Int32(endKey))
            return try collectAyahs(stmt)
        }
    }

    /// Search dataset — ALL ayahs.  Normalization (diacritic stripping +
    /// Uthmani→Imla'i alef folding) runs in Swift against this fetched
    /// list, NOT in SQL.  Same architecture as Android pt. 4 (the SQLite
    /// REPLACE chain hit a parser-stack ceiling at ~30+ nested calls and
    /// also couldn't express dual-form indexing).
    ///
    /// Fetched once on first search; cached in QuranRepository for the
    /// process lifetime.  ~1.5 MB read; ~6,236 ayahs.  Search is then
    /// O(n) substring scans on pre-normalized text.
    func getAllAyahsForSearch() throws -> [Ayah] {
        let sql = "SELECT id, sura, aya, text, page, juz FROM quran_text;"
        return try withStatement(sql) { stmt in
            try collectAyahs(stmt)
        }
    }

    /// Kotlin: @Query("SELECT page FROM quran_text WHERE sura = :suraId AND aya = :aya LIMIT 1")
    ///
    /// NOTE: only the Android legacy "Go to ayah" feature uses this. For page
    /// boundaries the repo uses MetadataParser, not this column.
    func getPageForAyah(suraId: Int, aya: Int) throws -> Int? {
        let sql = "SELECT page FROM quran_text WHERE sura = ? AND aya = ? LIMIT 1;"
        return try withStatement(sql) { stmt in
            sqlite3_bind_int(stmt, 1, Int32(suraId))
            sqlite3_bind_int(stmt, 2, Int32(aya))
            return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : nil
        }
    }

    /// Direct lookup of the full Uthmani text for a single ayah.
    ///
    /// Used by the long-press ayah action bar (copy / share) so the clean
    /// Uthmani Unicode — not the on-screen QCF PUA glyphs — leaves the app.
    /// O(1) via the PK on (sura, aya).
    func getAyahText(surah: Int, ayah: Int) throws -> String? {
        let sql = "SELECT text FROM quran_text WHERE sura = ? AND aya = ? LIMIT 1;"
        return try withStatement(sql) { stmt in
            sqlite3_bind_int(stmt, 1, Int32(surah))
            sqlite3_bind_int(stmt, 2, Int32(ayah))
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return colText(stmt, 0)
        }
    }

    // =========================================================================
    // MARK: QCF page rendering
    //
    // New in quran_v3.db (2026-04-20) — reads the per-page glyph layout that
    // backs the MushafPageView render path. These queries are cheap (≤15 rows
    // + ~50 words per page) so we don't paginate further.
    // =========================================================================

    /// Fetch every line on a page, with per-line words for `text` lines.
    /// Returns `nil` if the page does not exist (should never happen for
    /// 1…604 in a well-built DB; returning Optional lets the ViewModel show
    /// a diagnostic rather than crash).
    func getMushafPage(page: Int) throws -> MushafPage? {
        // 1) Pull the font asset + confirm the page exists.
        let pageFontSql = "SELECT font_asset FROM page_font WHERE page = ?;"
        guard let bodyFont: String = try withStatement(pageFontSql, { stmt in
            sqlite3_bind_int(stmt, 1, Int32(page))
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil as String? }
            return colText(stmt, 0)
        }) else {
            return nil
        }

        // 2) Pull all lines on the page.
        let linesSql = """
            SELECT line_no, type, glyph_text, font_asset,
                   surah_number, surah_text, verse_range
            FROM page_line
            WHERE page = ?
            ORDER BY line_no ASC;
        """
        // Store lines keyed by line_no so we can attach words after the fact.
        var lineBuilders: [(Int, MushafLineType, String?, String?, Int?, String?, String?)] = []
        try withStatement(linesSql) { stmt in
            sqlite3_bind_int(stmt, 1, Int32(page))
            while sqlite3_step(stmt) == SQLITE_ROW {
                let lineNo      = Int(sqlite3_column_int(stmt, 0))
                let typeRaw     = colText(stmt, 1) ?? ""
                let glyphText   = colText(stmt, 2)
                let fontAsset   = colText(stmt, 3)
                let surahNumber = colInt(stmt, 4)
                let surahText   = colText(stmt, 5)
                let verseRange  = colText(stmt, 6)

                guard let type = MushafLineType(rawValue: typeRaw) else {
                    throw DBError.stepFailed(
                        "unknown line type \(typeRaw) on page \(page) line \(lineNo)"
                    )
                }
                lineBuilders.append(
                    (lineNo, type, glyphText, fontAsset,
                     surahNumber, surahText, verseRange)
                )
            }
        }

        // 3) Pull every word for this page and index by line_no.
        let wordsSql = """
            SELECT line_no, pos, location, surah, ayah, word_index,
                   glyph_pua, glyph_pua_v2, uthmani
            FROM line_word
            WHERE page = ?
            ORDER BY line_no ASC, pos ASC;
        """
        var wordsByLine: [Int: [MushafWord]] = [:]
        try withStatement(wordsSql) { stmt in
            sqlite3_bind_int(stmt, 1, Int32(page))
            while sqlite3_step(stmt) == SQLITE_ROW {
                let lineNo     = Int(sqlite3_column_int(stmt, 0))
                let pos        = Int(sqlite3_column_int(stmt, 1))
                let location   = colText(stmt, 2) ?? ""
                let surah      = Int(sqlite3_column_int(stmt, 3))
                let ayah       = Int(sqlite3_column_int(stmt, 4))
                let wordIndex  = Int(sqlite3_column_int(stmt, 5))
                let glyphV1    = colText(stmt, 6) ?? ""
                let glyphV2    = colText(stmt, 7) ?? ""
                let uthmani    = colText(stmt, 8) ?? ""

                wordsByLine[lineNo, default: []].append(MushafWord(
                    page: page,
                    lineNo: lineNo,
                    pos: pos,
                    location: location,
                    surah: surah,
                    ayah: ayah,
                    wordIndex: wordIndex,
                    glyphPua: glyphV1,
                    glyphPuaV2: glyphV2,
                    uthmani: uthmani
                ))
            }
        }

        // 4) Stitch.
        let lines: [MushafLine] = lineBuilders.map { (lineNo, type, glyph, font, sn, st, vr) in
            MushafLine(
                page: page,
                lineNo: lineNo,
                type: type,
                glyphText: glyph,
                fontAsset: font,
                surahNumber: sn,
                surahText: st,
                verseRange: vr,
                words: wordsByLine[lineNo] ?? []
            )
        }
        return MushafPage(page: page, bodyFontAsset: bodyFont, lines: lines)
    }

    // =========================================================================
    // MARK: Bookmarks
    // =========================================================================

    func insertBookmark(_ bookmark: Bookmark) throws {
        let sql = """
            INSERT INTO bookmarks (pageNumber, timestamp)
            VALUES (?, ?)
            ON CONFLICT(pageNumber) DO UPDATE SET timestamp = excluded.timestamp;
        """
        try withStatement(sql) { stmt in
            sqlite3_bind_int(stmt, 1, Int32(bookmark.pageNumber))
            sqlite3_bind_int64(stmt, 2, bookmark.timestamp)
            try stepDone(stmt)
        }
    }

    func deleteBookmark(_ bookmark: Bookmark) throws {
        let sql = "DELETE FROM bookmarks WHERE pageNumber = ?;"
        try withStatement(sql) { stmt in
            sqlite3_bind_int(stmt, 1, Int32(bookmark.pageNumber))
            try stepDone(stmt)
        }
    }

    func deleteAllBookmarks() throws {
        let sql = "DELETE FROM bookmarks;"
        try withStatement(sql) { stmt in
            try stepDone(stmt)
        }
    }

    func getAllBookmarks() throws -> [Bookmark] {
        let sql = "SELECT pageNumber, timestamp FROM bookmarks ORDER BY timestamp DESC;"
        return try withStatement(sql) { stmt in
            var out: [Bookmark] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append(Bookmark(
                    pageNumber: Int(sqlite3_column_int(stmt, 0)),
                    timestamp:  sqlite3_column_int64(stmt, 1)
                ))
            }
            return out
        }
    }

    // =========================================================================
    // MARK: User Preferences
    // =========================================================================

    func saveUserPreferences(_ prefs: UserPreferences) throws {
        let sql = """
            INSERT INTO user_preferences
                (id, lastReadPage, wirdTargetType, wirdTargetValue,
                 wirdStartDate, wirdStartPage, wirdLastCompletedPage)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                lastReadPage          = excluded.lastReadPage,
                wirdTargetType        = excluded.wirdTargetType,
                wirdTargetValue       = excluded.wirdTargetValue,
                wirdStartDate         = excluded.wirdStartDate,
                wirdStartPage         = excluded.wirdStartPage,
                wirdLastCompletedPage = excluded.wirdLastCompletedPage;
        """
        try withStatement(sql) { stmt in
            sqlite3_bind_int(stmt, 1, Int32(prefs.id))
            sqlite3_bind_int(stmt, 2, Int32(prefs.lastReadPage))
            sqlite3_bind_text(stmt, 3, prefs.wirdTargetType.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 4, Int32(prefs.wirdTargetValue))
            if let startDate = prefs.wirdStartDate {
                sqlite3_bind_int64(stmt, 5, startDate)
            } else {
                sqlite3_bind_null(stmt, 5)
            }
            sqlite3_bind_int(stmt, 6, Int32(prefs.wirdStartPage))
            sqlite3_bind_int(stmt, 7, Int32(prefs.wirdLastCompletedPage))
            try stepDone(stmt)
        }
    }

    func getUserPreferencesValue() throws -> UserPreferences? {
        let sql = """
            SELECT id, lastReadPage, wirdTargetType, wirdTargetValue,
                   wirdStartDate, wirdStartPage, wirdLastCompletedPage
            FROM user_preferences WHERE id = 1;
        """
        return try withStatement(sql) { stmt in
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

            let id              = Int(sqlite3_column_int(stmt, 0))
            let lastReadPage    = Int(sqlite3_column_int(stmt, 1))
            let wirdTypeRaw     = String(cString: sqlite3_column_text(stmt, 2))
            let wirdTargetValue = Int(sqlite3_column_int(stmt, 3))
            let wirdStartDate: Int64? = sqlite3_column_type(stmt, 4) == SQLITE_NULL
                ? nil
                : sqlite3_column_int64(stmt, 4)
            let wirdStartPage         = Int(sqlite3_column_int(stmt, 5))
            let wirdLastCompletedPage = Int(sqlite3_column_int(stmt, 6))

            return UserPreferences(
                id:              id,
                lastReadPage:    lastReadPage,
                wirdTargetType:  ReadingTargetType(rawValue: wirdTypeRaw) ?? .finishInDays,
                wirdTargetValue: wirdTargetValue,
                wirdStartDate:   wirdStartDate,
                wirdStartPage:   wirdStartPage,
                wirdLastCompletedPage: wirdLastCompletedPage
            )
        }
    }

    // =========================================================================
    // MARK: Private helpers
    // =========================================================================

    /// Prepares a statement, runs `body` with it, and always finalises.
    @discardableResult
    private func withStatement<T>(_ sql: String, _ body: (OpaquePointer?) throws -> T) throws -> T {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let stmt = stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            if let s = stmt { sqlite3_finalize(s) }
            throw DBError.prepareFailed("rc=\(rc) msg=\(msg) sql=\(sql)")
        }
        defer { sqlite3_finalize(stmt) }
        return try body(stmt)
    }

    /// Steps a write statement and checks it ran to completion.
    private func stepDone(_ stmt: OpaquePointer?) throws {
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.stepFailed("rc=\(rc) msg=\(msg)")
        }
    }

    /// Iterates a SELECT on `quran_text` and maps rows to Ayah.
    private func collectAyahs(_ stmt: OpaquePointer?) throws -> [Ayah] {
        var out: [Ayah] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id   = colInt(stmt, 0)
            let sura = colInt(stmt, 1)
            let aya  = colInt(stmt, 2)
            let text = colText(stmt, 3)
            let page = colInt(stmt, 4)
            let juz  = colInt(stmt, 5)

            out.append(Ayah(
                id:   id,
                surah: sura,
                ayah:  aya,
                text:  text,
                page:  page,
                juz:   juz
            ))
        }
        return out
    }

    // Nil-returning column helpers — SQLite returns default (0 / NULL) for
    // NULL columns in `sqlite3_column_*`. We distinguish via column_type so
    // an honest `nil` bubbles up to the Swift model instead of `0`.
    private func colInt(_ stmt: OpaquePointer?, _ index: Int32) -> Int? {
        sqlite3_column_type(stmt, index) == SQLITE_NULL
            ? nil
            : Int(sqlite3_column_int(stmt, index))
    }

    private func colText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL,
              let cstr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cstr)
    }
}
