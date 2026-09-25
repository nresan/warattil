//
//  ToastCenter.swift
//  Warattil
//
//  Lightweight Android-Toast equivalent for iOS — mirrors Android's
//  `Toast.makeText(...).show()` API surface so the cross-platform
//  ViewModel code can call `ToastCenter.show(...)` from anywhere
//  without knowing about SwiftUI views.
//
//  Implementation: a global `@Published` String? on a singleton.
//  Any view that wants to render toasts attaches a `.toastOverlay()`
//  modifier; the modifier observes the singleton and renders a brief
//  bottom-anchored capsule when the value is non-nil, then clears
//  itself after ~1.8s (matching Android's Toast.LENGTH_SHORT).
//
//  Usage:
//    From a ViewModel:  ToastCenter.show("تم ضبط الورد")
//    From a host view:  .toastOverlay(theme: theme)
//
//  Why a singleton: ViewModels in this codebase don't hold a reference
//  to any SwiftUI binding, so the only realistic way to trigger UI
//  feedback from VM code is via a process-global observable.
//

import SwiftUI

/// Process-global toast queue.  Singleton; views observe via
/// `.toastOverlay()` and ToastCenter.show pushes a message.
@Observable
final class ToastCenter {

    static let shared = ToastCenter()

    /// Currently-visible message, or nil when no toast is showing.
    /// Views read this via @Bindable / observation tracking.
    private(set) var current: String?

    private var dismissTask: Task<Void, Never>?

    private init() {}

    /// Push a toast.  Replaces any in-flight toast and resets the
    /// auto-dismiss timer.  Safe to call from any actor — bounces to
    /// the main actor before mutating state.
    static func show(_ message: String) {
        Task { @MainActor in
            shared.dismissTask?.cancel()
            shared.current = message
            shared.dismissTask = Task { @MainActor [weak self_ = shared] in
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                if !Task.isCancelled {
                    self_?.current = nil
                }
            }
        }
    }
}

// =============================================================================
// MARK: - .toastOverlay() view modifier
// =============================================================================

/// Attaches a bottom-anchored toast surface to the host view.  Only one
/// modifier need be present in the view tree (typically on the root
/// MushaFScreen) — every ToastCenter.show call surfaces here.
struct ToastOverlay: ViewModifier {
    let theme: ThemeColors

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let msg = ToastCenter.shared.current {
                    Text(msg)
                        .font(.warattilChrome(size: 14))
                        .foregroundStyle(theme.text)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(theme.background)
                                .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 3)
                        )
                        .overlay(
                            Capsule()
                                .stroke(theme.gold.opacity(0.45), lineWidth: 0.75)
                        )
                        .padding(.bottom, 80)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .environment(\.layoutDirection, .rightToLeft)
                }
            }
            .animation(.spring(duration: 0.25), value: ToastCenter.shared.current)
    }
}

extension View {
    /// Attach the global ToastCenter overlay.  Place ONCE on the
    /// outermost view of the host screen so every ToastCenter.show
    /// call has somewhere to render.
    func toastOverlay(theme: ThemeColors) -> some View {
        modifier(ToastOverlay(theme: theme))
    }
}
