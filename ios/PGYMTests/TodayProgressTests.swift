import DesignSystem
import SwiftData
import XCTest
@testable import PGYM

/// Card I8: the week row, the four Today states, the 12-week series, the proof wall, lifts, the score
/// history, and turning the physique score off. Everything is built from fixtures; nothing touches the
/// network, Firebase or S3.
@MainActor
final class TodayProgressTests: XCTestCase {
    private let la = TimeZone(identifier: "America/Los_Angeles")!
    private let london = TimeZone(identifier: "Europe/London")!
    private let mwf: Set<Weekday> = [.mon, .wed, .fri]

    private var containers: [ModelContainer] = []
    private var roots: [URL] = []

    override func tearDown() {
        for root in roots { try? FileManager.default.removeItem(at: root) }
        roots = []
        containers = []
        super.tearDown()
    }

    // MARK: Fixtures

    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: iso) else {
            XCTFail("bad fixture date \(iso)")
            return .distantPast
        }
        return date
    }

    private func session(
        _ iso: String,
        tz: String = "Europe/London",
        status: SessionStatus = .stamped,
        proof: Int? = nil,
        routine: String = "Push A",
        routineId: String? = "push-a",
        exercises: [SessionSnapshot.Exercise] = [],
        score: Int? = nil,
        refused: String? = nil,
        receipt: StampReceipt? = nil
    ) -> SessionSnapshot {
        let start = date(iso)
        let ended = status == .draft ? start.addingTimeInterval(3000) : start.addingTimeInterval(3000)
        return SessionSnapshot(
            id: UUID().uuidString,
            routineId: routineId,
            routineName: routine,
            startedAt: start,
            endedAt: ended,
            timezone: tz,
            status: status,
            proofNumber: status == .stamped ? (proof ?? 1) : nil,
            stampedAt: status == .stamped ? ended : nil,
            receipt: receipt,
            exercises: exercises,
            physiqueScore: score,
            physiqueTip: score == nil ? nil : "Add a third set of rows.",
            physiqueRefusedReason: refused,
            cardKey: status == .stamped ? "users/u1/sessions/x/card.jpg" : nil
        )
    }

    private func receipt(at iso: String, weekCount: Int, weekGoal: Int, streak: Int, longest: Int, passes: Int = 0, proofCount: Int) -> StampReceipt {
        StampReceipt(
            sessionId: "s", proofNumber: proofCount, stampedAt: date(iso), weekKey: "", weekCount: weekCount,
            weekGoal: weekGoal, streakWeeks: streak, longestStreak: longest, passWeeks: passes, proofCount: proofCount,
            setCount: 10, totalVolume: 1000, durationSec: 3000, newBests: [], alreadyStamped: false
        )
    }

    private func bench(_ sets: [(Double, Int, SetType)]) -> SessionSnapshot.Exercise {
        SessionSnapshot.Exercise(
            exerciseId: "barbell-bench-press",
            name: "Bench press",
            sets: sets.enumerated().map { index, set in
                SessionSnapshot.LoggedSet(n: index + 1, weightKg: set.0, reps: set.1, type: set.2, done: true)
            }
        )
    }

    private func profile(streak: Int? = nil, proofCount: Int? = nil, longest: Int? = nil) -> UserProfile {
        UserProfile(
            uid: "u1", displayName: "Sam", email: "sam@example.com", birthYear: 1990, createdAt: nil,
            goalPerWeek: 3, gymDays: [.mon, .wed, .fri], reminderTime: .default, units: .kg,
            streakWeeks: streak, proofCount: proofCount, longestStreak: longest, passWeeks: nil, physiqueConsent: nil
        )
    }

    private func today(_ sessions: [SessionSnapshot], now iso: String, profile: UserProfile? = nil, tz: TimeZone? = nil) -> TodayModel {
        TodayModel(TodayModel.Inputs(
            sessions: sessions,
            plan: WeeklyPlan(goal: 3, days: mwf, time: .default),
            profile: profile ?? self.profile(streak: 6),
            now: date(iso),
            timeZone: tz ?? london
        ))
    }

    // MARK: Week row, west of UTC

    /// Los Angeles is UTC-8 in November. An evening session on Monday is already Tuesday in UTC, and a
    /// Sunday-night session is already Monday of the next week in UTC. Both must land on the local day.
    func testWeekRowForAUserWestOfUTC() {
        let mondayEvening = session("2026-11-17T02:00:00Z", tz: la.identifier)   // Mon 16 Nov 18:00 PST
        let sundayNight = session("2026-11-16T05:00:00Z", tz: la.identifier)     // Sun 15 Nov 21:00 PST
        let savedWithoutProof = session("2026-11-17T01:00:00Z", tz: la.identifier, status: .finished)

        // The fixtures do cross midnight in UTC.
        XCTAssertEqual(PlanCalendar(timeZone: TimeZone(identifier: "UTC")!).weekday(for: mondayEvening.startedAt), .tue)
        XCTAssertEqual(PlanCalendar(timeZone: TimeZone(identifier: "UTC")!).weekKey(for: sundayNight.startedAt).description, "2026-W47")

        let now = date("2026-11-17T03:00:00Z") // Mon 16 Nov 19:00 PST
        let row = WeekRow.make(sessions: [mondayEvening, sundayNight, savedWithoutProof], gymDays: mwf, goal: 3, now: now, timeZone: la)

        XCTAssertEqual(row.week.description, "2026-W47")
        XCTAssertEqual(row.today, .mon)
        XCTAssertEqual(row.count, 1, "Sunday night is last week; a session saved without proof never counts")
        XCTAssertEqual(row.days.map(\.status), [.done, .rest, .planned, .rest, .planned, .rest, .rest])
        XCTAssertFalse(row.isGoalReached)

        // Sunday 22:30 in Los Angeles is Monday in UTC: still the same local week, Monday still done.
        let sundayLate = WeekRow.make(sessions: [mondayEvening], gymDays: mwf, goal: 3, now: date("2026-11-23T06:30:00Z"), timeZone: la)
        XCTAssertEqual(sundayLate.week.description, "2026-W47")
        XCTAssertEqual(sundayLate.today, .sun)
        XCTAssertEqual(sundayLate.count, 1)
        XCTAssertEqual(sundayLate.days.first?.status, .done)
        XCTAssertEqual(sundayLate.days.last?.status, .today)
    }

    func testPendingProofCountsTowardTheWeek() {
        let pending = session("2026-11-16T18:00:00Z", status: .draft)
        XCTAssertTrue(pending.isPending)
        let row = WeekRow.make(sessions: [pending], gymDays: mwf, goal: 3, now: date("2026-11-16T20:00:00Z"), timeZone: london)
        XCTAssertEqual(row.count, 1)
        XCTAssertEqual(row.days.first?.status, .done)
    }

    // MARK: The four Today states

    func testTodayFirstRunWhenThereIsNoProof() {
        let started = session("2026-11-16T09:00:00Z", status: .finished)
        let model = today([started], now: "2026-11-16T12:00:00Z", profile: profile(streak: 0, proofCount: 0))
        XCTAssertEqual(model.state, .firstRun)
        XCTAssertEqual(model.state.viewID, "C4")
        XCTAssertNil(model.streakStampText, "C4 hides the streak stamp")
        XCTAssertNil(model.lastProof, "and the last proof row")
        XCTAssertEqual(model.weekRow.count, 0)
        XCTAssertEqual(model.weekRow.goal, 3)
    }

    func testTodayGymDayWithSessionsToGo() {
        let monday = session("2026-11-16T09:00:00Z", proof: 41)
        let model = today([monday], now: "2026-11-18T09:00:00Z")
        XCTAssertEqual(model.state, .gymDay)
        XCTAssertEqual(model.state.viewID, "C1")
        XCTAssertEqual(model.weekRow.count, 1)
        XCTAssertEqual(model.lockLine, "2 more to lock week 7.")
        XCTAssertEqual(model.streakStampText, "6 weeks running")
        XCTAssertEqual(model.lastProof?.proofNumber, 41)

        let wednesday = session("2026-11-18T08:00:00Z", proof: 42)
        let oneLeft = today([monday, wednesday], now: "2026-11-20T09:00:00Z")
        XCTAssertEqual(oneLeft.state, .gymDay)
        XCTAssertEqual(oneLeft.lockLine, "One session locks week 7.")
        XCTAssertEqual(oneLeft.lastProof?.proofNumber, 42, "newest first")
    }

    func testTodayRestDayNamesTheNextGymDay() {
        let monday = session("2026-11-16T09:00:00Z")
        let model = today([monday], now: "2026-11-17T09:00:00Z")
        XCTAssertEqual(model.state, .restDay(nextDay: .wed))
        XCTAssertEqual(model.state.viewID, "C2")
        XCTAssertNil(model.lockLine)

        // Sunday's next gym day wraps to Monday.
        XCTAssertEqual(TodayModel.nextGymDay(after: .sun, in: mwf), .mon)
        XCTAssertEqual(TodayCopy.nextSession(routine: "Pull A", day: "Thursday"), "Next session: Pull A on Thursday.")
    }

    func testTodayWeekDoneWhenTheGoalIsReached() {
        let week = [
            session("2026-11-16T09:00:00Z"),
            session("2026-11-18T09:00:00Z"),
            session("2026-11-20T09:00:00Z"),
        ]
        // No receipt this week: the week it locks is the profile's streak plus one.
        let local = today(week, now: "2026-11-21T10:00:00Z")
        XCTAssertEqual(local.state, .weekDone(week: 7))
        XCTAssertEqual(local.state.viewID, "C3")
        XCTAssertTrue(local.weekRow.isGoalReached)
        XCTAssertEqual(local.weekRow.days.filter { $0.status == .done }.map(\.weekday), [.mon, .wed, .fri])

        // With the server's answer from this week, its streak is the locked week.
        var stamped = week
        stamped[2].receipt = receipt(at: "2026-11-20T10:00:00Z", weekCount: 3, weekGoal: 3, streak: 7, longest: 9, proofCount: 42)
        let server = today(stamped, now: "2026-11-21T10:00:00Z")
        XCTAssertEqual(server.state, .weekDone(week: 7))
        XCTAssertEqual(server.streak.longestStreak, 9)
        XCTAssertEqual(server.streakStampText, "7 weeks running")

        // A goal day after the goal is reached is still C3, not C1: no "more to lock" line.
        let fridayAgain = today(week, now: "2026-11-20T18:00:00Z")
        XCTAssertEqual(fridayAgain.state, .weekDone(week: 7))
        XCTAssertNil(fridayAgain.lockLine)
    }

    func testFreshStartOnMondayAfterAShortWeek() {
        let lastWeek = session("2026-11-11T09:00:00Z") // Wed of W46: 1 of 3
        let model = today([lastWeek], now: "2026-11-16T08:00:00Z")
        XCTAssertTrue(model.freshStart)
        XCTAssertEqual(TodayCopy.newWeek(goal: 3), "New week. 0 of 3.")
        XCTAssertEqual(model.state, .gymDay)
    }

    func testStreakStampCopy() {
        XCTAssertEqual(TodayCopy.streak(0), "Week 1")
        XCTAssertEqual(TodayCopy.streak(1), "1 week running")
        XCTAssertEqual(TodayCopy.streak(12), "12 weeks running")
    }

    // MARK: 12-week series

    func testTwelveWeekSeriesFromFixtures() {
        let sessions = [
            session("2026-08-25T10:00:00Z"),                    // W35, outside the window
            session("2026-09-01T10:00:00Z"),                    // W36, the oldest bar
            session("2026-11-02T10:00:00Z"),                    // W45
            session("2026-11-03T10:00:00Z"),                    // W45
            session("2026-11-04T10:00:00Z"),                    // W45
            session("2026-11-10T10:00:00Z", status: .finished), // W46, no proof: not counted
            session("2026-11-11T10:00:00Z", status: .draft),    // W46, waiting for its stamp: counted
            session("2026-11-16T10:00:00Z"),                    // W47
            session("2026-11-17T10:00:00Z"),                    // W47
        ]
        let calendar = PlanCalendar(timeZone: london)
        let bars = ProgressModel.twelveWeeks(sessions, now: date("2026-11-18T12:00:00Z"), timeZone: london) { week in
            week >= WeekKey(year: 2026, week: 46) ? 4 : 3
        }

        XCTAssertEqual(bars.count, 12)
        XCTAssertEqual(bars.first?.week.description, "2026-W36")
        XCTAssertEqual(bars.last?.week.description, "2026-W47")
        XCTAssertEqual(bars.filter(\.isCurrent).map(\.week.description), ["2026-W47"])
        XCTAssertEqual(bars.map(\.count), [1, 0, 0, 0, 0, 0, 0, 0, 0, 3, 1, 2])
        XCTAssertEqual(bars.map(\.goal), [3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 4, 4])
        XCTAssertEqual(bars.filter(\.isHit).map(\.week.description), ["2026-W45"])
        for bar in bars {
            XCTAssertEqual(bar.start, calendar.startOfWeek(bar.week))
        }
    }

    /// 2026 has 53 ISO weeks; the series runs through W53 into 2027 without a gap.
    func testTwelveWeekSeriesAcrossTheYearEnd() {
        let bars = ProgressModel.twelveWeeks([session("2026-12-29T10:00:00Z")], now: date("2027-01-06T12:00:00Z"), timeZone: london) { _ in 3 }
        XCTAssertEqual(bars.map(\.week.description).suffix(3), ["2026-W52", "2026-W53", "2027-W01"])
        XCTAssertEqual(bars.first { $0.week.description == "2026-W53" }?.count, 1)
    }

    func testTwelveWeekSeriesWhenEmpty() {
        let bars = ProgressModel.twelveWeeks([], now: date("2026-11-18T12:00:00Z"), timeZone: london) { _ in 3 }
        XCTAssertEqual(bars.count, 12)
        XCTAssertTrue(bars.allSatisfy { $0.count == 0 })
    }

    // MARK: Proof wall, lifts, scores

    func testProofWallNewestFirstByMonthWithoutUnstampedSessions() {
        let groups = ProgressModel.proofWall([
            session("2026-10-30T10:00:00Z", proof: 1),
            session("2026-11-02T10:00:00Z", proof: 2),
            session("2026-11-05T10:00:00Z", status: .finished),
            session("2026-11-16T10:00:00Z", status: .draft),
        ], timeZone: london)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].sessions.count, 2, "November: the pending card and #002")
        XCTAssertTrue(groups[0].sessions[0].isPending)
        XCTAssertEqual(groups[0].sessions[1].proofNumber, 2)
        XCTAssertEqual(groups[1].sessions.map(\.proofNumber), [1])
    }

    func testLiftsAndLiftHistory() {
        let first = session("2026-11-02T10:00:00Z", proof: 1, exercises: [bench([(60, 10, .warmup), (80, 8, .working)])])
        let noProof = session("2026-11-05T10:00:00Z", status: .finished, exercises: [bench([(85, 5, .working)])])
        let best = session("2026-11-09T10:00:00Z", proof: 2, exercises: [bench([(90, 6, .working), (70, 12, .working)])])

        let lifts = ProgressModel.lifts([first, noProof, best])
        XCTAssertEqual(lifts.count, 1)
        XCTAssertEqual(lifts[0].bestWeightKg, 90)
        XCTAssertEqual(lifts[0].bestReps, 6)
        XCTAssertEqual(lifts[0].bestE1rmKg, 108, "Epley: 90 x (1 + 6/30)")
        XCTAssertEqual(lifts[0].sessionCount, 3)

        let history = ProgressModel.liftHistory(exerciseId: "barbell-bench-press", in: [first, noProof, best])
        XCTAssertEqual(history.name, "Bench press")
        XCTAssertEqual(history.entries.map(\.isProof), [true, false, true], "newest first, the no-proof session included")
        XCTAssertEqual(history.points.map(\.e1rmKg), [101.3, 99.2, 108], "oldest first")
        XCTAssertEqual(history.best?.kg, 90)
        XCTAssertEqual(history.entries.last?.sets.count, 2, "warm-ups are listed with the sets")
    }

    func testScoreHistoryKeepsRefusalsAsGaps() {
        let points = ProgressModel.scoreHistory([
            session("2026-11-02T10:00:00Z", score: 61),
            session("2026-11-04T10:00:00Z", refused: "several_people"),
            session("2026-11-06T10:00:00Z", score: 64),
            session("2026-11-07T10:00:00Z"),
        ])
        XCTAssertEqual(points.map(\.score), [61, nil, 64])
        XCTAssertEqual(ProgressModel.latestScore([session("2026-11-02T10:00:00Z", score: 61), session("2026-11-06T10:00:00Z", score: 64)]), 64)
        let segments = ScoreHistoryScreen.segments(points)
        XCTAssertEqual(segments.map(\.segment), [0, 1], "the refusal breaks the line")
        XCTAssertEqual(ProgressCopy.refusal("several_people"), "More than one person in the photo.")
        XCTAssertEqual(ProgressCopy.refusal("apparent_minor"), "This photo cannot be scored.")
        XCTAssertEqual(ProgressCopy.refusal("daily_limit"), "Scoring did not work this time.")
    }

    func testStreakFactsIgnoreAReceiptOlderThanLastWeek() {
        var old = session("2026-10-05T10:00:00Z")
        old.receipt = receipt(at: "2026-10-05T11:00:00Z", weekCount: 3, weekGoal: 3, streak: 9, longest: 9, proofCount: 30)
        let facts = StreakFacts.make(sessions: [old], profile: profile(streak: 0, proofCount: 31, longest: 9), now: date("2026-11-18T12:00:00Z"), timeZone: london)
        XCTAssertEqual(facts.streakWeeks, 0, "rollWeek may have moved it since; the profile wins")
        XCTAssertEqual(facts.proofCount, 31)
        XCTAssertEqual(facts.longestStreak, 9)
        XCTAssertEqual(facts.lockingWeekNumber, 1)
    }

    // MARK: Turning the physique score off

    private struct PrivacyRig {
        let container: ModelContainer
        let context: ModelContext
        let defaults: UserDefaults
        let writer: FakePhysiqueConsentWriter
        let consent: PhysiqueConsent
        let api: FakePrivacyAPI
        let source: FakePhysiqueSource
        let controls: DataControls
        let scored: WorkoutSession
        let refused: WorkoutSession
    }

    private func makePrivacyRig() throws -> PrivacyRig {
        let container = Models.makeContainer(inMemory: true)
        containers.append(container)
        let context = container.mainContext
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "pgym-i8-\(UUID().uuidString)"))
        let writer = FakePhysiqueConsentWriter()
        let consent = PhysiqueConsent(defaults: defaults, writer: writer)
        consent.load(uid: "u1", profileValue: true)
        let api = FakePrivacyAPI()
        let source = FakePhysiqueSource()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("i8-\(UUID().uuidString)")
        roots.append(root)
        let controls = DataControls(api: api, consent: consent, physique: source, store: ProofStore(root: root), images: nil, defaults: defaults)

        func stamped(_ number: Int, record: PhysiqueRecord) -> WorkoutSession {
            let session = WorkoutSession(routineId: nil, routineName: "Push A", startedAt: date("2026-11-1\(number)T10:00:00Z"), timezone: "Europe/London")
            session.endedAt = session.startedAt.addingTimeInterval(3000)
            session.status = .stamped
            session.proofNumber = number
            session.applyPhysique(record)
            context.insert(session)
            return session
        }
        let scored = stamped(1, record: PhysiqueRecord(score: 72, tip: "Add a third set of rows."))
        let refused = stamped(2, record: PhysiqueRecord(refusedReason: "unreadable"))
        try context.save()
        return PrivacyRig(
            container: container, context: context, defaults: defaults, writer: writer, consent: consent,
            api: api, source: source, controls: controls, scored: scored, refused: refused
        )
    }

    func testTurningAnalysisOffClearsScoresLocallyAndCallsTheServer() async throws {
        let rig = try makePrivacyRig()
        XCTAssertTrue(rig.consent.isOn)
        XCTAssertEqual(rig.scored.physiqueScore, 72)
        XCTAssertTrue(rig.refused.hasPhysique)

        let reached = await rig.controls.turnOffAnalysis(context: rig.context)

        XCTAssertTrue(reached)
        // On the phone: nothing left to show.
        let all = try rig.context.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertTrue(all.allSatisfy { !$0.hasPhysique && $0.physique == nil })
        XCTAssertNil(rig.scored.physiqueTip)
        // On the server: the consent flag goes false and the stored scores are deleted.
        XCTAssertFalse(rig.consent.isOn)
        XCTAssertEqual(rig.writer.writes, [false])
        XCTAssertEqual(rig.api.deleteScoresCalls, 1)
        XCTAssertFalse(rig.controls.scoreErasePending)
        XCTAssertFalse(rig.defaults.bool(forKey: DataControls.erasePendingKey))
    }

    func testTurningAnalysisOffOfflineClearsAtOnceAndRetriesTheServerDelete() async throws {
        let rig = try makePrivacyRig()
        rig.api.failure = ProofAPIError.offline
        rig.source.deliver(PhysiqueRecord(score: 72, tip: "x"), for: rig.scored.id)

        let reached = await rig.controls.turnOffAnalysis(context: rig.context)

        XCTAssertFalse(reached)
        XCTAssertNil(rig.scored.physiqueScore, "cleared on the phone even without a connection")
        XCTAssertFalse(rig.consent.isOn)
        XCTAssertTrue(rig.controls.scoreErasePending)
        XCTAssertTrue(rig.defaults.bool(forKey: DataControls.erasePendingKey), "survives a relaunch")

        // A refresh while the delete waits never brings a score back.
        try await rig.controls.refreshScores(uid: "u1", context: rig.context)
        XCTAssertNil(rig.scored.physiqueScore)

        rig.api.failure = nil
        await rig.controls.retryPending()
        XCTAssertEqual(rig.api.deleteScoresCalls, 1)
        XCTAssertFalse(rig.controls.scoreErasePending)
        await rig.controls.retryPending()
        XCTAssertEqual(rig.api.deleteScoresCalls, 1, "nothing left to send")
    }

    func testRefreshScoresCopiesTheServerResultWhileOn() async throws {
        let rig = try makePrivacyRig()
        rig.source.deliver(PhysiqueRecord(score: 75, tip: "Pause at the bottom."), for: rig.scored.id)
        try await rig.controls.refreshScores(uid: "u1", context: rig.context)
        XCTAssertEqual(rig.scored.physiqueScore, 75)
        XCTAssertEqual(rig.scored.physiqueTip, "Pause at the bottom.")
        XCTAssertFalse(rig.refused.hasPhysique, "the server no longer has the refusal")
    }

    func testDeleteAllPhotosKeepsSessionsAndProofNumbers() async throws {
        let rig = try makePrivacyRig()
        rig.scored.cardKey = "users/u1/sessions/\(rig.scored.id)/card.jpg"
        rig.scored.photoKey = "users/u1/sessions/\(rig.scored.id)/photo.jpg"
        let removed = try await rig.controls.deleteAllPhotos(context: rig.context)
        XCTAssertEqual(removed, 1)
        XCTAssertEqual(rig.api.deletePhotosCalls, 1)
        XCTAssertNil(rig.scored.cardKey)
        XCTAssertEqual(rig.scored.proofNumber, 1)
        XCTAssertEqual(try rig.context.fetch(FetchDescriptor<WorkoutSession>()).count, 2)
    }

    func testDeleteSessionCallsTheServerForAStampedSession() async throws {
        let rig = try makePrivacyRig()
        let id = rig.scored.id
        try await rig.controls.deleteSession(rig.scored, context: rig.context)
        XCTAssertEqual(rig.api.deletedSessions, [id])
        XCTAssertEqual(try rig.context.fetch(FetchDescriptor<WorkoutSession>()).count, 1)
    }

    // MARK: Export

    func testExportIsJSONWithProfileRoutinesSessionsAndSets() throws {
        let container = Models.makeContainer(inMemory: true)
        containers.append(container)
        let context = container.mainContext
        let workout = WorkoutSession(routineId: nil, routineName: "Push A", startedAt: date("2026-11-16T10:00:00Z"), timezone: "Europe/London")
        context.insert(workout)
        let exercise = SessionExercise(exerciseId: "barbell-bench-press", name: "Bench press", order: 0, targetSets: 3, targetReps: 5)
        context.insert(exercise)
        workout.exercises.append(exercise)
        let set = SessionSet(n: 1, weightKg: 100, reps: 5)
        set.done = true
        context.insert(set)
        exercise.sets.append(set)
        try context.save()

        let export = DataExport.make(profile: profile(streak: 2), physiqueConsent: false, routines: [], sessions: [workout], now: date("2026-11-16T12:00:00Z"))
        let json = try JSONSerialization.jsonObject(with: try export.json()) as? [String: Any]
        XCTAssertEqual(json?["format"] as? String, "pgym-export")
        XCTAssertEqual((json?["profile"] as? [String: Any])?["goalPerWeek"] as? Int, 3)
        let sessions = json?["sessions"] as? [[String: Any]]
        XCTAssertEqual(sessions?.count, 1)
        XCTAssertEqual(sessions?.first?["weekKey"] as? String, "2026-W47")
        let sets = ((sessions?.first?["exercises"] as? [[String: Any]])?.first?["sets"] as? [[String: Any]])
        XCTAssertEqual(sets?.first?["weightKg"] as? Double, 100)
        XCTAssertEqual(DataExport.fileName(now: date("2026-11-16T12:00:00Z"), timeZone: london), "pgym-export-2026-11-16.json")
    }
}
