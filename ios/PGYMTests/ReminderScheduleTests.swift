import XCTest
@testable import PGYM

/// A clock the tests move by hand.
private final class TestClock {
    var now: Date
    init(_ now: Date) { self.now = now }
}

/// The reminder schedule, card I3's done-when list: the plan for a goal of 3 and of 5, the
/// cancellation after a logged session, and a goal change that waits for next Monday. Plus the
/// Sunday nudge and the back-off after 5 ignored. No iOS notification centre: a fake records calls.
@MainActor
final class ReminderScheduleTests: XCTestCase {
    /// A zone with daylight saving, so wall-clock times are really checked.
    private let zone = TimeZone(identifier: "Europe/Amsterdam")!
    private let locale = Locale(identifier: "en_GB")
    private var cal: PlanCalendar { PlanCalendar(timeZone: zone) }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 11, year: Int = 2026) -> Date {
        var parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        parts.timeZone = zone
        return cal.calendar.date(from: parts)!
    }

    private func key(_ day: Int, month: Int = 11, year: Int = 2026) -> DayKey {
        DayKey(year: year, month: month, day: day)
    }

    private let mwf: Set<Weekday> = [.mon, .wed, .fri]
    private let monToFri: Set<Weekday> = [.mon, .tue, .wed, .thu, .fri]
    private let six = ReminderTime.default

    private func inputs(
        now: Date,
        plan: WeeklyPlan,
        sessions: Int = 0,
        trained: Set<DayKey> = [],
        ignored: Int = 0,
        facts: ReminderFacts = ReminderFacts()
    ) -> ReminderInputs {
        ReminderInputs(
            now: now,
            calendar: cal,
            schedule: PlanSchedule(first: plan, week: cal.weekKey(for: now)),
            trainedDays: trained,
            sessionsThisWeek: sessions,
            ignoredInARow: ignored,
            facts: facts,
            locale: locale
        )
    }

    private func makeScheduler(clock: TestClock, center: FakeNotificationCenter = FakeNotificationCenter(authorized: true)) -> (ReminderScheduler, FakeNotificationCenter) {
        let scheduler = ReminderScheduler(
            center: center,
            store: InMemoryReminderStore(),
            calendar: cal,
            locale: locale,
            clock: { clock.now }
        )
        return (scheduler, center)
    }

    private func gymDays(_ center: FakeNotificationCenter) -> [PlannedNotification] {
        center.scheduled.filter { $0.kind == .gymDay }
    }

    // MARK: Calendar basics

    func testWeekKeysAreISOWeeksStartingMonday() {
        // Sunday 15 Nov 2026 closes W46; Monday 16 Nov opens W47.
        XCTAssertEqual(cal.weekKey(for: date(15, 23, 59)).description, "2026-W46")
        XCTAssertEqual(cal.weekKey(for: date(16, 0, 1)).description, "2026-W47")
        XCTAssertEqual(cal.weekday(for: date(16, 9)), .mon)
        XCTAssertEqual(cal.date(.fri, of: WeekKey(year: 2026, week: 47), at: six), date(20, 18))
        // Across the year: week 53 of 2026 runs into January 2027.
        XCTAssertEqual(cal.week(WeekKey(year: 2026, week: 52), plus: 1).description, "2026-W53")
        XCTAssertEqual(cal.week(WeekKey(year: 2026, week: 53), plus: 1).description, "2027-W01")
    }

    func testReminderTimeStorage() {
        XCTAssertEqual(ReminderTime(string: "18:00"), ReminderTime(hour: 18, minute: 0))
        XCTAssertEqual(ReminderTime(hour: 7, minute: 5).storageValue, "07:05")
        XCTAssertNil(ReminderTime(string: "25:00"))
        XCTAssertNil(ReminderTime(string: "6pm"))
        XCTAssertEqual(ReminderTime.default.formatted(locale: locale), "18:00")
    }

    // MARK: Done when: a goal of 3

    /// Goal 3 on Mon, Wed, Fri at 18:00, planned on Monday morning: one reminder per gym day at
    /// 18:00, nothing on rest days, no Sunday nudge (three short, not one), and after the 5th
    /// daily reminder the plan falls back to one Monday line a week, in case all 5 are ignored.
    func testScheduleForGoalOfThree() {
        var facts = ReminderFacts()
        facts.routineNames = ["Full body"]
        let plan = WeeklyPlan(goal: 3, days: mwf, time: six)
        let out = ReminderPlanner.plan(inputs(now: date(16, 9), plan: plan, facts: facts))

        let daily = out.filter { $0.kind == .gymDay }
        XCTAssertEqual(daily.map(\.fireDate), [date(16, 18), date(18, 18), date(20, 18), date(23, 18), date(25, 18)])
        XCTAssertEqual(daily.map(\.id), [
            "pgym.gym.2026-11-16", "pgym.gym.2026-11-18", "pgym.gym.2026-11-20",
            "pgym.gym.2026-11-23", "pgym.gym.2026-11-25",
        ])
        XCTAssertTrue(daily.allSatisfy { mwf.contains(cal.weekday(for: $0.fireDate)) }, "never on a rest day")
        XCTAssertEqual(daily.first?.title, "Full body at 18:00")
        XCTAssertEqual(daily.first?.body, "0 of 3 done this week.")

        XCTAssertTrue(out.filter { $0.kind == .sundayNudge }.isEmpty, "three short is not one short")

        let weekly = out.filter { $0.kind == .weeklyLine }
        XCTAssertEqual(weekly.map(\.fireDate), [date(30, 18), date(7, 18, month: 12), date(14, 18, month: 12), date(21, 18, month: 12)])
        XCTAssertEqual(weekly.first?.title, "New week")
        XCTAssertEqual(weekly.first?.body, "3 sessions planned. Daily reminders are paused; open PGYM to turn them back on.")
        XCTAssertEqual(out.map(\.fireDate), out.map(\.fireDate).sorted(), "in fire order")
    }

    /// Later in the week: what has passed is not scheduled, and 18:00 today is still ahead.
    func testGoalOfThreeFromWednesdayAfternoon() {
        let plan = WeeklyPlan(goal: 3, days: mwf, time: six)
        let out = ReminderPlanner.plan(inputs(now: date(18, 17, 59), plan: plan, sessions: 1, trained: [key(16)]))
        let daily = out.filter { $0.kind == .gymDay }
        XCTAssertEqual(daily.first?.fireDate, date(18, 18))
        XCTAssertEqual(daily.first?.body, "1 of 3 done this week.")
    }

    // MARK: Done when: a goal of 5

    /// Goal 5, Monday to Friday: five reminders this week, the routine rotating through
    /// Push, Pull, Legs, then a Monday line from next week if all five go unopened.
    func testScheduleForGoalOfFive() {
        var facts = ReminderFacts()
        facts.routineNames = ["Push", "Pull", "Legs"]
        let plan = WeeklyPlan(goal: 5, days: monToFri, time: six)
        let out = ReminderPlanner.plan(inputs(now: date(16, 9), plan: plan, facts: facts))

        let daily = out.filter { $0.kind == .gymDay }
        XCTAssertEqual(daily.map(\.fireDate), [date(16, 18), date(17, 18), date(18, 18), date(19, 18), date(20, 18)])
        XCTAssertEqual(daily.map(\.title), ["Push at 18:00", "Pull at 18:00", "Legs at 18:00", "Push at 18:00", "Pull at 18:00"])
        XCTAssertTrue(daily.allSatisfy { $0.body == "0 of 5 done this week." })
        XCTAssertFalse(daily.contains { [.sat, .sun].contains(cal.weekday(for: $0.fireDate)) })

        let weekly = out.filter { $0.kind == .weeklyLine }
        XCTAssertEqual(weekly.first?.fireDate, date(23, 18))
        XCTAssertEqual(weekly.count, 5, "every Monday left in the six-week horizon")
        XCTAssertLessThan(out.count, 64, "iOS keeps at most 64 pending requests")
    }

    /// Goal 5 with 4 done by Thursday: "One session locks week 3." and the Sunday nudge at 18:00.
    func testGoalOfFiveOneShortSendsOneLeftAndSundayNudge() {
        var facts = ReminderFacts()
        facts.weekToLock = 3
        let plan = WeeklyPlan(goal: 5, days: monToFri, time: six)
        let trained: Set<DayKey> = [key(16), key(17), key(18)]
        let out = ReminderPlanner.plan(inputs(now: date(19, 9), plan: plan, sessions: 4, trained: trained, facts: facts))

        let thisWeek = out.filter { $0.kind == .gymDay && $0.fireDate < date(23, 0) }
        XCTAssertEqual(thisWeek.map(\.fireDate), [date(19, 18), date(20, 18)])
        XCTAssertTrue(thisWeek.allSatisfy { $0.body == "One session locks week 3." })

        let nudge = out.filter { $0.kind == .sundayNudge }
        XCTAssertEqual(nudge.count, 1)
        XCTAssertEqual(nudge.first?.fireDate, date(22, 18))
        XCTAssertEqual(nudge.first?.title, "One session left this week")
        XCTAssertEqual(nudge.first?.body, "Any routine counts. One set and a photo locks week 3.")
    }

    /// Goal reached: no more reminders this week; they start again next Monday.
    func testWeekDoneSendsNothingMoreThisWeek() {
        let plan = WeeklyPlan(goal: 3, days: mwf, time: six)
        let out = ReminderPlanner.plan(inputs(now: date(18, 20), plan: plan, sessions: 3, trained: [key(16), key(17), key(18)]))
        XCTAssertEqual(out.first?.fireDate, date(23, 18))
        XCTAssertTrue(out.filter { $0.kind == .sundayNudge }.isEmpty)
    }

    /// Two short on Saturday: no nudge. The nudge is for exactly one.
    func testNoSundayNudgeWhenTwoShort() {
        let plan = WeeklyPlan(goal: 3, days: mwf, time: six)
        let out = ReminderPlanner.plan(inputs(now: date(21, 10), plan: plan, sessions: 1))
        XCTAssertTrue(out.filter { $0.kind == .sundayNudge }.isEmpty)
    }

    // MARK: Done when: cancellation after a logged session

    /// A session logged on a gym day removes that day's reminder from iOS; the next gym day's
    /// reminder now says 1 of 3. A draft also stops the reminder but does not move the count.
    func testLoggedSessionCancelsThatDaysReminder() async {
        let clock = TestClock(date(16, 9))
        let (scheduler, center) = makeScheduler(clock: clock)
        await scheduler.setFirstPlan(WeeklyPlan(goal: 3, days: mwf, time: six), remindersEnabled: true)
        XCTAssertNotNil(center.pending["pgym.gym.2026-11-16"])

        clock.now = date(16, 10)
        await scheduler.sessionLogged(at: clock.now)

        XCTAssertNil(center.pending["pgym.gym.2026-11-16"], "no reminder after the session is logged")
        XCTAssertTrue(center.removed.contains("pgym.gym.2026-11-16"))
        XCTAssertEqual(center.pending["pgym.gym.2026-11-18"]?.body, "1 of 3 done this week.")
        XCTAssertEqual(center.pending["pgym.gym.2026-11-20"]?.body, "1 of 3 done this week.")

        // Wednesday: a draft started at 07:00 is "already trained" for the reminder.
        clock.now = date(18, 7)
        await scheduler.sessionLogged(at: clock.now, countsTowardWeek: false)
        XCTAssertNil(center.pending["pgym.gym.2026-11-18"])
        XCTAssertEqual(center.pending["pgym.gym.2026-11-20"]?.body, "1 of 3 done this week.", "a draft is not a counted session")
    }

    /// Training after the reminder fired is showing up, not ignoring it.
    func testSessionAfterReminderFiredIsNotIgnored() async {
        let clock = TestClock(date(16, 9))
        let (scheduler, _) = makeScheduler(clock: clock)
        await scheduler.setFirstPlan(WeeklyPlan(goal: 3, days: mwf, time: six), remindersEnabled: true)

        clock.now = date(16, 19)
        await scheduler.sessionLogged(at: clock.now)
        XCTAssertEqual(scheduler.state.ignoredInARow, 0)
    }

    // MARK: Done when: a goal change applies from the next week

    /// Goal 3 set on Monday; on Tuesday the user raises it to 5. This week keeps goal 3 and its
    /// Mon/Wed/Fri reminders; Monday to Friday reminders start next Monday.
    func testGoalChangeAppliesFromNextWeek() async {
        // Set up after Monday's 18:00, so no reminder has fired (and been ignored) by Tuesday.
        let clock = TestClock(date(16, 19))
        let (scheduler, center) = makeScheduler(clock: clock)
        await scheduler.setFirstPlan(WeeklyPlan(goal: 3, days: mwf, time: six), remindersEnabled: true)

        clock.now = date(17, 8)
        await scheduler.changePlan(WeeklyPlan(goal: 5, days: monToFri, time: six))

        let thisWeek = WeekKey(year: 2026, week: 47)
        let nextWeek = WeekKey(year: 2026, week: 48)
        XCTAssertEqual(scheduler.currentPlan?.goal, 3, "this week's goal does not move")
        XCTAssertEqual(scheduler.state.schedule?.plan(for: thisWeek).goal, 3)
        XCTAssertEqual(scheduler.state.schedule?.plan(for: nextWeek).goal, 5)
        XCTAssertEqual(scheduler.state.schedule?.latest.goal, 5)

        let daily = gymDays(center)
        XCTAssertEqual(daily.map(\.fireDate), [date(18, 18), date(20, 18), date(23, 18), date(24, 18), date(25, 18)],
                       "Tue and Thu this week stay rest days; next week is Monday to Friday")
        XCTAssertEqual(daily[0].body, "0 of 3 done this week.")
        XCTAssertEqual(daily[2].body, "0 of 5 done this week.")

        // Next Monday the change is simply the plan.
        clock.now = date(23, 9)
        await scheduler.reschedule()
        XCTAssertEqual(scheduler.currentPlan?.goal, 5)
        XCTAssertNil(scheduler.state.schedule?.pending)
    }

    /// The time is not a commitment: a new time applies to this week's remaining reminders.
    func testTimeChangeAppliesNow() async {
        let clock = TestClock(date(16, 9))
        let (scheduler, center) = makeScheduler(clock: clock)
        await scheduler.setFirstPlan(WeeklyPlan(goal: 3, days: mwf, time: six), remindersEnabled: true)

        await scheduler.changePlan(WeeklyPlan(goal: 3, days: mwf, time: ReminderTime(hour: 7, minute: 30)))
        XCTAssertEqual(gymDays(center).first?.fireDate, date(18, 7, 30))
        XCTAssertNil(scheduler.state.schedule?.pending)
    }

    func testPlanScheduleWithdrawsPendingChange() {
        let w47 = WeekKey(year: 2026, week: 47)
        let w48 = WeekKey(year: 2026, week: 48)
        let three = WeeklyPlan(goal: 3, days: mwf, time: six)
        let five = WeeklyPlan(goal: 5, days: monToFri, time: six)
        let changed = PlanSchedule(first: three, week: w47).changing(to: five, during: w47, nextWeek: w48)
        XCTAssertEqual(changed.plan(for: w48), five)
        let back = changed.changing(to: three, during: w47, nextWeek: w48)
        XCTAssertNil(back.pending, "changing back before Monday withdraws the change")
        XCTAssertEqual(back.plan(for: w48), three)
    }

    // MARK: Back-off after 5 ignored

    /// Five reminders fire and none is opened: daily reminders and the nudge pause, the Monday
    /// line takes over. Opening any PGYM notification brings the daily ones back.
    func testBackOffAfterFiveIgnoredAndResumeOnOpen() async {
        let clock = TestClock(date(16, 9))
        let (scheduler, center) = makeScheduler(clock: clock)
        await scheduler.setFirstPlan(WeeklyPlan(goal: 5, days: monToFri, time: six), remindersEnabled: true)
        XCTAssertEqual(gymDays(center).count, 5)

        clock.now = date(21, 10) // Saturday: Mon to Fri fired, none opened, no session.
        await scheduler.reschedule()
        XCTAssertEqual(scheduler.state.ignoredInARow, 5)
        XCTAssertTrue(scheduler.isPaused)
        XCTAssertTrue(gymDays(center).isEmpty, "daily reminders pause")
        XCTAssertTrue(center.scheduled.filter { $0.kind == .sundayNudge }.isEmpty)
        let weekly = center.scheduled.filter { $0.kind == .weeklyLine }
        XCTAssertEqual(weekly.first?.fireDate, date(23, 18))
        XCTAssertEqual(weekly.first?.id, "pgym.weekly.2026-W48")

        await scheduler.notificationOpened("pgym.weekly.2026-W48")
        XCTAssertFalse(scheduler.isPaused)
        XCTAssertEqual(gymDays(center).first?.fireDate, date(23, 18))
        XCTAssertEqual(gymDays(center).count, 5)
    }

    /// Four ignored then one opened: the count starts again from zero.
    func testOpenedReminderResetsTheCount() async {
        let clock = TestClock(date(16, 9))
        let (scheduler, _) = makeScheduler(clock: clock)
        await scheduler.setFirstPlan(WeeklyPlan(goal: 5, days: monToFri, time: six), remindersEnabled: true)

        clock.now = date(20, 18, 5) // Friday's fired too
        await scheduler.notificationOpened("pgym.gym.2026-11-20")
        XCTAssertEqual(scheduler.state.ignoredInARow, 0)
        XCTAssertFalse(scheduler.isPaused)
    }

    /// Already paused: only the Monday line, every week of the horizon.
    func testPausedPlanHasOnlyWeeklyLines() {
        let plan = WeeklyPlan(goal: 4, days: [.mon, .tue, .thu, .fri], time: six)
        let out = ReminderPlanner.plan(inputs(now: date(17, 9), plan: plan, ignored: 5))
        XCTAssertTrue(out.allSatisfy { $0.kind == .weeklyLine })
        XCTAssertEqual(out.first?.fireDate, date(23, 18))
        XCTAssertEqual(out.first?.body, "4 sessions planned. Daily reminders are paused; open PGYM to turn them back on.")
    }

    // MARK: Switches and sign-out

    func testRemindersOffSchedulesNothing() async {
        let clock = TestClock(date(16, 9))
        let (scheduler, center) = makeScheduler(clock: clock)
        await scheduler.setFirstPlan(WeeklyPlan(goal: 3, days: mwf, time: six), remindersEnabled: false)
        XCTAssertTrue(center.pending.isEmpty)
    }

    func testResetClearsEverything() async {
        let clock = TestClock(date(16, 9))
        let (scheduler, center) = makeScheduler(clock: clock)
        await scheduler.setFirstPlan(WeeklyPlan(goal: 3, days: mwf, time: six), remindersEnabled: true)
        scheduler.reset()
        XCTAssertNil(scheduler.state.schedule)
        XCTAssertTrue(gymDays(center).isEmpty)
    }

    // MARK: Copy

    func testGymDayBodyVariantsInCopyDeckOrder() {
        let run = ReminderFacts.LastRun(exercise: "Bench press", weight: 62.5, reps: 8)
        XCTAssertEqual(ReminderCopy.gymDayBody(left: 1, done: 3, goal: 4, weekToLock: 7, lastRun: run, unit: "kg", lastGymDayMissed: true, nextProof: 42),
                       "One session locks week 7.")
        XCTAssertEqual(ReminderCopy.gymDayBody(left: 2, done: 2, goal: 4, weekToLock: 7, lastRun: run, unit: "kg", lastGymDayMissed: true, nextProof: 42),
                       "2 of 4 done this week.")
        XCTAssertEqual(ReminderCopy.gymDayBody(left: 0, done: 4, goal: 4, weekToLock: 7, lastRun: run, unit: "kg", lastGymDayMissed: true, nextProof: 42),
                       "Last time: Bench press 62.5 kg x 8. Same again is fine.")
        XCTAssertEqual(ReminderCopy.gymDayBody(left: 0, done: 4, goal: 4, weekToLock: 7, lastRun: nil, unit: "kg", lastGymDayMissed: true, nextProof: 42),
                       "One set and a photo still counts.")
        XCTAssertEqual(ReminderCopy.gymDayBody(left: 0, done: 4, goal: 4, weekToLock: 7, lastRun: nil, unit: "kg", lastGymDayMissed: false, nextProof: 42),
                       "Proof #042 is next.")
    }

    /// No guilt words in anything the planner can send.
    func testNoGuiltCopy() {
        let plan = WeeklyPlan(goal: 5, days: monToFri, time: six)
        let texts = ReminderPlanner.plan(inputs(now: date(19, 9), plan: plan, sessions: 4)).flatMap { [$0.title, $0.body] }
        for banned in ["missed", "broke", "lose", "lost", "streak is", "hurry", "!"] {
            XCTAssertFalse(texts.contains { $0.localizedCaseInsensitiveContains(banned) }, "found \(banned)")
        }
    }
}
