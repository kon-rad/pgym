import Foundation
import SwiftData

/// Every write to a session goes through here and is saved at once, so the session survives an app
/// kill at any moment (pgym-flow-spec.md, "When the app is killed mid-session"), and every change
/// bumps the version the sync queue looks at.
struct SessionStore {
    let context: ModelContext

    // MARK: Reading

    /// The draft being logged, if any. There is at most one.
    func activeSession() throws -> WorkoutSession? {
        let draft = SessionStatus.draft.rawValue
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.statusRaw == draft && $0.endedAt == nil },
            sortBy: [SortDescriptor(\WorkoutSession.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func session(id: String) throws -> WorkoutSession? {
        var descriptor = FetchDescriptor<WorkoutSession>(predicate: #Predicate<WorkoutSession> { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Sessions that count as history (not discarded), newest first.
    func history() throws -> [WorkoutSession] {
        let discarded = SessionStatus.discarded.rawValue
        return try context.fetch(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.statusRaw != discarded },
            sortBy: [SortDescriptor(\WorkoutSession.startedAt, order: .reverse)]
        ))
    }

    /// The logged sets of this exercise in the most recent other session that has any.
    /// This is "Last time" on D2 and the source of the pre-filled weights.
    func lastSets(exerciseId: String, excludingSession sessionID: String?) throws -> [SessionSet] {
        let rows = try context.fetch(FetchDescriptor<SessionExercise>(
            predicate: #Predicate<SessionExercise> { $0.exerciseId == exerciseId }
        ))
        let candidates = rows.filter { row in
            guard let session = row.session else { return false }
            return session.id != sessionID
                && session.status != .discarded
                && row.sets.contains(where: \.done)
        }
        let latest = candidates.max { a, b in
            (a.session?.startedAt ?? .distantPast) < (b.session?.startedAt ?? .distantPast)
        }
        return latest?.orderedSets.filter(\.done) ?? []
    }

    func stat(exerciseId: String) throws -> ExerciseStat? {
        var descriptor = FetchDescriptor<ExerciseStat>(predicate: #Predicate<ExerciseStat> { $0.exerciseId == exerciseId })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// The best to beat for `set`: earlier sessions' best, raised by the sets already logged before it
    /// in this session. Equal to the best is not a best, so logging 100 x 5 twice flags only the first.
    func bestToBeat(for set: SessionSet) throws -> StoredBest {
        guard let exercise = set.exercise else { return .none }
        var best = try stat(exerciseId: exercise.exerciseId)?.best ?? .none
        guard let session = exercise.session else { return best }
        for other in session.exercises where other.exerciseId == exercise.exerciseId {
            for logged in other.sets where logged.id != set.id && logged.done {
                if let at = logged.doneAt, let mine = set.doneAt, at > mine { continue }
                best = SessionMath.raising(best, weightKg: logged.weightKg, reps: logged.reps, type: logged.type)
            }
        }
        return best
    }

    // MARK: Starting

    /// Starts a session from a routine (nil for an Empty session), with last session's weights filled
    /// in. If a draft is already open it is returned instead: there is never a second draft.
    @discardableResult
    func start(routine: Routine?, library: ExerciseLibrary, restSeconds: Int = WorkoutSession.defaultRestSeconds, now: Date = .now) throws -> WorkoutSession {
        if let open = try activeSession() { return open }
        let session = WorkoutSession(
            routineId: routine?.id,
            routineName: routine?.name ?? SessionCopy.emptySessionName,
            startedAt: now,
            restDefaultSeconds: restSeconds
        )
        context.insert(session)
        for (index, item) in (routine?.exercises ?? []).enumerated() {
            let exercise = try makeExercise(
                exerciseId: item.exerciseId,
                name: library.name(for: item.exerciseId),
                order: index,
                targetSets: item.targetSets,
                targetReps: item.targetReps,
                sessionID: session.id
            )
            session.exercises.append(exercise)
        }
        try context.save()
        return session
    }

    /// Builds an exercise with its set rows pre-filled (pgym-flow-spec.md, "Pre-fill"):
    /// the same set number from last time; more sets than last time copy the set above;
    /// a first-ever exercise has the target reps and an empty weight.
    private func makeExercise(
        exerciseId: String,
        name: String,
        order: Int,
        targetSets: Int?,
        targetReps: Int?,
        sessionID: String
    ) throws -> SessionExercise {
        let last = try lastSets(exerciseId: exerciseId, excludingSession: sessionID)
        let count = max(1, targetSets ?? max(last.count, RoutineItem.defaultSets))
        let exercise = SessionExercise(
            exerciseId: exerciseId,
            name: name,
            order: order,
            targetSets: count,
            targetReps: targetReps
        )
        context.insert(exercise)
        var above: (weight: Double?, reps: Int?)? = nil
        for n in 1...count {
            let previous = n <= last.count ? last[n - 1] : nil
            let weight: Double?
            let reps: Int?
            if let previous {
                weight = previous.weightKg
                reps = previous.reps
            } else if let above {
                weight = above.weight
                reps = above.reps
            } else {
                weight = nil
                reps = targetReps ?? RoutineItem.defaultReps
            }
            let set = SessionSet(
                n: n,
                weightKg: weight,
                reps: reps,
                type: previous?.type ?? .working,
                lastWeightKg: previous?.weightKg,
                lastReps: previous?.reps
            )
            context.insert(set)
            exercise.sets.append(set)
            above = (weight, reps)
        }
        return exercise
    }

    // MARK: Exercises

    /// D3: adds an exercise after the current one and makes it current.
    @discardableResult
    func addExercise(_ picked: Exercise, to session: WorkoutSession, now: Date = .now) throws -> SessionExercise {
        let ordered = session.orderedExercises
        let currentIndex = current(in: session).flatMap { cur in ordered.firstIndex { $0.id == cur.id } }
        let insertAt = currentIndex.map { $0 + 1 } ?? ordered.count
        for (index, exercise) in ordered.enumerated() where index >= insertAt {
            exercise.order = index + 1
        }
        let exercise = try makeExercise(
            exerciseId: picked.id,
            name: picked.name,
            order: insertAt,
            targetSets: nil,
            targetReps: nil,
            sessionID: session.id
        )
        session.exercises.append(exercise)
        session.currentExerciseID = exercise.id
        session.touch(now)
        try context.save()
        return exercise
    }

    /// The exercise open on D2: the one the user picked, else the first with an undone set, else the last.
    func current(in session: WorkoutSession) -> SessionExercise? {
        let ordered = session.orderedExercises
        if let id = session.currentExerciseID, let picked = ordered.first(where: { $0.id == id }) {
            return picked
        }
        return ordered.first(where: { !$0.isComplete }) ?? ordered.last
    }

    func makeCurrent(_ exercise: SessionExercise, in session: WorkoutSession) throws {
        session.currentExerciseID = exercise.id
        try context.save()
    }

    /// Up next and Done reorder: moves an exercise to a new position.
    func move(_ exercise: SessionExercise, to position: Int, in session: WorkoutSession, now: Date = .now) throws {
        var ordered = session.orderedExercises
        guard let from = ordered.firstIndex(where: { $0.id == exercise.id }) else { return }
        let item = ordered.remove(at: from)
        ordered.insert(item, at: max(0, min(position, ordered.count)))
        for (index, row) in ordered.enumerated() { row.order = index }
        session.touch(now)
        try context.save()
    }

    func removeExercise(_ exercise: SessionExercise, from session: WorkoutSession, now: Date = .now) throws {
        if session.currentExerciseID == exercise.id { session.currentExerciseID = nil }
        context.delete(exercise)
        for (index, row) in session.orderedExercises.filter({ $0.id != exercise.id }).enumerated() {
            row.order = index
        }
        session.touch(now)
        try context.save()
    }

    // MARK: Sets

    /// "+ Add set": a copy of the set above.
    @discardableResult
    func addSet(to exercise: SessionExercise, now: Date = .now) throws -> SessionSet {
        let ordered = exercise.orderedSets
        let above = ordered.last
        let n = (above?.n ?? 0) + 1
        let last = try lastSets(exerciseId: exercise.exerciseId, excludingSession: exercise.session?.id)
        let previous = n <= last.count ? last[n - 1] : nil
        let set = SessionSet(
            n: n,
            weightKg: above?.weightKg ?? previous?.weightKg,
            reps: above?.reps ?? previous?.reps ?? exercise.targetReps ?? RoutineItem.defaultReps,
            type: .working,
            lastWeightKg: previous?.weightKg,
            lastReps: previous?.reps
        )
        context.insert(set)
        exercise.sets.append(set)
        exercise.session?.touch(now)
        try context.save()
        return set
    }

    /// Changes the weight and copies it down to every undone set below in the same exercise.
    /// Done sets never change (pgym-flow-spec.md, "Editing set N").
    func setWeight(_ kg: Double?, for set: SessionSet, now: Date = .now) throws {
        let value = kg.map { max(0, $0) }
        set.weightKg = value
        for below in setsBelow(set) where !below.done {
            below.weightKg = value
        }
        try reevaluateBest(set)
        set.exercise?.session?.touch(now)
        try context.save()
    }

    /// Changes the reps and copies them down to every undone set below.
    func setReps(_ reps: Int?, for set: SessionSet, now: Date = .now) throws {
        let value = reps.map { max(0, $0) }
        set.reps = value
        for below in setsBelow(set) where !below.done {
            below.reps = value
        }
        try reevaluateBest(set)
        set.exercise?.session?.touch(now)
        try context.save()
    }

    func setType(_ type: SetType, for set: SessionSet, now: Date = .now) throws {
        set.type = type
        try reevaluateBest(set)
        set.exercise?.session?.touch(now)
        try context.save()
    }

    func setDetail(rpe: Int?, note: String, for set: SessionSet, now: Date = .now) throws {
        set.rpe = rpe.map { min(10, max(1, $0)) }
        set.note = String(note.prefix(280))
        set.exercise?.session?.touch(now)
        try context.save()
    }

    func deleteSet(_ set: SessionSet, now: Date = .now) throws {
        let exercise = set.exercise
        let session = exercise?.session
        let remaining = exercise?.orderedSets.filter { $0.id != set.id } ?? []
        context.delete(set)
        for (index, row) in remaining.enumerated() { row.n = index + 1 }
        session?.touch(now)
        try context.save()
    }

    enum CompletionResult: Equatable {
        /// Logged. `isNewBest` drives the BEST tag and the success haptic.
        case logged(isNewBest: Bool, exerciseComplete: Bool)
        /// The weight is empty: open the keypad on the weight instead of logging.
        case needsWeight
    }

    /// The check: one tap logs the set, flags a new best, and starts the rest timer.
    @discardableResult
    func complete(_ set: SessionSet, restSeconds: Int? = nil, now: Date = .now) throws -> CompletionResult {
        guard set.weightKg != nil else { return .needsWeight }
        if set.reps == nil { set.reps = set.exercise?.targetReps ?? RoutineItem.defaultReps }
        set.done = true
        set.doneAt = now
        let best = try bestToBeat(for: set)
        set.isNewBest = SessionMath.isNewBest(weightKg: set.weightKg, reps: set.reps, type: set.type, against: best)
        let exerciseComplete = set.exercise?.isComplete ?? false
        if let session = set.exercise?.session {
            startRest(session, seconds: restSeconds ?? session.restDefaultSeconds, now: now)
            if exerciseComplete, let exercise = set.exercise, session.currentExerciseID == exercise.id {
                // The finished exercise collapses and the next one opens.
                session.currentExerciseID = nil
            }
            session.touch(now)
        }
        try context.save()
        return .logged(isNewBest: set.isNewBest, exerciseComplete: exerciseComplete)
    }

    /// Unchecks a set. The rest timer is left alone.
    func uncomplete(_ set: SessionSet, now: Date = .now) throws {
        set.done = false
        set.doneAt = nil
        set.isNewBest = false
        set.exercise?.session?.touch(now)
        try context.save()
    }

    private func setsBelow(_ set: SessionSet) -> [SessionSet] {
        (set.exercise?.orderedSets ?? []).filter { $0.n > set.n }
    }

    private func reevaluateBest(_ set: SessionSet) throws {
        guard set.done else { return }
        set.isNewBest = SessionMath.isNewBest(weightKg: set.weightKg, reps: set.reps, type: set.type, against: try bestToBeat(for: set))
    }

    // MARK: Rest timer

    /// Stored as an end instant, so it keeps time through a lock, the background or a kill.
    func startRest(_ session: WorkoutSession, seconds: Int, now: Date = .now) {
        let length = max(5, seconds)
        session.restTotalSeconds = length
        session.restEndsAt = now.addingTimeInterval(TimeInterval(length))
    }

    /// Minus or plus 15 s. Ending at or before now clears the timer.
    func adjustRest(_ session: WorkoutSession, by seconds: Int, now: Date = .now) throws {
        guard let end = session.restEndsAt else { return }
        let next = end.addingTimeInterval(TimeInterval(seconds))
        if next <= now {
            session.restEndsAt = nil
        } else {
            session.restEndsAt = next
            session.restTotalSeconds = max(session.restTotalSeconds + seconds, Int(next.timeIntervalSince(now).rounded(.up)))
        }
        try context.save()
    }

    func skipRest(_ session: WorkoutSession) throws {
        session.restEndsAt = nil
        try context.save()
    }

    /// The D2 menu's rest length, used from the next check on.
    func setRestDefault(_ seconds: Int, for session: WorkoutSession) throws {
        session.restDefaultSeconds = min(600, max(15, seconds))
        try context.save()
    }

    /// Clears a rest timer that ran out while the app was closed (on relaunch).
    func clearExpiredRest(_ session: WorkoutSession, now: Date = .now) throws {
        if let end = session.restEndsAt, end <= now {
            session.restEndsAt = nil
            try context.save()
        }
    }

    // MARK: Ending

    /// Finish and take proof (`withProof`, stays a draft until the server stamps it), or Save without
    /// proof (`finished`, never a proof). Folds this session's sets into the stored bests once.
    func finish(_ session: WorkoutSession, withProof: Bool, now: Date = .now) throws {
        guard session.endedAt == nil, session.status == .draft else { return }
        session.endedAt = now
        session.restEndsAt = nil
        session.status = withProof ? .draft : .finished
        try foldIntoStats(session, now: now)
        session.touch(now)
        try context.save()
    }

    /// Discard on D5. The session becomes a tombstone, hidden everywhere; the sync queue removes it
    /// from Firestore if it ever got there, then from the phone (`purgeDiscarded`). Kept as an object
    /// until then so a screen still holding it never reads a deleted model.
    func discard(_ session: WorkoutSession, now: Date = .now) throws {
        session.status = .discarded
        session.endedAt = session.endedAt ?? now
        session.restEndsAt = nil
        session.touch(now)
        try context.save()
    }

    /// Removes discarded sessions that Firestore never had. Run when no screen shows a session.
    func purgeDiscarded() throws {
        let discarded = SessionStatus.discarded.rawValue
        let tombstones = try context.fetch(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.statusRaw == discarded && $0.lastSyncedAt == nil }
        ))
        for session in tombstones { context.delete(session) }
        if !tombstones.isEmpty { try context.save() }
    }

    /// Raises each exercise's stored best with this session's logged working sets.
    private func foldIntoStats(_ session: WorkoutSession, now: Date) throws {
        var perExercise: [String: StoredBest] = [:]
        var bestSet: [String: (Double, Int, Double)] = [:]
        for exercise in session.exercises {
            for set in exercise.sets where set.isWorkingDone {
                let current = perExercise[exercise.exerciseId] ?? .none
                perExercise[exercise.exerciseId] = SessionMath.raising(current, weightKg: set.weightKg, reps: set.reps, type: set.type)
                if let w = set.weightKg, let r = set.reps {
                    let e = SessionMath.e1rm(weightKg: w, reps: r)
                    if e > (bestSet[exercise.exerciseId]?.2 ?? 0) { bestSet[exercise.exerciseId] = (w, r, e) }
                }
            }
        }
        for (exerciseId, best) in perExercise {
            let stat: ExerciseStat
            if let existing = try self.stat(exerciseId: exerciseId) {
                stat = existing
            } else {
                stat = ExerciseStat(exerciseId: exerciseId)
                context.insert(stat)
            }
            if let top = bestSet[exerciseId], top.2 > stat.bestE1rmKg {
                stat.bestSetWeightKg = top.0
                stat.bestSetReps = top.1
            }
            stat.bestWeightKg = max(stat.bestWeightKg, best.weightKg)
            stat.bestE1rmKg = max(stat.bestE1rmKg, best.e1rmKg)
            stat.lastPerformedAt = max(stat.lastPerformedAt ?? .distantPast, session.startedAt)
            stat.sessionCount += 1
        }
    }
}
