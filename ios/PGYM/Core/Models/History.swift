import DesignSystem
import Foundation

/// A plain copy of one session for Today, Progress and Profile (card I8). The screens build these from
/// SwiftData and hand them to pure functions, so every rule (which week, which day, what counts) is
/// tested from fixtures without a store or a screen.
struct SessionSnapshot: Equatable, Sendable, Identifiable {
    struct LoggedSet: Equatable, Sendable {
        var n: Int
        var weightKg: Double?
        var reps: Int?
        var type: SetType
        var done: Bool

        var isWorkingDone: Bool { done && type == .working }
    }

    struct Exercise: Equatable, Sendable {
        var exerciseId: String
        var name: String
        var sets: [LoggedSet]
    }

    var id: String
    var routineId: String?
    var routineName: String
    var startedAt: Date
    var endedAt: Date?
    /// IANA zone where the session started. Its day and week are the ones it started in, there.
    var timezone: String
    var status: SessionStatus
    var proofNumber: Int?
    var stampedAt: Date?
    var receipt: StampReceipt?
    var exercises: [Exercise] = []
    var physiqueScore: Int?
    var physiqueTip: String?
    var physiqueRefusedReason: String?
    var cardKey: String?

    init(
        id: String,
        routineId: String? = nil,
        routineName: String,
        startedAt: Date,
        endedAt: Date? = nil,
        timezone: String,
        status: SessionStatus,
        proofNumber: Int? = nil,
        stampedAt: Date? = nil,
        receipt: StampReceipt? = nil,
        exercises: [Exercise] = [],
        physiqueScore: Int? = nil,
        physiqueTip: String? = nil,
        physiqueRefusedReason: String? = nil,
        cardKey: String? = nil
    ) {
        self.id = id
        self.routineId = routineId
        self.routineName = routineName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.timezone = timezone
        self.status = status
        self.proofNumber = proofNumber
        self.stampedAt = stampedAt
        self.receipt = receipt
        self.exercises = exercises
        self.physiqueScore = physiqueScore
        self.physiqueTip = physiqueTip
        self.physiqueRefusedReason = physiqueRefusedReason
        self.cardKey = cardKey
    }

    /// A proof: stamped by the server, or ended with a card that waits for its stamp (offline).
    /// Sessions saved without proof never count toward the week (pgym-flow-spec.md D5).
    var isProof: Bool { status == .stamped || isPending }

    /// Ended with a card, no server number yet.
    var isPending: Bool { status == .draft && endedAt != nil }

    /// Ended and kept: a proof or a session saved without proof. Lift history uses these.
    var isLogged: Bool { isProof || status == .finished }

    var timeZone: TimeZone { TimeZone(identifier: timezone) ?? .current }

    /// The ISO week the session started in, in its own time zone.
    var week: WeekKey { PlanCalendar(timeZone: timeZone).weekKey(for: startedAt) }

    /// The weekday the session started on, in its own time zone.
    var weekday: Weekday { PlanCalendar(timeZone: timeZone).weekday(for: startedAt) }

    var duration: TimeInterval {
        guard let endedAt else { return 0 }
        return max(0, endedAt.timeIntervalSince(startedAt))
    }

    var totals: SessionMath.Totals {
        SessionMath.totals(exercises.map { exercise in
            exercise.sets.map { SessionMath.LoggedSet(weightKg: $0.weightKg, reps: $0.reps, type: $0.type, done: $0.done) }
        })
    }

    var hasScore: Bool { physiqueScore != nil && physiqueRefusedReason == nil }
}

extension SessionSnapshot {
    init(_ session: WorkoutSession) {
        self.init(
            id: session.id,
            routineId: session.routineId,
            routineName: session.routineName,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            timezone: session.timezone,
            status: session.status,
            proofNumber: session.proofNumber,
            stampedAt: session.stampedAt,
            receipt: session.stampReceipt,
            exercises: session.orderedExercises.map { exercise in
                Exercise(
                    exerciseId: exercise.exerciseId,
                    name: exercise.name,
                    sets: exercise.orderedSets.map {
                        LoggedSet(n: $0.n, weightKg: $0.weightKg, reps: $0.reps, type: $0.type, done: $0.done)
                    }
                )
            },
            physiqueScore: session.physiqueScore,
            physiqueTip: session.physiqueTip,
            physiqueRefusedReason: session.physiqueRefusedReason,
            cardKey: session.cardKey
        )
    }

    static func all(_ sessions: [WorkoutSession]) -> [SessionSnapshot] {
        sessions.filter { $0.status != .discarded }.map(SessionSnapshot.init)
    }
}

/// The seven day rings for one week, in the user's time zone (C1, D11).
///
/// The current week is the user's week now. A session belongs to the day and week it started in, in
/// the zone it started in (pgym-architecture.md: "A session started before midnight and stamped after
/// counts for the day it started"), the same rule the server uses for `weekKey`. So an evening session
/// in Los Angeles that is already the next day in UTC still fills the evening's ring.
struct WeekRow: Equatable {
    struct Day: Equatable {
        var weekday: Weekday
        var status: DayRing.Status
    }

    var week: WeekKey
    var today: Weekday
    var days: [Day]
    /// Proofs this week, more than one a day included.
    var count: Int
    var goal: Int

    var isGoalReached: Bool { goal > 0 && count >= goal }

    static func make(
        sessions: [SessionSnapshot],
        gymDays: Set<Weekday>,
        goal: Int,
        now: Date,
        timeZone: TimeZone
    ) -> WeekRow {
        let calendar = PlanCalendar(timeZone: timeZone)
        let week = calendar.weekKey(for: now)
        let today = calendar.weekday(for: now)
        var done = Set<Weekday>()
        var count = 0
        for session in sessions where session.isProof && session.week == week {
            count += 1
            done.insert(session.weekday)
        }
        let days = Weekday.allCases.map { day -> Day in
            let status: DayRing.Status
            if done.contains(day) {
                status = .done
            } else if day == today {
                status = .today
            } else if gymDays.contains(day) {
                status = .planned
            } else {
                status = .rest
            }
            return Day(weekday: day, status: status)
        }
        return WeekRow(week: week, today: today, days: days, count: count, goal: goal)
    }
}

/// The server's streak numbers, from the freshest place the phone has them.
///
/// Every stamp answer carries the streak, the longest streak, pass weeks and the proof count, and it is
/// newer than the profile read at sign-in, so the newest receipt wins when it is from this week or the
/// last one. Older than that, `rollWeek` may have moved the numbers since, and the profile is used.
struct StreakFacts: Equatable {
    var streakWeeks: Int
    var longestStreak: Int
    var passWeeks: Int
    var proofCount: Int
    /// The server already counted this week as hit (a receipt from this week at or over its goal).
    var thisWeekLockedByServer: Bool

    static let zero = StreakFacts(streakWeeks: 0, longestStreak: 0, passWeeks: 0, proofCount: 0, thisWeekLockedByServer: false)

    static func make(
        sessions: [SessionSnapshot],
        profile: UserProfile?,
        now: Date,
        timeZone: TimeZone
    ) -> StreakFacts {
        let calendar = PlanCalendar(timeZone: timeZone)
        let thisWeek = calendar.weekKey(for: now)
        let lastWeek = calendar.week(thisWeek, plus: -1)
        let localProofs = sessions.filter(\.isProof).count
        let newest = sessions.compactMap(\.receipt).max { $0.stampedAt < $1.stampedAt }
        if let receipt = newest {
            let receiptWeek = calendar.weekKey(for: receipt.stampedAt)
            if receiptWeek == thisWeek || receiptWeek == lastWeek {
                let locked = receiptWeek == thisWeek && receipt.weekGoal > 0 && receipt.weekCount >= receipt.weekGoal
                // Proofs that wait for their stamp are counted on top of the server's number.
                let pendingAfter = sessions.filter { $0.isPending }.count
                return StreakFacts(
                    streakWeeks: receipt.streakWeeks,
                    longestStreak: max(receipt.longestStreak, receipt.streakWeeks),
                    passWeeks: receipt.passWeeks,
                    proofCount: max(receipt.proofCount + pendingAfter, localProofs),
                    thisWeekLockedByServer: locked
                )
            }
        }
        let streak = profile?.streakWeeks ?? 0
        return StreakFacts(
            streakWeeks: streak,
            longestStreak: max(profile?.longestStreak ?? 0, streak),
            passWeeks: profile?.passWeeks ?? 0,
            proofCount: max(profile?.proofCount ?? 0, localProofs),
            thisWeekLockedByServer: false
        )
    }

    /// The week number one more hit locks, or the number of the week already locked
    /// ("One session locks week 8.", "Week 8 locked."). The server's `streakWeeks` counts the open
    /// week only once it is hit (`backend/src/streak.ts`, `view`).
    var lockingWeekNumber: Int { thisWeekLockedByServer ? max(1, streakWeeks) : streakWeeks + 1 }
}
