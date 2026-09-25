//
//  TafseerLookup.swift
//  Warattil
//
//  Ports app/src/main/java/com/warattil/app/data/TafseerLookup.kt to Swift.
//
//  WARATTIL — Tafseer Muyassar lookup (iOS port, 2026-04-27)
//
//  Sibling to GhareebLookup; identical singleton shape so reasoning about
//  the two reading-aid lookups is uniform.
//
//  Source data
//  -----------
//  KFGQPC «التفسير الميسر» v3, parsed by V3's tools/parse_tafseer.py
//  from the staged XML at pipeline_data/tafseer_v3/tafseerMouaser_v03.xml.
//  License already cleared with the body text + Ghareeb dictionary —
//  same KFGQPC origin, same EULA terms.
//
//  Asset shape:
//
//      { "1:1":  "أبتدئ قراءة القرآن باسم الله…<span class=\"aya\">ﵡ ٱللَّهِﵠ</span>…",
//        "2:18": "هم صُمٌّ عن سماع الحق…",
//        … }
//
//  Key format: `"<sura>:<aya>"` (Western digits).  Value: explanation prose
//  with embedded `<span class="aya">…</span>` markers around quoted Quran
//  fragments.  AyahMeaningsSheet's tafseer-tab renderer walks those span
//  tags at composition time to emit gold + bold runs for the quoted
//  Quran fragments — same approach Golden Quran uses to visually
//  distinguish the Quran quotations from the surrounding scholarly
//  gloss.
//
//  Loading model: the asset (~1.9 MB JSON) parses in <200 ms on first
//  access; the lookup is gated behind a long-press → 📖 → tab tap, so
//  this cost is off the home-screen hot path.
//

import Foundation

enum TafseerLookup {

    private static let assetName = "tafseer_muyassar"
    private static let assetExt  = "json"

    private static var cache: [AyahKey: String]?
    private static let lock = DispatchQueue(label: "com.warattil.tafseer.cache")

    /// Returns the tafseer string for a given ayah, or nil if absent.
    /// Every ayah in the Mushaf has an entry in the source so nil is
    /// defensive contract, not an expected outcome.
    static func text(sura: Int, aya: Int) -> String? {
        let map = loadIfNeeded()
        return map[AyahKey(sura: sura, aya: aya)]
    }

    private static func loadIfNeeded() -> [AyahKey: String] {
        return lock.sync {
            if let cached = cache {
                return cached
            }
            let parsed = parseAsset()
            cache = parsed
            return parsed
        }
    }

    private static func parseAsset() -> [AyahKey: String] {
        guard let url = Bundle.main.url(forResource: assetName, withExtension: assetExt) else {
            assertionFailure("tafseer_muyassar.json not in bundle Resources")
            return [:]
        }
        guard let data = try? Data(contentsOf: url) else {
            assertionFailure("tafseer_muyassar.json could not be loaded from \(url)")
            return [:]
        }
        guard
            let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: String]
        else {
            assertionFailure("tafseer_muyassar.json is not a [String: String]")
            return [:]
        }

        var out: [AyahKey: String] = [:]
        out.reserveCapacity(json.count)
        for (key, value) in json {
            guard let ayahKey = AyahKey(serialized: key) else { continue }
            guard !value.isEmpty else { continue }
            out[ayahKey] = value
        }
        return out
    }
}
