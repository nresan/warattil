//
//  AzanScheduler.swift
//  Warattil
//
//  iOS counterpart to Android's AzanScheduler.kt — uses UNUserNotificationCenter
//  + UNCalendarNotificationTrigger to schedule per-prayer local notifications.
//
//  iOS vs Android architectural differences:
//
//    1. NO AlarmManager.  iOS has UNUserNotificationCenter for scheduled
//       local notifications.  Scheduled requests survive reboot natively,
//       so no boot-receiver equivalent is needed.
//
//    2. 64-pending-notification cap per app.  We schedule 12 days ahead
//       (5 × 12 = 60 requests) and re-schedule on every app launch via
//       refresh(); this keeps the queue topped up without overflowing.
//
//    3. NO foreground service for audio.  iOS notification sounds must
//       be < 30 s and bundled in the app or in Library/Sounds in .caf
//       format.  For v1.1 the sound is the system default; user-uploaded
//       audio is the v1.2 work item (see AzanSettings header note).
//
//    4. Notification tap → opens app via UNNotificationResponse handling
//       in WarattilApp.swift, which routes to today's wird page using
//       userInfo["prayer"] + userInfo["open_today_wird"]=true.  Same
//       compound-ajr loop as Android.
//
//  All operations are idempotent — scheduleAll() clears+rebuilds, so
//  calling it on every settings change OR on every app launch is safe.
//

import Foundation
import UserNotifications

enum AzanScheduler {

    /// How many days ahead we keep notifications queued.  At 5 prayers/day
    /// this is 60 requests, comfortably under iOS's 64-pending cap.
    static let scheduleHorizonDays: Int = 12

    /// Identifier prefix for all Azan notifications so we can selectively
    /// cancel only ours (not e.g. wird reminders, if those ever land).
    private static let idPrefix = "warattil.azan"

    /// Notification content identifiers — used so we can build deep links
    /// from the response in WarattilApp.swift's NotificationDelegate.
    static let userInfoPrayerKey  = "prayer"
    static let userInfoActionKey  = "action"
    static let actionOpenTodayWird = "open_today_wird"

    // MARK: - Permission request -----------------------------------------

    /// Request notification authorization.  Call when the user first
    /// enables the Azan master toggle.  Resolves with true on grant,
    /// false on denial or any error.
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    /// Inspect the current authorization state without prompting.
    /// Used to decide whether to show the "enable in Settings" hint
    /// when the user toggles Azan on but iOS has previously denied.
    static func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    // MARK: - Schedule / cancel ------------------------------------------

    /// Clear all pending Azan notifications and re-schedule the next
    /// [scheduleHorizonDays] days.  Idempotent — safe to call on every
    /// app launch or every settings change.  Bails early if Azan is
    /// disabled or no location is captured.
    static func refresh() {
        guard AzanSettings.isEnabled(),
              let (lat, lng) = AzanSettings.getLocation()
        else {
            cancelAll()
            return
        }

        cancelAll()

        let center = UNUserNotificationCenter.current()
        var cal = Calendar(identifier: .gregorian); cal.timeZone = .current
        let now = Date()
        let modes = AzanSettings.allModes()

        for dayOffset in 0..<scheduleHorizonDays {
            guard let baseDate = cal.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            let times = PrayerTimes.compute(date: baseDate, latitude: lat, longitude: lng)

            for prayer in Prayer.order {
                let minOfDay = times.forPrayer(prayer)
                let fireDate = PrayerTimes.absoluteDate(forMinutesOfDay: minOfDay, on: baseDate)

                // Skip past times within today's window — UNUserNotificationCenter
                // won't fire them anyway, and queuing them just wastes one of our
                // 64 pending slots.
                if fireDate <= now { continue }

                let dayKey = dayKeyFor(date: baseDate, calendar: cal)
                let request = buildRequest(prayer: prayer, fireDate: fireDate, dayKey: dayKey, mode: modes[prayer] ?? .notificationOnly)
                center.add(request) { error in
                    if let error {
                        // Non-fatal — log + move on.  Per-request failure
                        // doesn't break the rest of the schedule.
                        print("[AzanScheduler] failed to schedule \(prayer.rawValue) for \(fireDate): \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    /// Remove every pending Azan notification.  Use when the user
    /// disables the feature, or before a full re-schedule.  Leaves
    /// non-Azan notification requests alone.
    static func cancelAll() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let ids = pending
                .map { $0.identifier }
                .filter { $0.hasPrefix(idPrefix) }
            if !ids.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: ids)
            }
        }
    }

    // MARK: - Internals --------------------------------------------------

    private static func buildRequest(prayer: Prayer,
                                     fireDate: Date,
                                     dayKey: String,
                                     mode: AzanSettings.Mode) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "حان وقت صلاة \(prayer.arabicName)"
        content.body  = "تذكير من ورتّل"
        content.userInfo = [
            userInfoPrayerKey: prayer.rawValue,
            userInfoActionKey: actionOpenTodayWird
        ]
        // For v1.1, all three modes get the system default sound +
        // visual notification.  Custom-sound mapping (for v1.2 when we
        // bundle a short tone OR support user-uploaded .caf files) will
        // branch on `mode` here.  Keeping the switch in place so the
        // diff is small when we add real audio.
        switch mode {
        case .full, .short, .notificationOnly:
            content.sound = .default
        }

        var cal = Calendar(identifier: .gregorian); cal.timeZone = .current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

        let identifier = "\(idPrefix).\(prayer.rawValue).\(dayKey)"
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }

    private static func dayKeyFor(date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
