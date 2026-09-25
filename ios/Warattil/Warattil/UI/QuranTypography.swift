//
//  QuranTypography.swift
//  Warattil
//
//  Ports the font-loading + Eastern-digit + basmala-stripping helpers from
//  app/src/main/java/com/warattil/app/ui/MushaFBody.kt into Swift utilities.
//
//  Scope for Phase 1 (thin vertical slice):
//    ✅ Int → Eastern Arabic digits  (١ ٢ ٣ ...)
//    ✅ String → strip Quranic annotations U+06D6–U+06ED
//    ✅ String → strip leading Basmala (for ayah-1 of non-Fatiha/Tawbah surahs)
//    ✅ QuranFontInfo + `quranFont()` helper with Uthmani / fallback / system
//       resolution, cached in a static for cheap reads on every page.
//
//  Deferred:
//    ❌ Adaptive font-size binary search (Phase 2 — render engine sophistication)
//
//  The Eastern-digit helper is CRITICAL — ayah markers and page numbers MUST
//  render as ١٢٣ never 123. Scholars will not forgive it, and the Locked
//  Manifest calls it out explicitly. Every user-visible number in the Mushaf
//  UI goes through this function.
//

import SwiftUI
import CoreText
#if canImport(UIKit)
import UIKit
#endif

// =============================================================================
// MARK: Eastern Arabic digits
// =============================================================================

extension Int {
    /// Convert to an Eastern Arabic digit string as a SINGLE unit.
    /// Pass the complete number — never split digits before calling.
    /// `123 → "١٢٣"`
    func toArabicDigits() -> String {
        let eastern: [Character] = ["٠","١","٢","٣","٤","٥","٦","٧","٨","٩"]
        return String(self).map { c in
            guard let d = c.wholeNumberValue, (0...9).contains(d) else { return c }
            return eastern[d]
        }.reduce(into: "") { $0.append($1) }
    }
}

// =============================================================================
// MARK: Quranic-annotation stripping
// =============================================================================

extension String {

    /// Strip Quranic annotation codepoints U+06D6–U+06ED so the text measurer
    /// sees clean base characters only. Matches Kotlin's `String.stripAnnotations()`.
    func stripAnnotations() -> String {
        var out = String()
        out.reserveCapacity(count)
        for scalar in unicodeScalars {
            if scalar.value >= 0x06D6 && scalar.value <= 0x06ED { continue }
            out.unicodeScalars.append(scalar)
        }
        return out
    }
}

// =============================================================================
// MARK: Basmala detection + prefix stripping
// =============================================================================
//
// Rules (Madinah-standard):
//   • Al-Fatiha (surah 1)  — Basmala IS ayah 1. Do NOT strip.
//   • At-Tawbah (surah 9)  — No Basmala at all.
//   • Every other surah    — Banner renders ornamental Basmala above ayah 1.
//                            Strip any Basmala prefix stored inside ayah 1.
//

/// The canonical Basmala reduced to its 19 base letters (no diacritics,
/// no spaces, Alif-wasla normalised to plain Alif).
private let BASMALA_BASE = "بسماللهالرحمنالرحيم"

private func isArabicBaseLetter(_ scalar: Unicode.Scalar) -> Bool {
    let code = scalar.value
    if code < 0x0600 || code > 0x06FF { return false }
    if (0x0610...0x061A).contains(code) { return false }  // Arabic marks
    if code == 0x0640                    { return false }  // TATWEEL
    if (0x064B...0x065F).contains(code)  { return false }  // harakat
    if code == 0x0670                    { return false }  // superscript alef
    if (0x06D6...0x06ED).contains(code)  { return false }  // Quranic annotations
    return true
}

extension String {

    /// True if this text begins with the Basmala, robust to diacritics,
    /// annotations, Alif-wasla, and TATWEEL stretch chars.
    func startsWithBasmala() -> Bool {
        var clean = String()
        clean.reserveCapacity(self.count)
        for scalar in self.unicodeScalars {
            if !isArabicBaseLetter(scalar) { continue }
            // Normalise Alif-wasla (U+0671) → plain Alif (U+0627)
            if scalar.value == 0x0671 {
                clean.unicodeScalars.append(Unicode.Scalar(0x0627)!)
            } else {
                clean.unicodeScalars.append(scalar)
            }
        }
        return clean.trimmingCharacters(in: .whitespaces).hasPrefix(BASMALA_BASE)
    }

    /// Remove the leading Basmala if present, keeping every original diacritic
    /// on whatever remains. Returns the text unchanged if it does not begin
    /// with Basmala. Used for ayah 1 of every surah EXCEPT Al-Fatiha & Tawbah.
    func stripBasmalaPrefix() -> String {
        let scalars    = Array(self.unicodeScalars)
        var cleaned    = String()
        var rawIdxMap: [Int] = []   // parallel to `cleaned`
        rawIdxMap.reserveCapacity(scalars.count)
        for (i, s) in scalars.enumerated() {
            if Character(s).isWhitespace                { continue }
            if !isArabicBaseLetter(s)                   { continue }
            let normalised = (s.value == 0x0671) ? Unicode.Scalar(0x0627)! : s
            cleaned.unicodeScalars.append(normalised)
            rawIdxMap.append(i)
        }
        guard cleaned.count >= BASMALA_BASE.count else { return self }
        guard cleaned.hasPrefix(BASMALA_BASE)     else { return self }

        // Cut at the character *after* the final base letter of the Basmala,
        // then skip any trailing combining marks / tatweels attached to it.
        var cutAt = rawIdxMap[BASMALA_BASE.count - 1] + 1
        while cutAt < scalars.count {
            let s = scalars[cutAt]
            if isArabicBaseLetter(s)             { break }
            if Character(s).isWhitespace         { break }
            if s.value < 0x0600 || s.value > 0x06FF { break }
            cutAt += 1
        }
        // Convert scalar index back to String index
        let startIndex = self.unicodeScalars.index(
            self.unicodeScalars.startIndex,
            offsetBy: cutAt
        )
        let remainder = String(self.unicodeScalars[startIndex...])
        return String(remainder.drop(while: \.isWhitespace))
    }
}

// =============================================================================
// MARK: Font resolution
// =============================================================================

/// Descriptor for the Quran body font, including whether we resolved the
/// Uthmani face or had to fall back to Amiri / system serif.
struct QuranFontInfo: Equatable {
    let postScriptName: String?   // nil → SwiftUI system
    let isUthmani:      Bool

    func font(size: CGFloat) -> Font {
        if let name = postScriptName {
            return .custom(name, size: size)
        }
        return .system(size: size, design: .serif)
    }
}

/// Resolve the best available Quran font. Caches the result on first call.
///
/// Resolution order:
///   1. KFGQPC Uthmanic Script HAFS (primary)
///   2. Amiri Regular                (fallback — also bundled)
///   3. System serif                 (last resort)
///
/// The PostScript names must match what Font Book reports after the .otf/.ttf
/// files are registered. We register them at launch via `FontRegistrar`
/// (see below) instead of `UIAppFonts` in Info.plist — the Xcode 16
/// synchronized-folder layout makes the in-bundle path brittle, so we let
/// Core Text scan the bundle at runtime.
@MainActor
func quranFont() -> QuranFontInfo {
    if let cached = _cachedQuranFont { return cached }

    let uthmanic = WarattilConstants.Mushaf.fontUthmanic
    let fallback = WarattilConstants.Mushaf.fontFallback

    let info: QuranFontInfo
    if isFontAvailable(uthmanic) {
        info = QuranFontInfo(postScriptName: uthmanic, isUthmani: true)
    } else if isFontAvailable(fallback) {
        info = QuranFontInfo(postScriptName: fallback, isUthmani: false)
    } else {
        info = QuranFontInfo(postScriptName: nil, isUthmani: false)
    }
    _cachedQuranFont = info
    return info
}

@MainActor private var _cachedQuranFont: QuranFontInfo?

// =============================================================================
// MARK: Chrome Arabic font — Amiri across all UI surfaces
// =============================================================================
//
// WHY THIS HELPER EXISTS
// ----------------------
// SF Arabic — the iOS default Arabic face — reads as a modern geometric
// sans-serif that clashes with WARATTIL's cream / charcoal / gold Mushaf
// palette. Every user-visible chrome label ("الجزء N", "السور", "الأجزاء",
// "إغلاق", the page-badge number, sheet titles, row text …) should render
// as classical Naskh so the chrome reads as "scholarly print" rather
// than "iOS system UI".
//
// Amiri is already bundled (Amiri-Regular + Amiri-Bold) and registered at
// launch via FontRegistrar. This helper centralises the point-size
// correction Amiri needs vs. SF Arabic — Amiri's x-height is visibly
// tighter, so at equal point sizes Amiri reads smaller. We add a small
// compensating bump so the visible weight matches what a SF Arabic caller
// would expect at the same number.
//
// USAGE
// -----
//   .font(.warattilChrome(size: 15, weight: .medium))
//
// The `weight` argument picks Amiri-Regular vs. Amiri-Bold (SwiftUI's
// `.custom()` does not synthesise weights for embedded fonts — only the
// registered cut is used). Regular / light / medium map to Amiri-Regular;
// semibold / bold / heavy / black map to Amiri-Bold.
//
// If Amiri isn't registered (shouldn't happen in a release build — the
// FontRegistrar asserts at launch), SwiftUI silently falls back to the
// system font, so the UI still renders rather than disappearing.
//
// Nasser 2026-04-21: rolled out globally after swapping the header Juz
// label + footer page badge to Amiri.
// =============================================================================

extension Font {
    /// Classical-Naskh chrome font for all WARATTIL UI surfaces.
    /// Maps `weight` onto Amiri's two registered cuts (Regular / Bold).
    static func warattilChrome(
        size:   CGFloat,
        weight: Font.Weight = .regular
    ) -> Font {
        // Amiri's tighter x-height means a +1 pt bump keeps the optical
        // weight roughly at parity with the SF Arabic originals these
        // call-sites used to pass. For very small sizes (< 12 pt) we
        // skip the bump — the bump would round up too aggressively and
        // chrome labels like footer chip text would look disproportionate.
        let adjusted = size < 12 ? size : size + 1

        let isBold: Bool
        switch weight {
        case .ultraLight, .thin, .light, .regular, .medium:
            isBold = false
        default:
            // .semibold, .bold, .heavy, .black
            isBold = true
        }

        let name = isBold ? "Amiri-Bold" : "Amiri-Regular"
        return .custom(name, size: adjusted)
    }
}

/// True if a PostScript name resolves to a registered font on the current run.
/// Uses UIFont → CTFont bridging so it works before any SwiftUI view has
/// tried (and silently failed) to render the name.
private func isFontAvailable(_ postScriptName: String) -> Bool {
    #if canImport(UIKit)
    return UIFont(name: postScriptName, size: 12) != nil
    #else
    return false
    #endif
}

// =============================================================================
// MARK: Runtime font registration
// =============================================================================

/// Registers every .otf / .ttf file in the main bundle with Core Text so
/// `UIFont(name:size:)` can resolve them by PostScript name. Called once
/// from `WarattilApp.bootstrap()` before the first view renders.
///
/// Why runtime registration instead of Info.plist `UIAppFonts`?
///   Xcode 16's `PBXFileSystemSynchronizedRootGroup` copies resources while
///   preserving folder hierarchy, so a font under `Resources/Fonts/` ends
///   up at a path like `Fonts/…otf` inside the app bundle. `UIAppFonts`
///   entries must match the bundle-relative path exactly — brittle and
///   invisible until launch. `CTFontManagerRegisterFontsForURL` takes the
///   URL we already have from `Bundle.main.urls(forResourcesWithExtension:)`
///   so layout doesn't matter.
///
/// Idempotent: a second call re-registers each URL; Core Text returns
/// `kCTFontManagerErrorAlreadyRegistered`, which we discard silently.
enum FontRegistrar {

    // Intentionally NOT `@MainActor`. CTFontManagerRegisterFontsForURL is
    // thread-safe (Apple docs "Core Text → Thread Safety"), and we call
    // this from `WarattilApp.init()` which has no guaranteed actor
    // isolation under Swift 6 strict concurrency. Keeping the function
    // nonisolated lets both call sites (app init + any future async path)
    // invoke it without `MainActor.assumeIsolated` gymnastics.
    static func registerBundledFonts() {
        // We ship 605 per-page QCF fonts (one per Mushaf page + QCF_BSML
        // for basmalas / surah-header ornaments) as `.ttf`.
        //
        // We used to ship them as `.woff2` and register WOFF2 via Core Text.
        // iOS 13+ supports WOFF2 in CTFontManagerRegisterFontsForURL, BUT we
        // observed a reproducible rendering gap on iPhone 17 Pro simulator:
        // the LAST glyph of every line on body pages (3-604) rendered as a
        // tofu rectangle, while Al-Fatiha (page 1) rendered fine. Swapping
        // the same fonts to native TTF resolved the issue entirely. See
        // 2026-04-20 investigation notes.
        //
        // WOFF2 is intentionally NOT in the extension list below. If the
        // bundle still contains `.woff2` duplicates (they only get purged
        // when manually removed from the Xcode file reference + the on-disk
        // Resources/Fonts/qcf/ directory), they are inert — Core Text will
        // never see them.
        for ext in ["otf", "ttf"] {
            guard let urls = Bundle.main.urls(
                forResourcesWithExtension: ext,
                subdirectory: nil
            ) else { continue }

            for url in urls {
                var error: Unmanaged<CFError>?
                _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
                // The only common error is kCTFontManagerErrorAlreadyRegistered
                // on re-entry (SwiftUI previews, state restoration). Ignore it.
            }
        }
    }
}

// =============================================================================
// MARK: QCF per-page font resolution
// =============================================================================
//
// The KFGQPC QCF (Quran Complex Font) system places each Madinah-Mushaf page's
// glyphs inside Private Use Area codepoints of a dedicated per-page font. The
// layout JSON (see tools/qcf/layout) tells us which PUA glyphs make up each
// line; to render them we need the correct PostScript name for page N.
//
// Every font in fonts/qcf/ is named deterministically:
//
//     QCF_P001.woff2  … QCF_P604.woff2   → PostScript `QCF_P001` … `QCF_P604`
//     QCF_BSML.woff2                     → PostScript `QCF_BSML`
//
// (Verified with fontTools against the nuqayah/qpc-fonts v1 WOFF2 build.)
//
// These helpers never resolve at compile time — they only build strings.
// Use `QCFFonts.uiFont(forPage:size:)` when you need the actual UIFont that
// `NSAttributedString` or `UILabel` can consume.

enum QCFFonts {

    /// The shared basmala / surah-header-ornament font.
    static let bsmlPostScriptName = "QCF_BSML"

    /// PostScript name of the body font for a given 1-based Mushaf page.
    /// Returns `"QCF_P001"` … `"QCF_P604"`.
    static func bodyPostScriptName(forPage page: Int) -> String {
        precondition((1...604).contains(page), "page out of range: \(page)")
        return String(format: "QCF_P%03d", page)
    }

    /// True if the per-page font for this page has been registered. Mostly
    /// useful for debug asserts during bring-up — in normal operation every
    /// page should be available after `FontRegistrar.registerBundledFonts()`
    /// runs at launch.
    static func bodyIsAvailable(forPage page: Int) -> Bool {
        #if canImport(UIKit)
        return UIFont(name: bodyPostScriptName(forPage: page), size: 12) != nil
        #else
        return false
        #endif
    }

    #if canImport(UIKit)
    /// UIFont for the body of page N. Falls back to the previously-registered
    /// page font on the rare chance Core Text hasn't finished registering
    /// (e.g. mid-launch), so the glyph area stays non-empty.
    static func uiFont(forPage page: Int, size: CGFloat) -> UIFont {
        if let f = UIFont(name: bodyPostScriptName(forPage: page), size: size) {
            return f
        }
        // graceful degradation — system font will render PUA as empty boxes,
        // but we do NOT want to crash a released build over a missing font.
        return UIFont.systemFont(ofSize: size)
    }

    /// UIFont for basmalas and the ornamental surah-header bands.
    static func uiFontBsml(size: CGFloat) -> UIFont {
        if let f = UIFont(name: bsmlPostScriptName, size: size) {
            return f
        }
        return UIFont.systemFont(ofSize: size)
    }
    #endif

    /// SwiftUI Font for the body of page N.
    static func font(forPage page: Int, size: CGFloat) -> Font {
        .custom(bodyPostScriptName(forPage: page), size: size)
    }

    /// SwiftUI Font for basmala / surah-header glyphs.
    static func fontBsml(size: CGFloat) -> Font {
        .custom(bsmlPostScriptName, size: size)
    }
}
