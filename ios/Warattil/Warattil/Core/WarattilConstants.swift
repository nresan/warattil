//
//  WarattilConstants.swift
//  Warattil
//
//  WARATTIL V2 — Locked Manifest Constants (iOS port)
//
//  This file mirrors app/src/main/java/com/warattil/app/core/WarattilConstants.kt
//  from the Android project. Every hex value, point size, and string must match
//  Android exactly. Do not "modernise" values here — they are the cross-platform
//  source of truth the blueprint calls locked.
//

import SwiftUI

enum WarattilConstants {

    // =========================================================================
    // Heritage theme — default palette  (Cream / Charcoal / Mushaf Green)
    // =========================================================================
    enum Colors {
        static let cream         = Color(hex: 0xF5F5DC)  // page background
        static let charcoal      = Color(hex: 0x1A1A1A)  // body text
        static let mushafGreen   = Color(hex: 0x1B5E20)  // primary accent
        static let deepGold      = Color(hex: 0x996515)  // Islimi borders + ayah brackets
        static let bannerBG      = Color(hex: 0xF0EED8)  // surah name-plate fill
        static let divider       = Color(hex: 0x1B5E20, alpha: 0x33 / 255.0)  // 20 % green

        // ── Momentum bar — 30-40-30-Beyond law (theme-invariant) ─────────────
        static let progressLow    = Color(hex: 0xD32F2F)  // 0 – 30 %   Red 700
        static let progressMid    = Color(hex: 0xFFA000)  // 30 – 70 %  Amber 700
        static let progressHigh   = Color(hex: 0x1B5E20)  // 70 – 100 % Mushaf Green
        static let progressBeyond = Color(hex: 0x03A9F4)  // ≥ 100 %    Sky Blue
    }

    // =========================================================================
    // Dark theme (Obsidian)
    // =========================================================================
    enum DarkColors {
        static let background = Color(hex: 0x121212)
        static let text       = Color(hex: 0xE8DCC8)  // warm parchment off-white
        static let accent     = Color(hex: 0x4CAF50)  // lighter green on dark surface
        static let deepGold   = Color(hex: 0xB8860B)  // darkened gold for dark surface
        static let bannerBG   = Color(hex: 0x1E2A1E)
        static let divider    = Color(hex: 0x4CAF50, alpha: 0x33 / 255.0)
    }

    // =========================================================================
    // Sepia theme
    // =========================================================================
    enum SepiaColors {
        static let background = Color(hex: 0xF4E6C8)
        static let text       = Color(hex: 0x3B2A1A)
        static let accent     = Color(hex: 0x6B3A2A)
        static let deepGold   = Color(hex: 0x8B6914)
        static let bannerBG   = Color(hex: 0xEDD9B0)
        static let divider    = Color(hex: 0x6B3A2A, alpha: 0x33 / 255.0)
    }

    // =========================================================================
    // Typographic scale — LOCKED
    //
    // On iOS "pt" and Android "sp" are not strictly equivalent (sp scales with
    // user-font-size preference, pt only scales with Dynamic Type). For the
    // Quran body text we opt OUT of Dynamic Type scaling (see MushaFBody) —
    // the 48 pt landscape value is invariant. For chrome, we follow the same
    // numeric scale Android uses.
    // =========================================================================
    enum Typography {
        static let ayahFontLandscape:   CGFloat = 48   // landscape / wide-reading — invariant
        static let lineHeightLandscape: CGFloat = 72
        static let surahHeaderSize:     CGFloat = 20
        // 2026-05-03 — bumped 14 → 17 to match Android's JUZ_LABEL_SIZE (17.sp).
        // Android v3.0.0 settled on 17 as the natural anchor weight inside the
        // slim header strip — between the page-number badge (18) and the
        // overflow menu items (20). Used for «سورة X · الجزء N» in the header.
        static let juzLabelSize:        CGFloat = 17
        static let pageNumSize:         CGFloat = 18
        static let basmalaSize:         CGFloat = 18
        static let momentumMsgSize:     CGFloat = 13
    }

    // =========================================================================
    // Layout metrics — LOCKED
    // =========================================================================
    enum Layout {
        // 2026-04-21 — restored to 18 pt after Nasser flagged "text is
        // outside the screen boundary" on iPhone.
        //
        // The previous 12 pt gutter let wide glyph runs on dense pages
        // (ayahs that end on a long-tail letter like ن / ي / ى combined
        // with the ~1.55× rosette marker) sit flush against the device
        // bezel on iPhone 17 Pro. Android uses 16 dp; on iOS we go a
        // touch wider (18 pt) because (a) iOS doesn't apply the same
        // inset for the safe-area gutter that Compose's
        // `windowInsetsPadding(systemBars)` gives Android, and (b) the
        // rosette attachment's logical width is slightly wider than
        // Android's Unicode ﴿N﴾ run.
        //
        // The adaptive font engine automatically compensates — it'll
        // pick a slightly smaller body where needed so the visual
        // density stays close to Android's.
        static let pageHorizontalPadding: CGFloat = 18
        static let headerTopPadding:      CGFloat = 20
        static let dividerThickness:      CGFloat = 1
        static let barWidthFraction:      CGFloat = 0.88
        static let progressBarHeight:     CGFloat = 12
        static let progressBarRadius:     CGFloat = 6
    }

    // =========================================================================
    // Mushaf / Data
    // =========================================================================
    enum Mushaf {
        static let dbName        = "quran_v3.db"
        static let metadataAsset = "quran_metadata.xml"   // renamed from quran_metadata_fixed.xml on copy-in
        static let totalPages    = 604
        static let totalJuzaa    = 30
        static let totalSuwar    = 114
        static let totalAyahs    = 6236

        // Font PostScript names — confirm with Font Book on Mac after registering
        // the otf/ttf files. If these strings do not match the installed font's
        // PostScript name, SwiftUI silently falls back to system font.
        //
        // Body font is KFGQPCUthmanicScriptHAFS — same face the Android app
        // uses (app/.../core/WarattilConstants.kt :: FONT_UTHMANIC). Do NOT
        // substitute NotoNaskh / Amiri here: both have subtly different letter
        // shapes (Noto's modern geometry, Amiri's classical curves) that break
        // cross-platform parity. Stay on KFGQPC and solve any "looks too heavy"
        // complaint by adjusting weight/traits at the render site, not by
        // swapping the family.
        static let fontUthmanic  = "KFGQPCUthmanicScriptHAFS"
        static let fontFallback  = "Amiri-Regular"   // verified via fontTools name table (nameID 6)

        static let basmala       = "بِسۡمِ ٱللَّهِ ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ"

        static let surahTawbah   = 9  // no Basmala above this surah
        static let surahFatiha   = 1
    }

    // =========================================================================
    // Hifz (Memorization) — Phase 1: ayah as atomic unit
    //
    //   Mirrors app/src/main/java/com/warattil/app/core/WarattilConstants.kt
    //   Hifz object.  Storage primitive is the individual ayah, keyed by the
    //   paging-law monotonic formula  sura * 10000 + aya.  A page / surah /
    //   juz is "fully memorized" iff every ayah in its range is in the user's
    //   set.  Page density (memorized ayahs / total ayahs on page) drives
    //   the heatmap's 6-shade Mushaf-Green gradient.
    //
    //   Wire-format parity note:
    //     UserDefaults key names (prefAyahSet / prefPageCount / prefLegacyPages
    //     / prefLastTier) use the SAME string keys as Android's
    //     SharedPreferences so a future cloud-sync path could read both
    //     platforms off the same backing store.  Do not rename without
    //     updating Android simultaneously.
    // =========================================================================
    enum Hifz {
        // ── Reserved tint for anything Hifz-related ─────────────────────────
        static let hifzGold   = Color(hex: 0x996515)   // Deep Gold — icon / tier label
        static let hifzGoldBG = Color(hex: 0xFFF8E1)   // warm gold tint for badges

        // ── Heatmap density palette — desert → garden gradient ──────────────
        //   Untouched pages are Saharan-yellow; as memorization rises the tile
        //   warms through khaki, olive, seedling-green, and finally reaches
        //   full Mushaf Green at 100 %.  Pairs with the juz-completion flower
        //   overlay: two complementary signals (ground colour for density,
        //   flowers for juz completion).
        static let heatmapEmpty   = Color(hex: 0xE8D37A)  //   0 %    — Saharan yellow
        static let heatmapShade1  = Color(hex: 0xC8C258)  //   1-25 % — dry khaki
        static let heatmapShade2  = Color(hex: 0x98A841)  //  25-50 % — yellow olive
        static let heatmapShade3  = Color(hex: 0x5E8A34)  //  50-75 % — seedling green
        static let heatmapShade4  = Color(hex: 0x336B28)  //  75-99 % — mid-garden green
        static let heatmapFull    = Color(hex: 0x1B5E20)  // 100 %    — Mushaf Green

        // ── Juz-completion flower overlay ───────────────────────────────────
        //   Rendered on the last page of any fully-memorized juz.  Full
        //   Mushaf (30 juz) → exactly 30 flowers scattered across the
        //   garden.  Misaligned memorization earns zero flowers by design.
        static let flowerPetal    = Color(hex: 0xF5C14E)   // warm Islimi gold — petals
        static let flowerCenter   = Color(hex: 0xB8791A)   // deeper gold — stamens

        // ── Top-strip memorize icon tint states ─────────────────────────────
        static let stripAlphaEmpty:   Double = 0.30
        static let stripAlphaPartial: Double = 0.60
        static let stripAlphaFull:    Double = 1.00

        // ── UserDefaults keys ───────────────────────────────────────────────
        //   prefAyahSet     → [String] (Int64-as-string), authoritative store
        //   prefPageCount   → Int mirror of fully-memorized pages
        //   prefLegacyPages → pre-Phase-1 [String] (page numbers), migrated
        //                     on first launch and then removed.
        //   prefLastTier    → highest tier (0..6) the user has already seen
        //                     celebrated. Gate for HifzCelebrationDialog so
        //                     a crossing only fires once.  Never decreases.
        static let prefFile         = "warattil_prefs"
        static let prefAyahSet      = "memorized_ayahs"
        static let prefPageCount    = "memorized_pages_count"
        static let prefLegacyPages  = "memorized_pages"
        static let prefLastTier     = "hifz_last_celebrated_tier"

        // ── Tier table — matches Android exactly ────────────────────────────
        //    0  juz → tier 0 : ابدأ رحلة الحفظ      (no celebration)
        //    1  juz → tier 1 : براعم الحفظ
        //    3  juz → tier 2 : نبتة الحفظ
        //    7  juz → tier 3 : حافظ
        //   15  juz → tier 4 : حافظ متقدم
        //   25  juz → tier 5 : شارفت على الختم
        //   30  juz → tier 6 : حافظ للقرآن الكريم
        static func hifzTier(juzCount: Int) -> Int {
            switch juzCount {
            case 30...:      return 6
            case 25...29:    return 5
            case 15...24:    return 4
            case 7...14:     return 3
            case 3...6:      return 2
            case 1...2:      return 1
            default:         return 0
            }
        }

        /// Juz count required to reach the NEXT tier after `currentTier`,
        /// or nil if `currentTier` is already the top (6 = full hafiz).
        static func nextTierJuzThreshold(currentTier: Int) -> Int? {
            switch currentTier {
            case 0: return 1
            case 1: return 3
            case 2: return 7
            case 3: return 15
            case 4: return 25
            case 5: return 30
            default: return nil
            }
        }

        /// Arabic tier label for the dialog title + stats header.
        static func hifzTierLabel(tier: Int) -> String {
            switch tier {
            case 6: return "حافظ للقرآن الكريم"
            case 5: return "شارفت على الختم"
            case 4: return "حافظ متقدم"
            case 3: return "حافظ"
            case 2: return "نبتة الحفظ"
            case 1: return "براعم الحفظ"
            default: return "ابدأ رحلة الحفظ"
            }
        }

        // ── Monotonic key helpers ───────────────────────────────────────────
        //   Matches QuranDao.getAyahsByMonotonicRange formula exactly.
        //   Int64 (not Int) so a future JSON-blob migration has headroom.
        static func ayahKey(sura: Int, aya: Int) -> Int64 {
            Int64(sura) * 10000 + Int64(aya)
        }
        static func decodeSura(_ key: Int64) -> Int { Int(key / 10000) }
        static func decodeAya (_ key: Int64) -> Int { Int(key % 10000) }

        /// Maps a 0..1 density ratio to one of 6 heatmap shades.  Thresholds
        /// are open-on-the-right: a page with exactly one ayah done of 15
        /// (ratio ≈ 0.066) lands in SHADE_1, not EMPTY.  Only an untouched
        /// page (ratio == 0) reads as EMPTY.
        static func densityShade(_ ratio: Double) -> Color {
            switch ratio {
            case ...0:        return heatmapEmpty
            case ..<0.25:     return heatmapShade1
            case ..<0.50:     return heatmapShade2
            case ..<0.75:     return heatmapShade3
            case ..<1.0:      return heatmapShade4
            default:          return heatmapFull
            }
        }

        /// Tri-state alpha for the top-strip memorize icon.
        static func stripAlpha(_ ratio: Double) -> Double {
            if ratio <= 0      { return stripAlphaEmpty   }
            else if ratio < 1  { return stripAlphaPartial }
            else               { return stripAlphaFull    }
        }
    }
}

// =========================================================================
// Color(hex:) convenience — keeps the palette declarations readable.
// =========================================================================
extension Color {
    /// Build from a 24-bit RGB hex literal (e.g. 0xF5F5DC) and optional alpha.
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8)  & 0xFF) / 255.0
        let b = Double( hex        & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
