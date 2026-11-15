import Foundation
import SwiftData

/// Every write to routines goes through here, so ordering, sync flags and tombstones stay consistent
/// whether the change comes from F2, F3, B4 or a test.
struct RoutineStore {
    let context: ModelContext

    /// Routines shown to the user, in rotation order.
    static var activeDescriptor: FetchDescriptor<Routine> {
        FetchDescriptor<Routine>(
            predicate: #Predicate<Routine> { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\Routine.order), SortDescriptor(\Routine.createdAt)]
        )
    }

    func activeRoutines() throws -> [Routine] {
        try context.fetch(Self.activeDescriptor)
    }

    func routine(id: String) throws -> Routine? {
        var d = FetchDescriptor<Routine>(predicate: #Predicate<Routine> { $0.id == id })
        d.fetchLimit = 1
        return try context.fetch(d).first
    }

    /// Creates a routine from a new draft, or writes a draft back to its routine. Throws for an invalid draft.
    @discardableResult
    func save(_ draft: RoutineDraft, now: Date = .now) throws -> Routine {
        guard draft.isValid else { throw StoreError.invalidDraft(draft.problem!) }
        if let id = draft.routineID, let existing = try routine(id: id), !existing.isTombstone {
            existing.name = draft.trimmedName
            existing.exercises = draft.exercises
            existing.touch(now)
            try context.save()
            return existing
        }
        let routine = Routine(
            id: draft.routineID ?? UUID().uuidString,
            name: draft.trimmedName,
            order: try nextOrder(),
            exercises: draft.exercises,
            starterID: draft.starterID,
            now: now
        )
        context.insert(routine)
        try context.save()
        return routine
    }

    /// Soft delete: hidden at once, removed from the phone after Firestore has the delete.
    /// Past sessions keep their own copy of names and sets, so they are untouched.
    func delete(_ routine: Routine, now: Date = .now) throws {
        routine.deletedAt = now
        routine.touch(now)
        try context.save()
        try renumber(try activeRoutines())
    }

    /// F2 drag to reorder. Offsets are into `activeRoutines()`, like `List.onMove`.
    func move(fromOffsets source: IndexSet, toOffset destination: Int, now: Date = .now) throws {
        var list = try activeRoutines()
        list.moveElements(fromOffsets: source, toOffset: destination)
        try renumber(list, now: now)
    }

    /// Copies every workout of a starter into new routines at the end of the rotation.
    /// The starter itself is a constant and is never changed.
    @discardableResult
    func adopt(_ starter: StarterRoutine, now: Date = .now) throws -> [Routine] {
        var created: [Routine] = []
        for draft in starter.drafts() {
            created.append(try save(draft, now: now))
        }
        return created
    }

    /// Order values 0, 1, 2... in list order; only routines whose order changed are marked for sync.
    private func renumber(_ list: [Routine], now: Date = .now) throws {
        for (index, routine) in list.enumerated() where routine.order != index {
            routine.order = index
            routine.touch(now)
        }
        try context.save()
    }

    private func nextOrder() throws -> Int {
        (try activeRoutines().map(\.order).max() ?? -1) + 1
    }

    enum StoreError: Error, Equatable {
        case invalidDraft(RoutineDraft.Problem)
    }
}

/// Custom exercises from D3.
struct CustomExerciseStore {
    let context: ModelContext

    func all() throws -> [CustomExercise] {
        try context.fetch(FetchDescriptor<CustomExercise>(sortBy: [SortDescriptor(\CustomExercise.name)]))
    }

    /// Adds an exercise the catalogue does not have. An existing custom one with the same name (any case)
    /// is returned instead of a duplicate.
    @discardableResult
    func create(name: String, muscleGroup: MuscleGroup, equipment: Equipment, now: Date = .now) throws -> CustomExercise {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = ExerciseLibrary.words(trimmed)
        if let existing = try all().first(where: { ExerciseLibrary.words($0.name) == key }) {
            return existing
        }
        let custom = CustomExercise(name: trimmed, muscleGroup: muscleGroup, equipment: equipment, now: now)
        context.insert(custom)
        try context.save()
        return custom
    }
}

extension Array {
    /// Same semantics as SwiftUI's `move(fromOffsets:toOffset:)`, without importing SwiftUI into the model layer.
    mutating func moveElements(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted().map { self[$0] }
        let insertAt = destination - source.filter { $0 < destination }.count
        for index in source.sorted(by: >) {
            remove(at: index)
        }
        insert(contentsOf: moving, at: Swift.max(0, Swift.min(insertAt, count)))
    }
}
