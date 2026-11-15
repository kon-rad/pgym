import SwiftData
import XCTest
@testable import PGYM

final class RoutineTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var store: RoutineStore!

    override func setUpWithError() throws {
        container = Models.makeContainer(inMemory: true)
        context = ModelContext(container)
        store = RoutineStore(context: context)
    }

    override func tearDownWithError() throws {
        store = nil
        context = nil
        container = nil
    }

    private func names(in context: ModelContext) throws -> [String] {
        try RoutineStore(context: context).activeRoutines().map(\.name)
    }

    private func draft(_ name: String, _ ids: [String] = ["deadlift"]) -> RoutineDraft {
        RoutineDraft(name: name, exercises: ids.map { RoutineItem(exerciseId: $0) })
    }

    // MARK: Starters

    func testThreeStartersInB4Order() {
        XCTAssertEqual(StarterRoutine.all.map(\.title), ["Push, Pull, Legs", "Upper, Lower", "Full body"])
        XCTAssertEqual(StarterRoutine.pushPullLegs.workouts.map(\.name), ["Push", "Pull", "Legs"])
        XCTAssertEqual(StarterRoutine.upperLower.workouts.map(\.name), ["Upper", "Lower"])
        XCTAssertEqual(StarterRoutine.fullBody.workouts.map(\.name), ["Full body"])
        XCTAssertEqual(Set(StarterRoutine.all.map(\.id)).count, 3)
    }

    func testEveryStarterExerciseIsInTheCatalogue() throws {
        let library = ExerciseLibrary(catalogue: try ExerciseCatalogue.load())
        for starter in StarterRoutine.all {
            for workout in starter.workouts {
                XCTAssertFalse(workout.exercises.isEmpty)
                for target in workout.exercises {
                    XCTAssertNotNil(library.exercise(id: target.exerciseId), "\(starter.id): \(target.exerciseId)")
                    XCTAssertTrue(RoutineItem.setsRange.contains(target.sets))
                    XCTAssertTrue(RoutineItem.repsRange.contains(target.reps))
                }
            }
        }
    }

    func testSuggestedStarterFitsTheGoal() {
        XCTAssertEqual(StarterRoutine.suggested(forGoal: 2), .fullBody)
        XCTAssertEqual(StarterRoutine.suggested(forGoal: 3), .fullBody)
        XCTAssertEqual(StarterRoutine.suggested(forGoal: 4), .upperLower)
        XCTAssertEqual(StarterRoutine.suggested(forGoal: 5), .pushPullLegs)
        XCTAssertEqual(StarterRoutine.suggested(forGoal: 6), .pushPullLegs)
    }

    /// The card's test: a starter can be copied and edited without changing the starter.
    func testStarterCanBeCopiedAndEditedWithoutChangingTheStarter() throws {
        let before = StarterRoutine.pushPullLegs
        let adopted = try store.adopt(.pushPullLegs)
        XCTAssertEqual(adopted.map(\.name), ["Push", "Pull", "Legs"])
        XCTAssertTrue(adopted.allSatisfy { $0.starterID == StarterRoutine.pushPullLegs.id })

        // Edit the copy through F3's path: draft, change, save.
        let push = try XCTUnwrap(adopted.first)
        var edit = RoutineDraft(routine: push)
        edit.name = "Push A"
        edit.exercises[0].targetSets = 5
        edit.exercises[0].targetReps = 5
        edit.exercises.remove(at: 1)
        edit.add(try XCTUnwrap(ExerciseLibrary().exercise(id: "cable-crossover")))
        try store.save(edit)

        // The copy changed...
        let saved = try XCTUnwrap(try store.routine(id: push.id))
        XCTAssertEqual(saved.name, "Push A")
        XCTAssertEqual(saved.exercises.first?.targetLabel, "5 x 5")
        XCTAssertEqual(saved.exercises.last?.exerciseId, "cable-crossover")
        XCTAssertFalse(saved.exercises.contains { $0.exerciseId == "overhead-press" })

        // ...the starter did not.
        XCTAssertEqual(StarterRoutine.pushPullLegs, before)
        let template = StarterRoutine.pushPullLegs.workouts[0]
        XCTAssertEqual(template.name, "Push")
        XCTAssertEqual(template.exercises[0], .init(exerciseId: "barbell-bench-press", sets: 3, reps: 8))
        XCTAssertEqual(template.exercises[1].exerciseId, "overhead-press")
        XCTAssertFalse(template.exercises.contains { $0.exerciseId == "cable-crossover" })

        // A second copy comes out as the original starter, not as the edited one.
        let again = try store.adopt(.pushPullLegs)
        let freshPush = try XCTUnwrap(again.first)
        XCTAssertNotEqual(freshPush.id, push.id)
        XCTAssertEqual(freshPush.name, "Push")
        XCTAssertEqual(freshPush.exercises.map(\.exerciseId), template.exercises.map(\.exerciseId))
        XCTAssertEqual(freshPush.exercises.first?.targetLabel, "3 x 8")
        XCTAssertTrue(Set(freshPush.exercises.map(\.id)).isDisjoint(with: saved.exercises.map(\.id)))
    }

    func testAdoptAppendsToTheEndOfTheRotation() throws {
        try store.save(draft("Mine"))
        try store.adopt(.upperLower)
        XCTAssertEqual(try names(in: context), ["Mine", "Upper", "Lower"])
        XCTAssertEqual(try store.activeRoutines().map(\.order), [0, 1, 2])
    }

    // MARK: Reorder

    /// The card's test: reordering persists.
    func testReorderingPersists() throws {
        try store.adopt(.pushPullLegs)
        XCTAssertEqual(try names(in: context), ["Push", "Pull", "Legs"])
        try store.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(try names(in: context), ["Legs", "Push", "Pull"])

        // A fresh context reads from the store, not from memory: the order was saved.
        let fresh = ModelContext(container)
        XCTAssertEqual(try names(in: fresh), ["Legs", "Push", "Pull"])
        XCTAssertEqual(try RoutineStore(context: fresh).activeRoutines().map(\.order), [0, 1, 2])
    }

    func testReorderPersistsInAnOnDiskStore() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pgym-reorder-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        let config = ModelConfiguration(schema: Models.schema, url: url)

        do {
            let disk = try ModelContainer(for: Models.schema, configurations: [config])
            let s = RoutineStore(context: ModelContext(disk))
            try s.adopt(.pushPullLegs)
            try s.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        }
        let reopened = try ModelContainer(for: Models.schema, configurations: [config])
        XCTAssertEqual(try names(in: ModelContext(reopened)), ["Pull", "Legs", "Push"])
    }

    func testReorderMarksOnlyMovedRoutinesForSync() throws {
        try store.adopt(.pushPullLegs)
        for routine in try store.activeRoutines() { routine.needsSync = false }
        try context.save()
        try store.move(fromOffsets: IndexSet(integer: 1), toOffset: 3) // Push, Legs, Pull
        let flags = try store.activeRoutines().map { "\($0.name):\($0.needsSync)" }
        XCTAssertEqual(flags, ["Push:false", "Legs:true", "Pull:true"])
    }

    func testMoveElementsMatchesListOnMove() {
        var a = ["a", "b", "c", "d"]
        a.moveElements(fromOffsets: IndexSet(integer: 0), toOffset: 4)
        XCTAssertEqual(a, ["b", "c", "d", "a"])
        a.moveElements(fromOffsets: IndexSet([2, 3]), toOffset: 0)
        XCTAssertEqual(a, ["d", "a", "b", "c"])
        a.moveElements(fromOffsets: IndexSet(integer: 1), toOffset: 2)
        XCTAssertEqual(a, ["d", "a", "b", "c"])
    }

    func testExerciseOrderInsideARoutinePersists() throws {
        let routine = try store.save(draft("Legs", ["back-squat", "leg-press", "leg-extension"]))
        var edit = RoutineDraft(routine: routine)
        edit.exercises.moveElements(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        try store.save(edit)
        let fresh = try XCTUnwrap(try RoutineStore(context: ModelContext(container)).routine(id: routine.id))
        XCTAssertEqual(fresh.exercises.map(\.exerciseId), ["leg-extension", "back-squat", "leg-press"])
    }

    // MARK: Save, validate, delete

    func testDraftValidationUsesCopyDeckMessages() {
        XCTAssertEqual(RoutineDraft().problem, .missingName)
        XCTAssertEqual(RoutineDraft(name: "   ").problem?.message, "Give the routine a name.")
        XCTAssertEqual(RoutineDraft(name: "Push A").problem?.message, "Add at least one exercise.")
        XCTAssertTrue(draft("Push A").isValid)
        XCTAssertThrowsError(try store.save(RoutineDraft(name: "x")))
    }

    func testSaveTrimsTheNameAndFlagsForSync() throws {
        let routine = try store.save(draft("  Push A  "))
        XCTAssertEqual(routine.name, "Push A")
        XCTAssertTrue(routine.needsSync)
        XCTAssertNil(routine.lastSyncedAt)
    }

    func testTargetsAreClamped() {
        let item = RoutineItem(exerciseId: "deadlift", targetSets: 0, targetReps: 999)
        XCTAssertEqual(item.targetSets, RoutineItem.setsRange.lowerBound)
        XCTAssertEqual(item.targetReps, RoutineItem.repsRange.upperBound)
    }

    func testDeleteHidesTheRoutineAndRenumbers() throws {
        try store.adopt(.pushPullLegs)
        let pull = try XCTUnwrap(try store.activeRoutines().first { $0.name == "Pull" })
        try store.delete(pull)
        XCTAssertEqual(try names(in: context), ["Push", "Legs"])
        XCTAssertEqual(try store.activeRoutines().map(\.order), [0, 1])
        // Kept as a tombstone until Firestore has the delete.
        let tombstone = try XCTUnwrap(try store.routine(id: pull.id))
        XCTAssertTrue(tombstone.isTombstone)
        XCTAssertTrue(tombstone.needsSync)
    }

    // MARK: Custom exercises

    func testCustomExerciseIsCreatedOnceAndFoundBySearch() throws {
        let customs = CustomExerciseStore(context: context)
        let sled = try customs.create(name: " Sled push ", muscleGroup: .legs, equipment: .other)
        let again = try customs.create(name: "sled PUSH", muscleGroup: .core, equipment: .band)
        XCTAssertEqual(sled.id, again.id)
        XCTAssertTrue(sled.id.hasPrefix(CustomExercise.idPrefix))
        XCTAssertEqual(try customs.all().count, 1)

        let library = ExerciseLibrary(custom: try customs.all().map(\.exercise))
        let found = library.search("sled")
        XCTAssertEqual(found.map(\.name), ["Sled push"])
        XCTAssertTrue(found[0].isCustom)
        XCTAssertEqual(found[0].muscleGroup, .legs)
    }
}
