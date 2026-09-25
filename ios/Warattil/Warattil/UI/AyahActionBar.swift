//
//  AyahActionBar.swift
//  Warattil
//
//  Ports app/src/main/java/com/warattil/app/ui/AyahActionBar.kt to Swift.
//
//  WARATTIL V2 — Long-press action bar (iOS port, 2026-04-21)
//
//  Why this file exists
//  --------------------
//  On Android the Mushaf long-press UX is a floating pill — Copy / Share /
//  Close — pinned under the header strip. The earlier iOS build used a
//  SwiftUI `.contextMenu` attached to each AyahBlock, which is iOS-idiomatic
//  but diverges visually from Android. Nasser's directive has been "match
//  Android exactly"; this component brings the visual language in line.
//
//  Layout (matches AyahActionBar.kt lines 144-222)
//  -----------------------------------------------
//  • Capsule shape (24 pt corner radius)
//  • Cream background (theme.background)
//  • Mushaf-Green icon tint (theme.accent); Close is .65 alpha to read as
//    secondary.
//  • Deep-Gold 1 pt border at 45 % alpha
//  • Gold hairline (│) separators at 55 % alpha between Copy/Share and
//    Share/Close
//  • 8 pt shadow, 0.15 opacity
//
//  Terminology note — "نقل" not "نسخ"
//  ---------------------------------
//  The Arabic verb «نَسَخَ» is a reserved term in Islamic sciences: it names
//  the abrogation doctrine (الناسخ والمنسوخ). A copy-to-clipboard toast that
//  reads «نُسخت الآية» invites the wrong reading in a Mushaf app, so the
//  toast text is «نُقلت إلى الحافظة» (ن-ق-ل root — neutral, technology-
//  appropriate). The copy button's accessibility label is "نقل الآية" for
//  the same reason. The visible button label "نسخ" is a compromise kept for
//  recognisability — most iOS users scan for that glyph in Arabic locales.
//
//  Share payload
//  -------------
//  The host view passes in a pre-formatted share string. The single canonical
//  formatter lives in `ShareUtil.formatAyahForShare` so every share surface
//  (this bar, a future multi-ayah range share, the overflow menu) produces
//  byte-identical output. Do NOT re-implement the formatter here.
//
//  Toast
//  -----
//  SwiftUI has no native toast equivalent to Android's `Toast.makeText`. The
//  AyahToast struct below is a lightweight reimplementation — a capsule with
//  the same border treatment as the action bar itself, auto-dismissed by the
//  caller after 1.8 s.
//
//  Used by
//  -------
//  • MushaFPageView.PageBody — overlays this bar at top when an ayah is
//    selected via long-press.
//

import SwiftUI
import UIKit

// =============================================================================
// MARK: - AyahActionBar — the floating pill
// =============================================================================

/// Floating action bar shown when the user long-presses an ayah. Kept visually
/// minimal — only the actions whose backing subsystems exist on iOS today:
/// Memorize (Hifz toggle) / Copy / Share / Close. Bookmark-per-ayah, Play,
/// Note will arrive with their respective engines.
///
/// Order (inside the RTL ancestor, so first child lands on the visual RIGHT):
/// Memorize · Copy · Share · Close — same reading order as Android's
/// AyahActionBar (V3).
struct AyahActionBar: View {

    let theme:     ThemeColors
    let shareText: String
    let subject:   String

    /// Current memorization state for the selected ayah.  Drives the تلوين of
    /// the leading Hifz toggle — full gold when memorised, dim gold when not.
    /// For range selections this reflects the START ayah; the toggle still
    /// fires against the start ayah only so users don't inadvertently flip
    /// memorisation state across a multi-ayah block.
    let isMemorized:       Bool
    /// Fires when the Hifz toggle is tapped.  Caller is expected to mutate
    /// the shared ayah-set (viewModel.toggleAyah) but NOT dismiss the bar —
    /// Android intentionally keeps the pill visible after a memorize tap so
    /// the user can verify the glyph state before moving on.
    let onToggleMemorize:  () -> Void

    let onCopy:    () -> Void
    let onDismiss: () -> Void

    // MARK: Range controls — multi-ayah share (BLUEPRINT §11.3)
    //
    // Two plus/minus chips live between Memorize and Copy: "أضف آية" grows
    // the selection forward by one ayah, "آية أقل" shrinks it back toward
    // the start.  Disabled state uses 35 % accent alpha — same opacity we
    // apply to the Close icon's secondary treatment.
    //
    // When BOTH callbacks are nil the range UI is suppressed entirely — the
    // pill renders in its classic four-button layout so callers that don't
    // support range selection (e.g. future overflow menus) aren't forced
    // to stub the flags.
    //
    // We gate on a single `supportsRange` computed property so the visual
    // invariant "range chips appear as a pair, never alone" is enforced at
    // the type level.

    /// Called when the reader taps "أضف آية".  Caller is responsible for
    /// computing the new end ayah (usually `currentEnd + 1`, bounded by the
    /// surah's last ayah on the page) and mutating the selection.
    let onExtendForward:   (() -> Void)?
    /// Called when the reader taps "آية أقل".  Caller should shrink the
    /// range back by one, never below the start ayah (use the returned
    /// `canShrink` flag to disable the button at the floor).
    let onShrinkBackward:  (() -> Void)?
    /// Whether the "أضف آية" chip is tappable.  False when the range already
    /// ends at the surah's last ayah visible on the current page.
    let canExtendForward:  Bool
    /// Whether the "آية أقل" chip is tappable.  False when the range is
    /// already a single ayah (endAyah == ayah).
    let canShrinkBackward: Bool

    /// Optional — when non-nil, a 📖 book button appears between the range
    /// chips (or the Memorize toggle) and Copy.  Tap fires the callback,
    /// which the host typically uses to present `AyahMeaningsSheet` for the
    /// currently-selected ayah (Ghareeb + Tafseer).  Mirrors V3 Android's
    /// `onOpenMeanings` parameter on AyahActionBar.kt.  When nil the button
    /// is suppressed entirely so existing callers don't need to stub it.
    /// Placed last in the field list (after the range params) so the
    /// memberwise initialiser argument order matches the call site at
    /// MushaFPageView's PageBody.
    let onOpenMeanings: (() -> Void)?

    private var supportsRange: Bool {
        onExtendForward != nil && onShrinkBackward != nil
    }

    /// Haptic feedback on button taps — the Android build uses HapticFeedback
    /// inside each IconButton's onClick. We match that feel on iOS via a
    /// pre-prepared UIImpactFeedbackGenerator (light style).
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        HStack(spacing: 2) {
            // ── Memorize toggle ───────────────────────────────────────────────
            // First action in the pill: Hifz toggle.  Uses the same
            // `LawhHifzIcon` glyph as the header strip so a user who has
            // learned the strip's meaning recognises this action instantly.
            // Tint hops between gold-full (memorized) and dim gold (not yet)
            // — mirrors WarattilConstants.Hifz.stripAlphaEmpty on Android.
            // We intentionally do NOT dismiss the pill on toggle: users often
            // want to verify the glyph state before moving on, and a
            // self-dismissing toggle makes that impossible.
            Button {
                haptic.impactOccurred()
                onToggleMemorize()
            } label: {
                LawhHifzIcon(
                    size: 22,
                    tint: isMemorized
                        ? WarattilConstants.Hifz.hifzGold
                        : WarattilConstants.Hifz.hifzGold.opacity(
                            WarattilConstants.Hifz.stripAlphaEmpty
                          )
                )
                .frame(width: 44, height: 44)
            }
            .accessibilityLabel(isMemorized ? "إلغاء تعليم الحفظ" : "تعليم محفوظ")

            hairline

            // ── Range controls (optional) ─────────────────────────────────────
            // Plus/minus chip pair for extending the selection to a contiguous
            // multi-ayah range.  BLUEPRINT §11.3 — share multiple ayahs as one
            // quote.  The pair renders only when the caller opts in (both
            // closures non-nil); when suppressed the pill collapses back to
            // its classic Memorize · Copy · Share · Close layout.
            //
            // Disabled state: 35 % accent alpha and `.disabled(true)` so the
            // chip still reserves space (stable layout while a user extends
            // to the page boundary) but no longer reacts to taps.
            if supportsRange {
                Button {
                    haptic.impactOccurred()
                    onShrinkBackward?()
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(
                            theme.accent.opacity(canShrinkBackward ? 1.0 : 0.35)
                        )
                        .frame(width: 36, height: 44)
                }
                .disabled(!canShrinkBackward)
                .accessibilityLabel("إنقاص آية")

                Button {
                    haptic.impactOccurred()
                    onExtendForward?()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(
                            theme.accent.opacity(canExtendForward ? 1.0 : 0.35)
                        )
                        .frame(width: 36, height: 44)
                }
                .disabled(!canExtendForward)
                .accessibilityLabel("أضف آية")

                hairline
            }

            // ── Meanings (📖) ─────────────────────────────────────────────────
            // Optional — only renders when [onOpenMeanings] is wired by the
            // caller.  Opens AyahMeaningsSheet anchored at the selected ayah
            // (Ghareeb default tab + Tafseer second tab).  The bar itself
            // doesn't dismiss; users typically want to glance at a meaning
            // and come back to copy / share / extend the range.
            if let onOpenMeanings = onOpenMeanings {
                Button {
                    haptic.impactOccurred()
                    onOpenMeanings()
                } label: {
                    // Meanings icon (parity with Android task #55 — Material
                    // MenuBook → AutoStories swap).  AutoStories on Android
                    // is an open-book-with-illustration glyph; the closest
                    // SF Symbol with the same "open volume / story" reading
                    // is `books.vertical` (a small stack with a leading
                    // open spine).  Reads as "look it up in references"
                    // rather than the previous solid `book` which felt too
                    // close to the bookmark glyph in the same toolbar.
                    Image(systemName: "books.vertical")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(theme.accent)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("معاني الآية")

                hairline
            }

            // ── Copy ──────────────────────────────────────────────────────────
            Button {
                haptic.impactOccurred()
                onCopy()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(theme.accent)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("نقل الآية")

            hairline

            // ── Share ─────────────────────────────────────────────────────────
            // SwiftUI ShareLink wraps UIActivityViewController declaratively.
            // We can't programmatically "trigger" a ShareLink, but we CAN use
            // it as the button itself — passing a custom label so the visual
            // matches the other buttons. `subject` lets mail / message apps
            // populate their subject field without cluttering the body.
            ShareLink(
                item: shareText,
                subject: Text(subject)
            ) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(theme.accent)
                    .frame(width: 44, height: 44)
            }
            .simultaneousGesture(TapGesture().onEnded {
                haptic.impactOccurred()
                // Dismiss the pill as soon as Share fires — matches Android
                // where `shareAyahText` is followed by `onDismiss()`. The
                // system share sheet remains presented because it's owned by
                // UIKit, not by this view's lifecycle.
                onDismiss()
            })
            .accessibilityLabel("مشاركة الآية")

            hairline

            // ── Close ─────────────────────────────────────────────────────────
            // Rendered at 65 % accent alpha so it reads as a secondary
            // affordance, not a peer to the primary actions.
            Button {
                haptic.impactOccurred()
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(theme.accent.opacity(0.65))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("إغلاق")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(theme.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(theme.gold.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 2)
    }

    /// Gold hairline separator — echoes the divider treatment used elsewhere
    /// (About / Usage Guide sheets) and matches the Android `│` separator
    /// glyph drawn in AyahActionBar.kt lines 182-186 / 201-205.
    private var hairline: some View {
        Text("│")
            .font(.system(size: 20))
            .foregroundStyle(theme.gold.opacity(0.55))
    }
}

// =============================================================================
// MARK: - AyahToast — "نُقلت إلى الحافظة" clipboard confirmation
// =============================================================================

/// Minimal toast used to confirm the copy action. Auto-dismissal is owned by
/// the caller (typically a delayed Task in PageBody) so this view stays pure
/// presentation — it does not hold its own timer.
struct AyahToast: View {

    let text:  String
    let theme: ThemeColors

    var body: some View {
        Text(text)
            .font(.warattilChrome(size: 14, weight: .medium))
            .foregroundStyle(theme.text)
            .multilineTextAlignment(.center)
            .environment(\.layoutDirection, .rightToLeft)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(theme.background)
            )
            .overlay(
                Capsule().stroke(theme.gold.opacity(0.45), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 2)
    }
}

// =============================================================================
// MARK: - AyahSelection — identifiable selection token
// =============================================================================

/// Lightweight selection descriptor.  Having it be `Equatable` + `Identifiable`
/// lets SwiftUI's `.animation(_:, value:)` detect changes and drive the
/// show/hide transition on the floating bar.  A (surah, ayah) tuple wouldn't
/// conform to these protocols.
///
/// The selection now carries an *end ayah* so callers can represent a
/// contiguous RANGE (ayah … endAyah) within the same surah.  Single-ayah
/// selections keep `endAyah == ayah`, which the initialiser defaults to —
/// every call site that wrote `AyahSelection(surah: s, ayah: n)` keeps
/// working unchanged, and the new range share path lives behind an optional
/// argument on the initialiser.
///
/// `id` is derived from the START ayah (same monotonic key as Paging Law)
/// so extending the range does NOT invalidate the identifier — important for
/// `.animation(value:)` which would otherwise treat "extend by one" as a
/// completely new selection and replay the enter transition.
struct AyahSelection: Equatable, Identifiable {
    let surah:   Int
    let ayah:    Int      // Start ayah — kept named `ayah` for call-site compat.
    var endAyah: Int      // End ayah (≥ ayah).  Defaults to `ayah` for singles.

    init(surah: Int, ayah: Int, endAyah: Int? = nil) {
        self.surah   = surah
        self.ayah    = ayah
        self.endAyah = max(endAyah ?? ayah, ayah)
    }

    var id: Int { surah * 10_000 + ayah }

    /// True when the selection spans two or more ayahs.  Drives pluralisation
    /// in the action-bar labels and the "الآيات m–n" citation branch inside
    /// ShareUtil.formatAyahRangeForShare.
    var isRange: Bool { endAyah > ayah }
}
