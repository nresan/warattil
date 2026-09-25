package com.warattil.app.data

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "bookmarks")
data class Bookmark(
    @PrimaryKey val pageNumber: Int,
    val timestamp: Long = System.currentTimeMillis()
)

enum class ReadingTargetType {
    FINISH_IN_DAYS,
    PAGES_PER_DAY,
    JUZ_PER_DAY
}

@Entity(tableName = "user_preferences")
data class UserPreferences(
    @PrimaryKey val id: Int = 1, // Singleton row
    val lastReadPage: Int = 1,

    // Reading Plan (Wird) fields
    val wirdTargetType: ReadingTargetType = ReadingTargetType.FINISH_IN_DAYS,
    val wirdTargetValue: Int = 30, // Default 30 days
    val wirdStartDate: Long? = null,
    val wirdStartPage: Int = 1,
    val wirdLastCompletedPage: Int = 0
)