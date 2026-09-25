package com.warattil.app.ui

import androidx.compose.ui.graphics.Color

// =============================================================================
// WARATTIL V2 — Triple Aesthetic Engine
// Simple data-class approach: no Compose CompositionLocal overhead.
// Every composable receives a ThemeColors instance directly.
// =============================================================================

enum class AppTheme { HERITAGE, DARK, SEPIA }

/**
 * All colour slots a composable may need.
 * Momentum colours (progressLow/Mid/High/Beyond) are theme-invariant
 * by Rasm law — they only change meaning based on the Wird engine.
 */
data class ThemeColors(
    val background  : Color,
    val text        : Color,
    val accent      : Color,   // primary interactive / surah name colour
    val gold        : Color,   // borders, ayah-marker brackets, separator ✦
    val bannerBg    : Color,   // surah name-plate fill
    val divider     : Color,   // HorizontalDivider stroke
    // Momentum — invariant across all themes (30-40-30-Beyond law)
    val progressLow    : Color = Color(0xFFD32F2F), //  0–30 %  Red 700
    val progressMid    : Color = Color(0xFFFFA000), // 30–70 %  Amber 700
    val progressHigh   : Color = Color(0xFF1B5E20), // 70–100 % Mushaf Green
    val progressBeyond : Color = Color(0xFF03A9F4)  // >100 %   Sky Blue
)

// -----------------------------------------------------------------------------
// The three canonical themes
// -----------------------------------------------------------------------------

object WarattilTheme {

    /** Heritage Green / Cream — the founding aesthetic. */
    val Heritage = ThemeColors(
        background = Color(0xFFF5F5DC),   // Cream
        text       = Color(0xFF1A1A1A),   // Charcoal
        accent     = Color(0xFF1B5E20),   // Mushaf Green
        gold       = Color(0xFF996515),   // Deep Gold #996515
        bannerBg   = Color(0xFFF0EED8),
        divider    = Color(0x331B5E20)
    )

    /** Obsidian — true dark mode for night reading. */
    val Dark = ThemeColors(
        background = Color(0xFF121212),
        text       = Color(0xFFE8DCC8),   // warm parchment off-white
        accent     = Color(0xFF4CAF50),   // lighter green on dark surface
        gold       = Color(0xFFB8860B),   // darkened gold
        bannerBg   = Color(0xFF1E2A1E),
        divider    = Color(0x334CAF50)
    )

    /** Sepia — warm manuscript tone for extended sessions. */
    val Sepia = ThemeColors(
        background = Color(0xFFF4E6C8),   // warm parchment
        text       = Color(0xFF3B2A1A),   // dark umber
        accent     = Color(0xFF6B3A2A),   // terracotta
        gold       = Color(0xFF8B6914),   // aged gold
        bannerBg   = Color(0xFFEDD9B0),
        divider    = Color(0x336B3A2A)
    )

    fun of(theme: AppTheme): ThemeColors = when (theme) {
        AppTheme.HERITAGE -> Heritage
        AppTheme.DARK     -> Dark
        AppTheme.SEPIA    -> Sepia
    }
}
