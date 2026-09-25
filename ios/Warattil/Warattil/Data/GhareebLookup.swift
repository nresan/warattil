//
//  GhareebLookup.swift
//  Warattil
//
//  Ports app/src/main/java/com/warattil/app/data/GhareebLookup.kt to Swift.
//
//  WARATTIL — Ghareeb dictionary lookup (iOS port, 2026-04-27)
//
//  In-memory cache of ghareeb.json shipped under Resources/.  Mirror of
//  Android's GhareebLookup.kt so reasoning about the data layer is
//  uniform across the two platforms.
//
//  Source data
//  -----------
//  KFGQPC «الميسر في غريب القرآن الكريم» — the Quranic rare-word dictionary.
//  Ingested into a flat JSON map by V3's tools/parse_ghareeb.py:
//
//      { "1:7": [ ["أَنۡعَمۡتَ عَلَيۡهِمۡ", "مَنَنْتَ عليهم..."], ... ], ... }
//
//  Key format: `"<sura>:<aya>"` (Western digits).  Value: ordered list of
//  [phrase, meaning] pairs in source order (UI renders them top-to-bottom).
//
//  Loading model
//  -------------
//  The asset (~1.1 MB) is parsed once per process.  The lookup is gated
//  behind a long-press → 📖 → tab tap, so the first-paint cost is well
//  off the home-screen hot path.  Subsequent calls hit the cached map.
//
//  Thread safety
//  -------------
//  Swift's `actor` would be the modern choice, but every call site here
//  is on the main actor (the lookup feeds a SwiftUI sheet) and the parse
//  is fast enough that we don't need cross-actor isolation.  We use a
//  plain singleton with a private serial DispatchQueue to guard the
//  lazy-init handoff — same shape as `AtomicReference` on the JVM.
//

import Foundation

/// Phrase + plain-Arabic meaning, as they appear in the source.
struct GhareebEntry: Hashable {
    let phrase:  String
    let meaning: String
}

enum GhareebLookup {

    private static let assetName = "ghareeb"
    private static let assetExt  = "json"

    /// Lazily-built map.  Backed by a private queue for safe lazy-init.
    private static var cache: [AyahKey: [GhareebEntry]]?
    private static let lock = DispatchQueue(label: "com.warattil.ghareeb.cache")

    /// Returns the (phrase, meaning) entries for a given ayah, or an empty
    /// array if no entries exist (~1100 ayahs are too plain to need them).
    /// Safe to call from any context; the first invocation parses the JSON
    /// synchronously, subsequent calls are O(1) via the cached map.
    static func entries(sura: Int, aya: Int) -> [GhareebEntry] {
        let map = loadIfNeeded()
        return map[AyahKey(sura: sura, aya: aya)] ?? []
    }

    private static func loadIfNeeded() -> [AyahKey: [GhareebEntry]] {
        return lock.sync {
            if let cached = cache {
                return cached
            }
            let parsed = parseAsset()
            cache = parsed
            return parsed
        }
    }

    private static func parseAsset() -> [AyahKey: [GhareebEntry]] {
        guard let url = Bundle.main.url(forResource: assetName, withExtension: assetExt) else {
            assertionFailure("ghareeb.json not in bundle Resources")
            return [:]
        }
        guard let data = try? Data(contentsOf: url) else {
            assertionFailure("ghareeb.json could not be loaded from \(url)")
            return [:]
        }
        guard
            let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: [[String]]]
        else {
            assertionFailure("ghareeb.json is not a [String: [[String]]]")
            return [:]
        }

        var out: [AyahKey: [GhareebEntry]] = [:]
        out.reserveCapacity(json.count)

        for (key, pairs) in json {
            guard let ayahKey = AyahKey(serialized: key) else { continue }
            var list: [GhareebEntry] = []
            list.reserveCapacity(pairs.count)
            for pair in pairs {
                guard pair.count >= 2 else { continue }
                list.append(GhareebEntry(phrase: pair[0], meaning: pair[1]))
            }
            if !list.isEmpty {
                out[ayahKey] = list
            }
        }
        return out
    }
}

/// Compound key — `(sura, aya)`.  Hashable so it can power the cache map.
/// Defined here (not in a separate file) because it is shared with
/// TafseerLookup and is a value-only type with no behaviour beyond
/// serialisation.
struct AyahKey: Hashable {
    let sura: Int
    let aya:  Int

    /// Parses `"<sura>:<aya>"` (Western digits) — the wire format used by
    /// the JSON assets.  Returns nil for malformed input rather than
    /// crashing, so a corrupted asset degrades to "no entries" instead
    /// of an app crash.
    init?(serialized: String) {
        let parts = serialized.split(separator: ":")
        guard parts.count == 2,
              let s = Int(parts[0]),
              let a = Int(parts[1])
        else {
            return nil
        }
        self.sura = s
        self.aya  = a
    }

    init(sura: Int, aya: Int) {
        self.sura = sura
        self.aya  = aya
    }
}
