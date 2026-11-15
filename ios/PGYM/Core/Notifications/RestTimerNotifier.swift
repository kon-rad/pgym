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
    static let identifier = "pgym.rest.end"

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func scheduleRestEnd(at endsAt: Date, title: String, body: String) {
        cancelRestEnd()
        let interval = endsAt.timeIntervalSinceNow
        guard interval >= 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // The sound plays only when the ringer is on; iOS decides that, not the app.
        content.sound = .default
        content.interruptionLevel = .active
        content.threadIdentifier = "pgym.rest"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: Self.identifier, content: content, trigger: trigger)
        // Without notification permission (B3 skipped) this fails quietly: the in-app bar and haptic
        // still mark the end of the rest.
        center.add(request) { _ in }
    }

    func cancelRestEnd() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
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
