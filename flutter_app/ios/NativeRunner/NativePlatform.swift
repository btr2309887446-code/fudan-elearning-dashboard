import EventKit
import EventKitUI
import Foundation
import Security
import SwiftUI
import UIKit
import UserNotifications

@MainActor
final class NativeNotificationRouter: ObservableObject {
    static let shared = NativeNotificationRouter()
    var handler: ((String) -> Void)?
    private var pendingDay: String?

    func receive(_ day: String) {
        guard Beijing.parseKey(day) != nil else { return }
        if let handler { handler(day) } else { pendingDay = day }
    }

    func install(_ handler: @escaping (String) -> Void) {
        self.handler = handler
        if let pendingDay {
            self.pendingDay = nil
            handler(pendingDay)
        }
    }
}

enum NativeFreshStart {
    private static let marker = "native.didClearFlutterState.v1"
    private static let legacyDefaultsKeys = [
        "flutter.elearning.session", "flutter.elearning.snapshot", "flutter.elearning.prefs",
        "flutter.elearning.reminders",
    ]

    static func run(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: marker) else { return }
        for key in legacyDefaultsKeys { defaults.removeObject(forKey: key) }
        // The old Flutter client stores the remembered password under the same
        // bundle service, but its account is separate from native.* accounts.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "cn.edu.fudan.fudanElearning",
            kSecAttrAccount as String: "elearning.password",
        ]
        SecItemDelete(query as CFDictionary)
        NativeNotifications.cancelAll()
        defaults.set(true, forKey: marker)
    }
}

final class NativeAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               didReceive response: UNNotificationResponse,
                               withCompletionHandler completionHandler: @escaping () -> Void) {
        if let day = response.notification.request.content.userInfo["day"] as? String {
            Task { @MainActor in NativeNotificationRouter.shared.receive(day) }
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               willPresent notification: UNNotification,
                               withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}

enum NativeNotifications {
    static func requestPermission() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    static func replace(with reminders: [NativeReminderPlanner.Reminder]) async throws {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        for reminder in reminders {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            content.threadIdentifier = "assignment-deadlines"
            content.userInfo = ["day": reminder.day]
            var components = Beijing.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.at)
            components.timeZone = Beijing.timeZone
            let request = UNNotificationRequest(identifier: "deadline-\(reminder.id)",
                                                content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
            try await center.add(request)
        }
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}

enum NativeCalendarAccess {
    static func request() async throws -> Bool {
        let store = EKEventStore()
        if #available(iOS 17.0, *) {
            return try await store.requestWriteOnlyAccessToEvents()
        }
        return try await withCheckedThrowingContinuation { continuation in
            store.requestAccess(to: .event) { granted, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: granted) }
            }
        }
    }
}

struct CalendarEventEditor: UIViewControllerRepresentable {
    let title: String
    let course: String
    let deadline: Date
    let url: URL?
    let onFinish: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = deadline
        event.endDate = deadline.addingTimeInterval(60)
        event.timeZone = Beijing.timeZone
        event.notes = "课程：\(course)\n此事件表示作业截止时刻。后续截止变化不会自动更新此事件。"
        event.url = url
        if #available(iOS 17.0, *) {
            // The system editor asks only for the event being added.
        } else {
            event.calendar = store.defaultCalendarForNewEvents
        }
        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        controller.isModalInPresentation = true
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        private let onFinish: (Bool) -> Void
        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            controller.dismiss(animated: true) { self.onFinish(action == .saved) }
        }
    }
}

