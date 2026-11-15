import XCTest
@testable import PGYM

/// Onboarding B1 to B5 against the fakes: the goal must be chosen, the days must match it, the
/// answers land on `users/{uid}`, the starter routines are written, and reminders are scheduled.
/// Each test's world is built lazily inside the test (on the main actor), as in AuthFlowTests.
@MainActor
private final class World {
    let auth: FakeAuthService
    let users: FakeUserRepository
    let drafts = InMemoryOnboardingDraftStore()
    let center: FakeNotificationCenter
    let session: AppSession
    let scheduler: ReminderScheduler

    init() {
        let auth = FakeAuthService()
        let users = FakeUserRepository()
        let center = FakeNotificationCenter()
        self.auth = auth
        self.users = users
        self.center = center
        session = AppSession(
            dependencies: .fake(auth: auth, users: users),
            currentYear: { 2026 },
            units: .kg,
            timezone: "Europe/Amsterdam"
        )
        let zone = TimeZone(identifier: "Europe/Amsterdam")!
        let calendar = PlanCalendar(timeZone: zone)
        var parts = DateComponents(year: 2026, month: 11, day: 16, hour: 9)
        parts.timeZone = zone
        let monday = calendar.calendar.date(from: parts)!
        scheduler = ReminderScheduler(
            center: center,
            store: InMemoryReminderStore(),
            calendar: calendar,
            locale: Locale(identifier: "en_GB"),
            clock: { monday }
        )
    }
}

@MainActor
final class OnboardingTests: XCTestCase {
    private var world: World?
    private var current: World {
        if let world { return world }
        let made = World()
        world = made
        return made
    }

    private var auth: FakeAuthService { current.auth }
    private var users: FakeUserRepository { current.users }
    private var drafts: InMemoryOnboardingDraftStore { current.drafts }
    private var center: FakeNotificationCenter { current.center }
    private var session: AppSession { current.session }
    private var scheduler: ReminderScheduler { current.scheduler }

    /// A brand-new user, through A5, standing on B1.
    private func newUserOnB1() async throws -> OnboardingModel {
        auth.addEmailAccount(email: "new@example.com", password: "longenough")
        try await session.signIn(email: "new@example.com", password: "longenough")
        try await session.submitBirthYear(1990)
        XCTAssertEqual(session.route, .onboarding)
        let uid = try XCTUnwrap(session.user?.uid)
        return OnboardingModel(uid: uid, startingUnits: session.startingUnits, store: drafts)
    }

    // MARK: B1

    func testGoalIsNotPreselectedAndSentenceFollowsTheNumber() async throws {
        let model = try await newUserOnB1()
        XCTAssertNil(model.draft.goal, "the commitment depends on the user choosing")
        XCTAssertFalse(model.canLockIn)
        XCTAssertNil(model.commitment)

        model.lockIn()
        XCTAssertEqual(model.step, .goal, "Lock it in does nothing before a number is picked")

        model.pickGoal(4)
        XCTAssertEqual(model.commitment, "I will train 4 days a week.")
        model.pickGoal(7)
        XCTAssertEqual(model.draft.goal, 4, "only 2 to 6")
        model.pickGoal(1)
        XCTAssertEqual(model.draft.goal, 4)

        model.lockIn()
        XCTAssertEqual(model.step, .days)
    }

    // MARK: B2

    func testDaysMustMatchTheGoal() async throws {
        let model = try await newUserOnB1()
        model.pickGoal(3)
        model.lockIn()

        XCTAssertEqual(model.draft.days, [.mon, .wed, .fri], "pre-filled spread for 3")
        XCTAssertTrue(model.daysMatchGoal)
        XCTAssertEqual(model.counterText, "3 of 3 picked")

        model.toggle(.sat)
        XCTAssertTrue(model.isOverGoal)
        XCTAssertEqual(model.counterText, "4 of 3 picked")
        model.continueFromDays()
        XCTAssertEqual(model.step, .days, "Continue is off until the count matches")

        model.toggle(.sat)
        model.toggle(.fri)
        XCTAssertFalse(model.daysMatchGoal)
        model.continueFromDays()
        XCTAssertEqual(model.step, .days)

        model.toggle(.sun)
        XCTAssertTrue(model.daysMatchGoal)
        model.continueFromDays()
        XCTAssertEqual(model.step, .reminders)
    }

    /// "Change the goal" goes back to B1; a new goal brings its own spread.
    func testChangingTheGoalRefillsTheDays() async throws {
        let model = try await newUserOnB1()
        model.pickGoal(3)
        model.lockIn()
        model.changeGoal()
        XCTAssertEqual(model.step, .goal)
        XCTAssertFalse(model.movingForward)

        model.pickGoal(5)
        model.lockIn()
        XCTAssertEqual(model.draft.days, [.mon, .tue, .wed, .thu, .fri])
        XCTAssertTrue(model.daysMatchGoal)
    }

    func testDefaultSpreadsMatchEveryGoal() {
        for goal in GoalPolicy.range {
            XCTAssertEqual(GoalPolicy.defaultDays(for: goal).count, goal, "goal \(goal)")
        }
    }

    // MARK: B3 and B4, and saving

    /// The whole path: everything lands on `users/{uid}`, the starter routines are written,
    /// reminders are scheduled, and the user is on the tabs.
    func testFinishingSavesEverythingToTheUserDocument() async throws {
        let model = try await newUserOnB1()
        model.pickGoal(4)
        model.toggleUnits()
        XCTAssertEqual(model.draft.units, .lb)
        model.toggleUnits()
        model.lockIn()
        model.setTime(ReminderTime(hour: 18, minute: 30))
        model.continueFromDays()

        await model.turnOnReminders(scheduler)
        XCTAssertEqual(center.authorizationRequests, 1, "the iOS prompt only after the reason")
        XCTAssertEqual(model.draft.reminders, .allowed)
        XCTAssertEqual(model.step, .routine)

        XCTAssertEqual(model.selectedStarter, .upperLower, "4 days fits Upper/Lower")
        await model.finish(session: session, scheduler: scheduler)

        let uid = try XCTUnwrap(session.user?.uid)
        let write = try XCTUnwrap(users.onboardingWrites.last)
        XCTAssertEqual(write.uid, uid)
        let fields = write.settings.firestoreFields
        XCTAssertEqual(fields["goalPerWeek"] as? Int, 4)
        XCTAssertEqual(fields["gymDays"] as? [String], ["mon", "tue", "thu", "fri"])
        XCTAssertEqual(fields["reminderTime"] as? String, "18:30")
        XCTAssertEqual(fields["units"] as? String, "kg")
        XCTAssertEqual(fields["timezone"] as? String, "Europe/Amsterdam")
        XCTAssertEqual(Set(fields.keys), ["goalPerWeek", "gymDays", "reminderTime", "units", "timezone"],
                       "no server-owned field is written")

        XCTAssertEqual(users.routines[uid]?.keys.sorted(), ["starter-lower", "starter-upper"])
        XCTAssertEqual(users.documents[uid]?.goalPerWeek, 4)
        XCTAssertEqual(session.route, .main)
        XCTAssertNil(drafts.load(uid: uid), "the draft is gone once saved")

        XCTAssertEqual(scheduler.currentPlan?.goal, 4)
        let first = try XCTUnwrap(center.scheduled.first { $0.kind == .gymDay })
        XCTAssertEqual(first.title, "Upper at 18:30")

        // Signing back in goes to the tabs: onboarding is done.
        try session.signOut()
        try await session.signIn(email: "new@example.com", password: "longenough")
        XCTAssertEqual(session.route, .main)
    }

    func testSkippingRemindersSchedulesNothingAndNeverPrompts() async throws {
        let model = try await newUserOnB1()
        model.pickGoal(2)
        model.lockIn()
        model.continueFromDays()
        model.skipReminders()
        XCTAssertEqual(model.step, .routine)
        XCTAssertEqual(model.selectedStarter, .fullBody)

        await model.finish(buildOwn: true, session: session, scheduler: scheduler)
        XCTAssertEqual(center.authorizationRequests, 0)
        XCTAssertTrue(center.pending.isEmpty)
        XCTAssertEqual(session.route, .main)
        XCTAssertNil(users.routines[session.user?.uid ?? ""], "Build my own writes no starter")
    }

    func testDeclinedPromptShowsTheSettingsLine() async throws {
        center.grants = false
        let model = try await newUserOnB1()
        model.pickGoal(3)
        model.lockIn()
        model.continueFromDays()
        await model.turnOnReminders(scheduler)
        XCTAssertEqual(model.step, .routine, "B4 whatever the answer")
        XCTAssertTrue(model.showsRemindersDeclined)
    }

    func testSaveFailureStaysOnB4() async throws {
        let model = try await newUserOnB1()
        model.pickGoal(3)
        model.lockIn()
        model.continueFromDays()
        model.skipReminders()
        users.nextError = URLError(.notConnectedToInternet)

        await model.finish(session: session, scheduler: scheduler)
        XCTAssertEqual(model.errorText, OnboardingCopy.couldNotSave)
        XCTAssertEqual(session.route, .onboarding)
        XCTAssertNil(scheduler.state.schedule)
    }

    // MARK: Resume

    /// Quitting mid-way resumes at the same step with the same answers.
    func testQuittingResumesAtTheSameStep() async throws {
        let model = try await newUserOnB1()
        model.pickGoal(5)
        model.lockIn()
        model.toggle(.fri)
        model.toggle(.sat)

        let uid = try XCTUnwrap(session.user?.uid)
        let resumed = OnboardingModel(uid: uid, startingUnits: .kg, store: drafts)
        XCTAssertEqual(resumed.step, .days)
        XCTAssertEqual(resumed.draft.goal, 5)
        XCTAssertEqual(resumed.draft.days, [.mon, .tue, .wed, .thu, .sat])
    }

    // MARK: B5 units

    /// Units default from the phone's region: pounds where iOS reports US measures, else kg.
    func testUnitsDefaultFromRegion() {
        XCTAssertEqual(NewUserProfile.Units.default(for: Locale(identifier: "en_US")), .lb)
        XCTAssertEqual(NewUserProfile.Units.default(for: Locale(identifier: "en_GB")), .kg)
        XCTAssertEqual(NewUserProfile.Units.default(for: Locale(identifier: "de_DE")), .kg)
        XCTAssertEqual(NewUserProfile.Units.default(for: Locale(identifier: "pl_PL")), .kg)
    }

    func testOnboardingStartsOnTheRegionUnits() async throws {
        let lbSession = AppSession(dependencies: .fake(), currentYear: { 2026 }, units: .lb, timezone: "America/Chicago")
        XCTAssertEqual(lbSession.startingUnits, .lb)
        let model = OnboardingModel(uid: "someone", startingUnits: lbSession.startingUnits, store: InMemoryOnboardingDraftStore())
        XCTAssertEqual(model.draft.units, .lb)
    }

    // MARK: Starters

    func testStartersFitTheGoal() {
        XCTAssertEqual(StarterRoutine.suggested(for: 2), .fullBody)
        XCTAssertEqual(StarterRoutine.suggested(for: 3), .fullBody)
        XCTAssertEqual(StarterRoutine.suggested(for: 4), .upperLower)
        XCTAssertEqual(StarterRoutine.suggested(for: 5), .pushPullLegs)
        XCTAssertEqual(StarterRoutine.suggested(for: 6), .pushPullLegs)
        for starter in StarterRoutine.allCases {
            XCTAssertFalse(starter.routines.isEmpty)
            XCTAssertEqual(Set(starter.routines.map(\.id)).count, starter.routines.count, "unique IDs")
            let fields = starter.routines[0].firestoreFields
            XCTAssertNotNil(fields["exercises"] as? [[String: Any]])
        }
    }

    func testProfilePlanReadsBackFromTheDocument() {
        let profile = UserProfile(uid: "u", birthYear: 1990, goalPerWeek: 3, gymDays: [.mon, .wed, .fri], reminderTime: ReminderTime(string: "07:15"))
        XCTAssertEqual(profile.plan, WeeklyPlan(goal: 3, days: [.mon, .wed, .fri], time: ReminderTime(hour: 7, minute: 15)))
        let broken = UserProfile(uid: "u", birthYear: 1990, goalPerWeek: 4, gymDays: [.mon])
        XCTAssertNil(broken.plan, "days that do not match the goal are not a plan")
    }
}
