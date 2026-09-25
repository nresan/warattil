//
//  DailyAcknowledgementPill.swift
//  Warattil
//
//  Port of YesterdayAcknowledgementPill.kt to SwiftUI.
//
//  A calm one-shot greeting that surfaces when the reader returns after
//  a multi-day absence:
//
//      ┌──────────────────────────┐
//      │    أهلاً بعودتك            │
//      └──────────────────────────┘
//
//  Behaviour spec (locked, parity with Android V3):
//    • Fade-in 300 ms → dwell 5 s → fade-out 400 ms.
//    • `onAcknowledged` fires on first appearance, NOT on fade-out — so
//       toggling foreground/background during the dwell still counts as
//       acknowledged.  Mirrors Android's LaunchedEffect-on-show pattern.
//    • Non-interactive: no tap target, no close button.  Taps and swipes
//       pass through to the page underneath.
//    • Pinned anchor below the header overlay (top-center).  Header
//       padding handled by the caller (MushaFScreen places the overlay
//       after `.padding(.top, …)`).
//
//  Tone guardrail: «أهلاً بعودتك» — no "X days away", no "missed Y pages",
//  no streak language.  Nasser's mantra is no debt accounting.  See
//  feedback_warattil_no_debt_accounting + project_warattil_wird_requirements.
//

import SwiftUI

struct DailyAcknowledgementPill: View {

    let acknowledgement: MushaFViewModel.DailyAcknowledgement
    let theme:           ThemeColors
    let onAcknowledged:  () -> Void

    /// Three-phase animation state: hidden → fading-in (immediate) →
    /// dwelling → fading-out → hidden.  We collapse this to a single
    /// `opacity` + `.animation` driven by `isVisible`, with a separate
    /// `Task` scheduling the dwell + fade-out.
    @State private var isVisible: Bool = false

    /// Guards the fire-on-show callback against double-invocation when the
    /// view is recreated (SwiftUI re-runs `onAppear` on parent changes).
    @State private var didFireAcknowledgement: Bool = false

    var body: some View {
        Text(messageText)
            .font(.warattilChrome(size: 13, weight: .medium))
            .foregroundStyle(theme.text.opacity(0.85))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(theme.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(theme.gold.opacity(0.40), lineWidth: 1)
            )
            // tonalElevation 2 + shadowElevation 4 (Android) → soft shadow
            // that lifts the pill off the page body without dominating it.
            .shadow(color: Color.black.opacity(0.10), radius: 4, x: 0, y: 2)
            .environment(\.layoutDirection, .rightToLeft)
            // Non-interactive — taps fall through to the pager underneath.
            // `allowsHitTesting(false)` is the SwiftUI equivalent of
            // Android's "overlay above pager, no clickable modifier".
            .allowsHitTesting(false)
            .opacity(isVisible ? 1.0 : 0.0)
            .animation(
                isVisible
                    ? .easeIn(duration: 0.3)    // fade-in 300 ms
                    : .easeOut(duration: 0.4),  // fade-out 400 ms
                value: isVisible
            )
            .onAppear {
                // Fire the acknowledgement callback IMMEDIATELY on first
                // appearance so a foreground/background flicker during the
                // 5 s dwell still suppresses re-show on the next launch.
                if !didFireAcknowledgement {
                    didFireAcknowledgement = true
                    onAcknowledged()
                }
                // Drive the fade-in / dwell / fade-out timeline.
                isVisible = true
                Task {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    isVisible = false
                }
            }
    }

    /// Maps the acknowledgement variant to its locked Arabic copy.  Today
    /// the engine only emits `.welcomeBack`, but `.yesterdayRead` is
    /// covered exhaustively so adding it later is a one-line change.
    private var messageText: String {
        switch acknowledgement {
        case .welcomeBack:
            return "أهلاً بعودتك"
        case .yesterdayRead(let pagesRead, let pagesGoal):
            // Reserved — currently unreachable.  Wording matches Android
            // YesterdayAcknowledgementPill.kt for when it ships.
            if pagesRead >= pagesGoal && pagesGoal > 0 {
                return "أمس: أتممت الورد"
            }
            return "أمس: قرأت \(pagesRead.arabicDigits) من \(pagesGoal.arabicDigits) صفحة"
        }
    }
}
