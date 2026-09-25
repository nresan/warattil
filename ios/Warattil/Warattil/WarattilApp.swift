//
//  WarattilApp.swift
//  Warattil
//
//  App entry point. Responsibilities:
//    1. Force global RTL at the UIKit level so `SwiftUI.Menu` popovers,
//       sheet chrome, and any other UIKit-hosted surfaces lay out RTL —
//       the SwiftUI `.environment(\.layoutDirection, .rightToLeft)` only
//       reaches SwiftUI descendants and leaves UIKit hosts LTR.
//    2. Show a branded splash (logo on cream) for a guaranteed minimum
//       duration so the reader sees the WARATTIL identity before landing
//       on the Mushaf.
//    3. Load quran_metadata.xml into MetadataParser.shared and open the
//       bundled SQLite DB (QuranDatabase.shared).
//    4. Construct ContentView once bootstrap succeeds; otherwise render
//       an Arabic-language error screen.
//
//  Bootstrap work is synchronous-fast (~10 ms on device) — the visible
//  delay comes from the minimum-splash-duration timer in `bootstrap()`,
//  NOT from the XML/DB load.
//

import SwiftUI
import UIKit
import UserNotifications

@main
struct WarattilApp: App {

    /// Bootstrap state — the app body subscribes so ContentView only
    /// appears after the XML + DB are ready AND the splash has shown
    /// for its minimum duration. Failures surface as an Arabic-language
    /// error screen instead of crashing.
    @State private var bootstrapError: String?
    @State private var isReady: Bool = false

    /// Long-lived delegate that handles Azan notification interactions —
    /// shows them while foregrounded, routes taps to today's wird page.
    /// Held as a @StateObject so it survives view re-creations.
    @StateObject private var notificationDelegate = AzanNotificationDelegate.shared

    // MARK: - init — force UIKit semantic RTL
    //
    // `UIView.appearance().semanticContentAttribute = .forceRightToLeft`
    // sets the default layout direction for every UIView instantiated
    // afterward. This is the ONE lever that reaches UIKit-hosted SwiftUI
    // surfaces — chiefly `SwiftUI.Menu`'s popover (which is rendered by
    // UIContextMenuInteraction) and `.sheet` chrome (UISheetPresentation
    // Controller). Without this, those surfaces default to LTR because
    // `CFBundleDevelopmentRegion` is `en`, the system locale isn't
    // Arabic, and the SwiftUI `.layoutDirection` environment doesn't
    // cross the UIKit boundary.
    //
    // We also force the big UIKit chrome classes explicitly — the
    // global appearance set above covers them too, but pinning each
    // class makes the intent obvious at a code-review glance and
    // immunises us against future iOS changes to appearance proxy
    // inheritance rules.
    init() {
        // ─────────────────────────────────────────────────────────────────
        // Register bundled fonts SYNCHRONOUSLY here — BEFORE any SwiftUI
        // body evaluates.
        //
        // Why this has to happen in `init()` and not in `.task { bootstrap }`:
        //
        //   `.task` is an async modifier — it runs AFTER the first body
        //   evaluation, i.e. AFTER SplashView has already asked SwiftUI to
        //   resolve `Font.custom("KFGQPCUthmanicScriptHAFS", size:)`. If the
        //   face isn't registered at that moment, SwiftUI silently binds
        //   the Text view to the system-serif fallback for its lifetime.
        //   When `bootstrap()` later runs and finally registers the font,
        //   the next render flips to KFGQPC — Nasser sees the Muzzammil
        //   ayah visibly TOGGLE between two fonts mid-splash, which reads
        //   as a brand bug ("the logo looks broken, then fixes itself").
        //
        //   Calling `FontRegistrar.registerBundledFonts()` from `init()`
        //   guarantees CTFontManager has indexed the Uthmani + Amiri TTFs
        //   before the first `body` call — so the very first splash render
        //   paints in the locked trademark font and stays there.
        //
        //   The registrar is idempotent (CTFontManager returns
        //   `kCTFontManagerErrorAlreadyRegistered` on the second call),
        //   but we still remove the redundant call from bootstrap() so the
        //   single source of truth for registration is here.
        //
        // DO NOT move this back into bootstrap() to "keep init light."
        // The splash trademark regression is not worth the micro-saving.
        // ─────────────────────────────────────────────────────────────────
        FontRegistrar.registerBundledFonts()

        // Wire the Azan notification delegate.  Must happen in init()
        // before any UNUserNotificationCenter activity to guarantee
        // we receive willPresent / didReceive callbacks for any
        // notification that fires while the app is foregrounded or
        // newly-launched from a tap.  The delegate object itself is
        // held in the @StateObject above so SwiftUI keeps it alive.
        UNUserNotificationCenter.current().delegate = AzanNotificationDelegate.shared

        UIView.appearance().semanticContentAttribute                 = .forceRightToLeft
        UINavigationBar.appearance().semanticContentAttribute        = .forceRightToLeft
        UITabBar.appearance().semanticContentAttribute               = .forceRightToLeft
        UIToolbar.appearance().semanticContentAttribute              = .forceRightToLeft
        UITableView.appearance().semanticContentAttribute            = .forceRightToLeft
        UICollectionView.appearance().semanticContentAttribute       = .forceRightToLeft
        UIScrollView.appearance().semanticContentAttribute           = .forceRightToLeft
        UISearchBar.appearance().semanticContentAttribute            = .forceRightToLeft
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let err = bootstrapError {
                    BootstrapErrorView(message: err)
                } else if isReady {
                    ContentView()
                        .environment(\.layoutDirection, .rightToLeft)
                } else {
                    // Branded splash — logo on cream, RTL locale so any
                    // system strings (VoiceOver hints etc.) read right.
                    SplashView()
                }
            }
            // Apply an Arabic locale at the scene root so any UIKit-
            // hosted controls that fall back to the locale for direction
            // (rather than semanticContentAttribute) also render RTL.
            .environment(\.locale, Locale(identifier: "ar"))
            .task { await bootstrap() }
        }
    }

    // MARK: - Bootstrap

    /// Minimum time the splash stays visible after the app launches.
    /// The XML + DB load in roughly a frame on modern devices, so without
    /// this floor the splash would flicker for <100 ms.
    ///
    /// 2026-04-22 (later): bumped from 2.8 s → 4.0 s at Nasser's request —
    /// "the user needs to notice the logo before accessing the Quran; we
    /// need him to recognize our identity." 2.8 s still felt rushed, so
    /// we extend enough for the reader to (a) see the breathing animation
    /// complete a full up-and-down cycle, (b) read the Muzzammil ayah
    /// وَرَتِّلِ ٱلْقُرْءَانَ تَرْتِيلًا in full, and (c) notice the
    /// attribution سورة المزمّل ـ الآية ٤ settle.
    ///
    /// If this starts to feel like a stall, dial back toward ~3.0 s —
    /// but don't drop below 2.5 s without asking Nasser first. The splash
    /// IS the trademark; brevity here undoes the brand work.
    private static let minimumSplashDuration: UInt64 = 4_000_000_000 // 4.0 s in ns

    @MainActor
    private func bootstrap() async {
        // Guard against duplicate init when the task fires twice (e.g. scene
        // restoration). MetadataParser.load is idempotent but we avoid the
        // redundant work.
        if isReady { return }

        // Kick off the minimum-splash timer in parallel with the real work.
        // The user never sees the splash disappear faster than this.
        async let splashFloor: Void = Task.sleep(nanoseconds: Self.minimumSplashDuration)

        do {
            // Font registration happens SYNCHRONOUSLY in `init()` above so
            // the splash's locked Uthmani face resolves on its very first
            // body evaluation. Nothing to do here; the MetadataParser + DB
            // open are the only async-safe bootstrap steps that remain.

            try MetadataParser.shared.load(bundle: .main)
            try QuranDatabase.shared.open()

            // Wait for whichever is slower: the real bootstrap or the
            // minimum splash display time. `try?` because Task.sleep only
            // throws on cancellation — which here means the scene went
            // away; either way we should still flip `isReady`.
            _ = try? await splashFloor

            isReady = true

            // Top up the Azan notification queue.  refresh() is idempotent
            // and a fast no-op when Azan is disabled, so safe to call
            // unconditionally on every launch.  Keeps the 12-day rolling
            // window of scheduled prayers fresh without relying on any
            // background-task entitlements.
            AzanScheduler.refresh()
        } catch {
            // Surface a user-facing Arabic error. The localised description
            // from Swift is usually clear enough for debugging without
            // translating every error path here.
            bootstrapError = "تعذّر فتح المصحف: \(error.localizedDescription)"
        }
    }
}

// =============================================================================
// MARK: - SplashView — logo on cream
// =============================================================================
//
// Shown while the XML + DB load AND for a minimum of ~1.2 s so the brand
// registers. Intentionally simple: the logo, centered, with a slow breathing
// scale that hints at liveness without feeling like a loading spinner. No
// "Loading…" text — if bootstrap stalls long enough to need text, it has
// failed and `bootstrapError` takes over.
// =============================================================================

private struct SplashView: View {

    /// Slow breathing animation applied to the logo. Starts at 0.96× and
    /// gently scales to 1.04× over 1.4 s, mirroring the cadence of a
    /// recited breath. Purely cosmetic; can be removed without affecting
    /// bootstrap timing.
    @State private var breathe: CGFloat = 0.96

    // =========================================================================
    // ⚠️  LOCKED TYPOGRAPHY — DO NOT EDIT  ⚠️
    // =========================================================================
    //
    // The splash screen is WARATTIL's visual trademark. Nasser (2026-04-22):
    // "it is a logo or trademark that can't be changed at all." The Muzzammil
    // ayah is the product's signature; changing its font changes the brand.
    //
    // Therefore the splash does NOT route through `quranFont()` /
    // `WarattilConstants.Mushaf.fontUthmanic`. Those resolve the Mushaf body
    // font, which can be (and has been) swapped mid-project. Any change to
    // that constant would drag the splash along with it.
    //
    // The splash pins its PostScript name inline so it is immune to future
    // body-font changes. If the pinned face isn't registered for any reason
    // (shouldn't happen — `FontRegistrar.registerBundledFonts()` scans the
    // whole bundle at launch), we fall back deterministically to Amiri.
    //
    // IF YOU FIND YOURSELF EDITING THIS BLOCK BECAUSE OF A BODY-FONT REQUEST,
    // STOP. The body font and the splash font are intentionally decoupled.
    // Edit `WarattilConstants.Mushaf.fontUthmanic` or the body render path,
    // not this file.
    // =========================================================================
    private enum LockedSplashFont {
        /// Pinned PostScript name — the face the trademark was designed in.
        static let postScriptName = "KFGQPCUthmanicScriptHAFS"
        /// Deterministic fallback if the pinned face fails to register.
        /// Amiri is classical Naskh and the closest-shaped bundled face to
        /// the locked Uthmani rendering.
        static let fallbackPostScriptName = "Amiri-Regular"

        static func font(size: CGFloat) -> Font {
            if UIFont(name: postScriptName, size: size) != nil {
                return .custom(postScriptName, size: size)
            }
            if UIFont(name: fallbackPostScriptName, size: size) != nil {
                return .custom(fallbackPostScriptName, size: size)
            }
            // Last resort — never leaves the splash blank.
            return .system(size: size, design: .serif)
        }
    }

    var body: some View {
        // WARATTIL gold — same hue used for the ﴾ ﴿ ayah ornaments elsewhere
        // and sheet hairlines. Hardcoded here (not pulled from ThemeColors)
        // because the splash renders BEFORE the MushaFViewModel is constructed,
        // so no theme struct exists yet.
        let splashGold = Color(red: 0x99 / 255.0, green: 0x65 / 255.0, blue: 0x15 / 255.0)

        ZStack {
            // WARATTIL cream — matches the Mushaf page background so the
            // splash → Mushaf transition is imperceptible on the eye.
            Color(hex: 0xF5F5DC).ignoresSafeArea()

            VStack(spacing: 22) {
                // Logo from WarattilLogo.imageset — the same source as the
                // app icon. `.scaledToFit()` preserves the 1307×1288 aspect
                // ratio inside the 200×200 frame. Slightly smaller than the
                // previous 220 pt so the Muzzammil ayah block below has
                // vertical room without crowding the device bezel.
                //
                // 2026-04-22 clip fix: the PNG ships with white pixels in the
                // four corners (inside the square image bounds, outside the
                // rounded-square green art). On the cream splash those white
                // corners were visible as a thin white border hugging the
                // curve of the icon. We clip the image with a continuous-
                // corner RoundedRectangle at the same radius Apple uses on
                // home-screen icons (≈22.37 % of the edge length — Apple's
                // "squircle"), so the clipped shape matches the green art's
                // own rounding exactly. The logo artwork itself is untouched;
                // we only mask off the corner pixels.
                Image("WarattilLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 45, style: .continuous))
                    .scaleEffect(breathe)
                    .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)

                // ── Muzzammil source ayah ────────────────────────────────
                //
                // ﴾ وَرَتِّلِ ٱلْقُرْءَانَ تَرْتِيلًا ﴿ — Q 73:4. The ayah
                // from which the app takes its name.
                //
                // BRACKET ORIENTATION (2026-04-22 fix):
                //   The ornate-paren glyphs curve asymmetrically — ﴾ (U+FD3F)
                //   opens to the RIGHT (shape ≈ "{") and ﴿ (U+FD3E) opens to
                //   the LEFT (shape ≈ "}"). For the curves to embrace the
                //   ayah INWARD we need the "{"-shape on the visual LEFT and
                //   the "}"-shape on the visual RIGHT:
                //
                //       ﴾  وَرَتِّلِ ٱلْقُرْءَانَ تَرْتِيلًا  ﴿
                //       ↑                                       ↑
                //       visual LEFT (open-right)     visual RIGHT (open-left)
                //
                //   With `.layoutDirection = .leftToRight` on the HStack, the
                //   source order below IS the visual order left-to-right, so
                //   ﴾ comes first and ﴿ comes last. Earlier code had them
                //   swapped — Nasser reported the brackets rendering as
                //   "}ayah{" (opening outward) and asked for them to close
                //   inward as "{ayah}".
                //
                //   The inner ayah Text keeps its own `.rightToLeft` so the
                //   Arabic words themselves flow in their natural reading
                //   direction.
                HStack(spacing: 8) {
                    Text("﴾")
                        .font(LockedSplashFont.font(size: 26))
                        .foregroundStyle(splashGold)
                    Text("وَرَتِّلِ ٱلْقُرْءَانَ تَرْتِيلًا")
                        .font(LockedSplashFont.font(size: 22))
                        .foregroundStyle(Color(hex: 0x1A1A1A))
                        .environment(\.layoutDirection, .rightToLeft)
                    Text("﴿")
                        .font(LockedSplashFont.font(size: 26))
                        .foregroundStyle(splashGold)
                }
                .environment(\.layoutDirection, .leftToRight)

                // Source attribution — rendered in Amiri chrome so it reads
                // as a scholarly citation rather than Quranic text. Eastern
                // Arabic numeral ٤ matches the rest of WARATTIL's digit
                // style (see WarattilConstants.digit conventions).
                Text("سورة المزمّل ـ الآية ٤")
                    .font(.warattilChrome(size: 13))
                    .foregroundStyle(splashGold.opacity(0.80))
                    .environment(\.layoutDirection, .rightToLeft)
                    .padding(.top, -6)
            }
        }
        .onAppear {
            // Breathing loop — autoreverse so the scale bounces gently
            // between 0.96 and 1.04 for as long as the splash is visible.
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                breathe = 1.04
            }
        }
    }
}

// =============================================================================
// MARK: Bootstrap error screen
// =============================================================================

private struct BootstrapErrorView: View {
    let message: String

    var body: some View {
        ZStack {
            Color(hex: 0xF5F5DC).ignoresSafeArea()
            VStack(spacing: 12) {
                Text("حدث خطأ عند التشغيل")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color(hex: 0x1A1A1A))
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: 0x1A1A1A).opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .environment(\.layoutDirection, .rightToLeft)
        }
    }
}
