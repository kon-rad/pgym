import Foundation
import SwiftData

/// One exercise in a routine, with its targets. Firestore: an element of `routines/{id}.exercises`.
struct RoutineItem: Codable, Hashable, Identifiable, Sendable {
    /// Local row identity for lists and drag-to-reorder. Not sent to Firestore.
    var id: UUID
    var exerciseId: String
    var targetSets: Int
    var targetReps: Int

    static let setsRange = 1...10
    static let repsRange = 1...50
    static let defaultSets = 3
    static let defaultReps = 10

    init(id: UUID = UUID(), exerciseId: String, targetSets: Int = defaultSets, targetReps: Int = defaultReps) {
        self.id = id
        self.exerciseId = exerciseId
        self.targetSets = min(max(targetSets, Self.setsRange.lowerBound), Self.setsRange.upperBound)
        self.targetReps = min(max(targetReps, Self.repsRange.lowerBound), Self.repsRange.upperBound)
    }

    /// "3 x 8"
    var targetLabel: String { "\(targetSets) x \(targetReps)" }
}

/// A routine on the phone. Firestore: `users/{uid}/routines/{routineId}` with name, order, exercises.
///
/// The exercise list is stored as encoded JSON so its order is exactly what the user set: SwiftData
/// to-many relationships are unordered.
@Model
final class Routine {
    @Attribute(.unique) var id: String
    var name: String
    /// Rotation order in F2. The routine after the last one done is "Next up" on Today.
    var order: Int
    var exercisesData: Data
    /// The starter this routine was copied from, if any. Local only; the copy is independent of it.
    var starterID: String?
    var createdAt: Date
    var updatedAt: Date
    /// Changed on the phone and not yet written to Firestore.
    var needsSync: Bool
    /// Set when the routine has been in Firestore at least once.
    var lastSyncedAt: Date?
    /// Deleted on the phone; kept as a tombstone until Firestore has the delete. Hidden everywhere.
    var deletedAt: Date?

    init(
        id: String = UUID().uuidString,
        name: String,
        order: Int,
        exercises: [RoutineItem],
        starterID: String? = nil,
        now: Date = .now
    ) {
        self.id = id
        self.name = name
        self.order = order
        self.exercisesData = Self.encode(exercises)
        self.starterID = starterID
        self.createdAt = now
        self.updatedAt = now
        self.needsSync = true
        self.lastSyncedAt = nil
        self.deletedAt = nil
    }

    var exercises: [RoutineItem] {
        get { (try? JSONDecoder().decode([RoutineItem].self, from: exercisesData)) ?? [] }
        set { exercisesData = Self.encode(newValue) }
    }

    /// Named to stay clear of `PersistentModel.isDeleted`, which means something else.
    var isTombstone: Bool { deletedAt != nil }

    /// Marks a local change for the next sync.
    func touch(_ now: Date = .now) {
        updatedAt = now
        needsSync = true
    }

    static func encode(_ items: [RoutineItem]) -> Data {
        (try? JSONEncoder().encode(items)) ?? Data("[]".utf8)
    }
}

/// An exercise the user added in D3 that is not in the catalogue. Stored on the phone; it reaches
/// other phones inside the routines that use it (see `RoutineDocument.Entry`).
@Model
final class CustomExercise {
    @Attribute(.unique) var id: String
    var name: String
    var muscleGroupRaw: String
    var equipmentRaw: String
    var createdAt: Date

    static let idPrefix = "custom-"

    init(name: String, muscleGroup: MuscleGroup, equipment: Equipment, now: Date = .now) {
        self.id = Self.idPrefix + UUID().uuidString.lowercased()
        self.name = name
        self.muscleGroupRaw = muscleGroup.rawValue
        self.equipmentRaw = equipment.rawValue
        self.createdAt = now
    }

    /// Recreates a custom exercise that came from another phone, keeping its ID.
    init(exercise: Exercise, now: Date = .now) {
        self.id = exercise.id
        self.name = exercise.name
        self.muscleGroupRaw = exercise.muscleGroup.rawValue
        self.equipmentRaw = exercise.equipment.rawValue
        self.createdAt = now
    }

    var exercise: Exercise {
        Exercise(
            id: id,
            name: name,
            muscleGroup: MuscleGroup(rawValue: muscleGroupRaw) ?? .core,
            equipment: Equipment(rawValue: equipmentRaw) ?? .other,
            isCustom: true
        )
    }
}

/// The editable copy of a routine that F3 works on. Nothing touches the store until Save.
struct RoutineDraft: Equatable {
    var routineID: String?
    var name: String
    var exercises: [RoutineItem]
    var starterID: String?

    init(routineID: String? = nil, name: String = "", exercises: [RoutineItem] = [], starterID: String? = nil) {
        self.routineID = routineID
        self.name = name
        self.exercises = exercises
        self.starterID = starterID
    }

    init(routine: Routine) {
        self.init(routineID: routine.id, name: routine.name, exercises: routine.exercises, starterID: routine.starterID)
    }

    enum Problem: Equatable {
        case missingName, noExercises

        /// pgym-app-copy.md, F3 errors.
        var message: String {
            switch self {
            case .missingName: "Give the routine a name."
            case .noExercises: "Add at least one exercise."
            }
        }
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var problem: Problem? {
        if trimmedName.isEmpty { return .missingName }
        if exercises.isEmpty { return .noExercises }
        return nil
    }

    var isValid: Bool { problem == nil }
    var isNew: Bool { routineID == nil }

    mutating func add(_ exercise: Exercise) {
        exercises.append(RoutineItem(exerciseId: exercise.id))
    }
}
