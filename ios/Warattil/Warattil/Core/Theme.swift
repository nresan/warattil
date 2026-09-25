//
//  Theme.swift
//  Warattil
//
//  Ports app/src/main/java/com/warattil/app/ui/MushaFTheme.kt to Swift.
//
//  WARATTIL V2 — Triple Aesthetic Engine
//
//  Design notes:
//  - Raw color literals live in WarattilConstants.Colors / DarkColors / SepiaColors
//    so that the cross-platform palette is declared in exactly one place.
//  - This file wires those literals into the three canonical themes the UI
//    layer will consume.
//  - Kotlin's `data class ThemeColors(...)` becomes a Swift `struct ThemeColors`.
//    Structs in Swift are value types by default — same semantics as the
//    Kotlin data class (immutable, copy-on-write).
//  - Kotlin's `object WarattilTheme { ... }` becomes a Swift caseless `enum`
//    with static members. It's the idiomatic Swift namespace pattern: no
//    instances can be created, and the members are reachable via dot syntax
//    the same way `WarattilTheme.Heritage` is on Android.
//
//  Momentum colours (progressLow/Mid/High/Beyond) are theme-invariant by
//  Rasm law — they only change meaning based on the Wird engine. They are
//  defaulted on the struct initialiser so callers don't need to pass them
//  unless a theme genuinely overrides them (no theme currently does).
//

import SwiftUI

// =============================================================================
// AppTheme — enum of the three canonical themes.
// =============================================================================

enum AppTheme: String, CaseIterable, Sendable {
    case heritage = "HERITAGE"
    case dark     = "DARK"
    case sepia    = "SEPIA"
}

// =============================================================================
// ThemeColors — all colour slots a view may need.
//
// Mirrors `data class ThemeColors(...)` in MushaFTheme.kt exactly. Field
// names match Android 1:1 so that a future refactor touches both platforms
// with the same diff.
// =============================================================================

struct ThemeColors: Equatable, Sendable {

    // --- Surface & text --------------------------------------------------------
    let background: Color
    let text:       Color
    let accent:     Color   // primary interactive / surah-name colour
    let gold:       Color   // borders, ayah-marker brackets, separator ✦
    let bannerBg:   Color   // surah name-plate fill
    let divider:    Color   // HorizontalDivider stroke

    // --- Momentum — invariant across all themes (30-40-30-Beyond law) ---------
    let progressLow:    Color
    let progressMid:    Color
    let progressHigh:   Color
    let progressBeyond: Color

    init(
        background: Color,
        text:       Color,
        accent:     Color,
        gold:       Color,
        bannerBg:   Color,
        divider:    Color,
        progressLow:    Color = WarattilConstants.Colors.progressLow,
        progressMid:    Color = WarattilConstants.Colors.progressMid,
        progressHigh:   Color = WarattilConstants.Colors.progressHigh,
        progressBeyond: Color = WarattilConstants.Colors.progressBeyond
    ) {
        self.background     = background
        self.text           = text
        self.accent         = accent
        self.gold           = gold
        self.bannerBg       = bannerBg
        self.divider        = divider
        self.progressLow    = progressLow
        self.progressMid    = progressMid
        self.progressHigh   = progressHigh
        self.progressBeyond = progressBeyond
    }
}

// =============================================================================
// WarattilTheme — namespace holding the three canonical palettes.
//
// Usage:
//     let colors = WarattilTheme.of(.heritage)
//     view.background(colors.background)
// =============================================================================

enum WarattilTheme {

    /// Heritage Green / Cream — the founding aesthetic.
    static let heritage = ThemeColors(
        background: WarattilConstants.Colors.cream,
        text:       WarattilConstants.Colors.charcoal,
        accent:     WarattilConstants.Colors.mushafGreen,
        gold:       WarattilConstants.Colors.deepGold,
        bannerBg:   WarattilConstants.Colors.bannerBG,
        divider:    WarattilConstants.Colors.divider
    )

    /// Obsidian — true dark mode for night reading.
    static let dark = ThemeColors(
        background: WarattilConstants.DarkColors.background,
        text:       WarattilConstants.DarkColors.text,
        accent:     WarattilConstants.DarkColors.accent,
        gold:       WarattilConstants.DarkColors.deepGold,
        bannerBg:   WarattilConstants.DarkColors.bannerBG,
        divider:    WarattilConstants.DarkColors.divider
    )

    /// Sepia — warm manuscript tone for extended sessions.
    static let sepia = ThemeColors(
        background: WarattilConstants.SepiaColors.background,
        text:       WarattilConstants.SepiaColors.text,
        accent:     WarattilConstants.SepiaColors.accent,
        gold:       WarattilConstants.SepiaColors.deepGold,
        bannerBg:   WarattilConstants.SepiaColors.bannerBG,
        divider:    WarattilConstants.SepiaColors.divider
    )

    /// Resolve a theme enum value to its ThemeColors palette.
    ///
    /// Mirrors `WarattilTheme.of(theme: AppTheme)` on Android.
    static func of(_ theme: AppTheme) -> ThemeColors {
        switch theme {
        case .heritage: return heritage
        case .dark:     return dark
        case .sepia:    return sepia
        }
    }
}
