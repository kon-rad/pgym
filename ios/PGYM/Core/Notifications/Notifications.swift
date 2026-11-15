import Foundation

/// Local reminders: one per gym day, the Sunday nudge, and the weekly line after 5 ignored.
/// Card I3. Rules (pgym-design.md "Guardrails"; copy deck "Notifications"):
///
/// - One reminder per gym day at the user's time. None on rest days.
/// - None once a session is logged that day (a draft counts, pgym-flow-spec.md "Rules that make
///   this safe").
/// - None once the week's goal is reached: the week is locked and Today offers a bonus session.
/// - Sunday nudge at 18:00, only if the week is exactly one session short.
/// - After 5 reminders in a row go unopened, daily reminders and the nudge pause and a weekly line
///   is sent on Monday at the reminder time until one is opened or a session is logged.
///
/// `ReminderPlanner` is pure: same inputs, same notifications. `ReminderScheduler` feeds it and
/// hands its output to iOS.
enum Notifications {
    /// Every identifier PGYM schedules starts with this, so a reschedule removes only its own.
    static let idPrefix = "pgym."
    static let threadID = "pgym.reminders"
    /// Ignored in a row before daily reminders pause.
    static let backOffAfter = 5
}

/// What kind of notification, stored in `userInfo["kind"]`.
enum ReminderKind: String, Codable, Sendable {
    case gymDay
    case sundayNudge
    case weeklyLine
}

/// One notification the planner wants on the phone.
struct PlannedNotification: Equatable, Sendable {
    let id: String
    let kind: ReminderKind
    let fireDate: Date
    /// The gym day a `.gymDay` reminder is for.
    let day: DayKey
    let title: String
    let body: String
}

/// The numbers the copy needs that the planner cannot work out itself.
struct ReminderFacts: Codable, Equatable, Sendable {
    /// The week one more hit would lock: the server's `streakWeeks` + 1.
    var weekToLock: Int = 1
    /// The next proof number: `proofCount` + 1.
    var nextProof: Int = 1
    /// Routine names in rotation order (Today's "Next up" order). Empty means none yet.
    var routineNames: [String] = []
    /// Index into `routineNames` of the routine due next.
    var nextRoutineIndex: Int = 0
    /// The best set of the last run of the next routine, for variant 3.
    var lastRun: LastRun?
    /// Shown after weights in variant 3.
    var unitsLabel: String = "kg"

    struct LastRun: Codable, Equatable, Sendable {
        var exercise: String
        var weight: Double
        var reps: Int
    }

    /// The routine the `k`-th upcoming gym day would train, in rotation.
    func routine(at k: Int) -> String? {
        guard !routineNames.isEmpty else { return nil }
        let index = ((nextRoutineIndex + k) % routineNames.count + routineNames.count) % routineNames.count
        return routineNames[index]
    }
}

/// Every reminder string, from the copy deck ("Notifications"). No guilt, no countdowns.
enum ReminderCopy {
    /// Variant title for every gym-day reminder: "{routine} at {time}".
    static func title(routine: String?, time: String) -> String {
        // Inferred: the copy deck has no title for a user with no routine yet.
        "\(routine ?? "Gym day") at \(time)"
    }

    static func oneLeft(week: Int) -> String { "One session locks week \(week)." }
    static func progress(done: Int, goal: Int) -> String { "\(done) of \(goal) done this week." }
    static func lastTime(_ run: ReminderFacts.LastRun, unit: String) -> String {
        "Last time: \(run.exercise) \(formatWeight(run.weight)) \(unit) x \(run.reps). Same again is fine."
    }
    static let stillCounts = "One set and a photo still counts."
    static func proofNext(_ proof: Int) -> String { "Proof #\(String(format: "%03d", proof)) is next." }

    static let sundayTitle = "One session left this week"
    static func sundayBody(week: Int) -> String { "Any routine counts. One set and a photo locks week \(week)." }

    static let weeklyTitle = "New week"
    static func weeklyBody(goal: Int) -> String {
        "\(goal) sessions planned. Daily reminders are paused; open PGYM to turn them back on."
    }

    /// The gym-day body: the first variant whose condition is true (copy deck, "Gym-day
    /// reminder: 5 variants"); variant 5 if none.
    static func gymDayBody(
        left: Int,
        done: Int,
        goal: Int,
        weekToLock: Int,
        lastRun: ReminderFacts.LastRun?,
        unit: String,
        lastGymDayMissed: Bool,
        nextProof: Int
    ) -> String {
        if left == 1 { return oneLeft(week: weekToLock) }
        if left >= 2 { return progress(done: done, goal: goal) }
        if let lastRun { return lastTime(lastRun, unit: unit) }
        if lastGymDayMissed { return stillCounts }
        return proofNext(nextProof)
    }

    static func formatWeight(_ weight: Double) -> String {
        weight.rounded() == weight ? String(Int(weight)) : String(format: "%.1f", weight)
    }
}

/// Everything the planner looks at.
struct ReminderInputs: Sendable {
    var now: Date
    var calendar: PlanCalendar
    var schedule: PlanSchedule
    /// Days with a logged (or draft) session.
    var trainedDays: Set<DayKey>
    /// Sessions logged in the current week.
    var sessionsThisWeek: Int
    /// Gym-day reminders ignored in a row so far.
    var ignoredInARow: Int
    var remindersEnabled: Bool = true
    var sundayNudgeEnabled: Bool = true
    var facts: ReminderFacts = ReminderFacts()
    var locale: Locale = .current
    /// Weeks ahead to schedule, counting this one. iOS keeps at most 64 pending requests per app;
    /// this plan never needs more than 5 dailies + 1 nudge + one weekly line per week.
    var horizonWeeks: Int = 6
}

enum ReminderPlanner {
    /// The notifications that should be pending right now, in fire order.
    static func plan(_ input: ReminderInputs) -> [PlannedNotification] {
        guard input.remindersEnabled, input.horizonWeeks > 0 else { return [] }
        let cal = input.calendar
        let thisWeek = cal.weekKey(for: input.now)
        let schedule = input.schedule.normalized(for: thisWeek)
        let weeks = (0..<input.horizonWeeks).map { cal.week(thisWeek, plus: $0) }

        var budget = max(0, Notifications.backOffAfter - input.ignoredInARow)
        var out: [PlannedNotification] = []
        var lastDailyFire: Date?
        var upcoming = 0 // gym days ahead, for the routine rotation
        var sundayHasGymReminder = false

        for week in weeks {
            let plan = schedule.plan(for: week)
            let isThisWeek = week == thisWeek
            let done = isThisWeek ? input.sessionsThisWeek : 0
            let left = plan.goal - done
            if left <= 0 { continue } // week locked: nothing more to ask for

            for day in plan.orderedDays {
                let fire = cal.date(day, of: week, at: plan.time)
                let key = cal.dayKey(for: fire)
                guard fire > input.now, !input.trainedDays.contains(key) else { continue }
                guard budget > 0 else { break }
                budget -= 1
                lastDailyFire = fire
                if isThisWeek, day == .sun { sundayHasGymReminder = true }

                let missed = isThisWeek && previousGymDayMissed(before: day, in: week, plan: plan, input: input)
                let body = ReminderCopy.gymDayBody(
                    left: left,
                    done: done,
                    goal: plan.goal,
                    weekToLock: input.facts.weekToLock,
                    lastRun: input.facts.lastRun,
                    unit: input.facts.unitsLabel,
                    lastGymDayMissed: missed,
                    nextProof: input.facts.nextProof
                )
                out.append(PlannedNotification(
                    id: gymDayID(key),
                    kind: .gymDay,
                    fireDate: fire,
                    day: key,
                    title: ReminderCopy.title(routine: input.facts.routine(at: upcoming), time: plan.time.formatted(locale: input.locale)),
                    body: body
                ))
                upcoming += 1
            }
        }

        // The Sunday nudge: this week only (later weeks' counts are not known yet), only when
        // exactly one session short, never while paused, and never on top of a Sunday reminder.
        let currentPlan = schedule.plan(for: thisWeek)
        let paused = input.ignoredInARow >= Notifications.backOffAfter
        if input.sundayNudgeEnabled, !paused, !sundayHasGymReminder,
           currentPlan.goal - input.sessionsThisWeek == 1 {
            let fire = cal.date(.sun, of: thisWeek, at: .sundayNudge)
            if fire > input.now {
                out.append(PlannedNotification(
                    id: "\(Notifications.idPrefix)sunday.\(thisWeek)",
                    kind: .sundayNudge,
                    fireDate: fire,
                    day: cal.dayKey(for: fire),
                    title: ReminderCopy.sundayTitle,
                    body: ReminderCopy.sundayBody(week: input.facts.weekToLock)
                ))
            }
        }

        // The back-off. Daily reminders stop after the budget runs out; from then on, one line on
        // each Monday at the reminder time. Already paused: every Monday ahead. Not paused yet but
        // the budget ran out inside the horizon: every Monday after the last daily one.
        let budgetRanOut = budget == 0
        if budgetRanOut {
            for week in weeks {
                let plan = schedule.plan(for: week)
                let fire = cal.date(.mon, of: week, at: plan.time)
                guard fire > input.now else { continue }
                if let lastDailyFire, fire <= lastDailyFire { continue }
                out.append(PlannedNotification(
                    id: "\(Notifications.idPrefix)weekly.\(week)",
                    kind: .weeklyLine,
                    fireDate: fire,
                    day: cal.dayKey(for: fire),
                    title: ReminderCopy.weeklyTitle,
                    body: ReminderCopy.weeklyBody(goal: plan.goal)
                ))
            }
        }

        return out.sorted { $0.fireDate < $1.fireDate }
    }

    static func gymDayID(_ day: DayKey) -> String { "\(Notifications.idPrefix)gym.\(day)" }

    /// Variant 4's condition: the gym day before `day` this week has passed with no session.
    private static func previousGymDayMissed(before day: Weekday, in week: WeekKey, plan: WeeklyPlan, input: ReminderInputs) -> Bool {
        guard let previous = plan.orderedDays.last(where: { $0 < day }) else { return false }
        let fire = input.calendar.date(previous, of: week, at: plan.time)
        return fire <= input.now && !input.trainedDays.contains(input.calendar.dayKey(for: fire))
    }
}
