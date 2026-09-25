//
//  Bookmark.swift
//  Warattil
//
//  Ports app/src/main/java/com/warattil/app/data/Bookmark.kt to Swift.
//
//  Three types live in one file to mirror the Android source exactly:
//    • ReadingTargetType — enum
//    • Bookmark          — row in the `bookmarks` table
//    • UserPreferences   — single-row singleton in the `user_preferences` table
//
//  These are pure value types. Persistence logic lives in QuranDao / QuranDatabase.
//

import Foundation

// =============================================================================
// ReadingTargetType
//
// String-backed so the raw values match Room's default enum persistence:
// Room (v2.7+) stores enum values by their .name — so "FINISH_IN_DAYS" etc.
// We match those exact strings so that, if the same user ever exports/imports
// across platforms, the persisted column contents line up.
// =============================================================================

enum ReadingTargetType: String, CaseIterable, Equatable, Sendable {
    case finishInDays = "FINISH_IN_DAYS"
    case pagesPerDay  = "PAGES_PER_DAY"
    case juzPerDay    = "JUZ_PER_DAY"
}

// =============================================================================
// Bookmark — `bookmarks` table row.
//
// Android schema:
//   @Entity(tableName = "bookmarks")
//   data class Bookmark(
//       @PrimaryKey val pageNumber: Int,
//       val timestamp: Long = System.currentTimeMillis()
//   )
//
// iOS note: Kotlin's Long == Swift's Int64. We keep it Int64 in the struct so
// millisecond-epoch values (~10^12 today, well beyond Int32) are safe.
// =============================================================================

struct Bookmark: Equatable, Hashable, Sendable {
    let pageNumber: Int
    let timestamp:  Int64

    /// Default-initialiser matching the Kotlin data class: `timestamp` defaults
    /// to "now" in milliseconds since epoch — the same unit Android uses.
    init(pageNumber: Int, timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        self.pageNumber = pageNumber
        self.timestamp  = timestamp
    }
}

// =============================================================================
// UserPreferences — singleton row (id == 1) holding reading-plan (Wird) state.
//
// Android schema:
//   @Entity(tableName = "user_preferences")
//   data class UserPreferences(
//       @PrimaryKey val id: Int = 1,
//       val lastReadPage: Int = 1,
//       val wirdTargetType: ReadingTargetType = FINISH_IN_DAYS,
//       val wirdTargetValue: Int = 30,
//       val wirdStartDate: Long? = null,
//       val wirdStartPage: Int = 1,
//       val wirdLastCompletedPage: Int = 0
//   )
// =============================================================================

struct UserPreferences: Equatable, Hashable, Sendable {
    let id: Int                                   // always 1 (singleton row)
    let lastReadPage: Int
    let wirdTargetType: ReadingTargetType
    let wirdTargetValue: Int                      // days, pages-per-day, or juz-per-day
    let wirdStartDate: Int64?                     // ms since epoch, nil if plan not started
    let wirdStartPage: Int
    let wirdLastCompletedPage: Int

    init(
        id: Int = 1,
        lastReadPage: Int = 1,
        wirdTargetType: ReadingTargetType = .finishInDays,
        wirdTargetValue: Int = 30,
        wirdStartDate: Int64? = nil,
        wirdStartPage: Int = 1,
        wirdLastCompletedPage: Int = 0
    ) {
        self.id                    = id
        self.lastReadPage          = lastReadPage
        self.wirdTargetType        = wirdTargetType
        self.wirdTargetValue       = wirdTargetValue
        self.wirdStartDate         = wirdStartDate
        self.wirdStartPage         = wirdStartPage
        self.wirdLastCompletedPage = wirdLastCompletedPage
    }
}
