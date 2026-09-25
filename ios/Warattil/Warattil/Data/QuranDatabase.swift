//
//  QuranDatabase.swift
//  Warattil
//
//  Ports app/src/main/java/com/warattil/app/data/QuranDatabase.kt to Swift.
//
//  Lifecycle responsibilities (matches Android Room with `createFromAsset`):
//    1. On first launch, copy the bundled `quran_v3.db` from the app bundle
//       into the app's Documents directory (the bundle is read-only on iOS).
//    2. Open the copied DB and ensure the `bookmarks` and `user_preferences`
//       tables exist — Android Room creates these automatically from @Entity
//       annotations; on iOS we run `CREATE TABLE IF NOT EXISTS` ourselves.
//    3. Hand out a `QuranDao` backed by the open connection.
//
//  Why raw SQLite3 (not GRDB)?
//    - Zero Swift Package Manager dependencies → no Xcode UI steps for Nasser.
//    - `import SQLite3` is Apple-provided, always available.
//    - The query surface is small (~10 methods); raw SQLite is fine.
//    - Can swap to GRDB later if we need ValueObservation / Combine streams.
//
//  Thread-safety:
//    - A single serial DispatchQueue ("quran.db.queue") is used for all DB
//      access. SQLite connections are not safe to share across threads without
//      a guarantee of serial access. Room handles this via its executor;
//      we use a queue. Callers hit `perform { ... }` or the async wrappers.
//

import Foundation
import SQLite3

// Required by SQLite C API — sqlite3_bind_text needs a destructor to know how
// to manage the buffer. `SQLITE_TRANSIENT` tells SQLite to make its own copy
// (safe for any Swift String). The constant is a macro in C, so we reconstruct
// it here via unsafeBitCast the way most Swift SQLite wrappers do.
let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// =============================================================================
// QuranDatabase — singleton owner of the SQLite connection.
// =============================================================================

final class QuranDatabase {

    /// Process-wide singleton; matches Android's `@Volatile INSTANCE` pattern.
    static let shared = QuranDatabase()

    /// Open SQLite handle. `nil` until `open()` completes successfully.
    private(set) var db: OpaquePointer?

    /// Serial queue protecting all DB access. All public methods on
    /// `QuranDao` should be called inside `perform { ... }`.
    let queue = DispatchQueue(label: "quran.db.queue", qos: .userInitiated)

    /// The schema version the bundled DB ships with — compared against the
    /// Documents-dir copy's `PRAGMA user_version` at launch. When the number
    /// here is newer than what the device has on disk, `copyBundledDBIfNeeded`
    /// performs an in-place schema migration that preserves `bookmarks` +
    /// `user_preferences` rows and replaces the text/QCF data with the
    /// bundled copy.
    ///
    /// Bump this constant (and re-stamp the bundled DB with the same number)
    /// whenever the bundled DB's schema or content changes in a way installs
    /// need to pick up:
    ///   python3 -c "import sqlite3; c = sqlite3.connect('quran_v3.db');
    ///               c.execute('PRAGMA user_version = N'); c.commit()"
    ///
    /// Current: 8 — first version to carry the QCF per-page render tables
    /// (page_font / page_line / line_word / ayah). Earlier installs only had
    /// quran_text + bookmarks + user_preferences and rendered tofu on the
    /// QCF-only pages (4-5, most of juz 1).
    static let bundledSchemaVersion: Int32 = 8

    private init() {}

    // -------------------------------------------------------------------------
    // Public: open / DAO factory
    // -------------------------------------------------------------------------

    /// Open (or re-open) the database. Idempotent — second call is a no-op.
    ///
    /// Throws if the bundled DB is missing, the copy fails, or SQLite rejects
    /// the file. Call from app startup and crash loud if it fails — a missing
    /// quran DB is a shipping bug, not a runtime-recoverable state.
    func open() throws {
        if db != nil { return }

        let writableURL = try copyBundledDBIfNeeded()

        var handle: OpaquePointer?
        let result = sqlite3_open_v2(
            writableURL.path,
            &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK, handle != nil else {
            let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if handle != nil { sqlite3_close(handle) }
            throw DBError.openFailed("sqlite3_open_v2 rc=\(result) msg=\(msg)")
        }

        self.db = handle
        try ensureUserTables()
    }

    /// Returns a DAO bound to the current connection. Must call `open()` first.
    func quranDao() throws -> QuranDao {
        guard let db = db else {
            throw DBError.notOpen("Call QuranDatabase.shared.open() before quranDao()")
        }
        return QuranDao(db: db, queue: queue)
    }

    /// Test-only: close and forget the connection.
    func __closeForTesting() {
        if let db = db {
            sqlite3_close(db)
            self.db = nil
        }
    }

    // -------------------------------------------------------------------------
    // Private: bundle-copy + schema bootstrap
    // -------------------------------------------------------------------------

    /// Copies the read-only bundled `quran_v3.db` into the Documents directory
    /// the first time the app runs, and — on subsequent launches — triggers a
    /// preserving schema migration when the bundled `user_version` is newer
    /// than the Documents copy's. User-written rows (`bookmarks` +
    /// `user_preferences`) survive the migration; everything else is replaced
    /// wholesale from the bundled file.
    ///
    /// This guards against the class of bug where an older dev build shipped
    /// an incomplete DB (e.g. legacy quran_text-only), the user's Documents
    /// dir cached that older copy, and new bundle features (QCF per-page
    /// glyphs, added juz data, etc.) silently never reach the device because
    /// `fileExists` returned true and we short-circuited the copy.
    private func copyBundledDBIfNeeded() throws -> URL {
        let fm = FileManager.default

        guard let bundleURL = Bundle.main.url(
            forResource: "quran_v3", withExtension: "db"
        ) else {
            throw DBError.bundleMissing("quran_v3.db not found in app bundle")
        }

        let docsURL = try fm.url(
            for: .documentDirectory,
            in:  .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let destURL = docsURL.appendingPathComponent("quran_v3.db")

        if !fm.fileExists(atPath: destURL.path) {
            // First install — simple copy, no migration needed.
            try fm.copyItem(at: bundleURL, to: destURL)
        } else {
            // Existing install — only replace if the bundle ships a newer
            // user_version than the Documents copy.
            let docsVersion = (try? readUserVersion(at: destURL)) ?? 0
            if docsVersion < Self.bundledSchemaVersion {
                try migrateInPlace(bundleURL: bundleURL, destURL: destURL)
            }
        }

        // Clean up a stale quran_v2.db left by earlier dev builds so the
        // Documents directory doesn't grow over time. Only remove it after
        // the v3 copy is confirmed in place — we never drop pre-migration
        // user data blindly.
        let stale = docsURL.appendingPathComponent("quran_v2.db")
        if fm.fileExists(atPath: destURL.path),
           fm.fileExists(atPath: stale.path) {
            try? fm.removeItem(at: stale)
        }
        return destURL
    }

    /// Reads `PRAGMA user_version` from the SQLite file at `url`. Returns 0
    /// when the file can't be opened read-only (treated as "needs migration"
    /// by the caller).
    private func readUserVersion(at url: URL) throws -> Int32 {
        var handle: OpaquePointer?
        let rc = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil)
        guard rc == SQLITE_OK, let h = handle else {
            if handle != nil { sqlite3_close(handle) }
            return 0
        }
        defer { sqlite3_close(h) }

        var stmt: OpaquePointer?
        let pRc = sqlite3_prepare_v2(h, "PRAGMA user_version;", -1, &stmt, nil)
        guard pRc == SQLITE_OK, let s = stmt else { return 0 }
        defer { sqlite3_finalize(s) }
        guard sqlite3_step(s) == SQLITE_ROW else { return 0 }
        return sqlite3_column_int(s, 0)
    }

    /// Replaces the Documents-dir copy with the bundled file while preserving
    /// `bookmarks` + `user_preferences` rows.
    ///
    /// Steps:
    ///   1. Snapshot user-writable tables from the old Documents DB.
    ///   2. Replace the file on disk with the bundled copy.
    ///   3. Re-open the new file, ensure `bookmarks` / `user_preferences`
    ///      tables exist (they may or may not ship in the bundle), and
    ///      replay the snapshotted rows.
    ///
    /// The snapshot phase is tolerant — if the old DB is too broken to
    /// produce a snapshot, we log and proceed with a clean replace. The
    /// alternative (aborting the migration) would leave the user stuck on
    /// the broken schema forever.
    private func migrateInPlace(bundleURL: URL, destURL: URL) throws {
        let savedBookmarks = (try? snapshotBookmarks(at: destURL)) ?? []
        let savedPrefs     = try? snapshotPreferences(at: destURL)

        let fm = FileManager.default
        try fm.removeItem(at: destURL)
        try fm.copyItem(at: bundleURL, to: destURL)

        // Open briefly to restore the preserved rows. Uses a local handle —
        // the "real" handle owned by `self.db` will be opened by the caller
        // (open()) right after this returns.
        var handle: OpaquePointer?
        let rc = sqlite3_open_v2(
            destURL.path, &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil
        )
        guard rc == SQLITE_OK, let h = handle else {
            if handle != nil { sqlite3_close(handle) }
            return
        }
        defer { sqlite3_close(h) }

        // Make sure the user-writable tables exist — the bundled DB may ship
        // without them (e.g. when rebuilt by a QCF-only importer run).
        try createUserTables(on: h)

        if let prefs = savedPrefs {
            try restorePreferences(prefs, on: h)
        }
        for bm in savedBookmarks {
            try restoreBookmark(bm, on: h)
        }
    }

    // --- Snapshot + restore helpers (local to migration) ---------------------

    private struct BookmarkSnapshot {
        let pageNumber: Int32
        let timestamp:  Int64
    }

    private struct PreferencesSnapshot {
        let id: Int32
        let lastReadPage: Int32
        let wirdTargetType: String
        let wirdTargetValue: Int32
        let wirdStartDate: Int64?
        let wirdStartPage: Int32
        let wirdLastCompletedPage: Int32
    }

    private func snapshotBookmarks(at url: URL) throws -> [BookmarkSnapshot] {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let h = handle else {
            if handle != nil { sqlite3_close(handle) }
            return []
        }
        defer { sqlite3_close(h) }

        var stmt: OpaquePointer?
        let sql = "SELECT pageNumber, timestamp FROM bookmarks;"
        guard sqlite3_prepare_v2(h, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else {
            return []
        }
        defer { sqlite3_finalize(s) }

        var out: [BookmarkSnapshot] = []
        while sqlite3_step(s) == SQLITE_ROW {
            out.append(BookmarkSnapshot(
                pageNumber: sqlite3_column_int(s, 0),
                timestamp:  sqlite3_column_int64(s, 1)
            ))
        }
        return out
    }

    private func snapshotPreferences(at url: URL) throws -> PreferencesSnapshot? {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let h = handle else {
            if handle != nil { sqlite3_close(handle) }
            return nil
        }
        defer { sqlite3_close(h) }

        var stmt: OpaquePointer?
        let sql = """
            SELECT id, lastReadPage, wirdTargetType, wirdTargetValue,
                   wirdStartDate, wirdStartPage, wirdLastCompletedPage
            FROM user_preferences WHERE id = 1;
        """
        guard sqlite3_prepare_v2(h, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else {
            return nil
        }
        defer { sqlite3_finalize(s) }
        guard sqlite3_step(s) == SQLITE_ROW else { return nil }

        let typePtr = sqlite3_column_text(s, 2)
        let typeStr = typePtr.map { String(cString: $0) } ?? "FINISH_IN_DAYS"
        let startDate: Int64? = sqlite3_column_type(s, 4) == SQLITE_NULL
            ? nil : sqlite3_column_int64(s, 4)

        return PreferencesSnapshot(
            id:                    sqlite3_column_int(s, 0),
            lastReadPage:          sqlite3_column_int(s, 1),
            wirdTargetType:        typeStr,
            wirdTargetValue:       sqlite3_column_int(s, 3),
            wirdStartDate:         startDate,
            wirdStartPage:         sqlite3_column_int(s, 5),
            wirdLastCompletedPage: sqlite3_column_int(s, 6)
        )
    }

    private func createUserTables(on h: OpaquePointer) throws {
        try exec(h, """
            CREATE TABLE IF NOT EXISTS bookmarks (
                pageNumber INTEGER PRIMARY KEY NOT NULL,
                timestamp  INTEGER NOT NULL DEFAULT 0
            );
        """)
        try exec(h, """
            CREATE TABLE IF NOT EXISTS user_preferences (
                id                    INTEGER PRIMARY KEY NOT NULL,
                lastReadPage          INTEGER NOT NULL DEFAULT 1,
                wirdTargetType        TEXT    NOT NULL DEFAULT 'FINISH_IN_DAYS',
                wirdTargetValue       INTEGER NOT NULL DEFAULT 30,
                wirdStartDate         INTEGER,
                wirdStartPage         INTEGER NOT NULL DEFAULT 1,
                wirdLastCompletedPage INTEGER NOT NULL DEFAULT 0
            );
        """)
    }

    private func restoreBookmark(_ bm: BookmarkSnapshot, on h: OpaquePointer) throws {
        var stmt: OpaquePointer?
        let sql = """
            INSERT INTO bookmarks (pageNumber, timestamp)
            VALUES (?, ?)
            ON CONFLICT(pageNumber) DO UPDATE SET timestamp = excluded.timestamp;
        """
        guard sqlite3_prepare_v2(h, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else {
            return
        }
        defer { sqlite3_finalize(s) }
        sqlite3_bind_int(s, 1, bm.pageNumber)
        sqlite3_bind_int64(s, 2, bm.timestamp)
        _ = sqlite3_step(s)
    }

    private func restorePreferences(_ p: PreferencesSnapshot, on h: OpaquePointer) throws {
        var stmt: OpaquePointer?
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
        guard sqlite3_prepare_v2(h, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else {
            return
        }
        defer { sqlite3_finalize(s) }
        sqlite3_bind_int(s, 1, p.id)
        sqlite3_bind_int(s, 2, p.lastReadPage)
        sqlite3_bind_text(s, 3, p.wirdTargetType, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(s, 4, p.wirdTargetValue)
        if let date = p.wirdStartDate {
            sqlite3_bind_int64(s, 5, date)
        } else {
            sqlite3_bind_null(s, 5)
        }
        sqlite3_bind_int(s, 6, p.wirdStartPage)
        sqlite3_bind_int(s, 7, p.wirdLastCompletedPage)
        _ = sqlite3_step(s)
    }

    /// Creates the user-writable tables on first open if missing. The Quran
    /// text table (`quran_text`) is pre-populated in the bundled DB and we
    /// never touch its schema.
    private func ensureUserTables() throws {
        guard let db = db else { return }

        // bookmarks
        try exec(db, """
            CREATE TABLE IF NOT EXISTS bookmarks (
                pageNumber INTEGER PRIMARY KEY NOT NULL,
                timestamp  INTEGER NOT NULL DEFAULT 0
            );
        """)

        // user_preferences — singleton row (id == 1).
        try exec(db, """
            CREATE TABLE IF NOT EXISTS user_preferences (
                id                    INTEGER PRIMARY KEY NOT NULL,
                lastReadPage          INTEGER NOT NULL DEFAULT 1,
                wirdTargetType        TEXT    NOT NULL DEFAULT 'FINISH_IN_DAYS',
                wirdTargetValue       INTEGER NOT NULL DEFAULT 30,
                wirdStartDate         INTEGER,
                wirdStartPage         INTEGER NOT NULL DEFAULT 1,
                wirdLastCompletedPage INTEGER NOT NULL DEFAULT 0
            );
        """)
    }

    /// Fire-and-forget statement execution. Throws on SQLite error.
    private func exec(_ db: OpaquePointer, _ sql: String) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            let msg = errMsg.flatMap { String(cString: $0) } ?? "unknown"
            sqlite3_free(errMsg)
            throw DBError.execFailed("rc=\(rc) msg=\(msg) sql=\(sql)")
        }
    }
}

// =============================================================================
// Errors
// =============================================================================

enum DBError: Error, Equatable {
    case bundleMissing(String)
    case openFailed(String)
    case execFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case notOpen(String)
}
