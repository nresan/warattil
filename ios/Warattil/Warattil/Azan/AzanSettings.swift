//
//  AzanSettings.swift
//  Warattil
//
//  Swift port of AzanSettings.kt — UserDefaults-backed model for the
//  prayer-reminder feature.  Stores:
//    • master on/off
//    • cached location (lat / lng / human-readable label)
//    • per-prayer mode (FULL / SHORT / NOTIFICATION_ONLY)
//
//  Deliberately NOT stored on iOS for v1.1:
//    • user-uploaded audio file URIs.  iOS notification sounds must be
//      < 30 s and bundled in the app (or copied to Library/Sounds in
//      .caf/.wav/.aiff format).  Arbitrary user MP3/M4A playback when
//      the app is backgrounded is restricted.  All three "modes" in
//      v1.1 behave as "system-default notification + vibration" — the
//      UI shows the picker (so users see what's coming) but selecting
//      FULL or SHORT currently maps to NOTIFICATION_ONLY at fire time.
//      Real audio handling is the iOS v1.2 work item.
//
//  Persistence: UserDefaults.standard.  Same keys + types as the
//  Android SharedPreferences "warattil_prefs" file so the design is
//  conceptually transferable; the actual storage isn't shared between
//  platforms (different sandboxes).
//

import Foundation

enum AzanSettings {

    /// Per-prayer mode the user picked for a given prayer time.  All
    /// three values render as picker rows in AzanSettingsSheet; on iOS
    /// v1.1 the fire-time behavior is "notification + vibration"
    /// regardless of which is selected (see header note).
    enum Mode: String, CaseIterable, Codable {
        case full              = "FULL"
        case short             = "SHORT"
        case notificationOnly  = "NOTIFICATION_ONLY"

        /// Arabic label for the picker row.
        var label: String {
            switch self {
            case .full:             return "الأذان الكامل"
            case .short:            return "الأذان المختصر"
            case .notificationOnly: return "تنبيه على الشاشة مع الاهتزاز"
            }
        }

        static func fromPref(_ s: String?) -> Mode {
            guard let s else { return .notificationOnly }
            return Mode(rawValue: s) ?? .notificationOnly
        }
    }

    // MARK: - Keys (mirror Android SharedPreferences keys for parity) -----

    private static let kEnabled        = "azan_enabled"
    private static let kLat            = "azan_lat"
    private static let kLng            = "azan_lng"
    private static let kLocationLabel  = "azan_location_label"
    private static func modeKey(_ p: Prayer) -> String { "azan_mode_\(p.prefKey)" }

    private static var defaults: UserDefaults { .standard }

    // MARK: - Master toggle ----------------------------------------------

    static func isEnabled() -> Bool {
        defaults.bool(forKey: kEnabled)
    }

    static func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: kEnabled)
    }

    // MARK: - Location ---------------------------------------------------

    /// Returns (lat, lng) if captured, or nil if the user hasn't granted yet.
    static func getLocation() -> (Double, Double)? {
        guard defaults.object(forKey: kLat) != nil,
              defaults.object(forKey: kLng) != nil
        else { return nil }
        return (defaults.double(forKey: kLat), defaults.double(forKey: kLng))
    }

    static func setLocation(latitude: Double, longitude: Double, label: String = "") {
        defaults.set(latitude,  forKey: kLat)
        defaults.set(longitude, forKey: kLng)
        if !label.isEmpty { defaults.set(label, forKey: kLocationLabel) }
    }

    static func locationLabel() -> String {
        defaults.string(forKey: kLocationLabel) ?? ""
    }

    // MARK: - Per-prayer mode --------------------------------------------

    static func mode(for p: Prayer) -> Mode {
        Mode.fromPref(defaults.string(forKey: modeKey(p)))
    }

    static func setMode(_ mode: Mode, for p: Prayer) {
        defaults.set(mode.rawValue, forKey: modeKey(p))
    }

    /// Convenience: returns the current mode map for all five prayers.
    /// Used by AzanScheduler when deciding sound vs. silent for each
    /// scheduled UNNotificationRequest.
    static func allModes() -> [Prayer: Mode] {
        var out: [Prayer: Mode] = [:]
        for p in Prayer.order { out[p] = mode(for: p) }
        return out
    }
}
