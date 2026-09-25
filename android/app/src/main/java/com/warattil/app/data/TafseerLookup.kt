package com.warattil.app.data

import android.content.Context
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicReference

// =============================================================================
// TafseerLookup — in-memory cache of tafseer_muyassar.json shipped under
// assets/.  Sibling to GhareebLookup; identical singleton shape so reasoning
// about lifecycle is uniform across the two reading-aid sources.
//
// Source: KFGQPC «التفسير الميسر» v3, parsed by tools/parse_tafseer.py from
// the staged XML at pipeline_data/tafseer_v3/tafseerMouaser_v03.xml (license
// already cleared with the body text + Ghareeb dictionary — same KFGQPC
// origin, same EULA terms).
//
// Asset shape:
//
//     { "1:1": "أبتدئ قراءة القرآن باسم الله…<span class=\"aya\">ﵡ ٱللَّهِﵠ</span>…",
//       "2:18": "هم صُمٌّ عن سماع الحق…",
//       … }
//
// Key format: `"<sura>:<aya>"` (Western digits).  Value: the explanation
// prose with embedded `<span class="aya">…</span>` markers around quoted
// Quran fragments.  Renderer (buildTafseerAttributed in AyahMeaningsSheet)
// walks those span tags at composition time to swap fonts on the quoted
// runs — same trick Golden Quran uses to visually distinguish the Quran
// quotations from the surrounding scholarly gloss.
//
// Loaded ONCE per process.  ~1.9 MB JSON parses in <200 ms on a Snapdragon
// 870; the lookup is gated behind a long-press → 📖 → tab tap, so the
// first-paint cost is not on the home page hot path.
// =============================================================================

object TafseerLookup {

    private const val ASSET_NAME = "tafseer_muyassar.json"

    /** Lazily-built map. AtomicReference for safe lazy-init across threads. */
    private val cache: AtomicReference<Map<Pair<Int, Int>, String>?> =
        AtomicReference(null)

    /**
     * Returns the tafseer string for a given ayah, or null if the ayah is
     * absent (shouldn't happen — every ayah in the Mushaf has an entry —
     * but the contract is defensive).  Safe to call from any thread; the
     * first invocation parses the JSON synchronously, subsequent calls
     * are O(1).
     */
    fun textFor(context: Context, sura: Int, aya: Int): String? {
        val map = cache.get() ?: loadAndCache(context)
        return map[sura to aya]
    }

    private fun loadAndCache(context: Context): Map<Pair<Int, Int>, String> {
        // Double-check: another thread may have populated cache while we
        // were waiting for our turn.
        cache.get()?.let { return it }

        val raw = context.assets.open(ASSET_NAME)
            .bufferedReader(Charsets.UTF_8)
            .use { it.readText() }
        val obj = JSONObject(raw)
        val out = HashMap<Pair<Int, Int>, String>(obj.length())

        val keys = obj.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            val parts = key.split(':')
            if (parts.size != 2) continue
            val sura = parts[0].toIntOrNull() ?: continue
            val aya  = parts[1].toIntOrNull() ?: continue
            val text = obj.optString(key, "")
            if (text.isBlank()) continue
            out[sura to aya] = text
        }

        cache.compareAndSet(null, out)
        return cache.get() ?: out
    }
}
