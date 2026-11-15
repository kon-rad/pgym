import Foundation
import Observation
import SwiftData

/// The Firestore shape of `users/{uid}/sessions/{sessionId}` that the phone writes
/// (pgym-architecture.md, "Data model"). Server-only fields (proofNumber, stampedAt, physique,
/// photoKey, cardKey, newBests) are never in it: the security rules reject them from the client.
///
/// One field beyond the architecture table, additive: `note` on a set, only when the user wrote one (D4).
struct SessionDocument: Equatable, Sendable {
    struct SetEntry: Equatable, Sendable {
        var n: Int
        var weight: Double?
        var reps: Int?
        var type: String
        var done: Bool
        var rpe: Int?
        var note: String?
    }

    struct ExerciseEntry: Equatable, Sendable {
        var exerciseId: String
        var name: String
        var sets: [SetEntry]
    }

    var id: String
    var routineId: String?
    var routineName: String
    var startedAt: Date
    var endedAt: Date?
    var durationSec: Int?
    var timezone: String
    var weekKey: String
    var exercises: [ExerciseEntry]
    var setCount: Int
    var totalVolume: Double
    var status: String

    @MainActor
    init(session: WorkoutSession) {
        id = session.id
        routineId = session.routineId
        routineName = session.routineName
        startedAt = session.startedAt
        endedAt = session.endedAt
        durationSec = session.endedAt.map { Int($0.timeIntervalSince(session.startedAt).rounded()) }
        timezone = session.timezone
        weekKey = session.weekKey
        exercises = session.orderedExercises.map { exercise in
            ExerciseEntry(
                exerciseId: exercise.exerciseId,
                name: exercise.name,
                sets: exercise.orderedSets.map { set in
                    SetEntry(
                        n: set.n,
                        weight: set.weightKg,
                        reps: set.reps,
                        type: set.type.rawValue,
                        done: set.done,
                        rpe: set.rpe,
                        note: set.note.isEmpty ? nil : set.note
                    )
                }
            )
        }
        let totals = session.totals
        setCount = totals.setCount
        totalVolume = totals.volumeKg
        // The phone writes only draft or finished; `stamped` is the server's.
        status = session.status == .finished ? SessionStatus.finished.rawValue : SessionStatus.draft.rawValue
    }

    /// Dictionary for `setData(merge: true)`. Dates stay `Date`; the SDK stores them as timestamps.
    var firestoreData: [String: Any] {
        var data: [String: Any] = [
            "routineName": routineName,
            "startedAt": startedAt,
            "timezone": timezone,
            "weekKey": weekKey,
            "setCount": setCount,
            "totalVolume": totalVolume,
            "status": status,
            "exercises": exercises.map { exercise -> [String: Any] in
                [
                    "exerciseId": exercise.exerciseId,
                    "name": exercise.name,
                    "sets": exercise.sets.map { set -> [String: Any] in
                        var map: [String: Any] = ["n": set.n, "type": set.type, "done": set.done]
                        if let weight = set.weight { map["weight"] = weight }
                        if let reps = set.reps { map["reps"] = reps }
                        if let rpe = set.rpe { map["rpe"] = rpe }
                        if let note = set.note { map["note"] = note }
                        return map
                    },
                ]
            },
        ]
        if let routineId { data["routineId"] = routineId }
        if let endedAt { data["endedAt"] = endedAt }
        if let durationSec { data["durationSec"] = durationSec }
        return data
    }
}

/// `users/{uid}/exerciseStats/{exerciseId}` as the server writes it.
struct RemoteExerciseStat: Equatable, Sendable {
    var exerciseId: String
    var bestWeight: Double
    var bestE1rm: Double
    var bestSetWeight: Double?
    var bestSetReps: Int?
    var lastPerformedAt: Date?
    var sessionCount: Int
}

/// Where sessions go. Firestore in the app, a fake in tests.
protocol SessionRemote: AnyObject {
    /// Writes the whole client part of the document under its own ID. Writing the same document again
    /// replaces it; it can never make a second session.
    func upsert(_ document: SessionDocument, uid: String) async throws
    /// Removes a session the user discarded after it had synced (callable `deleteSession`).
    func delete(sessionID: String, uid: String) async throws
    func fetchExerciseStats(uid: String) async throws -> [RemoteExerciseStat]
}

enum SyncError: Error, Equatable {
    case timedOut
    case offline
}

/// Writes queued session changes to Firestore. The queue is the sessions themselves: a session is
/// queued while `localVersion > syncedVersion`, which survives a kill because both live in SwiftData.
@MainActor
final class SessionSyncEngine {
    struct Report: Equatable {
        var written = 0
        var deleted = 0
        var purged = 0
    }

    let remote: SessionRemote
    /// A Firestore write that has not been acknowledged in this time counts as failed and is retried.
    let writeTimeout: TimeInterval

    init(remote: SessionRemote, writeTimeout: TimeInterval = 20) {
        self.remote = remote
        self.writeTimeout = writeTimeout
    }

    /// Sessions with changes Firestore has not got, oldest first.
    static func pending(in context: ModelContext) throws -> [WorkoutSession] {
        try context.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\WorkoutSession.startedAt)]))
            .filter(\.needsSync)
    }

    /// Writes every queued session once. Stops at the first failure and throws, leaving the rest queued.
    func flush(context: ModelContext, uid: String, now: Date = .now) async throws -> Report {
        var report = Report()
        for session in try Self.pending(in: context) {
            switch session.status {
            case .stamped:
                // The proof belongs to the server now; the phone never writes it again.
                session.syncedVersion = session.localVersion
            case .discarded:
                if session.lastSyncedAt != nil {
                    let id = session.id
                    try await withTimeout { try await self.remote.delete(sessionID: id, uid: uid) }
                    report.deleted += 1
                } else {
                    report.purged += 1
                }
                context.delete(session)
            case .draft, .finished:
                let version = session.localVersion
                let document = SessionDocument(session: session)
                do {
                    try await withTimeout { try await self.remote.upsert(document, uid: uid) }
                } catch {
                    session.syncFailures += 1
                    try? context.save()
                    throw error
                }
                // Only the version that was written is marked; an edit made during the write stays queued.
                session.syncedVersion = max(session.syncedVersion, version)
                session.lastSyncedAt = now
                session.syncFailures = 0
                report.written += 1
            }
            try context.save()
        }
        return report
    }

    /// Raises the phone's stored bests with the server's, so a reinstall or a second phone still knows
    /// what to beat. Never lowers a best.
    func pullStats(context: ModelContext, uid: String) async throws {
        let remoteStats = try await withTimeout { try await self.remote.fetchExerciseStats(uid: uid) }
        let store = SessionStore(context: context)
        for remote in remoteStats {
            let stat: ExerciseStat
            if let existing = try store.stat(exerciseId: remote.exerciseId) {
                stat = existing
            } else {
                stat = ExerciseStat(exerciseId: remote.exerciseId)
                context.insert(stat)
            }
            if remote.bestE1rm > stat.bestE1rmKg {
                stat.bestSetWeightKg = remote.bestSetWeight
                stat.bestSetReps = remote.bestSetReps
            }
            stat.bestWeightKg = max(stat.bestWeightKg, remote.bestWeight)
            stat.bestE1rmKg = max(stat.bestE1rmKg, remote.bestE1rm)
            stat.sessionCount = max(stat.sessionCount, remote.sessionCount)
            if let at = remote.lastPerformedAt {
                stat.lastPerformedAt = max(stat.lastPerformedAt ?? .distantPast, at)
            }
        }
        try context.save()
    }

    private func withTimeout<T: Sendable>(_ body: @escaping @MainActor () async throws -> T) async throws -> T {
        let limit = writeTimeout
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await body() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(limit * 1_000_000_000))
                throw SyncError.timedOut
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw SyncError.timedOut }
            return first
        }
    }
}

/// Runs the engine: one flush at a time, a short pause to batch rapid set changes, and retries with
/// back-off after a failure. Triggered by every session change, by the network coming back and by the
/// app coming to the front. Nothing here ever blocks the session screen.
@MainActor
@Observable
final class SessionSyncQueue {
    /// Sessions waiting to reach Firestore, for the small "will sync" line.
    private(set) var pendingCount = 0
    /// The last attempt failed; the next trigger or retry tries again.
    private(set) var lastAttemptFailed = false
    /// Completed flush attempts, failed or not. For tests.
    private(set) var attempts = 0

    private let container: ModelContainer
    @ObservationIgnored private var engine: SessionSyncEngine?
    @ObservationIgnored private var uid: () -> String?
    @ObservationIgnored private var isOnline: () -> Bool
    private let sleep: (TimeInterval) async -> Void
    let debounce: TimeInterval
    let retryDelays: [TimeInterval]
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var again = false
    @ObservationIgnored private var statsPulled = false

    init(
        container: ModelContainer,
        engine: SessionSyncEngine?,
        uid: @escaping () -> String?,
        isOnline: @escaping () -> Bool = { true },
        debounce: TimeInterval = 1.5,
        retryDelays: [TimeInterval] = [2, 5, 15, 30, 60],
        sleep: @escaping (TimeInterval) async -> Void = { seconds in
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        }
    ) {
        self.container = container
        self.engine = engine
        self.uid = uid
        self.isOnline = isOnline
        self.debounce = debounce
        self.retryDelays = retryDelays
        self.sleep = sleep
    }

    /// Swaps in Firebase once it is configured and a user is signed in.
    func configure(engine: SessionSyncEngine?, uid: @escaping () -> String?, isOnline: @escaping () -> Bool) {
        self.engine = engine
        self.uid = uid
        self.isOnline = isOnline
        requestSync()
    }

    /// Asks for a sync. Calls while one is running are folded into one more round.
    func requestSync() {
        refreshPending()
        if task != nil {
            again = true
            return
        }
        task = Task { @MainActor [weak self] in
            await self?.run()
            self?.task = nil
        }
    }

    /// Waits for the running sync, retries included. For tests and for sign-out.
    func waitUntilIdle() async {
        while let running = task {
            await running.value
        }
    }

    private func run() async {
        if debounce > 0 { await sleep(debounce) }
        var failures = 0
        repeat {
            again = false
            guard let engine, let uid = uid() else { break }
            guard isOnline() else {
                // Offline: wait for the network monitor to call again. Sets are safe on the phone.
                lastAttemptFailed = true
                break
            }
            let context = container.mainContext
            do {
                attempts += 1
                _ = try await engine.flush(context: context, uid: uid)
                lastAttemptFailed = false
                failures = 0
                if !statsPulled {
                    statsPulled = (try? await engine.pullStats(context: context, uid: uid)) != nil
                }
            } catch {
                lastAttemptFailed = true
                guard failures < retryDelays.count else { break }
                let delay = retryDelays[failures]
                failures += 1
                await sleep(delay)
                again = true
            }
            refreshPending()
        } while again
        refreshPending()
    }

    func refreshPending() {
        pendingCount = (try? SessionSyncEngine.pending(in: container.mainContext).count) ?? 0
    }
}
