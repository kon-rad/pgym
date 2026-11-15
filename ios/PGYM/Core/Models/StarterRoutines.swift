import Foundation

/// One exercise slot in a routine: `{exerciseId, targetSets, targetReps}` in
/// `users/{uid}/routines/{routineId}.exercises` (pgym-architecture.md, "Data model").
struct RoutineExercise: Codable, Equatable, Sendable {
    let exerciseId: String
    let name: String
    let targetSets: Int
    let targetReps: Int
}

/// A routine as the phone writes it to `users/{uid}/routines/{routineId}`.
struct RoutineDraft: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let order: Int
    let exercises: [RoutineExercise]

    /// The Firestore field map.
    var firestoreFields: [String: Any] {
        [
            "name": name,
            "order": order,
            "exercises": exercises.map {
                ["exerciseId": $0.exerciseId, "targetSets": $0.targetSets, "targetReps": $0.targetReps] as [String: Any]
            },
        ]
    }
}

/// B4's three starters (pgym-app-views.md, B4). The exercise IDs are the catalogue IDs card I4
/// ships; the sets and reps are plain beginner defaults and still need the trainer review that
/// pgym-app-views.md lists as open.
enum StarterRoutine: String, CaseIterable, Codable, Identifiable, Sendable {
    case pushPullLegs
    case upperLower
    case fullBody

    var id: String { rawValue }

    /// "Push, Pull, Legs" (copy deck B4).
    var title: String {
        switch self {
        case .pushPullLegs: "Push, Pull, Legs"
        case .upperLower: "Upper, Lower"
        case .fullBody: "Full body"
        }
    }

    /// "3 workouts in rotation." (copy deck B4).
    var caption: String {
        switch self {
        case .pushPullLegs: "3 workouts in rotation."
        case .upperLower: "2 workouts in rotation."
        case .fullBody: "1 workout, every session."
        }
    }

    /// The starter that fits a goal (pgym-flow-spec.md, B4, a proposal): 2 or 3 days gives Full
    /// body, 4 gives Upper/Lower, 5 or 6 gives Push/Pull/Legs.
    static func suggested(for goal: Int) -> StarterRoutine {
        switch goal {
        case ...3: .fullBody
        case 4: .upperLower
        default: .pushPullLegs
        }
    }

    /// The routines this starter writes, in rotation order. IDs are fixed so a retried save
    /// overwrites instead of adding a second copy.
    var routines: [RoutineDraft] {
        switch self {
        case .pushPullLegs:
            [
                RoutineDraft(id: "starter-push", name: "Push", order: 0, exercises: [
                    Self.ex("bench-press", "Bench press", 3, 8),
                    Self.ex("overhead-press", "Overhead press", 3, 8),
                    Self.ex("incline-dumbbell-press", "Incline dumbbell press", 3, 10),
                    Self.ex("lateral-raise", "Lateral raise", 3, 15),
                    Self.ex("triceps-pushdown", "Triceps pushdown", 3, 12),
                ]),
                RoutineDraft(id: "starter-pull", name: "Pull", order: 1, exercises: [
                    Self.ex("deadlift", "Deadlift", 3, 5),
                    Self.ex("pull-up", "Pull-up", 3, 8),
                    Self.ex("barbell-row", "Barbell row", 3, 8),
                    Self.ex("face-pull", "Face pull", 3, 15),
                    Self.ex("biceps-curl", "Biceps curl", 3, 12),
                ]),
                RoutineDraft(id: "starter-legs", name: "Legs", order: 2, exercises: [
                    Self.ex("back-squat", "Back squat", 3, 6),
                    Self.ex("romanian-deadlift", "Romanian deadlift", 3, 8),
                    Self.ex("leg-press", "Leg press", 3, 10),
                    Self.ex("leg-curl", "Leg curl", 3, 12),
                    Self.ex("calf-raise", "Calf raise", 3, 15),
                ]),
            ]
        case .upperLower:
            [
                RoutineDraft(id: "starter-upper", name: "Upper", order: 0, exercises: [
                    Self.ex("bench-press", "Bench press", 3, 8),
                    Self.ex("barbell-row", "Barbell row", 3, 8),
                    Self.ex("overhead-press", "Overhead press", 3, 10),
                    Self.ex("pull-up", "Pull-up", 3, 8),
                    Self.ex("biceps-curl", "Biceps curl", 2, 12),
                ]),
                RoutineDraft(id: "starter-lower", name: "Lower", order: 1, exercises: [
                    Self.ex("back-squat", "Back squat", 3, 6),
                    Self.ex("romanian-deadlift", "Romanian deadlift", 3, 8),
                    Self.ex("leg-press", "Leg press", 3, 10),
                    Self.ex("leg-curl", "Leg curl", 3, 12),
                    Self.ex("calf-raise", "Calf raise", 3, 15),
                ]),
            ]
        case .fullBody:
            [
                RoutineDraft(id: "starter-full-body", name: "Full body", order: 0, exercises: [
                    Self.ex("back-squat", "Back squat", 3, 6),
                    Self.ex("bench-press", "Bench press", 3, 8),
                    Self.ex("barbell-row", "Barbell row", 3, 8),
                    Self.ex("overhead-press", "Overhead press", 2, 10),
                    Self.ex("romanian-deadlift", "Romanian deadlift", 2, 10),
                ]),
            ]
        }
    }

    /// The exercise list on one line, for the starter card ("Bench press, Overhead press, ...").
    var summary: String {
        routines.map { "\($0.name): " + $0.exercises.prefix(3).map(\.name).joined(separator: ", ") }
            .joined(separator: " / ")
    }

    private static func ex(_ id: String, _ name: String, _ sets: Int, _ reps: Int) -> RoutineExercise {
        RoutineExercise(exerciseId: id, name: name, targetSets: sets, targetReps: reps)
    }
}
