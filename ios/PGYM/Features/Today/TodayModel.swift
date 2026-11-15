import DesignSystem
import Foundation

/// Strings for C1 to C4, from pgym-app-copy.md, "C. Today tab", plus the shared state lines.
enum TodayCopy {
    static func streak(_ weeks: Int) -> String {
        switch weeks {
        case ...0: "Week 1"
        case 1: "1 week running"
        default: "\(weeks) weeks running"
        }
    }

    static let thisWeek = "This week"
    static func weekCount(_ n: Int, of goal: Int) -> String { "\(n) of \(goal)" }
    static func newWeek(goal: Int) -> String { "New week. 0 of \(goal)." }
    static let nextUp = "Next up"
    static func cardMeta(exercises: Int, lastDuration: String?) -> String {
        guard let lastDuration else { return exercises == 1 ? "1 exercise." : "\(exercises) exercises." }
        return "\(exercises) exercises. Last time \(lastDuration)."
    }
    static func oneLeft(week: Int) -> String { "One session locks week \(week)." }
    static func moreLeft(_ left: Int, week: Int) -> String { "\(left) more to lock week \(week)." }
    static let startSession = "Start session"
    static let change = "Change"
    static let lastProof = "Last proof"
    static func lastProofMeta(proof: Int, day: String) -> String { "Proof #\(ProofNumber.padded(proof)), \(day)" }
    static func lastProofPending(day: String) -> String { "Pending, \(day)" }
    static func passWeeks(_ n: Int) -> String { "Pass weeks banked: \(n)" }

    // C2
    static let restDay = "Rest day"
    static func nextSession(routine: String?, day: String) -> String {
        guard let routine else { return "Next session on \(day)." }
        return "Next session: \(routine) on \(day)."
    }
    static let trainAnyway = "Train anyway"

    // C3
    static func weekLocked(_ week: Int) -> String { "Week \(week) locked." }
    static func weekDoneBody(goal: Int) -> String { "\(goal) of \(goal). Next week starts Monday." }
    static let extras = "Extra sessions add to your totals and proof count."
    static let bonus = "Start a bonus session"

    // C4
    static let firstRunTitle = "Proof #001 is waiting."
    static let firstRunBody = "Log one set, take one photo, and it is yours."

    // Shared states (pgym-app-copy.md, "Empty, loading, offline and error states"; flow spec C1)
    static func willSync(_ n: Int) -> String { n == 1 ? "1 session will sync." : "\(n) sessions will sync." }
    static let offline = "Offline. Changes will sync."
    static let syncFailed = "PGYM's server did not answer. Your sets are safe on this phone."
    static let tryAgain = "Try again"
    static let loading = "Loading"
}

/// "042": proof numbers keep at least three digits everywhere they are shown as text.
enum ProofNumber {
    static func padded(_ n: Int) -> String {
        let digits = String(max(0, n))
        return String(repeating: "0", count: max(0, 3 - digits.count)) + digits
    }
}

/// Which of the four C1 states shows, and everything on it. Pure: built from session snapshots, the
/// plan, the streak numbers and the clock, so each state is tested from fixtures.
///
/// Order (pgym-flow-spec.md, "C. Today tab"): first run, week done, rest day, gym day. The fifth case
/// in the flow spec, a draft in progress, never reaches this screen: `SessionHost` covers the tabs with
/// D2 whenever a draft is open, so Today does not model it.
struct TodayModel: Equatable {
    enum State: Equatable {
        /// C4: no proof yet.
        case firstRun
        /// C3: the goal is reached this week. `week` is the streak week it locked.
        case weekDone(week: Int)
        /// C2: today is not a gym day. `nextDay` is the next gym day after today, if any is set.
        case restDay(nextDay: Weekday?)
        /// C1: a gym day with sessions still to go.
        case gymDay

        var viewID: String {
            switch self {
            case .gymDay: "C1"
            case .restDay: "C2"
            case .weekDone: "C3"
            case .firstRun: "C4"
            }
        }
    }

    struct LastProof: Equatable {
        var sessionID: String
        var proofNumber: Int?
        var startedAt: Date
        var cardKey: String?
    }

    var state: State
    var weekRow: WeekRow
    var streak: StreakFacts
    var lastProof: LastProof?
    /// The line under the Next up title on C1: "One session locks week 8." Nil on the other states.
    var lockLine: String?
    /// "New week. 0 of 4." on the Monday after a short week, in place of the count.
    var freshStart: Bool

    var streakStampText: String? {
        if case .firstRun = state { return nil }
        return TodayCopy.streak(streak.streakWeeks)
    }

    struct Inputs {
        var sessions: [SessionSnapshot]
        var plan: WeeklyPlan?
        var profile: UserProfile?
        var now: Date
        var timeZone: TimeZone
    }

    init(_ input: Inputs) {
        let plan = input.plan ?? input.profile?.plan
        let goal = plan?.goal ?? input.profile?.goalPerWeek ?? 0
        let gymDays = plan?.days ?? Set(input.profile?.gymDays ?? [])
        let row = WeekRow.make(sessions: input.sessions, gymDays: gymDays, goal: goal, now: input.now, timeZone: input.timeZone)
        let facts = StreakFacts.make(sessions: input.sessions, profile: input.profile, now: input.now, timeZone: input.timeZone)

        let proofs = input.sessions.filter(\.isProof).sorted { $0.startedAt > $1.startedAt }
        let last = proofs.first.map {
            LastProof(sessionID: $0.id, proofNumber: $0.status == .stamped ? $0.proofNumber : nil, startedAt: $0.startedAt, cardKey: $0.cardKey)
        }

        let calendar = PlanCalendar(timeZone: input.timeZone)
        let lastWeek = calendar.week(row.week, plus: -1)
        let lastWeekCount = proofs.filter { $0.week == lastWeek }.count
        let fresh = !proofs.isEmpty && row.count == 0 && row.today == .mon && goal > 0 && lastWeekCount < goal

        let resolved: State
        if proofs.isEmpty && (input.profile?.proofCount ?? 0) == 0 {
            resolved = .firstRun
        } else if row.isGoalReached {
            resolved = .weekDone(week: facts.lockingWeekNumber)
        } else if !gymDays.isEmpty && !gymDays.contains(row.today) {
            resolved = .restDay(nextDay: Self.nextGymDay(after: row.today, in: gymDays))
        } else {
            resolved = .gymDay
        }

        var line: String?
        if case .gymDay = resolved, goal > 0 {
            let left = goal - row.count
            line = left == 1
                ? TodayCopy.oneLeft(week: facts.lockingWeekNumber)
                : TodayCopy.moreLeft(left, week: facts.lockingWeekNumber)
        }

        state = resolved
        weekRow = row
        streak = facts
        lastProof = last
        lockLine = line
        freshStart = fresh
    }

    /// The next gym day after `today`, wrapping into next week.
    static func nextGymDay(after today: Weekday, in days: Set<Weekday>) -> Weekday? {
        guard !days.isEmpty else { return nil }
        let all = Weekday.allCases
        for offset in 1...7 {
            let day = all[(today.mondayIndex + offset) % 7]
            if days.contains(day) { return day }
        }
        return nil
    }

    /// "Last time 52 min": how long the routine's most recent logged run took.
    static func lastDuration(of routineID: String?, in sessions: [SessionSnapshot]) -> TimeInterval? {
        guard let routineID else { return nil }
        let last = sessions
            .filter { $0.routineId == routineID && $0.isLogged && $0.endedAt != nil }
            .max { $0.startedAt < $1.startedAt }
        guard let last, last.duration > 0 else { return nil }
        return last.duration
    }

    /// "52 min", "1 h 05 min".
    static func durationLabel(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        if minutes < 60 { return "\(minutes) min" }
        return String(format: "%d h %02d min", minutes / 60, minutes % 60)
    }
}
