import Foundation

/// Strings for E1 to E5, from pgym-app-copy.md, "E. Progress tab".
enum ProgressCopy {
    static let title = "Progress"
    static let proofs = "Proofs"
    static let streak = "Streak"
    static func streakValue(_ weeks: Int) -> String { weeks == 1 ? "1 week" : "\(weeks) weeks" }
    static let score = "Score"
    static let scoreOff = "Off"
    static let last12 = "Last 12 weeks"
    static func goalLabel(_ goal: Int) -> String { "Goal \(goal)" }
    static let proofWall = "Proof wall"
    static let seeAll = "See all"
    static let lifts = "Lifts"
    static func liftBest(weight: String, unit: String, reps: Int) -> String { "Best \(weight) \(unit) x \(reps)" }
    static let empty = "No proofs yet. Your first one starts the wall."
    static let emptyLifts = "Lifts show up after your first session."
    static let scoreHistoryRow = "Score history"
    static let couldNotLoad = "Could not load your history."

    // E2
    static func proofCount(_ n: Int) -> String { n == 1 ? "1 proof" : "\(n) proofs" }
    static let pending = "Pending"
    static let wallEmpty = "Nothing here yet. Each stamped session adds a card."

    // E3
    static func meta(proof: Int?, date: String, time: String?) -> String {
        let number = proof.map { "Proof #\(ProofNumber.padded($0))" } ?? pending
        return [number, date, time].compactMap { $0 }.joined(separator: " · ")
    }
    static let sets = "Sets"
    static let totalLifted = "Total lifted"
    static let time = "Time"
    static let unstamped = "Saved without proof. Not counted toward the week."
    static let shareAgain = "Share again"
    static let deleteSession = "Delete session"
    static func deleteTitle(proof: Int?) -> String {
        guard let proof else { return "Delete this session?" }
        return "Delete proof #\(ProofNumber.padded(proof))?"
    }
    static let deleteBody = "Photo, card and sets are deleted. The number is not used again. If it counted toward a week, that week drops by one."
    static let delete = "Delete"
    static let cancel = "Cancel"
    static let cardFailed = "Could not load the card."
    static let retry = "Retry"
    static let deleteFailed = "That did not delete. Check your connection and try again."
    static let needsConnection = "Needs a connection."
    static let warmup = "Warm-up"

    // No-score lines (D11, E3, E5)
    static let noScoreLead = "No score this time."
    static let noScoreFooter = "The session still counts."
    static func refusal(_ reason: String) -> String {
        switch reason {
        case "no_person": "No person in the photo."
        case "several_people": "More than one person in the photo."
        case "face_only": "The photo shows a face only. Step back next time."
        case "unreadable": "Too dark to read. More light next time."
        case "apparent_minor": "This photo cannot be scored."
        default: "Scoring did not work this time."
        }
    }

    // E4
    static let bestSet = "Best set"
    static let e1rm = "Estimated one-rep max"
    static let e1rmCaption = "Worked out from your sets with the Epley formula. An estimate, not a tested max."
    static let everySession = "Every session"
    static let liftEmpty = "Log this lift once to see its history."
    static let oneSession = "One session so far."
    static let noProof = "No proof"

    // E5
    static let scoreTitle = "Score history"
    static let scoreBody = "Only you see this. Each score is compared only with your own earlier photos."
    static let scoreOverTime = "Score over time"
    static func scoreRow(date: String, score: Int) -> String { "\(date) · \(score)" }
    static let toggle = "Physique score"
    static let toggleCaption = "Turning it off deletes every score and tip on this page."
    static let confirmTitle = "Turn off and delete scores?"
    static func confirmBody(_ count: Int) -> String {
        count == 1 ? "1 score and tip is deleted. Your photos and proofs stay." : "\(count) scores and tips are deleted. Your photos and proofs stay."
    }
    static let confirmOff = "Turn off and delete"
    static let keepOn = "Keep it on"
    static let offState = "The physique score is off."
    static let turnOn = "Turn on the score"
    static let under18 = "The physique score is for people 18 and over."
    static let firstScoreSoon = "Your first score comes with your next proof."
    static let scoresFailed = "Could not load scores."
    static let turnOffFailed = "Scores are cleared on this phone. The server copy is deleted when you are back online."
}

/// One bar on E1's chart: proofs in one ISO week against that week's goal.
struct WeekBar: Equatable, Identifiable {
    var week: WeekKey
    /// Monday 00:00 of the week, in the user's zone. The chart's x value.
    var start: Date
    var count: Int
    var goal: Int
    var isCurrent: Bool

    var id: WeekKey { week }
    var isHit: Bool { goal > 0 && count >= goal }
}

/// E1, E2, E4 and E5 worked out from session snapshots. Pure and tested from fixtures.
enum ProgressModel {
    static let weeksShown = 12

    /// The last 12 weeks, oldest first, the current week last. A week with no proof is a zero bar,
    /// never left out: the chart's spacing is the calendar's. Weeks are the user's weeks now; a
    /// session counts in the week it started in, in its own zone (as on the server).
    static func twelveWeeks(
        _ sessions: [SessionSnapshot],
        now: Date,
        timeZone: TimeZone,
        goal: (WeekKey) -> Int
    ) -> [WeekBar] {
        let calendar = PlanCalendar(timeZone: timeZone)
        let current = calendar.weekKey(for: now)
        var counts: [WeekKey: Int] = [:]
        for session in sessions where session.isProof {
            counts[session.week, default: 0] += 1
        }
        return (0..<weeksShown).map { index in
            let week = calendar.week(current, plus: index - (weeksShown - 1))
            return WeekBar(
                week: week,
                start: calendar.startOfWeek(week),
                count: counts[week] ?? 0,
                goal: goal(week),
                isCurrent: week == current
            )
        }
    }

    /// E2: proofs newest first, grouped by the month they started in (user's zone). Saved-without-proof
    /// sessions are not on the wall.
    struct MonthGroup: Equatable, Identifiable {
        var monthStart: Date
        var sessions: [SessionSnapshot]
        var id: Date { monthStart }
    }

    static func proofWall(_ sessions: [SessionSnapshot], timeZone: TimeZone) -> [MonthGroup] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let proofs = sessions.filter(\.isProof).sorted { $0.startedAt > $1.startedAt }
        var groups: [MonthGroup] = []
        for proof in proofs {
            let parts = calendar.dateComponents([.year, .month], from: proof.startedAt)
            let start = calendar.date(from: parts) ?? proof.startedAt
            if let last = groups.indices.last, groups[last].monthStart == start {
                groups[last].sessions.append(proof)
            } else {
                groups.append(MonthGroup(monthStart: start, sessions: [proof]))
            }
        }
        return groups
    }

    /// E1's lift rows: every exercise with a logged working set, most recent first.
    struct Lift: Equatable, Identifiable {
        var exerciseId: String
        var name: String
        var bestWeightKg: Double
        var bestReps: Int
        var bestE1rmKg: Double
        var lastPerformedAt: Date
        var sessionCount: Int
        var id: String { exerciseId }
    }

    static func lifts(_ sessions: [SessionSnapshot]) -> [Lift] {
        var byID: [String: Lift] = [:]
        for session in sessions where session.isLogged {
            for exercise in session.exercises {
                guard let best = bestSet(exercise.sets) else { continue }
                if var lift = byID[exercise.exerciseId] {
                    lift.sessionCount += 1
                    if session.startedAt > lift.lastPerformedAt {
                        lift.lastPerformedAt = session.startedAt
                        lift.name = exercise.name
                    }
                    if best.e1rm > lift.bestE1rmKg {
                        lift.bestE1rmKg = best.e1rm
                        lift.bestWeightKg = best.kg
                        lift.bestReps = best.reps
                    }
                    byID[exercise.exerciseId] = lift
                } else {
                    byID[exercise.exerciseId] = Lift(
                        exerciseId: exercise.exerciseId,
                        name: exercise.name,
                        bestWeightKg: best.kg,
                        bestReps: best.reps,
                        bestE1rmKg: best.e1rm,
                        lastPerformedAt: session.startedAt,
                        sessionCount: 1
                    )
                }
            }
        }
        return byID.values.sorted {
            $0.lastPerformedAt != $1.lastPerformedAt ? $0.lastPerformedAt > $1.lastPerformedAt : $0.name < $1.name
        }
    }

    /// The best working set by estimated one-rep max (ties: the heavier, then the first).
    static func bestSet(_ sets: [SessionSnapshot.LoggedSet]) -> (kg: Double, reps: Int, e1rm: Double)? {
        var best: (kg: Double, reps: Int, e1rm: Double)?
        for set in sets where set.isWorkingDone {
            guard let reps = set.reps, reps > 0 else { continue }
            let kg = max(0, set.weightKg ?? 0)
            let e1rm = SessionMath.e1rm(weightKg: kg, reps: reps)
            if let current = best {
                if e1rm > current.e1rm || (e1rm == current.e1rm && kg > current.kg) { best = (kg, reps, e1rm) }
            } else {
                best = (kg, reps, e1rm)
            }
        }
        return best
    }

    /// E4: one exercise over time.
    struct LiftHistory: Equatable {
        struct Point: Equatable, Identifiable {
            var date: Date
            var e1rmKg: Double
            var id: Date { date }
        }

        struct Entry: Equatable, Identifiable {
            var sessionID: String
            var date: Date
            var timezone: String
            var isProof: Bool
            var proofNumber: Int?
            var sets: [SessionSnapshot.LoggedSet]
            var id: String { sessionID }
        }

        var name: String
        var best: (kg: Double, reps: Int)?
        var bestE1rmKg: Double
        /// Oldest first, one point per session with a weighted working set.
        var points: [Point]
        /// Newest first, every logged session with this exercise.
        var entries: [Entry]

        static func == (lhs: LiftHistory, rhs: LiftHistory) -> Bool {
            lhs.name == rhs.name && lhs.best?.kg == rhs.best?.kg && lhs.best?.reps == rhs.best?.reps
                && lhs.bestE1rmKg == rhs.bestE1rmKg && lhs.points == rhs.points && lhs.entries == rhs.entries
        }
    }

    static func liftHistory(exerciseId: String, in sessions: [SessionSnapshot]) -> LiftHistory {
        var name = ""
        var best: (kg: Double, reps: Int, e1rm: Double)?
        var points: [LiftHistory.Point] = []
        var entries: [LiftHistory.Entry] = []
        for session in sessions.filter(\.isLogged).sorted(by: { $0.startedAt < $1.startedAt }) {
            guard let exercise = session.exercises.first(where: { $0.exerciseId == exerciseId }) else { continue }
            let logged = exercise.sets.filter(\.done)
            guard !logged.isEmpty else { continue }
            name = exercise.name
            entries.append(LiftHistory.Entry(
                sessionID: session.id,
                date: session.startedAt,
                timezone: session.timezone,
                isProof: session.isProof,
                proofNumber: session.status == .stamped ? session.proofNumber : nil,
                sets: logged
            ))
            if let top = bestSet(exercise.sets) {
                if top.e1rm > 0 { points.append(LiftHistory.Point(date: session.startedAt, e1rmKg: top.e1rm)) }
                if best == nil || top.e1rm > best!.e1rm { best = top }
            }
        }
        return LiftHistory(
            name: name,
            best: best.map { ($0.kg, $0.reps) },
            bestE1rmKg: best?.e1rm ?? 0,
            points: points,
            entries: entries.reversed()
        )
    }

    /// E5: stamped sessions with an analysis, oldest first. A refusal is a gap on the line, never a zero.
    struct ScorePoint: Equatable, Identifiable {
        var sessionID: String
        var date: Date
        var score: Int?
        var tip: String?
        var refusedReason: String?
        var id: String { sessionID }
    }

    static func scoreHistory(_ sessions: [SessionSnapshot]) -> [ScorePoint] {
        sessions
            .filter { $0.status == .stamped && ($0.physiqueScore != nil || $0.physiqueRefusedReason != nil) }
            .sorted { ($0.stampedAt ?? $0.startedAt) < ($1.stampedAt ?? $1.startedAt) }
            .map {
                ScorePoint(
                    sessionID: $0.id,
                    date: $0.stampedAt ?? $0.startedAt,
                    score: $0.hasScore ? $0.physiqueScore : nil,
                    tip: $0.hasScore ? $0.physiqueTip : nil,
                    refusedReason: $0.physiqueRefusedReason
                )
            }
    }

    /// The newest score, for E1's Score tile.
    static func latestScore(_ sessions: [SessionSnapshot]) -> Int? {
        scoreHistory(sessions).last(where: { $0.score != nil })?.score
    }
}
