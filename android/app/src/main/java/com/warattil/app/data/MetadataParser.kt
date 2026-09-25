package com.warattil.app.data

import android.content.Context
import android.util.Xml
import org.xmlpull.v1.XmlPullParser
import java.io.InputStream

data class SuraMetadata(
    val index: Int,
    val name: String,
    val ayas: Int,
    val start: Int
)

data class PageMetadata(
    val index: Int,
    val sura: Int,
    val aya: Int
)

data class JuzMetadata(
    val index: Int,
    val sura: Int,
    val aya: Int
)

/**
 * Single source of truth for Mushaf boundaries.  PAGING LAW: page / juz /
 * surah ranges come from this object, never the DB `page` column.
 *
 * Boundaries are expressed as monotonic keys: `sura * 10000 + aya`.  A
 * range `startKey..endKey` covers every valid (sura, aya) pair in that
 * window (skipping gaps where a surah has fewer ayahs than 10000 — which
 * is always, since the largest surah is 286 ayahs).
 *
 * The ayah-key enumeration helpers at the bottom ( [getPageAyahKeys],
 * [getSurahAyahKeys], [getJuzAyahKeys] ) walk over (startKey..endKey)
 * consulting [SuraMetadata.ayas] to produce the real set of ayah keys
 * without touching the DB — fast enough to call 604 times per heatmap
 * render.
 */
object MetadataParser {
    private val suras = mutableListOf<SuraMetadata>()
    private val pages = mutableListOf<PageMetadata>()
    private val juzs  = mutableListOf<JuzMetadata>()

    // Fast-lookup indices populated at load() — O(1) replacements for the
    // List.find(...) scans used elsewhere in the file.  Safe to access once
    // load() has run (which it has by the time any UI code calls in).
    private val suraByIndex: HashMap<Int, SuraMetadata> = HashMap(128)

    fun load(context: Context) {
        if (suras.isNotEmpty()) return

        val inputStream: InputStream = context.assets.open("quran_metadata_fixed.xml")
        val parser = Xml.newPullParser()
        parser.setFeature(XmlPullParser.FEATURE_PROCESS_NAMESPACES, false)
        parser.setInput(inputStream, null)

        var eventType = parser.eventType
        while (eventType != XmlPullParser.END_DOCUMENT) {
            val tagName = parser.name
            when (eventType) {
                XmlPullParser.START_TAG -> {
                    when (tagName) {
                        "sura" -> {
                            val index = parser.getAttributeValue(null, "index").toInt()
                            val name  = parser.getAttributeValue(null, "name")
                            val ayas  = parser.getAttributeValue(null, "ayas").toInt()
                            val start = parser.getAttributeValue(null, "start").toInt()
                            val meta  = SuraMetadata(index, name, ayas, start)
                            suras.add(meta)
                            suraByIndex[index] = meta
                        }
                        "page" -> {
                            val index = parser.getAttributeValue(null, "index").toInt()
                            val sura  = parser.getAttributeValue(null, "sura").toInt()
                            val aya   = parser.getAttributeValue(null, "aya").toInt()
                            pages.add(PageMetadata(index, sura, aya))
                        }
                        "juz" -> {
                            val index = parser.getAttributeValue(null, "index").toInt()
                            val sura  = parser.getAttributeValue(null, "sura").toInt()
                            val aya   = parser.getAttributeValue(null, "aya").toInt()
                            juzs.add(JuzMetadata(index, sura, aya))
                        }
                    }
                }
            }
            eventType = parser.next()
        }
        inputStream.close()
    }

    fun getPageBoundaries(pageIndex: Int): Pair<Int, Int> {
        val currentPage = pages.find { it.index == pageIndex } ?: return Pair(0, 0)
        val nextPage    = pages.find { it.index == pageIndex + 1 }

        val startKey = currentPage.sura * 10000 + currentPage.aya
        val endKey = if (nextPage != null) {
            // A page must end exactly one Ayah before the next page's start index
            val nextSura = nextPage.sura
            val nextAya  = nextPage.aya

            if (nextAya > 1) {
                nextSura * 10000 + (nextAya - 1)
            } else {
                // Next page starts at a new Sura, so this page ends at the last Ayah of the previous Sura
                val prevSuraIndex = nextSura - 1
                val prevSura      = suraByIndex[prevSuraIndex]
                if (prevSura != null) {
                    prevSuraIndex * 10000 + prevSura.ayas
                } else {
                    startKey // Fallback
                }
            }
        } else {
            // Last page ends at Sura 114, Aya 6
            114 * 10000 + 6
        }

        return Pair(startKey, endKey)
    }

    fun getJuzBoundaries(juzIndex: Int): Pair<Int, Int> {
        val currentJuz = juzs.find { it.index == juzIndex } ?: return Pair(0, 0)
        val nextJuz    = juzs.find { it.index == juzIndex + 1 }

        val startKey = currentJuz.sura * 10000 + currentJuz.aya
        val endKey = if (nextJuz != null) {
            val nextSura = nextJuz.sura
            val nextAya  = nextJuz.aya

            if (nextAya > 1) {
                nextSura * 10000 + (nextAya - 1)
            } else {
                val prevSuraIndex = nextSura - 1
                val prevSura      = suraByIndex[prevSuraIndex]
                if (prevSura != null) {
                    prevSuraIndex * 10000 + prevSura.ayas
                } else {
                    startKey
                }
            }
        } else {
            114 * 10000 + 6
        }

        return Pair(startKey, endKey)
    }

    fun getSuraName(index: Int): String = suraByIndex[index]?.name ?: ""
    fun getSuras(): List<SuraMetadata>   = suras

    // =========================================================================
    // Ayah-key → Page lookup  (Phase 1.1 — juz-completion flower placement)
    //
    //   The 604-page Mushaf has monotonically increasing page start-keys, so
    //   finding "which page contains this ayah" is a single linear scan.  We
    //   keep the scan here (not cached) because it runs at most 30 times when
    //   the heatmap recomposes (one per juz) — well below the threshold where
    //   a binary search or dense page-key array would be justified.
    // =========================================================================

    /**
     * 1-based page number that contains the given monotonic ayah key, or 0
     * if the key is invalid / pre-Fatiha.  Relies on the invariant that
     * [pages] is stored in index order with monotonically increasing
     * (sura * 10000 + aya) start keys — which the XML guarantees.
     */
    fun getPageForAyahKey(ayahKey: Int): Int {
        var found = 0
        for (p in pages) {
            val startKey = p.sura * 10000 + p.aya
            if (startKey <= ayahKey) found = p.index else break
        }
        return found
    }

    /**
     * Last Mushaf page that contains any ayah of juz [juzIndex] (1..30).
     * This is the cell in the 604-page heatmap where the juz-completion
     * flower is placed when the whole juz has been memorized.
     *
     * Note: when a juz boundary falls mid-page (e.g. juz N+1 starts partway
     * through page X), both juz N and juz N+1 can report page X.  The flower
     * still commemorates *juz completion*, not *page completion*, so this
     * is semantically correct — the flower on page X means "juz N is done,"
     * regardless of whether juz N+1's ayahs on that same page are memorized.
     */
    fun getJuzLastPage(juzIndex: Int): Int {
        val (_, endKey) = getJuzBoundaries(juzIndex)
        if (endKey == 0) return 0
        return getPageForAyahKey(endKey)
    }

    // =========================================================================
    // Ayah-key enumeration  (Phase 1 — Hifz ayah-atomic storage)
    //
    // These helpers produce the real, gap-free list of monotonic ayah keys
    // inside a page / surah / juz range.  They are pure in-memory walks over
    // boundary data + [SuraMetadata.ayas]; no DB access, safe to call from
    // the heatmap recomposition path.
    //
    // Monotonic key = sura * 10000 + aya.  We return them as Long so the
    // caller can store them in the ayah-set (Set<Long>) without coercion.
    // =========================================================================

    /**
     * Every ayah key that belongs to [pageIndex] (1-based, 1..604).  Empty
     * list for invalid pages.  Typical return size: 8 .. 20 keys.
     */
    fun getPageAyahKeys(pageIndex: Int): List<Long> {
        val (startKey, endKey) = getPageBoundaries(pageIndex)
        if (startKey == 0 && endKey == 0) return emptyList()
        return ayahKeysInRange(startKey, endKey)
    }

    /**
     * Every ayah key in surah [surahIndex] (1-based, 1..114).  Empty list
     * for invalid surahs.
     */
    fun getSurahAyahKeys(surahIndex: Int): List<Long> {
        val meta = suraByIndex[surahIndex] ?: return emptyList()
        val out = ArrayList<Long>(meta.ayas)
        val base = surahIndex.toLong() * 10000L
        for (aya in 1..meta.ayas) out.add(base + aya)
        return out
    }

    /**
     * Every ayah key in juz [juzIndex] (1-based, 1..30).  Empty list for
     * invalid juz numbers.
     */
    fun getJuzAyahKeys(juzIndex: Int): List<Long> {
        val (startKey, endKey) = getJuzBoundaries(juzIndex)
        if (startKey == 0 && endKey == 0) return emptyList()
        return ayahKeysInRange(startKey, endKey)
    }

    /** Total ayahs physically on [pageIndex] — fast (no allocation beyond
     *  the temporary list). */
    fun getPageAyahCount(pageIndex: Int): Int = getPageAyahKeys(pageIndex).size

    // ── Private — range walker ────────────────────────────────────────────
    //   Takes an inclusive `startKey..endKey` window and enumerates every
    //   real ayah key inside it.  The key invariant: when the range crosses
    //   a surah boundary, we cap the running surah at its declared ayah
    //   count (SuraMetadata.ayas) rather than at 10000 — surah 2 has 286
    //   ayahs, not 9999.

    private fun ayahKeysInRange(startKey: Int, endKey: Int): List<Long> {
        if (startKey > endKey) return emptyList()
        val startSura = startKey / 10000
        val startAya  = startKey % 10000
        val endSura   = endKey   / 10000
        val endAya    = endKey   % 10000

        // Rough upper bound to reduce list resizing: average page is ~10 ayahs,
        // juz is ~200.  Enough to skip most ArrayList grows without
        // over-allocating when pages are short (Surah 2 page 5 etc.).
        val out = ArrayList<Long>(32)

        for (sura in startSura..endSura) {
            val meta = suraByIndex[sura] ?: continue
            val from = if (sura == startSura) startAya else 1
            val to   = if (sura == endSura)   endAya   else meta.ayas
            if (from > to) continue
            val base = sura.toLong() * 10000L
            for (aya in from..to) out.add(base + aya)
        }
        return out
    }
}
