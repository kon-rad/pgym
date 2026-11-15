import Foundation
import UserNotifications

/// Schedules the one local notification that ends a rest, so the user hears it with the phone
/// locked or the app in the background. The timer itself is an end instant on the session; this
/// only mirrors it into the notification centre.
protocol RestNotificationScheduling: AnyObject {
    /// Replaces any pending rest notification with one at `endsAt`.
    func scheduleRestEnd(at endsAt: Date, title: String, body: String)
    func cancelRestEnd()
}

final class RestTimerNotifier: RestNotificationScheduling {
    /// Not under `Notifications.idPrefix` ("pgym."): the reminder scheduler (card I3) removes and
    /// counts every pending identifier with that prefix as one of its own.
    static let identifier = "pgym-rest.end"

    private let center: UNUserNotificationCenter
    /// The notification centre talks to a system service and can block for seconds when that
    /// service is slow. Every call goes through this serial queue, never the main thread, so
    /// starting a session or ticking a set cannot freeze the screen. Serial keeps cancel-then-add in order.
    private let queue = DispatchQueue(label: "pgym.rest-notifier", qos: .utility)

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func scheduleRestEnd(at endsAt: Date, title: String, body: String) {
        cancelRestEnd()
        guard endsAt.timeIntervalSinceNow >= 1 else { return }
        queue.async { [center] in
            self.add(center: center, endsAt: endsAt, title: title, body: body)
        }
    }

    private func add(center: UNUserNotificationCenter, endsAt: Date, title: String, body: String) {
        // Measured here, on the queue, so time spent waiting does not make the rest end late.
        let interval = endsAt.timeIntervalSinceNow
        guard interval >= 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // The sound plays only when the ringer is on; iOS decides that, not the app.
        content.sound = .default
        content.interruptionLevel = .active
        content.threadIdentifier = "pgym-rest"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: Self.identifier, content: content, trigger: trigger)
        // Without notification permission (B3 skipped) this fails quietly: the in-app bar and haptic
        // still mark the end of the rest.
        center.add(request) { _ in }
    }

    func cancelRestEnd() {
        queue.async { [center] in
            center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
            center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
        }
    }
}

/// For tests and previews: records what would have been scheduled.
final class RecordingRestNotifier: RestNotificationScheduling {
    private(set) var scheduled: [Date] = []
    private(set) var cancelCount = 0
    private(set) var pending: Date?

    func scheduleRestEnd(at endsAt: Date, title: String, body: String) {
        scheduled.append(endsAt)
        pending = endsAt
    }

    func cancelRestEnd() {
        cancelCount += 1
        pending = nil
    }
}
