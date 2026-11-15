import Foundation

/// A day of the week, Monday first (the week resets on Monday, pgym-design.md "Fresh start").
/// Raw values match the backend's `WEEKDAYS` (`backend/src/apiSchemas.ts`) and are what
/// `users/{uid}.gymDays` stores.
enum Weekday: String, CaseIterable, Codable, Comparable, Hashable, Sendable {
    case mon, tue, wed, thu, fri, sat, sun

    /// 0 for Monday to 6 for Sunday.
    var mondayIndex: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    /// `Calendar`'s weekday number (Sunday is 1, Saturday is 7) for every calendar.
    var calendarWeekday: Int { self == .sun ? 1 : mondayIndex + 2 }

    init?(calendarWeekday: Int) {
        guard (1...7).contains(calendarWeekday) else { return nil }
        self = calendarWeekday == 1 ? .sun : Self.allCases[calendarWeekday - 2]
    }

    /// "Mon" (copy deck B2: "Mon, Tue, Wed, Thu, Fri, Sat, Sun").
    var short: String {
        switch self {
        case .mon: "Mon"
        case .tue: "Tue"
        case .wed: "Wed"
        case .thu: "Thu"
        case .fri: "Fri"
        case .sat: "Sat"
        case .sun: "Sun"
        }
    }

    /// For VoiceOver.
    var full: String {
        switch self {
        case .mon: "Monday"
        case .tue: "Tuesday"
        case .wed: "Wednesday"
        case .thu: "Thursday"
        case .fri: "Friday"
        case .sat: "Saturday"
        case .sun: "Sunday"
        }
    }

    static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.mondayIndex < rhs.mondayIndex }
}

/// The one reminder time for every gym day, stored as `"HH:mm"` in `users/{uid}.reminderTime`.
struct ReminderTime: Codable, Hashable, Comparable, Sendable {
    let hour: Int
    let minute: Int

    init(hour: Int, minute: Int) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    /// Parses `"18:00"`. Nil for anything else.
    init?(string: String) {
        let parts = string.split(separator: ":")
        guard parts.count == 2, parts.allSatisfy({ $0.count == 2 }),
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute)
        else { return nil }
        self.init(hour: hour, minute: minute)
    }

    /// `"18:00"`.
    var storageValue: String { String(format: "%02d:%02d", hour, minute) }

    /// The default from the reminder example in pgym-design.md ("Push A at 18:00"). Unvalidated
    /// (pgym-flow-spec.md, B2).
    static let `default` = ReminderTime(hour: 18, minute: 0)
    /// The Sunday nudge (pgym-app-views.md: "18:00 on Sunday").
    static let sundayNudge = ReminderTime(hour: 18, minute: 0)

    /// "18:00" in 24-hour locales, "6:00 PM" in 12-hour ones.
    func formatted(locale: Locale = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let date = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: hour, minute: minute)) ?? .now
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        return formatter.string(from: date)
    }

    static func < (lhs: ReminderTime, rhs: ReminderTime) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }
}

/// An ISO week, for example `2026-W47`. The same key the server writes on sessions
/// (`users/{uid}/sessions/{id}.weekKey`) and uses to roll the streak.
struct WeekKey: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    let year: Int
    let week: Int

    var description: String { String(format: "%04d-W%02d", year, week) }

    static func < (lhs: WeekKey, rhs: WeekKey) -> Bool { (lhs.year, lhs.week) < (rhs.year, rhs.week) }
}

/// A calendar day in the user's time zone, `2026-11-16`. Used to remember which days already
/// have a session, so their reminder is not sent.
struct DayKey: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    static func < (lhs: DayKey, rhs: DayKey) -> Bool { (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day) }
}

/// Week arithmetic in the user's time zone. ISO 8601 weeks: Monday first, and the week belongs
/// to the year that holds its Thursday, as on the server.
struct PlanCalendar: Sendable {
    let calendar: Calendar

    init(timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        self.calendar = calendar
    }

    var timeZone: TimeZone { calendar.timeZone }

    func weekKey(for date: Date) -> WeekKey {
        let parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return WeekKey(year: parts.yearForWeekOfYear ?? 0, week: parts.weekOfYear ?? 0)
    }

    func dayKey(for date: Date) -> DayKey {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return DayKey(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
    }

    func weekday(for date: Date) -> Weekday {
        Weekday(calendarWeekday: calendar.component(.weekday, from: date)) ?? .mon
    }

    /// Midnight at the start of the Monday of `week`.
    func startOfWeek(_ week: WeekKey) -> Date {
        var parts = DateComponents()
        parts.calendar = calendar
        parts.timeZone = calendar.timeZone
        parts.yearForWeekOfYear = week.year
        parts.weekOfYear = week.week
        parts.weekday = Weekday.mon.calendarWeekday
        parts.hour = 0
        parts.minute = 0
        return calendar.date(from: parts) ?? .distantPast
    }

    /// The local date and time `time` on `day` of `week`. Daylight-saving changes are handled
    /// by the calendar: 18:00 stays 18:00 on the wall clock.
    func date(_ day: Weekday, of week: WeekKey, at time: ReminderTime) -> Date {
        let monday = startOfWeek(week)
        let dayStart = calendar.date(byAdding: .day, value: day.mondayIndex, to: monday) ?? monday
        return calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: dayStart) ?? dayStart
    }

    func dayKey(_ day: Weekday, of week: WeekKey) -> DayKey {
        dayKey(for: date(day, of: week, at: ReminderTime(hour: 12, minute: 0)))
    }

    /// The week `offset` weeks after `week`.
    func week(_ week: WeekKey, plus offset: Int) -> WeekKey {
        let monday = startOfWeek(week)
        let moved = calendar.date(byAdding: .day, value: 7 * offset, to: monday) ?? monday
        // Noon, so a daylight-saving shift can never push the date into the neighbouring week.
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: moved) ?? moved
        return weekKey(for: noon)
    }
}

/// The weekly goal and the plan that carries it out: which days, and what time
/// (pgym-design.md, "Commitment" and "Implementation intention").
struct WeeklyPlan: Codable, Equatable, Sendable {
    var goal: Int
    var days: Set<Weekday>
    var time: ReminderTime

    /// Gym days, Monday first.
    var orderedDays: [Weekday] { days.sorted() }

    /// The day count must match the goal (B2), and the goal must be 2 to 6.
    var isValid: Bool { GoalPolicy.range.contains(goal) && days.count == goal }

    /// `["mon", "wed", "fri"]` for `users/{uid}.gymDays`.
    var storedDays: [String] { orderedDays.map(\.rawValue) }
}

/// The rules for the weekly goal.
enum GoalPolicy {
    /// "How many days a week?", 2 to 6 (pgym-app-views.md, B1).
    static let range = 2...6

    /// B2's pre-filled spread for each goal, so a user who accepts it only taps Continue.
    /// A proposal (pgym-flow-spec.md, B2): rest days fall between gym days where they can.
    static func defaultDays(for goal: Int) -> Set<Weekday> {
        switch goal {
        case ...2: [.mon, .thu]
        case 3: [.mon, .wed, .fri]
        case 4: [.mon, .tue, .thu, .fri]
        case 5: [.mon, .tue, .wed, .thu, .fri]
        default: [.mon, .tue, .wed, .thu, .fri, .sat]
        }
    }
}

/// Which plan is in force for which week.
///
/// A change to the goal or the gym days applies from the next Monday, never mid-week
/// (pgym-design.md: "The goal can change only for the following week"; copy deck B1: "A change
/// starts the next week"). The server works the same way: it locks each week's goal when the
/// week opens (`backend/src/streak.ts`, `closeWeek`), reading `users/{uid}.goalPerWeek`.
/// A change to the reminder time alone applies at once, because it moves no goalposts.
struct PlanSchedule: Codable, Equatable, Sendable {
    /// The plan for `currentFrom` and every week after it until `pendingFrom`.
    private(set) var current: WeeklyPlan
    private(set) var currentFrom: WeekKey
    /// A change the user made, waiting for its Monday.
    private(set) var pending: WeeklyPlan?
    private(set) var pendingFrom: WeekKey?

    /// The first plan (onboarding, or a phone that has never seen one): in force this week.
    init(first plan: WeeklyPlan, week: WeekKey) {
        current = plan
        currentFrom = week
    }

    /// The plan in force for `week`.
    func plan(for week: WeekKey) -> WeeklyPlan {
        if let pending, let pendingFrom, week >= pendingFrom { return pending }
        return current
    }

    /// The plan the user last chose: what `users/{uid}` stores and what F4 shows.
    var latest: WeeklyPlan { pending ?? current }

    /// Moves a pending change into `current` once its week has come.
    func normalized(for week: WeekKey) -> PlanSchedule {
        guard let pending, let pendingFrom, week >= pendingFrom else { return self }
        var copy = self
        copy.current = pending
        copy.currentFrom = pendingFrom
        copy.pending = nil
        copy.pendingFrom = nil
        return copy
    }

    /// The schedule after the user picks `plan` during `week`, whose next week is `nextWeek`.
    func changing(to plan: WeeklyPlan, during week: WeekKey, nextWeek: WeekKey) -> PlanSchedule {
        var copy = normalized(for: week)
        let goalAndDaysSame = plan.goal == copy.current.goal && plan.days == copy.current.days
        if goalAndDaysSame {
            // Same commitment: a new time applies now, and any pending change is withdrawn.
            copy.current.time = plan.time
            copy.pending = nil
            copy.pendingFrom = nil
        } else {
            copy.pending = plan
            copy.pendingFrom = nextWeek
            // The time is not a commitment; it moves today as well.
            copy.current.time = plan.time
        }
        return copy
    }
}
