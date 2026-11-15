import Foundation
import Observation
import UserNotifications

// MARK: The iOS notification centre, behind a protocol

/// What the scheduler needs from `UNUserNotificationCenter`. `SystemNotificationCenter` is the
/// real one; `FakeNotificationCenter` backs the unit tests, UI tests and previews.
@MainActor
protocol NotificationCenterClient: AnyObject {
    /// Shows the iOS prompt the first time; later calls return the stored answer.
    func requestAuthorization() async -> Bool
    func isAuthorized() async -> Bool
    func pendingIdentifiers() async -> [String]
    func add(_ notification: PlannedNotification, calendar: PlanCalendar) async
    func removePending(_ identifiers: [String])
}

@MainActor
final class SystemNotificationCenter: NotificationCenterClient {
    private let center: UNUserNotificationCenter
    /// Removing requests is a blocking call to a system service; it must never run on the main
    /// thread. Removes and adds share this serial queue so a remove always lands before the add after it.
    private let queue = DispatchQueue(label: "pgym.reminder-center", qos: .utility)

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    func add(_ notification: PlannedNotification, calendar: PlanCalendar) async {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.threadIdentifier = Notifications.threadID
        content.userInfo = ["kind": notification.kind.rawValue]
        // Wall-clock components, so 18:00 stays 18:00 across a daylight-saving change.
        var parts = calendar.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: notification.fireDate)
        parts.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        let request = UNNotificationRequest(identifier: notification.id, content: content, trigger: trigger)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            queue.async { [center] in
                center.add(request) { _ in done.resume() }
            }
        }
    }

    func removePending(_ identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        queue.async { [center] in
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }
}

/// In-memory notification centre. Records every call.
@MainActor
final class FakeNotificationCenter: NotificationCenterClient {
    var grants = true
    private(set) var authorized: Bool
    private(set) var authorizationRequests = 0
    private(set) var pending: [String: PlannedNotification] = [:]
    private(set) var removed: [String] = []

    init(authorized: Bool = false) {
        self.authorized = authorized
    }

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        authorized = authorized || grants
        return authorized
    }

    func isAuthorized() async -> Bool { authorized }

    func pendingIdentifiers() async -> [String] { Array(pending.keys) }

    func add(_ notification: PlannedNotification, calendar: PlanCalendar) async {
        pending[notification.id] = notification
    }

    func removePending(_ identifiers: [String]) {
        for id in identifiers where pending[id] != nil {
            pending[id] = nil
            removed.append(id)
        }
    }

    /// Pending notifications in fire order.
    var scheduled: [PlannedNotification] { pending.values.sorted { $0.fireDate < $1.fireDate } }
}

// MARK: Stored state

/// What the scheduler keeps on the phone between launches.
struct ReminderState: Codable, Equatable, Sendable {
    /// Nil until onboarding (or a sign-in on a new phone) gives a plan.
    var schedule: PlanSchedule?
    var remindersEnabled = false
    var sundayNudgeEnabled = true
    var trainedDays: Set<DayKey> = []
    /// Sessions logged in `sessionsWeek`.
    var sessionsWeek: WeekKey?
    var sessionsInWeek = 0
    var ignoredInARow = 0
    /// Gym-day reminders handed to iOS whose outcome (opened, trained, ignored) is not counted yet.
    var outstanding: [Outstanding] = []
    var facts = ReminderFacts()

    struct Outstanding: Codable, Equatable, Sendable {
        let id: String
        let day: DayKey
        let fireDate: Date
        var opened = false
    }
}

/// Where `ReminderState` lives. `UserDefaultsReminderStore` on the phone; `InMemoryReminderStore`
/// in tests.
@MainActor
protocol ReminderStateStore: AnyObject {
    func load() -> ReminderState
    func save(_ state: ReminderState)
}

@MainActor
final class InMemoryReminderStore: ReminderStateStore {
    var state: ReminderState

    init(_ state: ReminderState = ReminderState()) {
        self.state = state
    }

    func load() -> ReminderState { state }
    func save(_ state: ReminderState) { self.state = state }
}

@MainActor
final class UserDefaultsReminderStore: ReminderStateStore {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "pgym.reminders.v1") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> ReminderState {
        guard let data = defaults.data(forKey: key),
              let state = try? JSONDecoder().decode(ReminderState.self, from: data)
        else { return ReminderState() }
        return state
    }

    func save(_ state: ReminderState) {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: key)
        }
    }
}

// MARK: The scheduler

/// Keeps iOS's pending notifications equal to what `ReminderPlanner` says they should be.
///
/// Everything that changes the answer calls `reschedule()`: the plan, a logged session, an opened
/// notification, the app coming to the foreground (the day moved on, reminders fired).
@MainActor
@Observable
final class ReminderScheduler {
    private(set) var state: ReminderState
    /// Whether iOS lets PGYM post notifications. Refreshed by `reschedule()`.
    private(set) var isAuthorized = false

    private let center: NotificationCenterClient
    private let store: ReminderStateStore
    private let clock: () -> Date
    private let locale: Locale
    let calendar: PlanCalendar

    init(
        center: NotificationCenterClient,
        store: ReminderStateStore,
        calendar: PlanCalendar = PlanCalendar(),
        locale: Locale = .current,
        clock: @escaping () -> Date = { .now }
    ) {
        self.center = center
        self.store = store
        self.calendar = calendar
        self.locale = locale
        self.clock = clock
        state = store.load()
    }

    /// True after 5 ignored in a row, until one is opened or a session is logged.
    var isPaused: Bool { state.ignoredInARow >= Notifications.backOffAfter }

    /// The plan in force this week.
    var currentPlan: WeeklyPlan? {
        state.schedule?.plan(for: calendar.weekKey(for: clock()))
    }

    // MARK: Plan

    /// Onboarding: the first plan applies from this week.
    func setFirstPlan(_ plan: WeeklyPlan, remindersEnabled: Bool, facts: ReminderFacts? = nil) async {
        state.schedule = PlanSchedule(first: plan, week: calendar.weekKey(for: clock()))
        state.remindersEnabled = remindersEnabled
        if let facts { state.facts = facts }
        await reschedule()
    }

    /// F4 (and any later change): goal and days apply from next Monday; the time applies now.
    func changePlan(_ plan: WeeklyPlan) async {
        let week = calendar.weekKey(for: clock())
        if let schedule = state.schedule {
            state.schedule = schedule.changing(to: plan, during: week, nextWeek: calendar.week(week, plus: 1))
        } else {
            state.schedule = PlanSchedule(first: plan, week: week)
        }
        await reschedule()
    }

    /// A signed-in user on a phone with no stored plan (reinstall, second phone): take the plan
    /// from `users/{uid}` as this week's.
    func adoptIfMissing(_ plan: WeeklyPlan?, remindersEnabled: Bool) async {
        guard state.schedule == nil, let plan, plan.isValid else { return }
        state.schedule = PlanSchedule(first: plan, week: calendar.weekKey(for: clock()))
        state.remindersEnabled = remindersEnabled
        await reschedule()
    }

    func updateFacts(_ facts: ReminderFacts) async {
        state.facts = facts
        await reschedule()
    }

    func setRemindersEnabled(_ on: Bool) async {
        state.remindersEnabled = on
        await reschedule()
    }

    func setSundayNudgeEnabled(_ on: Bool) async {
        state.sundayNudgeEnabled = on
        await reschedule()
    }

    // MARK: Permission

    /// B3's Turn on reminders: the iOS prompt. Reminders are on in PGYM whatever the answer, so
    /// they start working if the user later allows them in iOS Settings.
    @discardableResult
    func requestAuthorization() async -> Bool {
        let granted = await center.requestAuthorization()
        isAuthorized = granted
        return granted
    }

    // MARK: Events

    /// A session was logged at `date` (the day it started). That day's reminder is cancelled and
    /// paused reminders come back: the user is showing up.
    ///
    /// - Parameter countsTowardWeek: true once the session counts for the week (stamped, so it has
    ///   a set and a photo). A draft passes false: it already stops today's reminder
    ///   (pgym-flow-spec.md: "A draft today counts as already trained for the reminder") but does
    ///   not move the week count.
    func sessionLogged(at date: Date, countsTowardWeek: Bool = true) async {
        let day = calendar.dayKey(for: date)
        let week = calendar.weekKey(for: date)
        state.trainedDays.insert(day)
        state.ignoredInARow = 0
        guard countsTowardWeek else {
            await reschedule()
            return
        }
        if let counted = state.sessionsWeek, counted == week {
            // A second session the same day still adds to the week: the server counts sessions.
            state.sessionsInWeek += 1
        } else if state.sessionsWeek == nil || week > state.sessionsWeek! {
            state.sessionsWeek = week
            state.sessionsInWeek = 1
        }
        await reschedule()
    }

    /// The user tapped a PGYM notification (`identifier` from the request).
    func notificationOpened(_ identifier: String) async {
        guard identifier.hasPrefix(Notifications.idPrefix) else { return }
        if let index = state.outstanding.firstIndex(where: { $0.id == identifier }) {
            state.outstanding[index].opened = true
        }
        state.ignoredInARow = 0
        await reschedule()
    }

    /// Signing out: nothing for the next person on this phone.
    func reset() {
        let ids = state.outstanding.map(\.id)
        state = ReminderState()
        store.save(state)
        center.removePending(ids)
        Task { [center] in
            let pending = await center.pendingIdentifiers().filter { $0.hasPrefix(Notifications.idPrefix) }
            center.removePending(pending)
        }
    }

    // MARK: Rescheduling

    /// Counts the outcome of every reminder that has fired, then replaces PGYM's pending requests
    /// with the planner's answer.
    func reschedule() async {
        let now = clock()
        settleFiredReminders(now: now)
        pruneOldDays(now: now)
        isAuthorized = await center.isAuthorized()

        let thisWeek = calendar.weekKey(for: now)
        if let schedule = state.schedule {
            state.schedule = schedule.normalized(for: thisWeek)
        }

        var planned: [PlannedNotification] = []
        if let schedule = state.schedule {
            planned = ReminderPlanner.plan(ReminderInputs(
                now: now,
                calendar: calendar,
                schedule: schedule,
                trainedDays: state.trainedDays,
                sessionsThisWeek: state.sessionsWeek == thisWeek ? state.sessionsInWeek : 0,
                ignoredInARow: state.ignoredInARow,
                remindersEnabled: state.remindersEnabled,
                sundayNudgeEnabled: state.sundayNudgeEnabled,
                facts: state.facts,
                locale: locale
            ))
        }

        let existing = await center.pendingIdentifiers().filter { $0.hasPrefix(Notifications.idPrefix) }
        center.removePending(existing)
        for notification in planned {
            await center.add(notification, calendar: calendar)
        }

        // Fired ones were settled above; what remains outstanding is replaced by the new plan.
        state.outstanding = planned
            .filter { $0.kind == .gymDay }
            .map { ReminderState.Outstanding(id: $0.id, day: $0.day, fireDate: $0.fireDate) }
        store.save(state)
    }

    /// The back-off count. In fire order: an opened reminder, or one on a day the user trained,
    /// resets the count; any other fired reminder adds one.
    private func settleFiredReminders(now: Date) {
        let fired = state.outstanding.filter { $0.fireDate <= now }.sorted { $0.fireDate < $1.fireDate }
        for reminder in fired {
            if reminder.opened || state.trainedDays.contains(reminder.day) {
                state.ignoredInARow = 0
            } else {
                state.ignoredInARow += 1
            }
        }
        state.outstanding.removeAll { $0.fireDate <= now }
    }

    /// Trained days older than two weeks are never looked at again.
    private func pruneOldDays(now: Date) {
        guard let cutoff = calendar.calendar.date(byAdding: .day, value: -14, to: now) else { return }
        let oldest = calendar.dayKey(for: cutoff)
        state.trainedDays = state.trainedDays.filter { $0 >= oldest }
    }
}

// MARK: Taps on notifications

/// Receives taps on PGYM notifications and shows them as banners while the app is open.
/// Set as `UNUserNotificationCenter.current().delegate` at launch, before the app finishes
/// launching, so a tap that cold-starts the app is not lost.
final class NotificationTapRouter: NSObject, UNUserNotificationCenterDelegate {
    /// Called on the main actor with the request identifier.
    var onOpen: (@MainActor (String) -> Void)?
    /// Taps that arrived before `onOpen` was set.
    private var early: [String] = []

    // The async forms of the delegate methods: their signatures do not depend on how a given SDK
    // annotates the completion handlers.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let identifier = response.notification.request.identifier
        await deliver(identifier)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    @MainActor
    private func deliver(_ identifier: String) {
        if let onOpen {
            onOpen(identifier)
        } else {
            early.append(identifier)
        }
    }

    /// Hands over taps that arrived before the app was ready.
    @MainActor
    func drain() -> [String] {
        defer { early = [] }
        return early
    }
}
