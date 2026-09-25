package com.warattil.app.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

import com.warattil.app.core.WarattilConstants

// Version 8 holds the KFGQPC v2.0 content refresh (re-populated quran_text
// from hafsData_v2-0.json).  fallbackToDestructiveMigration() means an
// existing local copy gets dropped and re-imported from the asset on
// version mismatch.
//
// 2026-04-27: Bookmark + UserPreferences entities REMOVED from this
// database.  They now live in UserDatabase which is NOT pre-populated
// from an asset and does NOT use destructive migration — so the user's
// bookmarks and wird state survive every Quran-content refresh AND
// every cold-start identity_hash mismatch.  See UserDatabase + the
// QuranRepository constructor for the full split rationale.
//
// Asset note: the shipped quran_v2.db still has bookmarks /
// user_preferences tables in its schema, but Room ignores tables that
// aren't in the entity set.  Cleanup of those dead tables in the asset
// is a low-priority pipeline task — they cost ~0 disk and don't affect
// runtime behaviour.
@Database(entities = [Ayah::class], version = 8, exportSchema = false)
abstract class QuranDatabase : RoomDatabase() {
    abstract fun quranDao(): QuranDao

    companion object {
        @Volatile
        private var INSTANCE: QuranDatabase? = null

        fun getDatabase(context: Context): QuranDatabase {
            return INSTANCE ?: synchronized(this) {
                val instance = Room.databaseBuilder(
                    context.applicationContext,
                    QuranDatabase::class.java,
                    "quran_database"
                )
                .createFromAsset(WarattilConstants.Mushaf.DB_NAME)
                .fallbackToDestructiveMigration()
                .build()
                INSTANCE = instance
                instance
            }
        }
    }
}
