//
//  Ayah.swift
//  Warattil
//
//  Row model for the `quran_text` table in quran_v2.db.
//  Mirrors app/src/main/java/com/warattil/app/data/Ayah.kt.
//
//  IMPORTANT: the `page` column exists in the DB but is NEVER used for paging
//  decisions in the app. Page boundaries come exclusively from MetadataParser
//  (quran_metadata.xml). See BLUEPRINT §2.2.
//

import Foundation

/// A single ayah row. Fields match the SQLite column names.
///
/// GRDB note: when we wire the repository up, this will conform to
/// `FetchableRecord` + `TableRecord` there — keeping this file framework-free
/// so the model compiles without GRDB (useful for Package.swift test target).
public struct Ayah: Equatable, Hashable {
    public let id: Int?
    public let surah: Int?     // SQLite column: `sura`
    public let ayah: Int?      // SQLite column: `aya`
    public let text: String?
    public let page: Int?      // legacy — do not use for paging
    public let juz: Int?

    public init(
        id: Int? = nil,
        surah: Int?,
        ayah: Int?,
        text: String?,
        page: Int? = nil,
        juz: Int? = nil
    ) {
        self.id = id
        self.surah = surah
        self.ayah = ayah
        self.text = text
        self.page = page
        self.juz = juz
    }

    /// Monotonic ordering key: `surah * 10000 + ayah`. Used by the paging-law
    /// range queries. Nil if either surah or ayah is missing.
    public var monotonicKey: Int? {
        guard let s = surah, let a = ayah else { return nil }
        return s * 10000 + a
    }

    /// Convenience used by range-query builders and tests.
    public static func monotonicKey(surah: Int, ayah: Int) -> Int {
        surah * 10000 + ayah
    }
}
