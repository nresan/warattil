package com.warattil.app.data

import androidx.room.*
import kotlinx.coroutines.flow.Flow

@Dao
interface QuranDao {
    @Query("SELECT * FROM quran_text WHERE page = :pageNumber ORDER BY id ASC")
    fun getAyahsByPage(pageNumber: Int): Flow<List<Ayah>>

    @Query("SELECT * FROM quran_text WHERE id BETWEEN :startId AND :endId ORDER BY id ASC")
    fun getAyahsByRange(startId: Int, endId: Int): Flow<List<Ayah>>

    @Query("SELECT * FROM quran_text WHERE (sura * 10000 + aya) BETWEEN :startKey AND :endKey ORDER BY (sura * 10000 + aya) ASC")
    fun getAyahsByMonotonicRange(startKey: Int, endKey: Int): Flow<List<Ayah>>

    @Query("SELECT * FROM quran_text WHERE sura = :surahNumber ORDER BY aya ASC")
    fun getAyahsBySurah(surahNumber: Int): Flow<List<Ayah>>

    // Search dataset — ALL ayahs.  Normalization (diacritic stripping +
    // Uthmani→Imla'i alef folding) runs in Kotlin against this fetched
    // list, NOT in SQL.
    //
    // Why not SQL: the strip set has 35 distinct codepoints in actual use
    // and another 10 we'd want to defend against, which translates to a
    // 45-deep nested REPLACE chain.  Android's bundled SQLite parser has
    // a fixed yyparse() stack that overflows around ~30+ deep nested
    // function calls (Nasser confirmed 2026-04-27 pt. 4: build hit
    // SQLITE_ERROR "parser stack overflow" on the 45-deep chain).
    //
    // Fetching the full 6,236 ayahs is one ~1.5 MB read.  In-memory
    // normalization in Kotlin (see QuranRepository.searchAyahs) takes
    // <50 ms on first search; a one-time cache makes subsequent
    // searches O(n) string scans on already-normalized text.  Net
    // result is faster than the old SQL path AND covers every glyph
    // KFGQPC v2.0 emits.
    @Query("SELECT * FROM quran_text")
    suspend fun getAllAyahsForSearch(): List<Ayah>

    @Query("SELECT page FROM quran_text WHERE sura = :suraId AND aya = :aya LIMIT 1")
    suspend fun getPageForAyah(suraId: Int, aya: Int): Int?

    // 2026-04-27: bookmark + user_preferences DAO methods MOVED to UserDao.
    // They now operate on a separate UserDatabase that doesn't use
    // createFromAsset / destructive migration — so the user's wird state
    // and bookmarks survive every cold start.  See UserDatabase header
    // for the full architectural rationale.
}
