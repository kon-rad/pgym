import Foundation

/// A workout inside a starter: "Push" in Push/Pull/Legs. Immutable; adopting it copies it.
struct StarterWorkout: Hashable, Sendable {
    let name: String
    let exercises: [Target]

    struct Target: Hashable, Sendable {
        let exerciseId: String
        let sets: Int
        let reps: Int
    }
}

/// The three starters from pgym-app-views.md B4: Push/Pull/Legs, Upper/Lower, Full body.
/// They are templates that ship in the app. A user never edits a starter: adopting one makes
/// ordinary routines, and editing those leaves the starter as it was.
///
/// The programming is a common beginner layout, not reviewed by a trainer (open item in pgym-app-views.md).
struct StarterRoutine: Hashable, Identifiable, Sendable {
    let id: String
    /// Option label in B4 ("Push, Pull, Legs").
    let title: String
    /// Option caption in B4.
    let caption: String
    /// Weekly goals this starter fits (pgym-flow-spec.md B4 proposal).
    let fitsGoals: ClosedRange<Int>
    let workouts: [StarterWorkout]

    static let pushPullLegs = StarterRoutine(
        id: "starter-push-pull-legs",
        title: "Push, Pull, Legs",
        caption: "3 workouts in rotation.",
        fitsGoals: 5...6,
        workouts: [
            StarterWorkout(name: "Push", exercises: [
                .init(exerciseId: "barbell-bench-press", sets: 3, reps: 8),
                .init(exerciseId: "overhead-press", sets: 3, reps: 8),
                .init(exerciseId: "incline-dumbbell-bench-press", sets: 3, reps: 10),
                .init(exerciseId: "dumbbell-lateral-raise", sets: 3, reps: 12),
                .init(exerciseId: "triceps-pushdown", sets: 3, reps: 12),
            ]),
            StarterWorkout(name: "Pull", exercises: [
                .init(exerciseId: "deadlift", sets: 3, reps: 5),
                .init(exerciseId: "lat-pulldown", sets: 3, reps: 10),
                .init(exerciseId: "seated-cable-row", sets: 3, reps: 10),
                .init(exerciseId: "face-pull", sets: 3, reps: 15),
                .init(exerciseId: "dumbbell-curl", sets: 3, reps: 12),
            ]),
            StarterWorkout(name: "Legs", exercises: [
                .init(exerciseId: "back-squat", sets: 3, reps: 8),
                .init(exerciseId: "romanian-deadlift", sets: 3, reps: 10),
                .init(exerciseId: "leg-press", sets: 3, reps: 10),
                .init(exerciseId: "lying-leg-curl", sets: 3, reps: 12),
                .init(exerciseId: "standing-calf-raise", sets: 3, reps: 15),
            ]),
        ]
    )

    static let upperLower = StarterRoutine(
        id: "starter-upper-lower",
        title: "Upper, Lower",
        caption: "2 workouts in rotation.",
        fitsGoals: 4...4,
        workouts: [
            StarterWorkout(name: "Upper", exercises: [
                .init(exerciseId: "barbell-bench-press", sets: 3, reps: 8),
                .init(exerciseId: "barbell-row", sets: 3, reps: 8),
                .init(exerciseId: "overhead-press", sets: 3, reps: 10),
                .init(exerciseId: "lat-pulldown", sets: 3, reps: 10),
                .init(exerciseId: "dumbbell-curl", sets: 2, reps: 12),
                .init(exerciseId: "triceps-pushdown", sets: 2, reps: 12),
            ]),
            StarterWorkout(name: "Lower", exercises: [
                .init(exerciseId: "back-squat", sets: 3, reps: 8),
                .init(exerciseId: "romanian-deadlift", sets: 3, reps: 10),
                .init(exerciseId: "leg-press", sets: 3, reps: 12),
                .init(exerciseId: "lying-leg-curl", sets: 3, reps: 12),
                .init(exerciseId: "standing-calf-raise", sets: 3, reps: 15),
                .init(exerciseId: "hanging-knee-raise", sets: 3, reps: 12),
            ]),
        ]
    )

    static let fullBody = StarterRoutine(
        id: "starter-full-body",
        title: "Full body",
        caption: "1 workout, every session.",
        fitsGoals: 2...3,
        workouts: [
            StarterWorkout(name: "Full body", exercises: [
                .init(exerciseId: "back-squat", sets: 3, reps: 8),
                .init(exerciseId: "barbell-bench-press", sets: 3, reps: 8),
                .init(exerciseId: "barbell-row", sets: 3, reps: 8),
                .init(exerciseId: "overhead-press", sets: 2, reps: 10),
                .init(exerciseId: "romanian-deadlift", sets: 2, reps: 10),
                .init(exerciseId: "cable-crunch", sets: 2, reps: 12),
            ]),
        ]
    )

    /// In the B4 order.
    static let all: [StarterRoutine] = [pushPullLegs, upperLower, fullBody]

    /// The starter that fits a weekly goal of 2 to 6: 2 or 3 Full body, 4 Upper/Lower, 5 or 6 Push/Pull/Legs.
    static func suggested(forGoal goal: Int) -> StarterRoutine {
        all.first { $0.fitsGoals.contains(goal) } ?? (goal < 2 ? fullBody : pushPullLegs)
    }

    /// The workouts' names, "Push · Pull · Legs".
    var workoutLine: String { workouts.map(\.name).joined(separator: " · ") }

    /// Every exercise in the starter, once, in one line: the collapsed list on the B4 card.
    func exerciseLine(using library: ExerciseLibrary) -> String {
        var seen = Set<String>()
        let names = workouts.flatMap(\.exercises).compactMap { target -> String? in
            guard seen.insert(target.exerciseId).inserted else { return nil }
            return library.name(for: target.exerciseId)
        }
        return names.joined(separator: ", ")
    }

    /// The editable drafts this starter becomes, one per workout. Fresh row IDs every call, so two
    /// adoptions never share state.
    func drafts() -> [RoutineDraft] {
        workouts.map { workout in
            RoutineDraft(
                name: workout.name,
                exercises: workout.exercises.map {
                    RoutineItem(exerciseId: $0.exerciseId, targetSets: $0.sets, targetReps: $0.reps)
                },
                starterID: id
            )
        }
    }
}
