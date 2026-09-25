//
//  AzanSettingsSheet.swift
//  Warattil
//
//  SwiftUI port of AzanSettingsSheet.kt — prayer-reminder configuration.
//  Mirrors the Android sheet structure but uses iOS Form + CLLocationManager
//  + UNUserNotificationCenter instead of Android Composable + LocationServices
//  + AlarmManager.
//
//  Three sections:
//
//    1. Master toggle ("تفعيل تذكير الصلاة")
//         + handles notification-permission request on first enable
//         + falls back to a "غير مفعّل في الإعدادات" hint when iOS notif
//           permission has been denied (user must enable in iOS Settings)
//
//    2. Location row
//         + tap-to-capture via CLLocationManager (whenInUse)
//         + shows captured coordinates after grant
//
//    3. Per-prayer mode rows (5 prayers × 3-option picker)
//         + iOS v1.1 limitation note: all three modes currently behave
//           as "notification + system vibration" (no user-uploaded audio
//           yet — that's the v1.2 work item)
//

import SwiftUI
import CoreLocation
import UserNotifications
import Combine

struct AzanSettingsSheet: View {

    let theme:     ThemeColors
    let font:      QuranFontInfo
    let onDismiss: () -> Void

    // Local @State that mirrors AzanSettings + reactively re-renders on change.
    @State private var isEnabled:      Bool   = AzanSettings.isEnabled()
    @State private var location:       (Double, Double)? = AzanSettings.getLocation()
    @State private var modes:          [Prayer: AzanSettings.Mode] = AzanSettings.allModes()
    @State private var authStatus:     UNAuthorizationStatus = .notDetermined
    @State private var locationStatus: CLAuthorizationStatus = .notDetermined
    @StateObject private var locationFetcher = LocationFetcher()

    var body: some View {
        NavigationStack {
            Form {

                // ── Header description ─────────────────────────────────
                Section {
                    Text("تذكير هادئ بالصلوات الخمس — لتقترن قراءتك للقرآن بإقامة الصلاة في وقتها.")
                        .font(.warattilChrome(size: 14))
                        .foregroundStyle(theme.text.opacity(0.75))
                        .multilineTextAlignment(.leading)
                }
                .listRowBackground(theme.background.opacity(0.0))

                // ── Master toggle ──────────────────────────────────────
                Section {
                    Toggle(isOn: $isEnabled) {
                        HStack(spacing: 10) {
                            Image(systemName: "bell.fill")
                                .foregroundStyle(theme.accent)
                            Text("تفعيل تذكير الصلاة")
                                .foregroundStyle(theme.text)
                        }
                    }
                    .tint(theme.accent)
                    .onChange(of: isEnabled) { _, newValue in
                        handleEnableToggle(newValue)
                    }

                    if isEnabled && authStatus == .denied {
                        Text("الإشعارات معطّلة في إعدادات النظام — فعّلها من إعدادات iPhone لاستلام تذكير الصلاة.")
                            .font(.warattilChrome(size: 12))
                            .foregroundStyle(theme.progressLow)   // warning red
                    }
                }

                // ── Location row ───────────────────────────────────────
                if isEnabled {
                    Section {
                        Button {
                            captureLocation()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "location.fill")
                                    .foregroundStyle(theme.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    if let (lat, lng) = location {
                                        Text("تم تحديد موقعك")
                                            .foregroundStyle(theme.text)
                                            .fontWeight(.medium)
                                        Text(String(format: "نحسب أوقات الصلاة وفقًا لإحداثياتك (%.3f، %.3f)", lat, lng))
                                            .font(.warattilChrome(size: 11))
                                            .foregroundStyle(theme.text.opacity(0.6))
                                    } else {
                                        Text("اضغط لتحديد موقعك")
                                            .foregroundStyle(theme.accent)
                                            .fontWeight(.medium)
                                        Text("نحتاج إحداثياتك لحساب أوقات الصلاة محليًا — لا تُرسَل إلى أي خادم")
                                            .font(.warattilChrome(size: 11))
                                            .foregroundStyle(theme.text.opacity(0.6))
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    } header: {
                        Text("الموقع")
                            .foregroundStyle(theme.accent)
                    }
                }

                // ── Per-prayer mode rows ───────────────────────────────
                if isEnabled && location != nil {
                    Section {
                        ForEach(Prayer.order, id: \.self) { prayer in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(prayer.arabicName)
                                    .font(.warattilChrome(size: 16, weight: .semibold))
                                    .foregroundStyle(theme.accent)
                                Picker("", selection: bindingForMode(prayer)) {
                                    ForEach(AzanSettings.Mode.allCases, id: \.self) { mode in
                                        Text(mode.label).tag(mode)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .onChange(of: modes[prayer]) { _, _ in
                                    rescheduleAfterDelay()
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text("اختر لكل صلاة")
                            .foregroundStyle(theme.accent)
                    } footer: {
                        // Honest disclosure of the iOS v1.1 limitation —
                        // all three modes currently behave the same way
                        // because notification audio handling isn't built
                        // yet on the iOS side.  Removes user confusion.
                        Text("ملاحظة: تشغيل الأذان الصوتي قادم في تحديثٍ قريب لنسخة iPhone. حاليًا تصلك تذكيرات الصلاة كإشعار مرئي مع اهتزاز خفيف.")
                            .font(.warattilChrome(size: 11))
                            .foregroundStyle(theme.text.opacity(0.55))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    WarattilSheetTitle(text: "أوقات الصلاة", theme: theme)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { onDismiss() }
                        .foregroundStyle(theme.accent)
                        .fontWeight(.bold)
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .task {
            authStatus = await AzanScheduler.currentAuthorizationStatus()
        }
        .onReceive(locationFetcher.$result) { result in
            if let result {
                AzanSettings.setLocation(latitude: result.lat, longitude: result.lng)
                location = (result.lat, result.lng)
                rescheduleAfterDelay()
            }
        }
    }

    // MARK: - State helpers ----------------------------------------------

    private func bindingForMode(_ prayer: Prayer) -> Binding<AzanSettings.Mode> {
        Binding(
            get: { modes[prayer] ?? .notificationOnly },
            set: { newValue in
                modes[prayer] = newValue
                AzanSettings.setMode(newValue, for: prayer)
            }
        )
    }

    // MARK: - Enable / disable side effects ------------------------------

    private func handleEnableToggle(_ newValue: Bool) {
        AzanSettings.setEnabled(newValue)
        if newValue {
            // First-enable flow: request notification permission, then
            // schedule.  If permission gets denied we surface the hint
            // shown above in the toggle Section.
            Task {
                let granted = await AzanScheduler.requestAuthorization()
                authStatus = await AzanScheduler.currentAuthorizationStatus()
                if granted, location != nil {
                    AzanScheduler.refresh()
                }
            }
        } else {
            AzanScheduler.cancelAll()
        }
    }

    private func captureLocation() {
        locationFetcher.requestOnce()
    }

    /// Re-schedule notifications after a settings change.  Tiny debounce
    /// so toggling rapidly through picker options doesn't cause repeated
    /// full re-schedules; UN clears/rebuilds 60 requests each call.
    @State private static var rescheduleTask: Task<Void, Never>?
    private func rescheduleAfterDelay() {
        Self.rescheduleTask?.cancel()
        Self.rescheduleTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000) // 350 ms
            if !Task.isCancelled, isEnabled, location != nil {
                AzanScheduler.refresh()
            }
        }
    }
}

// =============================================================================
// MARK: - LocationFetcher — one-shot CLLocationManager wrapper
// =============================================================================
//
// CLLocationManager is delegate-based and persists across SwiftUI re-renders
// poorly — wrap it in an ObservableObject that holds the manager and
// publishes a Result the view can subscribe to.  Asks for whenInUse auth
// on first request; falls through silently if denied.
//

final class LocationFetcher: NSObject, ObservableObject, CLLocationManagerDelegate {

    struct Result {
        let lat: Double
        let lng: Double
    }

    @Published var result: Result?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestOnce() {
        let status = manager.authorizationStatus
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            // The delegate callback will fire requestLocation when grant
            // arrives (see locationManagerDidChangeAuthorization).
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            // Silent fail — the settings sheet's "غير مفعّل" hint covers
            // the visible feedback.  User can re-grant from iOS Settings.
            break
        @unknown default:
            break
        }
    }

    // MARK: - CLLocationManagerDelegate -----------------------------------

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse
            || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        result = Result(lat: loc.coordinate.latitude, lng: loc.coordinate.longitude)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Quiet failure — the user can tap "اضغط لتحديد موقعك" again.
    }
}
