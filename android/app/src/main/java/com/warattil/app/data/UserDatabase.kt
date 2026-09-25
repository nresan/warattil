package com.warattil.app.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

// =============================================================================
// UserDatabase — bookmarks + wird preferences, persistent across app restarts.
//
// WHY THIS IS SEPARATE FROM QuranDatabase
// ---------------------------------------
// QuranDatabase ships as a pre-populated SQLite asset (`quran_v2.db`) that
// holds the read-only KFGQPC content.  It uses `createFromAsset(...)` plus
// `fallbackToDestructiveMigration()` so the local copy is rebuilt from the
// new asset on every content refresh.
//
// That destructive lifecycle is fine for read-only content — but it would
// delete the user's bookmarks and wird state on every schema bump (and,
// pre-fix, on every cold start because the asset's identity_hash doesn't
// match Room's expectation).  Nasser reported wird state being wiped on
// app restart (2026-04-27) — that was this exact bug.
//
// FIX: user state lives in its OWN Room database, populated entirely at
// runtime (no asset), no destructive migration.  When the schema version
// bumps in the future we'll write proper migrations; in the meantime
// the user's progress survives every restart and every reinstall of
// the QuranDatabase asset.
//
// SCHEMA VERSION
// --------------
// Kept at 7 — the Bookmark and UserPreferences entities have the same
// structure they had when they lived inside QuranDatabase.  Future
// schema changes bump THIS version independently of the Quran content
// cadence.
// =============================================================================

@Database(
    entities     = [Bookmark::class, UserPreferences::class],
    version      = 7,
    exportSchema = false
)
abstract class UserDatabase : RoomDatabase() {

    abstract fun userDao(): UserDao

    companion object {
        @Volatile
        private var INSTANCE: UserDatabase? = null

        fun getDatabase(context: Context): UserDatabase {
            return INSTANCE ?: synchronized(this) {
                val instance = Room.databaseBuilder(
                    context.applicationContext,
                    UserDatabase::class.java,
                    "user_database"
                )
                // No createFromAsset — UserDatabase starts empty and is
                // populated entirely by the app's own writes.
                //
                // No fallbackToDestructiveMigration — losing the user's
                // bookmarks + wird state silently on every schema mismatch
                // is exactly the bug we're fixing.  Future schema bumps
                // require proper Room migrations; the build will fail
                // loudly if a migration is missing rather than wiping
                // user data.
                .build()
                INSTANCE = instance
                instance
            }
        }
    }
}
