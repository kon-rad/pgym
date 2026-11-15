import SwiftData
import XCTest
@testable import PGYM

/// Card I5: totals, new bests, units, the session surviving a relaunch, and the sync queue.
/// Every test owns its store; nothing touches the network or Firebase.
@MainActor
final class SessionTests: XCTestCase {
    private let bench = "barbell-bench-press"
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// Containers are kept for the whole test so their contexts stay valid.
    private var containers: [ModelContainer] = []

    private func makeContext() -> ModelContext {
        let container = Models.makeContainer(inMemory: true)
        containers.append(container)
        return container.mainContext
    }

    private func pushA(sets: Int = 3, reps: Int = 8) -> Routine {
        Routine(name: "Push A", order: 0, exercises: [RoutineItem(exerciseId: bench, targetSets: sets, targetReps: reps)])
    }

    /// Logs a finished earlier session of bench press with the given sets, so there is a stored best.
    @discardableResult
    private func logEarlierSession(_ store: SessionStore, routine: Routine, sets: [(Double, Int)], at start: Date) throws -> WorkoutSession {
        let session = try store.start(routine: routine, library: ExerciseLibrary(), now: start)
        let exercise = try XCTUnwrap(session.orderedExercises.first)
        while exercise.sets.count < sets.count { try store.addSet(to: exercise, now: start) }
        for (index, (weight, reps)) in sets.enumerated() {
            let set = exercise.orderedSets[index]
            try store.setWeight(weight, for: set, now: start)
            try store.setReps(reps, for: set, now: start)
        }
        for (index, set) in exercise.orderedSets.enumerated() where index < sets.count {
            try store.complete(set, now: start.addingTimeInterval(Double(index + 1) * 60))
        }
        try store.finish(session, withProof: false, now: start.addingTimeInterval(3600))
        return session
    }

    // MARK: Total volume counts working sets only

    func testTotalVolumeCountsWorkingSetsOnly() {
        let totals = SessionMath.totals([
            [
                .init(weightKg: 40, reps: 10, type: .warmup, done: true),   // warm-up: excluded
                .init(weightKg: 80, reps: 8, type: .working, done: true),   // 640
                .init(weightKg: 80, reps: 8, type: .working, done: true),   // 640
                .init(weightKg: 80, reps: 8, type: .working, done: false),  // not done: excluded
            ],
            [
                .init(weightKg: 20, reps: 12, type: .warmup, done: true),   // warm-up only exercise
            ],
            [
                .init(weightKg: 0, reps: 12, type: .working, done: true),   // bodyweight: counts as a set, 0 volume
            ],
        ])
        XCTAssertEqual(totals.volumeKg, 1280)
        XCTAssertEqual(totals.setCount, 3)
        XCTAssertEqual(totals.exerciseCount, 2)
    }

    func testSessionTotalsIgnoreWarmupsAfterTypeChange() throws {
        let context = makeContext()
        let store = SessionStore(context: context)
        let session = try store.start(routine: pushA(), library: ExerciseLibrary(), now: t0)
        let sets = try XCTUnwrap(session.orderedExercises.first).orderedSets
        try store.setWeight(100, for: sets[0], now: t0)
        try store.setReps(5, for: sets[0], now: t0)
        for (i, set) in sets.enumerated() { try store.complete(set, now: t0.addingTimeInterval(Double(i))) }
        XCTAssertEqual(session.totals.volumeKg, 1500)

        try store.setType(.warmup, for: sets[0], now: t0)
        XCTAssertEqual(session.totals.volumeKg, 1000)
        XCTAssertEqual(session.totals.setCount, 2)
        XCTAssertEqual(SessionDocument(session: session).totalVolume, 1000)
    }

    // MARK: New best only when it beats the stored best

    func testEpley() {
        XCTAssertEqual(SessionMath.e1rm(weightKg: 100, reps: 1), 100)
        XCTAssertEqual(SessionMath.e1rm(weightKg: 100, reps: 5), 116.7)
        XCTAssertEqual(SessionMath.e1rm(weightKg: 80, reps: 8), 101.3)
        XCTAssertEqual(SessionMath.e1rm(weightKg: 0, reps: 8), 0)
        XCTAssertEqual(SessionMath.e1rm(weightKg: 80, reps: 0), 0)
    }

    func testNewBestFlaggedOnlyWhenItBeatsStoredBest() {
        let stored = StoredBest(weightKg: 100, e1rmKg: SessionMath.e1rm(weightKg: 100, reps: 5)) // 116.7
        // Equal is not a best.
        XCTAssertFalse(SessionMath.isNewBest(weightKg: 100, reps: 5, type: .working, against: stored))
        // Lower on both is not a best.
        XCTAssertFalse(SessionMath.isNewBest(weightKg: 95, reps: 5, type: .working, against: stored))
        // More weight is a best.
        XCTAssertTrue(SessionMath.isNewBest(weightKg: 102.5, reps: 1, type: .working, against: stored))
        // Same weight, more reps: a higher estimated one-rep max is a best.
        XCTAssertTrue(SessionMath.isNewBest(weightKg: 100, reps: 6, type: .working, against: stored))
        // Lighter but a higher estimate (90 x 10 = 120) is a best.
        XCTAssertTrue(SessionMath.isNewBest(weightKg: 90, reps: 10, type: .working, against: stored))
        // Warm-ups never are.
        XCTAssertFalse(SessionMath.isNewBest(weightKg: 150, reps: 5, type: .warmup, against: stored))
        // With nothing stored there is nothing to beat: the first session sets the baseline.
        XCTAssertFalse(SessionMath.isNewBest(weightKg: 150, reps: 5, type: .working, against: .none))
    }

    func testNewBestInSessionAgainstStoredAndEarlierSets() throws {
        let context = makeContext()
        let store = SessionStore(context: context)
        let routine = pushA()
        context.insert(routine)
        try logEarlierSession(store, routine: routine, sets: [(100, 5), (100, 5), (100, 5)], at: t0)

        let stat = try XCTUnwrap(try store.stat(exerciseId: bench))
        XCTAssertEqual(stat.bestWeightKg, 100)
        XCTAssertEqual(stat.bestE1rmKg, 116.7)

        let later = t0.addingTimeInterval(86_400 * 3)
        let session = try store.start(routine: routine, library: ExerciseLibrary(), now: later)
        let sets = try XCTUnwrap(session.orderedExercises.first).orderedSets

        // Pre-filled 100 x 5 equals the best: no flag.
        XCTAssertEqual(try store.complete(sets[0], now: later.addingTimeInterval(60)), .logged(isNewBest: false, exerciseComplete: false))
        XCTAssertFalse(sets[0].isNewBest)

        // 102.5 x 5 beats it.
        try store.setWeight(102.5, for: sets[1], now: later)
        XCTAssertEqual(try store.complete(sets[1], now: later.addingTimeInterval(120)), .logged(isNewBest: true, exerciseComplete: false))
        XCTAssertTrue(sets[1].isNewBest)

        // Repeating 102.5 x 5 only equals the set just logged: no second flag.
        XCTAssertEqual(sets[2].weightKg, 102.5, "copy-down from set 2")
        XCTAssertEqual(try store.complete(sets[2], now: later.addingTimeInterval(180)), .logged(isNewBest: false, exerciseComplete: true))
        XCTAssertFalse(sets[2].isNewBest)
    }

    func testEmptyWeightOpensKeypadInsteadOfLogging() throws {
        let context = makeContext()
        let store = SessionStore(context: context)
        let session = try store.start(routine: pushA(), library: ExerciseLibrary(), now: t0)
        let first = try XCTUnwrap(session.orderedExercises.first?.orderedSets.first)
        XCTAssertNil(first.weightKg, "a first-ever exercise has an empty weight")
        XCTAssertEqual(first.reps, 8, "and the routine's target reps")
        XCTAssertEqual(try store.complete(first, now: t0), .needsWeight)
        XCTAssertFalse(first.done)
    }

    // MARK: Pre-fill, copy-down and the rest timer

    func testLastSessionWeightsArePrefilled() throws {
        let context = makeContext()
        let store = SessionStore(context: context)
        let routine = pushA(sets: 4)
        context.insert(routine)
        try logEarlierSession(store, routine: routine, sets: [(80, 8), (80, 8), (77.5, 7)], at: t0)

        let session = try store.start(routine: routine, library: ExerciseLibrary(), now: t0.addingTimeInterval(86_400))
        let sets = try XCTUnwrap(session.orderedExercises.first).orderedSets
        XCTAssertEqual(sets.count, 4)
        XCTAssertEqual(sets.map(\.weightKg), [80, 80, 77.5, 77.5], "set 4 copies the set above")
        XCTAssertEqual(sets.map(\.reps), [8, 8, 7, 7])
        XCTAssertEqual(sets.map(\.lastWeightKg), [80, 80, 77.5, nil])
        XCTAssertEqual(sets.map(\.lastReps), [8, 8, 7, nil])
        XCTAssertEqual(session.orderedExercises.first?.name, "Barbell bench press")
    }

    func testEditCopiesDownToUndoneSetsOnly() throws {
        let context = makeContext()
        let store = SessionStore(context: context)
        let session = try store.start(routine: pushA(), library: ExerciseLibrary(), now: t0)
        let sets = try XCTUnwrap(session.orderedExercises.first).orderedSets
        try store.setWeight(60, for: sets[0], now: t0)
        try store.complete(sets[0], now: t0)
        try store.setWeight(62.5, for: sets[1], now: t0)
        XCTAssertEqual(sets.map(\.weightKg), [60, 62.5, 62.5], "copied down from set 2, set 1 is done")
        try store.complete(sets[1], now: t0.addingTimeInterval(60))
        try store.setWeight(65, for: sets[0], now: t0)
        XCTAssertEqual(sets.map(\.weightKg), [65, 62.5, 65], "done set 2 never changes; undone set 3 does")
    }

    func testRestTimerIsAnEndInstant() throws {
        let context = makeContext()
        let store = SessionStore(context: context)
        let session = try store.start(routine: pushA(), library: ExerciseLibrary(), restSeconds: 90, now: t0)
        let set = try XCTUnwrap(session.orderedExercises.first?.orderedSets.first)
        try store.setWeight(60, for: set, now: t0)
        try store.complete(set, now: t0)
        XCTAssertEqual(session.restEndsAt, t0.addingTimeInterval(90))

        try store.adjustRest(session, by: 15, now: t0.addingTimeInterval(10))
        XCTAssertEqual(session.restEndsAt, t0.addingTimeInterval(105))
        try store.adjustRest(session, by: -15, now: t0.addingTimeInterval(10))
        XCTAssertEqual(session.restEndsAt, t0.addingTimeInterval(90))

        // Ran out while the app was closed: cleared on relaunch.
        try store.clearExpiredRest(session, now: t0.addingTimeInterval(200))
        XCTAssertNil(session.restEndsAt)
    }

    func testRestNotificationScheduledAtEnd() {
        let notifier = RecordingRestNotifier()
        let end = t0.addingTimeInterval(90)
        notifier.scheduleRestEnd(at: end, title: SessionCopy.restNotificationTitle, body: "")
        XCTAssertEqual(notifier.pending, end)
        notifier.cancelRestEnd()
        XCTAssertNil(notifier.pending)
    }

    // MARK: kg to lb display round-trips without drift

    func testPoundsRoundTripWithoutDrift() {
        let lb = WeightUnit.lb
        var value = 0.0
        while value <= 1000 {
            let kg = lb.kilograms(fromDisplay: value)
            XCTAssertEqual(lb.displayValue(kg: kg), value, "\(value) lb")
            // Twenty more trips through storage and display: still the same.
            var again = kg
            for _ in 0..<20 { again = lb.kilograms(fromDisplay: lb.displayValue(kg: again)) }
            XCTAssertEqual(lb.displayValue(kg: again), value, "\(value) lb after 20 trips")
            value += 0.5
        }
        XCTAssertEqual(lb.format(kg: lb.kilograms(fromDisplay: 100)), "100")
        XCTAssertEqual(lb.format(kg: lb.kilograms(fromDisplay: 225)), "225")
    }

    func testKilogramsRoundTripAndSteps() {
        let kg = WeightUnit.kg
        var value = 0.0
        while value <= 500 {
            XCTAssertEqual(kg.displayValue(kg: kg.kilograms(fromDisplay: value)), value)
            value += 1.25
        }
        XCTAssertEqual(kg.stepped(kg: 80, by: 1), 82.5)
        XCTAssertEqual(kg.stepped(kg: 80, by: -1), 77.5)
        XCTAssertEqual(kg.stepped(kg: 1, by: -1), 0, "never below zero")
        XCTAssertEqual(kg.format(kg: 102.5), "102.5")
        XCTAssertEqual(kg.format(kg: 80), "80")

        let lb = WeightUnit.lb
        let start = lb.kilograms(fromDisplay: 225)
        let up = lb.stepped(kg: start, by: 1)
        XCTAssertEqual(lb.displayValue(kg: up), 230)
        XCTAssertEqual(lb.displayValue(kg: lb.stepped(kg: up, by: -1)), 225)
    }

    func testKilogramsShownInPoundsAreNotRewrittenWhenUntouched() {
        // 100 kg shows as 220.5 lb. Opening and closing the keypad must not store 220.5 lb (100.02 kg).
        let lb = WeightUnit.lb
        let state = KeypadState(setID: "s", field: .weight, text: lb.format(kg: 100))
        XCTAssertEqual(state.text, "220.5")
        XCTAssertFalse(state.isEdited)
    }

    func testKeypadReplacesSelectedValueAndSteps() {
        var state = KeypadState(setID: "s", field: .weight, text: "80")
        state.type(8)
        state.type(5)
        XCTAssertEqual(state.text, "85", "the first digit replaces the selected value")
        state.step(1, unit: .kg)
        XCTAssertEqual(state.text, "87.5")
        state.step(-1, unit: .lb)
        XCTAssertEqual(state.text, "82.5")
        state.decimal()
        state.type(2)
        state.type(5)
        XCTAssertEqual(state.text, "0.25")
        var reps = KeypadState(setID: "s", field: .reps, text: "8")
        reps.step(-1, unit: .kg)
        XCTAssertEqual(reps.reps, 7)
        reps.decimal()
        XCTAssertEqual(reps.text, "7", "reps take no decimal point")
    }

    // MARK: A session restored after relaunch has the same sets

    func testSessionRestoredAfterRelaunchHasSameSets() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pgym-relaunch-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
        }

        struct Snapshot: Equatable {
            var n: Int
            var weight: Double?
            var reps: Int?
            var type: SetType
            var done: Bool
            var isNewBest: Bool
            var rpe: Int?
            var note: String
        }
        func snapshot(_ session: WorkoutSession) -> [[Snapshot]] {
            session.orderedExercises.map { exercise in
                exercise.orderedSets.map {
                    Snapshot(n: $0.n, weight: $0.weightKg, reps: $0.reps, type: $0.type, done: $0.done, isNewBest: $0.isNewBest, rpe: $0.rpe, note: $0.note)
                }
            }
        }

        let before: [[Snapshot]]
        let sessionID: String
        let restEnd: Date?
        do {
            let container = try Models.makeContainer(url: url)
            let store = SessionStore(context: container.mainContext)
            let session = try store.start(routine: pushA(), library: ExerciseLibrary(), now: t0)
            let exercise = try XCTUnwrap(session.orderedExercises.first)
            let sets = exercise.orderedSets
            try store.setWeight(60, for: sets[0], now: t0)
            try store.complete(sets[0], now: t0.addingTimeInterval(30))
            try store.setReps(6, for: sets[1], now: t0)
            try store.complete(sets[1], now: t0.addingTimeInterval(200))
            try store.setType(.warmup, for: sets[2], now: t0)
            try store.setDetail(rpe: 8, note: "Felt fast", for: sets[1], now: t0)
            try store.addSet(to: exercise, now: t0)
            _ = try store.addExercise(
                Exercise(id: "dumbbell-bench-press", name: "Dumbbell bench press", muscleGroup: .chest, equipment: .dumbbell),
                to: session,
                now: t0
            )
            before = snapshot(session)
            sessionID = session.id
            restEnd = session.restEndsAt
            // No explicit save here: every store call already saved, which is the point.
        }

        // "Relaunch": a new container on the same file, as the app does after a kill.
        let reopened = try Models.makeContainer(url: url)
        let store = SessionStore(context: reopened.mainContext)
        let restored = try XCTUnwrap(try store.activeSession())
        XCTAssertEqual(restored.id, sessionID)
        XCTAssertEqual(restored.startedAt, t0)
        XCTAssertEqual(restored.routineName, "Push A")
        XCTAssertEqual(restored.restEndsAt, restEnd)
        XCTAssertEqual(snapshot(restored), before)
        XCTAssertEqual(restored.orderedExercises.map(\.exerciseId), [bench, "dumbbell-bench-press"])
        XCTAssertEqual(restored.doneSetCount, 2)
    }

    // MARK: Sync queue: retries after a network failure, never writes a session twice

    private func makeQueue(
        _ context: ModelContext,
        remote: FakeSessionRemote,
        online: @escaping @MainActor () -> Bool = { true }
    ) -> SessionSyncQueue {
        SessionSyncQueue(
            container: context.container,
            engine: SessionSyncEngine(remote: remote, writeTimeout: 5),
            uid: { "user-1" },
            isOnline: online,
            debounce: 0,
            retryDelays: [0, 0, 0],
            sleep: { _ in }
        )
    }

    func testSyncQueueRetriesAfterNetworkFailureAndWritesOnce() async throws {
        let context = makeContext()
        let store = SessionStore(context: context)
        let session = try store.start(routine: pushA(), library: ExerciseLibrary(), now: t0)
        let set = try XCTUnwrap(session.orderedExercises.first?.orderedSets.first)
        try store.setWeight(60, for: set, now: t0)
        try store.complete(set, now: t0)

        let remote = FakeSessionRemote()
        remote.failuresLeft = 1 // the gym's signal drops on the first try
        let queue = makeQueue(context, remote: remote)

        queue.requestSync()
        await queue.waitUntilIdle()

        XCTAssertEqual(remote.upsertAttempts, 2, "one failure, then one retry")
        XCTAssertEqual(remote.successfulWrites, [session.id], "written exactly once")
        XCTAssertEqual(remote.documents.count, 1)
        XCTAssertFalse(session.needsSync)
        XCTAssertNotNil(session.lastSyncedAt)
        XCTAssertEqual(session.syncFailures, 0)
        XCTAssertEqual(queue.pendingCount, 0)

        // Nothing changed: asking again writes nothing.
        queue.requestSync()
        queue.requestSync()
        await queue.waitUntilIdle()
        XCTAssertEqual(remote.successfulWrites, [session.id])

        // A real change is written once more, to the same document.
        try store.setReps(9, for: set, now: t0.addingTimeInterval(10))
        queue.requestSync()
        await queue.waitUntilIdle()
        XCTAssertEqual(remote.successfulWrites, [session.id, session.id])
        XCTAssertEqual(remote.documents.count, 1, "one session is one document, never two")
        XCTAssertEqual(remote.documents[session.id]?.exercises.first?.sets.first?.reps, 9)
    }

    func testSyncQueueWaitsWhileOfflineThenWritesOnce() async throws {
        let context = makeContext()
        let store = SessionStore(context: context)
        let session = try store.start(routine: pushA(), library: ExerciseLibrary(), now: t0)
        let remote = FakeSessionRemote()
        var online = false
        let queue = makeQueue(context, remote: remote, online: { online })

        queue.requestSync()
        await queue.waitUntilIdle()
        XCTAssertEqual(remote.upsertAttempts, 0, "offline: nothing is tried, the session stays queued")
        XCTAssertTrue(session.needsSync)
        XCTAssertEqual(queue.pendingCount, 1)

        online = true
        queue.requestSync()
        await queue.waitUntilIdle()
        XCTAssertEqual(remote.successfulWrites, [session.id])
        XCTAssertFalse(session.needsSync)
    }

    func testSyncQueueGivesUpAfterRetriesAndKeepsSessionQueued() async throws {
        let context = makeContext()
        let store = SessionStore(context: context)
        let session = try store.start(routine: pushA(), library: ExerciseLibrary(), now: t0)
        let remote = FakeSessionRemote()
        remote.failuresLeft = 100
        let queue = makeQueue(context, remote: remote)

        queue.requestSync()
        await queue.waitUntilIdle()
        XCTAssertEqual(remote.upsertAttempts, 4, "first try plus three retries")
        XCTAssertTrue(session.needsSync, "still queued for the next trigger")
        XCTAssertTrue(queue.lastAttemptFailed)
        XCTAssertTrue(remote.successfulWrites.isEmpty)
    }

    func testSyncNeverWritesStampedOrServerFields() async throws {
        let context = makeContext()
        let store = SessionStore(context: context)
        let session = try store.start(routine: pushA(), library: ExerciseLibrary(), now: t0)
        let document = SessionDocument(session: session)
        for key in ["proofNumber", "stampedAt", "physique", "photoKey", "cardKey", "newBests"] {
            XCTAssertNil(document.firestoreData[key], key)
        }
        XCTAssertEqual(document.firestoreData["status"] as? String, "draft")

        session.status = .stamped
        session.touch(t0)
        let remote = FakeSessionRemote()
        let queue = makeQueue(context, remote: remote)
        queue.requestSync()
        await queue.waitUntilIdle()
        XCTAssertEqual(remote.upsertAttempts, 0)
        XCTAssertFalse(session.needsSync)
    }

    func testDiscardedSessionIsRemovedRemotelyOnlyIfItSynced() async throws {
        let context = makeContext()
        let store = SessionStore(context: context)
        let remote = FakeSessionRemote()
        let queue = makeQueue(context, remote: remote)

        let synced = try store.start(routine: pushA(), library: ExerciseLibrary(), now: t0)
        let syncedID = synced.id
        queue.requestSync()
        await queue.waitUntilIdle()
        try store.discard(synced, now: t0)
        XCTAssertNil(try store.activeSession())
        queue.requestSync()
        await queue.waitUntilIdle()
        XCTAssertEqual(remote.deletedIDs, [syncedID])
        XCTAssertNil(try store.session(id: syncedID))

        let local = try store.start(routine: pushA(), library: ExerciseLibrary(), now: t0.addingTimeInterval(60))
        let localID = local.id
        try store.discard(local, now: t0.addingTimeInterval(60))
        try store.purgeDiscarded()
        XCTAssertNil(try store.session(id: localID))
        queue.requestSync()
        await queue.waitUntilIdle()
        XCTAssertEqual(remote.deletedIDs, [syncedID], "a session Firestore never had is not deleted there")
        XCTAssertEqual(remote.successfulWrites, [syncedID])
    }

    // MARK: Starting and Next up

    func testOnlyOneDraftAtATime() throws {
        let context = makeContext()
        let store = SessionStore(context: context)
        let first = try store.start(routine: pushA(), library: ExerciseLibrary(), now: t0)
        let second = try store.start(routine: nil, library: ExerciseLibrary(), now: t0.addingTimeInterval(5))
        XCTAssertEqual(first.id, second.id)
    }

    func testNextUpRotatesThroughRoutines() {
        let a = Routine(name: "A", order: 0, exercises: [])
        let b = Routine(name: "B", order: 1, exercises: [])
        let c = Routine(name: "C", order: 2, exercises: [])
        XCTAssertEqual(NextUp.routine(in: [a, b, c], lastRoutineID: nil)?.name, "A")
        XCTAssertEqual(NextUp.routine(in: [a, b, c], lastRoutineID: a.id)?.name, "B")
        XCTAssertEqual(NextUp.routine(in: [a, b, c], lastRoutineID: c.id)?.name, "A")
        XCTAssertEqual(NextUp.routine(in: [a, b, c], lastRoutineID: "deleted")?.name, "A")
        XCTAssertNil(NextUp.routine(in: [], lastRoutineID: nil))
    }

    func testSaveWithoutProofFinishesAndCountsBestsOnce() throws {
        let context = makeContext()
        let store = SessionStore(context: context)
        let routine = pushA()
        context.insert(routine)
        let session = try logEarlierSession(store, routine: routine, sets: [(100, 5)], at: t0)
        XCTAssertEqual(session.status, .finished)
        XCTAssertNotNil(session.endedAt)
        try store.finish(session, withProof: false, now: t0.addingTimeInterval(7200))
        XCTAssertEqual(try store.stat(exerciseId: bench)?.sessionCount, 1, "finishing twice folds once")
        XCTAssertNil(try store.activeSession())
    }
}

/// Firestore stand-in: documents by ID, with a switch to fail the next writes like a dropped signal.
final class FakeSessionRemote: SessionRemote {
    var failuresLeft = 0
    private(set) var upsertAttempts = 0
    private(set) var successfulWrites: [String] = []
    private(set) var documents: [String: SessionDocument] = [:]
    private(set) var deletedIDs: [String] = []
    var stats: [RemoteExerciseStat] = []

    func upsert(_ document: SessionDocument, uid: String) async throws {
        upsertAttempts += 1
        if failuresLeft > 0 {
            failuresLeft -= 1
            throw URLError(.notConnectedToInternet)
        }
        documents[document.id] = document
        successfulWrites.append(document.id)
    }

    func delete(sessionID: String, uid: String) async throws {
        documents[sessionID] = nil
        deletedIDs.append(sessionID)
    }

    func fetchExerciseStats(uid: String) async throws -> [RemoteExerciseStat] {
        stats
    }
}
