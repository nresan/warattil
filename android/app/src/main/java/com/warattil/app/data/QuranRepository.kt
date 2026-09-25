package com.warattil.app.data

import android.content.Context
import com.warattil.app.core.WarattilConstants.Mushaf
import kotlinx.coroutines.flow.first

// =============================================================================
// Data Models
// =============================================================================

data class PageContent(
    val pageNumber: Int,
    val ayahs    : List<Ayah>,
    val surahName: String,
    val juzNumber: Int
)

/**
 * A single Quran search hit, fully resolved to a Mushaf page number.
 *
 * The page is determined via [MetadataParser] (monotonic key law), NOT the
 * database `page` column.
 */
data class SearchResult(
    val pageNumber  : Int,
    val surahNumber : Int,
    val surahName   : String,
    val ayahNumber  : Int,
    val text        : String
)

// =============================================================================
// Repository
// =============================================================================

/**
 * QuranRepository — sole data-access gateway for Mushaf content.
 *
 * PAGING LAW (non-negotiable invariant):
 *   Page boundaries are derived EXCLUSIVELY from [MetadataParser].
 *   The database `page` column is NEVER used for boundary determination.
 *   Range queries use monotonic key: sura * 10000 + aya.
 */
class QuranRepository(context: Context) {

    // Two databases by design (2026-04-27):
    //   • QuranDatabase  — read-only Quran content shipped as an asset.
    //                      Uses createFromAsset + fallbackToDestructiveMigration
    //                      so a content refresh just bumps the version and
    //                      ships a new .db.  Loss of "user data" inside this
    //                      DB is acceptable because it doesn't HOLD user data.
    //   • UserDatabase   — bookmarks + wird state.  Persists across all
    //                      restarts and content refreshes.  Pre-fix, both
    //                      sets of entities lived in QuranDatabase, which
    //                      meant the destructive migration on the Quran
    //                      content side wiped the user state on every cold
    //                      start (asset DB has no room_master_table → Room
    //                      always schema-mismatched and re-imported the
    //                      empty asset).  Splitting fixes that.
    private val db       = QuranDatabase.getDatabase(context)
    private val quranDao = db.quranDao()
    private val userDb   = UserDatabase.getDatabase(context)
    private val userDao  = userDb.userDao()

    // -------------------------------------------------------------------------
    // Index maps — built ONCE lazily from MetadataParser (fast, in-memory)
    // -------------------------------------------------------------------------

    /**
     * Maps surah index (1–114) → the first Mushaf page that surah appears on.
     * Computed by scanning all 604 pages for the monotonic key of ayah 1 of
     * each surah — O(604 × 114) lightweight MetadataParser lookups, cached.
     */
    val surahStartPages: Map<Int, Int> by lazy {
        (1..114).associateWith { surah ->
            val firstKey = surah * 10000 + 1   // monotonic key for ayah 1
            findPageForKey(firstKey)
        }
    }

    /**
     * Maps juz number (1–30) → the first Mushaf page of that Juz.
     * Derived from [MetadataParser.getJuzBoundaries].
     */
    val juzStartPages: Map<Int, Int> by lazy {
        (1..30).associateWith { juz ->
            val (juzStartKey, _) = MetadataParser.getJuzBoundaries(juz)
            findPageForKey(juzStartKey)
        }
    }

    // -------------------------------------------------------------------------
    // Public API — Page Content
    // -------------------------------------------------------------------------

    /**
     * Fetches the full content for a given Mushaf [pageNumber] (1-indexed).
     *
     * @throws IllegalArgumentException if [pageNumber] is outside 1..604.
     */
    suspend fun getPageContent(pageNumber: Int): PageContent {
        require(pageNumber in 1..604) {
            "Invalid Mushaf page: $pageNumber. Must be in range 1–604."
        }

        val (startKey, endKey) = MetadataParser.getPageBoundaries(pageNumber)
        val ayahs = quranDao.getAyahsByMonotonicRange(startKey, endKey).first()
        val surahName = MetadataParser.getSuraName(ayahs.firstOrNull()?.surah ?: 1)
        val juzNumber = resolveJuzForPage(pageNumber)

        return PageContent(
            pageNumber = pageNumber,
            ayahs      = ayahs,
            surahName  = surahName,
            juzNumber  = juzNumber
        )
    }

    // -------------------------------------------------------------------------
    // Public API — Search
    //
    // Architecture (2026-04-27 pt. 4): normalization runs in Kotlin against
    // an in-memory cache, NOT in SQL.  The previous SQL strip chain blew
    // SQLite's parser stack at 45 nested REPLACEs (Android's bundled SQLite
    // has a fixed yyparse() stack that overflows around ~30+).  Even after
    // pruning to actually-occurring codepoints we'd be at 35, still risky.
    //
    // The Kotlin path:
    //   1. First search triggers a one-time fetch of all 6,236 ayahs
    //      (~1.5 MB read), each paired with its normalized form
    //      (diacritics stripped, dagger / subscript / wasla alefs folded
    //      to plain alef ا — see [normalizeForSearch]).
    //   2. Subsequent searches scan the cache with a simple `contains`
    //      check on the normalized form.  ~6k strings × ~150 chars is
    //      well under 50 ms even on a low-end device.
    //   3. Cache is rebuilt only on app restart (memory-resident; the
    //      Quran content doesn't change inside a session).
    //
    // Net result is faster than the SQL path AND covers KFGQPC v2.0's
    // full annotation glyph inventory without parser-stack risk.
    // -------------------------------------------------------------------------

    /**
     * Snapshot of one ayah with two pre-normalized variants — see
     * [normalizeForSearch] for the fold rules and [normalizeStripAlef]
     * for the strip variant.
     *
     * Why dual-form: the dagger alef (U+0670) is ambiguous in Imla'i.
     * In some words it represents a long-a that IS written as a full
     * alef in modern spelling (الكافرون → ٱلۡكَٰفِرُونَ).  In other
     * words the same glyph represents a long-a that's NOT written as
     * a full alef in modern spelling (الرحمن → ٱلرَّحۡمَٰنِ).  No single-
     * pass normalization can satisfy both — folding the dagger alef
     * to ا finds الكافرون but breaks الرحمن; stripping it does the
     * opposite.  Indexing BOTH variants and OR-ing the match covers
     * both spelling conventions at the cost of a second pass per
     * ayah.  Memory remains <4 MB total.
     */
    private data class SearchEntry(
        val ayah: Ayah,
        val foldedText:  String,   // dagger/subscript alef → ا (Imla'i with alef)
        val strippedText: String   // dagger/subscript alef removed (Imla'i without alef)
    )

    /** Lazily-built in-memory search index.  Null = not loaded yet. */
    @Volatile private var searchCache: List<SearchEntry>? = null
    private val searchCacheLock = Any()

    private suspend fun ensureSearchCache(): List<SearchEntry> {
        searchCache?.let { return it }
        val all = quranDao.getAllAyahsForSearch()
        val built = all.map { a ->
            val raw = a.text ?: ""
            SearchEntry(
                ayah          = a,
                foldedText    = normalizeForSearch(raw),
                strippedText  = normalizeStripAlef(raw)
            )
        }
        synchronized(searchCacheLock) {
            if (searchCache == null) searchCache = built
        }
        return searchCache ?: built
    }

    /**
     * Performs a diacritic-tolerant full-text search on the Quran text.
     *
     * Both the haystack (each ayah's body) and the needle (user query)
     * are normalized via [normalizeForSearch] — diacritics dropped,
     * dagger / subscript alefs folded to plain alef ا — so a user who
     * types «الكافرون» (Imla'i orthography) finds «ٱلۡكَٰفِرُونَ» in the
     * Mushaf (Uthmani orthography).
     *
     * Returns up to 100 results. Each result is resolved to its correct
     * Mushaf page via [MetadataParser] (NOT the DB `page` column).
     */
    suspend fun searchAyahs(query: String): List<SearchResult> {
        if (query.isBlank()) return emptyList()
        val needle = normalizeForSearch(query.trim())
        if (needle.isEmpty()) return emptyList()

        val cache = ensureSearchCache()
        val results = mutableListOf<SearchResult>()
        for (entry in cache) {
            if (results.size >= 100) break
            // Match if EITHER form contains the needle — covers both
            // Imla'i conventions for dagger-alef'd words.  See SearchEntry
            // doc for why dual-form indexing is necessary.
            val hit = entry.foldedText.contains(needle) ||
                      entry.strippedText.contains(needle)
            if (!hit) continue
            val a = entry.ayah
            val surah = a.surah ?: continue
            val aya   = a.ayah  ?: continue
            val text  = a.text  ?: continue
            val key   = surah * 10000 + aya
            results.add(
                SearchResult(
                    pageNumber  = findPageForKey(key),
                    surahNumber = surah,
                    surahName   = MetadataParser.getSuraName(surah),
                    ayahNumber  = aya,
                    text        = text
                )
            )
        }
        return results
    }

    /**
     * Bridges KFGQPC's **Uthmani** Mushaf orthography to the **Imla'i**
     * (modern) spelling that users type on their keyboards.  This is
     * the entire story behind the search-not-finding-words bugs the
     * Tanzil text didn't have: Tanzil ships Imla'i (matches what users
     * type), KFGQPC ships Uthmani (uses different glyphs for the same
     * sounds — dagger alef, alef-wasla, alef-maqsura, etc).
     *
     * Both the indexed text and the user's query run through this
     * function so they meet in a common normalized form.
     *
     * Folds applied (Uthmani → Imla'i / forgiving):
     *   • Alef variants  أ إ آ ٱ ٰ ٖ → ا   (hamza-on-alef + dagger +
     *                                       subscript + wasla all
     *                                       collapse to plain alef)
     *   • Alef-maqsura  ى → ي              (final ى often typed as ي)
     *   • Tatweel       ـ → ∅              (purely decorative stretch)
     *
     * Marks dropped entirely (don't change letter identity):
     *   • 0x064B-0x0652 — tanwin / harakat / shadda / sukun (standard)
     *   • 0x0653        — madda above
     *   • 0x0654-0x0655 — hamza above / below  (would otherwise leave
     *                                           bare alef inconsistent
     *                                           with the alef-folds
     *                                           above; dropping them
     *                                           here keeps the result
     *                                           coherent)
     *   • 0x0657-0x065F — extra vowel marks
     *   • 0x06D6-0x06ED — recitation pause + small-high-marks
     *                     (includes 0x06E1 = KFGQPC's sukun)
     *
     * Marks preserved on purpose: NONE — every Arabic combining mark
     * we see in the body is either a diacritic (drop) or a vowel-
     * length glyph that has an Imla'i equivalent (fold).
     *
     * Letters preserved on purpose:
     *   • 0x0624 ؤ — waw with hamza (semantically different from و
     *                in word identity; users typing the bare letter
     *                might miss matches but we accept that for
     *                precision)
     *   • 0x0626 ئ — yeh with hamza (same reasoning)
     *   • 0x0629 ة — ta marbuta (semantic feminine ending, distinct
     *                from ه in many contexts)
     */
    private fun normalizeForSearch(s: String): String {
        if (s.isEmpty()) return s
        val out = StringBuilder(s.length)
        for (c in s) {
            when (c.code) {
                // ── Letter folds: Uthmani → Imla'i ──────────────────────
                0x0622, 0x0623, 0x0625, 0x0671 -> out.append('ا')   // آ أ إ ٱ → ا
                0x0656, 0x0670                 -> out.append('ا')   // subscript / dagger alef → ا
                0x0649                         -> out.append('ي')   // alef-maqsura ى → ي
                0x0640                         -> Unit              // tatweel ـ → strip
                // ── Diacritic marks: drop entirely ──────────────────────
                in 0x064B..0x065F              -> Unit              // tashkeel + extra vowels
                in 0x06D6..0x06ED              -> Unit              // recitation marks (incl. 06E1 sukun)
                else                           -> out.append(c)
            }
        }
        return out.toString()
    }

    /**
     * Strip-alef variant of [normalizeForSearch] — same letter folds and
     * diacritic strips, BUT the dagger/subscript alefs are dropped
     * instead of folded to ا.  Used as the second indexed form per ayah
     * to satisfy users typing «الرحمن» (no alef between م and ن — the
     * conventional modern spelling) against KFGQPC's «ٱلرَّحۡمَٰنِ» (which
     * has a dagger alef).  See SearchEntry doc for why we index both.
     */
    private fun normalizeStripAlef(s: String): String {
        if (s.isEmpty()) return s
        val out = StringBuilder(s.length)
        for (c in s) {
            when (c.code) {
                // Same letter folds EXCEPT 0656 / 0670 — those are stripped here
                0x0622, 0x0623, 0x0625, 0x0671 -> out.append('ا')   // آ أ إ ٱ → ا
                0x0656, 0x0670                 -> Unit              // dagger / subscript alef → drop
                0x0649                         -> out.append('ي')   // alef-maqsura ى → ي
                0x0640                         -> Unit              // tatweel ـ → strip
                in 0x064B..0x065F              -> Unit              // tashkeel + extras
                in 0x06D6..0x06ED              -> Unit              // recitation marks
                else                           -> out.append(c)
            }
        }
        return out.toString()
    }

    // -------------------------------------------------------------------------
    // Public API — Bookmark / Preferences  (delegates to UserDao)
    //
    // 2026-04-27: switched from quranDao to userDao.  Bookmarks and wird
    // state now live in UserDatabase, which is NOT pre-populated from an
    // asset and does NOT use destructive migration.  Pre-fix, every cold
    // start triggered Room's destructive migration on QuranDatabase
    // (because the asset DB has no room_master_table) which silently
    // wiped these tables.  Splitting them into UserDatabase fixes the
    // restart-loses-everything bug Nasser reported.
    // -------------------------------------------------------------------------

    fun getBookmarksFlow() = userDao.getAllBookmarks()

    suspend fun saveBookmark(pageNumber: Int) =
        userDao.insertBookmark(Bookmark(pageNumber = pageNumber))

    suspend fun removeBookmark(pageNumber: Int) =
        userDao.deleteBookmark(Bookmark(pageNumber = pageNumber))

    suspend fun clearAllBookmarks() =
        userDao.deleteAllBookmarks()

    fun getUserPreferencesFlow() = userDao.getUserPreferences()

    suspend fun saveUserPreferences(prefs: UserPreferences) =
        userDao.saveUserPreferences(prefs)

    suspend fun getUserPreferences(): UserPreferences? =
        userDao.getUserPreferencesValue()

    // -------------------------------------------------------------------------
    // Private helpers
    // -------------------------------------------------------------------------

    /**
     * Returns the 1-indexed Mushaf page that contains [targetKey].
     * Scans all 604 pages once; MetadataParser boundaries are in-memory.
     */
    private fun findPageForKey(targetKey: Int): Int {
        for (page in 1..Mushaf.TOTAL_PAGES) {
            val (start, end) = MetadataParser.getPageBoundaries(page)
            if (targetKey in start..end) return page
        }
        return 1
    }

    private fun resolveJuzForPage(pageNumber: Int): Int {
        val (pageStartKey, _) = MetadataParser.getPageBoundaries(pageNumber)
        var resolved = 1
        for (juz in 1..30) {
            val (juzKey, _) = MetadataParser.getJuzBoundaries(juz)
            if (juzKey <= pageStartKey) resolved = juz else break
        }
        return resolved
    }
}