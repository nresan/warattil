package com.warattil.app.core

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * WARATTIL V2 — Locked Manifest Constants
 * Single Heritage Green/Cream theme.  Dark mode is a simple boolean overlay.
 */
object WarattilConstants {

    // =========================================================================
    // Light-Mode Palette  (Heritage Green / Cream)
    // =========================================================================
    object Colors {
        val CREAM        = Color(0xFFF5F5DC)   // page background
        val CHARCOAL     = Color(0xFF1A1A1A)   // body text
        val MUSHAF_GREEN = Color(0xFF1B5E20)   // primary accent
        val DEEP_GOLD    = Color(0xFF996515)   // Islimi borders + ayah brackets
        val BANNER_BG    = Color(0xFFF0EED8)   // surah name-plate fill
        val DIVIDER      = Color(0x331B5E20)   // separator lines

        // ── Momentum bar — 30-40-30-Beyond law (never overridden) ────────────
        val PROGRESS_LOW    = Color(0xFFD32F2F)  // 0 – 30 %   Red 700
        val PROGRESS_MID    = Color(0xFFFFA000)  // 30 – 70 %  Amber 700
        val PROGRESS_HIGH   = Color(0xFF1B5E20)  // 70 – 100 % Mushaf Green
        val PROGRESS_BEYOND = Color(0xFF03A9F4)  // ≥ 100 %    Sky Blue
    }

    // =========================================================================
    // Dark-Mode Overlay  (Charcoal / Warm Gold)
    // =========================================================================
    object DarkColors {
        val BACKGROUND = Color(0xFF121212)
        val TEXT       = Color(0xFFE8DCC8)   // warm parchment off-white
        val ACCENT     = Color(0xFF4CAF50)   // lighter green on dark surface
        val DEEP_GOLD  = Color(0xFFB8860B)   // darkened gold for dark surface
        val BANNER_BG  = Color(0xFF1E2A1E)
        val DIVIDER    = Color(0x334CAF50)
    }

    // =========================================================================
    // Typographic Scale — LOCKED
    // =========================================================================
    object Typography {
        val AYAH_FONT_LANDSCAPE   = 48.sp   // Elderly / landscape — invariant
        val LINE_HEIGHT_LANDSCAPE = 72.sp
        val SURAH_HEADER_SIZE     = 20.sp
        // Header strip — "سورة X · الجزء N" location label.  Bumped
        // 14sp → 17sp on 2026-04-27 (Nasser feedback) so a reader can
        // tell where they are at a glance without leaning in.  The
        // label now sits visually halfway between the page-number
        // badge (18sp) and the menu item labels (20sp), which feels
        // like the natural anchor weight inside the slim header strip.
        val JUZ_LABEL_SIZE        = 17.sp
        val PAGE_NUM_SIZE         = 18.sp
        val BASMALA_SIZE          = 18.sp
        val MOMENTUM_MSG_SIZE     = 13.sp
    }

    // =========================================================================
    // Layout Metrics — LOCKED
    // =========================================================================
    object Layout {
        val PAGE_HORIZONTAL_PADDING = 16.dp
        val HEADER_TOP_PADDING      = 20.dp
        val DIVIDER_THICKNESS       = 1.dp
        const val BAR_WIDTH_FRACTION = 0.88f
        val PROGRESS_BAR_HEIGHT     = 12.dp
        val PROGRESS_BAR_RADIUS     = 6.dp

        // ── Body breathing room above the momentum bar (PIPELINE #48) ────────
        //
        // The Scaffold's bottomBar inset already reserves the *measured*
        // footer height for the body, but the adaptive font engine in
        // MushaFBody.adaptiveFontSp underestimates rendered line height on
        // dense pages by a few px (Compose includeFontPadding + per-Text
        // ascender/descender padding the measurer doesn't fully model).  On
        // a Samsung S22 in portrait the cumulative undershoot is enough to
        // push the last line of an al-Baqarah-dense page behind the wird
        // bar.  iOS doesn't see this because UIKit's TextKit measures
        // closer to render.
        //
        // Adding 12 dp of explicit breathing pad inside the pager modifier
        // does two things at once:
        //   1. Shrinks BoxWithConstraints.maxHeight passed to adaptiveFontSp
        //      → the engine picks a body sp that fits in the smaller area.
        //   2. Leaves a visible cushion between the last text line and the
        //      momentum-bar motivation line so even sparse pages don't read
        //      "stuck to the chrome."
        //
        // 12 dp is the smallest value that consistently kept ayah 286 of
        // page 49 (al-Baqarah's longest dense page) clear on an S22; ≥ 8 dp
        // reads as breathing room visually without shrinking the body font
        // perceptibly on dense pages.
        // Bottom breathing room between the body content and the footer.
        // The adaptive font engine sizes content against
        //   availH = pagerHeight − BODY_BOTTOM_BREATHING
        // multiplied by a SAFETY factor of 0.97.  Bumped 12dp → 24dp on
        // 2026-04-27 (Nasser) because dual-banner pages (e.g. p.293 with
        // Al-Isra ending + Al-Kahf banner + basmala + ayah 1) clipped at
        // the bottom when the WirdResumeChip was visible.  Root cause: a
        // small banner/basmala underestimate (~8dp) plus the chip-induced
        // bottomBar growth left content slightly taller than the engine
        // predicted, and clipToBounds() chopped the last line.  An extra
        // 12dp universal cushion costs ~1sp average font reduction —
        // imperceptible — but absorbs any future similar measurement
        // shortfall without bespoke conditional logic.
        val BODY_BOTTOM_BREATHING   = 24.dp
    }

    // =========================================================================
    // Mushaf / Data
    // =========================================================================
    object Mushaf {
        const val DB_NAME        = "quran_v2.db"
        const val METADATA_ASSET = "quran_metadata_fixed.xml"
        const val TOTAL_PAGES    = 604
        const val TOTAL_JUZAA    = 30
        const val TOTAL_SUWAR    = 114
        const val TOTAL_AYAHS    = 6236
        // Upgraded 2026-04-24 — KFGQPC v0.09 → v2.0 (update 13).  New font
        // file is `kfgqpc_hafs_uthmanic_script.ttf` (single-piece, matches
        // the name the Complex uses in their own data packaging).  Glyph
        // fixes included: Baqarah 18 final-ya, Baqarah 72 فادارأتم, and
        // assorted smaller shape corrections.  License is the KFGQPC EULA
        // embedded in the font itself — Use/Copy/Distribute free of cost,
        // no modification, see project_warattil_wird_anchor and the
        // content-refresh notes.
        const val FONT_UTHMANIC  = "kfgqpc_hafs_uthmanic_script"
        const val FONT_FALLBACK  = "amiri_regular"
        const val BASMALA        = "بِسۡمِ ٱللَّهِ ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ"
        const val SURAH_TAWBAH   = 9
        const val SURAH_FATIHA   = 1
    }

    // =========================================================================
    // Hifz (Memorization)  — Phase 1: ayah as atomic unit
    //
    //   Storage primitive is now the individual ayah, keyed by the paging-law
    //   monotonic formula  sura * 10000 + aya.  A page / surah / juz is
    //   "fully memorized" iff every ayah in its range is in the user's set.
    //   A page's "density" is (memorized ayahs on page) / (total ayahs on
    //   page) and drives the heatmap's 6-shade Mushaf-Green gradient.
    //
    //   The primitive changed from Int page to Long ayah-key so that partial
    //   memorization (a few ayahs) has somewhere to live, and so that bulk
    //   gestures (mark a whole juz / a whole surah) can be stored at the
    //   same granularity without rounding losses.
    // =========================================================================
    object Hifz {
        // ── Reserved tint for anything Hifz-related ─────────────────────────
        val HIFZ_GOLD    = Color(0xFF996515)   // Deep Gold — icon / tier label
        val HIFZ_GOLD_BG = Color(0xFFFFF8E1)   // warm gold tint for badges

        // ── Heatmap density palette — desert → garden gradient ──────────────
        //   The page grid tells a "garden growing greener" story.  Untouched
        //   pages are Saharan-yellow, as if waiting for rain; as a user
        //   memorizes more of a page the tile warms toward khaki, then olive,
        //   then seedling-green, and finally reaches the full Mushaf Green at
        //   100 %.  The metaphor pairs with the juz-completion flower overlay
        //   (placed on the last page of any fully-memorized juz) to give the
        //   604-cell heatmap two complementary signals: ground colour for
        //   page density, flowers for juz completion.
        val HEATMAP_EMPTY   = Color(0xFFE8D37A)  //   0 %    — Saharan yellow
        val HEATMAP_SHADE_1 = Color(0xFFC8C258)  //   1-25 % — dry khaki
        val HEATMAP_SHADE_2 = Color(0xFF98A841)  //  25-50 % — yellow olive
        val HEATMAP_SHADE_3 = Color(0xFF5E8A34)  //  50-75 % — seedling green
        val HEATMAP_SHADE_4 = Color(0xFF336B28)  //  75-99 % — mid-garden green
        val HEATMAP_FULL    = Color(0xFF1B5E20)  // 100 %    — Mushaf Green

        // ── Juz-completion flower overlay ───────────────────────────────────
        //   Rendered on the last page of any fully-memorized juz.  Full
        //   Mushaf (30 juz memorized) therefore shows exactly 30 flowers
        //   scattered across the garden.  Misaligned memorization (e.g.
        //   pages 5-38 — more than a juz-worth but completing neither juz 1
        //   nor juz 2) earns zero flowers by design: the garden is greener
        //   but empty of blooms, which is the correct signal.
        val FLOWER_PETAL  = Color(0xFFF5C14E)   // warm Islimi gold — petals
        val FLOWER_CENTER = Color(0xFFB8791A)   // deeper gold — stamens

        // ── Top-strip memorize icon tint states ─────────────────────────────
        //   Mirrors the heatmap palette: a page that is partially memorized
        //   gives the top-strip glyph a warmer presence even before the
        //   page is fully done.
        const val STRIP_ALPHA_EMPTY   = 0.30f
        const val STRIP_ALPHA_PARTIAL = 0.60f
        const val STRIP_ALPHA_FULL    = 1.00f

        // ── SharedPreferences keys ──────────────────────────────────────────
        //   AYAH_SET   → StringSet<Long-as-string>, the authoritative store
        //   PAGE_COUNT → Int mirror of *fully*-memorized pages, for the
        //                HifzRevisionWorker cold path (no MetadataParser
        //                load needed to produce a count for the notification).
        //   LEGACY     → the pre-Phase-1 StringSet<Int-as-string> of pages;
        //                read once for migration, then deleted.
        const val PREF_FILE          = "warattil_prefs"
        const val PREF_AYAH_SET      = "memorized_ayahs"
        const val PREF_PAGE_COUNT    = "memorized_pages_count"
        const val PREF_LEGACY_PAGES  = "memorized_pages"
        /** Highest tier (0..6) the user has already been celebrated at.  Used
         *  to gate the HifzCelebrationDialog so a given threshold crossing
         *  only fires confetti once.  Never decreases — if a user clears ayahs
         *  and rebuilds, they don't re-celebrate old milestones.  (Losing
         *  and re-earning a milestone is an edge case; holding the line
         *  avoids accidental re-trigger loops.) */
        const val PREF_LAST_TIER     = "hifz_last_celebrated_tier"

        // ── Tier table ─────────────────────────────────────────────────────
        //   Scholarly progression from "starting" to "full hafiz".  The
        //   celebration dialog fires when the user crosses into any tier ≥ 1.
        //   Tier 0 is the default starting state — no celebration there.
        //
        //   Juz thresholds (inclusive):
        //     0  juz → tier 0 : ابدأ رحلة الحفظ
        //     1  juz → tier 1 : براعم الحفظ
        //     3  juz → tier 2 : نبتة الحفظ
        //     7  juz → tier 3 : حافظ
        //     15 juz → tier 4 : حافظ متقدم
        //     25 juz → tier 5 : شارفت على الختم
        //     30 juz → tier 6 : حافظ للقرآن الكريم
        //
        //   Kept as a single source of truth so HifzLogSheet and the
        //   celebration dialog agree on both thresholds and labels.  Any
        //   change to this table should update both surfaces.
        fun hifzTier(juzCount: Int): Int = when {
            juzCount >= 30 -> 6
            juzCount >= 25 -> 5
            juzCount >= 15 -> 4
            juzCount >= 7  -> 3
            juzCount >= 3  -> 2
            juzCount >= 1  -> 1
            else           -> 0
        }

        /** Juz count required to reach the NEXT tier after [currentTier],
         *  or null if [currentTier] is already the top (6 = full hafiz). */
        fun nextTierJuzThreshold(currentTier: Int): Int? = when (currentTier) {
            0 -> 1
            1 -> 3
            2 -> 7
            3 -> 15
            4 -> 25
            5 -> 30
            else -> null
        }

        /** Arabic tier label for dialog title + stats header. */
        fun hifzTierLabel(tier: Int): String = when (tier) {
            6 -> "حافظ للقرآن الكريم"
            5 -> "شارفت على الختم"
            4 -> "حافظ متقدم"
            3 -> "حافظ"
            2 -> "نبتة الحفظ"
            1 -> "براعم الحفظ"
            else -> "ابدأ رحلة الحفظ"
        }

        // ── Monotonic key helpers ───────────────────────────────────────────
        //   Matches the paging-law formula enforced in MetadataParser /
        //   QuranDao.getAyahsByMonotonicRange.  Using Long (not Int) because
        //   the set may carry up to 6236 entries and we want headroom for
        //   any future JSON-blob migration.
        fun ayahKey(sura: Int, aya: Int): Long =
            sura.toLong() * 10000L + aya.toLong()

        fun decodeSura(key: Long): Int = (key / 10000L).toInt()
        fun decodeAya (key: Long): Int = (key % 10000L).toInt()

        /**
         * Maps a 0 .. 1 density ratio to one of 6 heatmap shades.  Thresholds
         * are open-on-the-right: a page with exactly one ayah done out of 15
         * ( ratio = 0.066 ) lands in SHADE_1, not EMPTY.  Only an untouched
         * page ( ratio == 0 ) reads as EMPTY.
         */
        fun densityShade(ratio: Float): Color = when {
            ratio <= 0f    -> HEATMAP_EMPTY
            ratio <  0.25f -> HEATMAP_SHADE_1
            ratio <  0.50f -> HEATMAP_SHADE_2
            ratio <  0.75f -> HEATMAP_SHADE_3
            ratio <  1.00f -> HEATMAP_SHADE_4
            else           -> HEATMAP_FULL
        }

        /** Tri-state alpha for the top-strip memorize icon. */
        fun stripAlpha(ratio: Float): Float = when {
            ratio <= 0f   -> STRIP_ALPHA_EMPTY
            ratio <  1.0f -> STRIP_ALPHA_PARTIAL
            else          -> STRIP_ALPHA_FULL
        }
    }
}
