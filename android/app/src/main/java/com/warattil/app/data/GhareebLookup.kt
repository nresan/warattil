package com.warattil.app.data

import android.content.Context
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicReference

// =============================================================================
// GhareebLookup — in-memory cache of ghareeb.json shipped under assets/.
//
// Source data: KFGQPC «الميسر في غريب القرآن الكريم» — the Quranic rare-word
// dictionary.  Ingested into a flat JSON map by tools/parse_ghareeb.py:
//
//     { "1:7": [ ["أَنۡعَمۡتَ عَلَيۡهِمۡ", "مَنَنْتَ عليهم..." ], ... ], ... }
//
// Key format is `"<sura>:<aya>"` (Western digits).  Value is an ordered list
// of [phrase, meaning] pairs as they appear in the source — ordered so the
// UI renders them top-to-bottom in reading order.
//
// Loaded ONCE per process.  ~1.1 MB JSON parses in <100 ms on a Snapdragon
// 870, so we just read it eagerly on first lookup (no I/O on the home page
// path because the lookup is gated behind a long-press → menu tap).
// =============================================================================

/** Phrase + its plain-Arabic meaning, as they appear in the source. */
data class GhareebEntry(
    val phrase  : String,
    val meaning : String
)

object GhareebLookup {

    private const val ASSET_NAME = "ghareeb.json"

    /** Lazily-built map. AtomicReference for safe lazy-init across threads. */
    private val cache: AtomicReference<Map<Pair<Int, Int>, List<GhareebEntry>>?> =
        AtomicReference(null)

    /**
     * Returns the (phrase, meaning) entries for a given ayah, or an empty
     * list if no entries exist (~1100 ayahs are too plain to need them).
     * Safe to call from a Composable; the first invocation parses the JSON
     * synchronously (~100 ms on cold start), subsequent calls are O(1).
     */
    fun entriesFor(context: Context, sura: Int, aya: Int): List<GhareebEntry> {
        val map = cache.get() ?: loadAndCache(context)
        return map[sura to aya] ?: emptyList()
    }

    private fun loadAndCache(
        context: Context
    ): Map<Pair<Int, Int>, List<GhareebEntry>> {
        // Double-check: another thread may have populated cache while we
        // were waiting for our turn.
        cache.get()?.let { return it }

        val raw = context.assets.open(ASSET_NAME)
            .bufferedReader(Charsets.UTF_8)
            .use { it.readText() }
        val obj = JSONObject(raw)
        val out = HashMap<Pair<Int, Int>, List<GhareebEntry>>(obj.length())

        val keys = obj.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            val parts = key.split(':')
            if (parts.size != 2) continue
            val sura = parts[0].toIntOrNull() ?: continue
            val aya  = parts[1].toIntOrNull() ?: continue
            val arr  = obj.optJSONArray(key) ?: continue
            val list = ArrayList<GhareebEntry>(arr.length())
            for (i in 0 until arr.length()) {
                val pair = arr.optJSONArray(i) ?: continue
                if (pair.length() < 2) continue
                list.add(
                    GhareebEntry(
                        phrase  = pair.getString(0),
                        meaning = pair.getString(1)
                    )
                )
            }
            if (list.isNotEmpty()) {
                out[sura to aya] = list
            }
        }

        cache.compareAndSet(null, out)
        return cache.get() ?: out
    }
}
