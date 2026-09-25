//
//  AzanNotificationDelegate.swift
//  Warattil
//
//  UNUserNotificationCenterDelegate for Azan reminders.  Two responsibilities:
//
//    1. When a prayer notification fires while the app is foregrounded,
//       iOS by default suppresses it.  We override willPresent to show
//       it as a banner + play the sound anyway — Nasser wants the
//       reminder visible even if the user happens to be reading.
//
//    2. When the user taps a delivered Azan notification, route them
//       toward today's wird page.  v1.1 uses a NotificationCenter
//       broadcast (`.azanTapped`) that the MushaFViewModel can observe;
//       deep linking via SceneDelegate URL routing is overkill for one
//       in-app destination.  Same compound-ajr loop pattern Android
//       uses (intent.putExtra("open_today_wird", true)).
//
//  Singleton because UNUserNotificationCenter.delegate is a single global
//  slot.  @StateObject in WarattilApp keeps a strong reference so SwiftUI
//  view re-creations don't deallocate it.
//

import Foundation
import UserNotifications
import Combine

/// Broadcast name the rest of the app subscribes to when an Azan
/// notification is tapped.  Subscribers (e.g. MushaFViewModel) can
/// route the user to today's wird page in response.
extension Notification.Name {
    static let azanTapped = Notification.Name("warattil.azan.tapped")
}

final class AzanNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, ObservableObject {

    /// Process-wide singleton — UNUserNotificationCenter only holds one
    /// delegate slot, so multiple instances would race.  Held here AND
    /// referenced from WarattilApp's @StateObject so SwiftUI lifecycle
    /// can't deallocate it.
    static let shared = AzanNotificationDelegate()

    private override init() { super.init() }

    // MARK: - UNUserNotificationCenterDelegate ---------------------------

    /// Foreground delivery — show the banner + play sound even when
    /// the app is up front.  Without this, iOS quietly drops the
    /// notification (a UX regression vs Android which always vibrates).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                @escaping (UNNotificationPresentationOptions) -> Void) {
        // Only intercept OUR notifications — leave other apps' / future
        // categories to default presentation behaviour.
        if notification.request.identifier.hasPrefix("warattil.azan") {
            completionHandler([.banner, .sound, .list])
        } else {
            completionHandler([])
        }
    }

    /// Tap delivery — fired when the user taps the notification (foreground
    /// or background).  Broadcast so any subscriber can route to today's
    /// wird page.  Includes the prayer name in userInfo so subscribers
    /// can show a contextual welcome if useful.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if let action = userInfo[AzanScheduler.userInfoActionKey] as? String,
           action == AzanScheduler.actionOpenTodayWird {
            NotificationCenter.default.post(
                name: .azanTapped,
                object: nil,
                userInfo: userInfo
            )
        }
        completionHandler()
    }
}
