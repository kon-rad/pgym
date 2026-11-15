import SwiftData
import XCTest
@testable import PGYM

/// In-memory stand-in for `users/{uid}/routines`. No network, no Firebase.
final class FakeRoutineRemote: RoutineRemote {
    var documents: [String: [String: RoutineDocument]] = [:]
    var deletes: [String] = []
    var failNextWrite = false

    struct Offline: Error {}

    func upsert(_ document: RoutineDocument, uid: String) async throws {
        if failNextWrite {
            failNextWrite = false
            throw Offline()
        }
        documents[uid, default: [:]][document.id] = document
    }

    func delete(routineID: String, uid: String) async throws {
        deletes.append(routineID)
        documents[uid]?[routineID] = nil
    }

    func fetchAll(uid: String) async throws -> [RoutineDocument] {
        Array((documents[uid] ?? [:]).values)
    }
}

final class RoutineSyncTests: XCTestCase {
    private let uid = "user-1"
    /// Each context is a separate phone. Containers are kept alive for the whole test.
    private var containers: [ModelContainer] = []

    private func makeContext() -> ModelContext {
        let container = Models.makeContainer(inMemory: true)
        containers.append(container)
        return ModelContext(container)
    }

    @MainActor
    func testPushWritesPendingRoutinesInTheArchitectureShape() async throws {
        let context = makeContext()
        let store = RoutineStore(context: context)
        try store.adopt(.upperLower)
        let remote = FakeRoutineRemote()
        let engine = RoutineSyncEngine(remote: remote)

        let report = try await engine.push(context: context, uid: uid, library: ExerciseLibrary())
        XCTAssertEqual(report.pushed, 2)

        let upper = try XCTUnwrap(try store.activeRoutines().first)
        let doc = try XCTUnwrap(remote.documents[uid]?[upper.id])
        XCTAssertEqual(doc.name, "Upper")
        XCTAssertEqual(doc.order, 0)
        XCTAssertEqual(doc.exercises.first, .init(exerciseId: "barbell-bench-press", targetSets: 3, targetReps: 8, name: nil))

        let data = doc.firestoreData
        XCTAssertEqual(Set(data.keys), ["name", "order", "exercises", "updatedAt"])
        let first = try XCTUnwrap((data["exercises"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(first.keys), ["exerciseId", "targetSets", "targetReps"], "no local row IDs, no name for catalogue exercises")

        XCTAssertTrue(try store.activeRoutines().allSatisfy { !$0.needsSync && $0.lastSyncedAt != nil })
        let second = try await engine.push(context: context, uid: uid, library: ExerciseLibrary())
        XCTAssertEqual(second.pushed, 0, "nothing left to push")
    }

    @MainActor
    func testCustomExerciseNameTravelsWithTheRoutine() async throws {
        let context = makeContext()
        let custom = try CustomExerciseStore(context: context).create(name: "Sled push", muscleGroup: .legs, equipment: .other)
        try RoutineStore(context: context).save(RoutineDraft(name: "Conditioning", exercises: [RoutineItem(exerciseId: custom.id)]))
        let remote = FakeRoutineRemote()
        let library = ExerciseLibrary(custom: [custom.exercise])

        let engine = RoutineSyncEngine(remote: remote)
        _ = try await engine.push(context: context, uid: uid, library: library)
        let doc = try XCTUnwrap(remote.documents[uid]?.values.first)
        XCTAssertEqual(doc.exercises.first?.name, "Sled push")
        XCTAssertEqual(doc.exercises.first?.muscleGroup, "legs")
        XCTAssertEqual(doc.exercises.first?.equipment, "other")

        // A second phone gets the custom exercise with the routine, under the same ID.
        let phoneB = makeContext()
        _ = try await engine.pull(context: phoneB, uid: uid)
        let mirrored = try CustomExerciseStore(context: phoneB).all()
        XCTAssertEqual(mirrored.map(\.id), [custom.id])
        let libraryB = ExerciseLibrary(custom: mirrored.map(\.exercise))
        XCTAssertEqual(libraryB.exercise(id: custom.id)?.name, "Sled push")
        XCTAssertEqual(libraryB.exercise(id: custom.id)?.muscleGroup, .legs)

        // Pulling again does not duplicate it.
        _ = try await engine.pull(context: phoneB, uid: uid)
        XCTAssertEqual(try CustomExerciseStore(context: phoneB).all().count, 1)
    }

    @MainActor
    func testDeletePushesTheDeleteThenDropsTheTombstone() async throws {
        let context = makeContext()
        let store = RoutineStore(context: context)
        let remote = FakeRoutineRemote()
        let engine = RoutineSyncEngine(remote: remote)
        let routines = try store.adopt(.pushPullLegs)
        _ = try await engine.push(context: context, uid: uid, library: ExerciseLibrary())

        let pullID = routines[1].id
        try store.delete(routines[1])
        let report = try await engine.push(context: context, uid: uid, library: ExerciseLibrary())

        XCTAssertEqual(report.deleted, 1)
        XCTAssertEqual(remote.deletes, [pullID])
        XCTAssertNil(remote.documents[uid]?[pullID])
        XCTAssertNil(try store.routine(id: pullID))
        // Legs moved up to order 1 and was pushed again with it.
        XCTAssertEqual(remote.documents[uid]?.values.sorted { $0.order < $1.order }.map(\.name), ["Push", "Legs"])
    }

    @MainActor
    func testFailedWriteKeepsTheChangeForNextTime() async throws {
        let context = makeContext()
        let store = RoutineStore(context: context)
        try store.save(RoutineDraft(name: "Push A", exercises: [RoutineItem(exerciseId: "barbell-bench-press")]))
        let remote = FakeRoutineRemote()
        remote.failNextWrite = true
        let engine = RoutineSyncEngine(remote: remote)

        do {
            _ = try await engine.push(context: context, uid: uid, library: ExerciseLibrary())
            XCTFail("expected the offline error")
        } catch {}
        XCTAssertTrue(try store.activeRoutines()[0].needsSync)

        let report = try await engine.push(context: context, uid: uid, library: ExerciseLibrary())
        XCTAssertEqual(report.pushed, 1)
        XCTAssertFalse(try store.activeRoutines()[0].needsSync)
    }

    @MainActor
    func testPullBringsRoutinesFromAnotherPhone() async throws {
        let remote = FakeRoutineRemote()
        let engine = RoutineSyncEngine(remote: remote)

        let phoneA = makeContext()
        try RoutineStore(context: phoneA).adopt(.upperLower)
        _ = try await engine.push(context: phoneA, uid: uid, library: ExerciseLibrary())

        let phoneB = makeContext()
        let report = try await engine.pull(context: phoneB, uid: uid)
        XCTAssertEqual(report.pulled, 2)
        let routines = try RoutineStore(context: phoneB).activeRoutines()
        XCTAssertEqual(routines.map(\.name), ["Upper", "Lower"])
        XCTAssertEqual(routines[0].exercises.map(\.exerciseId), StarterRoutine.upperLower.workouts[0].exercises.map(\.exerciseId))
        XCTAssertTrue(routines.allSatisfy { !$0.needsSync })
    }

    @MainActor
    func testNewerRemoteEditWinsOlderDoesNot() async throws {
        let context = makeContext()
        let store = RoutineStore(context: context)
        let t0 = Date(timeIntervalSince1970: 1_000)
        let routine = try store.save(RoutineDraft(name: "Push", exercises: [RoutineItem(exerciseId: "push-up")]), now: t0)
        let remote = FakeRoutineRemote()
        let engine = RoutineSyncEngine(remote: remote)
        _ = try await engine.push(context: context, uid: uid, library: ExerciseLibrary())

        // Another phone renamed it later.
        remote.documents[uid]?[routine.id]?.name = "Push (gym B)"
        remote.documents[uid]?[routine.id]?.updatedAt = t0.addingTimeInterval(60)
        _ = try await engine.pull(context: context, uid: uid)
        XCTAssertEqual(try store.routine(id: routine.id)?.name, "Push (gym B)")

        // This phone edits after that; an older remote copy must not overwrite it.
        var edit = RoutineDraft(routine: try XCTUnwrap(try store.routine(id: routine.id)))
        edit.name = "Push heavy"
        try store.save(edit, now: t0.addingTimeInterval(120))
        _ = try await engine.pull(context: context, uid: uid)
        XCTAssertEqual(try store.routine(id: routine.id)?.name, "Push heavy")
        XCTAssertTrue(try XCTUnwrap(try store.routine(id: routine.id)).needsSync)
    }

    @MainActor
    func testRoutineDeletedOnAnotherPhoneIsRemovedHere() async throws {
        let context = makeContext()
        let store = RoutineStore(context: context)
        let remote = FakeRoutineRemote()
        let engine = RoutineSyncEngine(remote: remote)
        let routines = try store.adopt(.upperLower)
        _ = try await engine.push(context: context, uid: uid, library: ExerciseLibrary())

        remote.documents[uid]?[routines[0].id] = nil
        let unsynced = try store.save(RoutineDraft(name: "Local only", exercises: [RoutineItem(exerciseId: "plank")]))
        let report = try await engine.pull(context: context, uid: uid)

        XCTAssertEqual(report.removedLocally, 1)
        XCTAssertEqual(try store.activeRoutines().map(\.name), ["Lower", "Local only"])
        XCTAssertNotNil(try store.routine(id: unsynced.id), "a routine never synced is not treated as deleted")
    }

    func testDocumentReadsFirestoreShapedData() {
        let data: [String: Any] = [
            "name": "Legs",
            "order": NSNumber(value: 2),
            "updatedAt": Date(timeIntervalSince1970: 5),
            "exercises": [
                ["exerciseId": "back-squat", "targetSets": NSNumber(value: 5), "targetReps": 5],
                ["targetSets": 3],
            ] as [[String: Any]],
        ]
        let doc = RoutineDocument(id: "r1", data: data) { $0 as? Date }
        XCTAssertEqual(doc?.order, 2)
        XCTAssertEqual(doc?.exercises, [.init(exerciseId: "back-squat", targetSets: 5, targetReps: 5, name: nil)])
        XCTAssertEqual(doc?.updatedAt, Date(timeIntervalSince1970: 5))
        XCTAssertNil(RoutineDocument(id: "bad", data: ["order": 1]) { _ in nil })
    }
}
