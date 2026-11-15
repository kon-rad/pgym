import Foundation

/// The best weight and best estimated one-rep max for one exercise, in kilograms.
struct StoredBest: Equatable, Sendable {
    var weightKg: Double
    var e1rmKg: Double

    static let none = StoredBest(weightKg: 0, e1rmKg: 0)

    /// Nothing recorded yet. A first-ever exercise sets a baseline; it is not flagged as a best
    /// (same rule as `mergeStats` on the server: a best needs an earlier session to beat).
    var isEmpty: Bool { weightKg <= 0 && e1rmKg <= 0 }
}

/// Pure numbers for a session: Epley, totals, new bests. Mirrors `backend/src/sessionStats.ts` so the
/// phone shows what the server will stamp.
enum SessionMath {
    /// Epley estimate of the one-rep max: weight x (1 + reps / 30), and the weight itself for a single.
    /// Rounded to 0.1 kg, like the server.
    static func e1rm(weightKg: Double, reps: Int) -> Double {
        guard weightKg > 0, reps > 0 else { return 0 }
        let estimate = reps == 1 ? weightKg : weightKg * (1 + Double(reps) / 30)
        return (estimate * 10).rounded() / 10
    }

    /// True when this set beats the stored best weight or the stored best estimated one-rep max.
    /// Equal is not a best. Warm-ups and empty sets never are.
    static func isNewBest(weightKg: Double?, reps: Int?, type: SetType, against best: StoredBest) -> Bool {
        guard type == .working, !best.isEmpty, let weightKg, let reps, weightKg > 0, reps > 0 else { return false }
        return weightKg > best.weightKg || e1rm(weightKg: weightKg, reps: reps) > best.e1rmKg
    }

    /// The stored best raised by a set that was logged.
    static func raising(_ best: StoredBest, weightKg: Double?, reps: Int?, type: SetType) -> StoredBest {
        guard type == .working, let weightKg, let reps, weightKg > 0, reps > 0 else { return best }
        return StoredBest(
            weightKg: max(best.weightKg, weightKg),
            e1rmKg: max(best.e1rmKg, e1rm(weightKg: weightKg, reps: reps))
        )
    }

    struct Totals: Equatable, Sendable {
        /// Logged working sets.
        var setCount: Int
        /// Weight x reps over logged working sets, in kilograms, rounded to 0.1.
        var volumeKg: Double
        /// Exercises with at least one logged working set.
        var exerciseCount: Int
    }

    /// A plain set for the totals, so the math can be tested without SwiftData.
    struct LoggedSet: Equatable, Sendable {
        var weightKg: Double?
        var reps: Int?
        var type: SetType
        var done: Bool
    }

    /// Total volume counts working sets only: done, not warm-up (pgym-design.md, "Data points").
    static func totals(_ exercises: [[LoggedSet]]) -> Totals {
        var sets = 0
        var volume = 0.0
        var exerciseCount = 0
        for exercise in exercises {
            var any = false
            for set in exercise where set.done && set.type == .working {
                sets += 1
                any = true
                volume += max(0, set.weightKg ?? 0) * Double(max(0, set.reps ?? 0))
            }
            if any { exerciseCount += 1 }
        }
        return Totals(setCount: sets, volumeKg: (volume * 10).rounded() / 10, exerciseCount: exerciseCount)
    }
}

extension WorkoutSession {
    var totals: SessionMath.Totals {
        SessionMath.totals(orderedExercises.map { exercise in
            exercise.orderedSets.map { SessionMath.LoggedSet(weightKg: $0.weightKg, reps: $0.reps, type: $0.type, done: $0.done) }
        })
    }

    /// ISO week of the start, in the session's own time zone ("2026-W46"). The server recomputes it.
    var weekKey: String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: timezone) ?? .current
        let parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: startedAt)
        let week = parts.weekOfYear ?? 1
        return "\(parts.yearForWeekOfYear ?? 1970)-W" + (week < 10 ? "0\(week)" : "\(week)")
    }
}
