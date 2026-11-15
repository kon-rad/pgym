import Foundation
import SwiftData

/// Where a session is in its life. Raw values are the Firestore `status` values
/// (pgym-architecture.md, "Data model"), plus one that never leaves the phone.
enum SessionStatus: String, Codable, Sendable {
    /// Being logged, or waiting for its proof photo.
    case draft
    /// Saved without a proof (D5). Shows in lift history, never as a proof.
    case finished
    /// The server stamped it. Written only by `stampSession`; the phone never sets it (card I7).
    case stamped
    /// Discarded on D5. Local only: removed from the phone once Firestore no longer has it.
    case discarded
}

/// Warm-up sets do not count toward total lifted (pgym-design.md, "Data points").
/// Raw values match `type` in the backend's `sessionStats.ts`.
enum SetType: String, Codable, CaseIterable, Sendable {
    case working
    case warmup

    var label: String {
        switch self {
        case .working: "Working"
        case .warmup: "Warm-up"
        }
    }
}

/// One gym session on the phone. Firestore: `users/{uid}/sessions/{sessionId}`.
///
/// Every change is saved at once (pgym-flow-spec.md, "When the app is killed mid-session"), so a
/// kill loses nothing. Time is stored as instants, never as running counts: elapsed time is
/// `now - startedAt`, and the rest timer is an end instant.
@Model
final class WorkoutSession {
    @Attribute(.unique) var id: String
    var routineId: String?
    var routineName: String
    var startedAt: Date
    /// Set when the user taps Finish and take proof, or Save without proof.
    var endedAt: Date?
    /// IANA zone at the start. The day and week of a session are where it started.
    var timezone: String
    var statusRaw: String
    @Relationship(deleteRule: .cascade, inverse: \SessionExercise.session)
    var exercises: [SessionExercise] = []
    /// The exercise open on D2. Nil means the first one with an undone set.
    var currentExerciseID: String?

    /// Rest timer: when it ends, and the length it was started with (for the bar).
    var restEndsAt: Date?
    var restTotalSeconds: Int
    /// The default rest for this session, from the D2 menu.
    var restDefaultSeconds: Int

    var updatedAt: Date
    /// Bumped on every local change. The sync queue writes a session while `localVersion` is ahead
    /// of `syncedVersion`, and records the version it wrote, so the same version is never written twice.
    var localVersion: Int
    var syncedVersion: Int
    /// The document exists in Firestore (it was written at least once).
    var lastSyncedAt: Date?
    /// The last sync attempt failed; for the "will sync" line and the retry back-off.
    var syncFailures: Int

    // MARK: Stamp (card I7). All optional, so stores from earlier builds open without a migration.

    /// The server's proof number. Nil until `stampSession` answers; the phone never makes one up.
    var proofNumber: Int? = nil
    /// The server's clock at the stamp. Replaces the phone time on the card.
    var stampedAt: Date? = nil
    /// `users/{uid}/sessions/{id}/photo.jpg` and `card.jpg` once stamped, for signed links later.
    var photoKey: String? = nil
    var cardKey: String? = nil
    /// The whole `stampSession` answer (week, streak, new bests), JSON, for D11 after a relaunch.
    var stampReceiptData: Data? = nil
    /// The physique score was on (on this phone's knowledge) when the stamp was asked for, so D11
    /// waits for a score. Nil or false: no score UI for this session.
    var physiqueRequested: Bool? = nil
    /// Upload or stamp attempts that failed, for the back-off.
    var stampFailures: Int? = nil

    static let defaultRestSeconds = 90

    init(
        id: String = UUID().uuidString,
        routineId: String?,
        routineName: String,
        startedAt: Date = .now,
        timezone: String = TimeZone.current.identifier,
        restDefaultSeconds: Int = WorkoutSession.defaultRestSeconds
    ) {
        self.id = id
        self.routineId = routineId
        self.routineName = routineName
        self.startedAt = startedAt
        self.endedAt = nil
        self.timezone = timezone
        self.statusRaw = SessionStatus.draft.rawValue
        self.currentExerciseID = nil
        self.restEndsAt = nil
        self.restTotalSeconds = restDefaultSeconds
        self.restDefaultSeconds = restDefaultSeconds
        self.updatedAt = startedAt
        self.localVersion = 1
        self.syncedVersion = 0
        self.lastSyncedAt = nil
        self.syncFailures = 0
    }

    var status: SessionStatus {
        get { SessionStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }

    /// The draft being logged right now: not ended, not discarded.
    var isActive: Bool { status == .draft && endedAt == nil }

    /// Ended with a proof card and waiting for the server's stamp (offline, or uploading).
    var awaitsStamp: Bool { status == .draft && endedAt != nil }

    /// The server's answer, once stamped.
    var stampReceipt: StampReceipt? {
        get { stampReceiptData.flatMap { try? JSONDecoder().decode(StampReceipt.self, from: $0) } }
        set { stampReceiptData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    /// Exercises in the order the user sees them.
    var orderedExercises: [SessionExercise] {
        exercises.sorted { $0.order < $1.order }
    }

    var needsSync: Bool { localVersion > syncedVersion }

    /// Marks a local change for the sync queue.
    func touch(_ now: Date = .now) {
        updatedAt = now
        localVersion += 1
    }

    /// All logged (done) sets, any type.
    var doneSetCount: Int {
        exercises.reduce(0) { $0 + $1.sets.filter(\.done).count }
    }

    func elapsed(at now: Date) -> TimeInterval {
        max(0, (endedAt ?? now).timeIntervalSince(startedAt))
    }
}

/// One exercise inside a session, with its sets. Firestore: an element of `sessions/{id}.exercises`.
@Model
final class SessionExercise {
    @Attribute(.unique) var id: String
    var exerciseId: String
    /// Copied at the start so a session reads right after the catalogue or a custom name changes.
    var name: String
    var order: Int
    var targetSets: Int
    var targetReps: Int?
    var session: WorkoutSession?
    @Relationship(deleteRule: .cascade, inverse: \SessionSet.exercise)
    var sets: [SessionSet] = []

    init(id: String = UUID().uuidString, exerciseId: String, name: String, order: Int, targetSets: Int, targetReps: Int?) {
        self.id = id
        self.exerciseId = exerciseId
        self.name = name
        self.order = order
        self.targetSets = targetSets
        self.targetReps = targetReps
    }

    var orderedSets: [SessionSet] {
        sets.sorted { $0.n < $1.n }
    }

    /// Every set checked, and at least one set exists.
    var isComplete: Bool { !sets.isEmpty && sets.allSatisfy(\.done) }
}

/// One set. Weight is in kilograms; nil means not entered yet (a first-ever exercise).
@Model
final class SessionSet {
    @Attribute(.unique) var id: String
    /// Set number, from 1.
    var n: Int
    var weightKg: Double?
    var reps: Int?
    var typeRaw: String
    var done: Bool
    var doneAt: Date?
    /// Effort, 1 to 10. Optional and hidden by default.
    var rpe: Int?
    var note: String
    /// What the same set did last session ("80 x 8"), for the LAST column. Copied at the start.
    var lastWeightKg: Double?
    var lastReps: Int?
    /// This set beat the stored best when it was logged. Shown as the NEW BEST tag. Local only:
    /// `newBests` on the session document is written by the server (backend/firestore.rules).
    var isNewBest: Bool
    var exercise: SessionExercise?

    init(
        id: String = UUID().uuidString,
        n: Int,
        weightKg: Double?,
        reps: Int?,
        type: SetType = .working,
        lastWeightKg: Double? = nil,
        lastReps: Int? = nil
    ) {
        self.id = id
        self.n = n
        self.weightKg = weightKg
        self.reps = reps
        self.typeRaw = type.rawValue
        self.done = false
        self.doneAt = nil
        self.rpe = nil
        self.note = ""
        self.lastWeightKg = lastWeightKg
        self.lastReps = lastReps
        self.isNewBest = false
    }

    var type: SetType {
        get { SetType(rawValue: typeRaw) ?? .working }
        set { typeRaw = newValue.rawValue }
    }

    /// Counts toward totals and bests: done and not a warm-up (same rule as the server).
    var isWorkingDone: Bool { done && type == .working }
}

/// The best this user has done on one exercise, from earlier sessions. Firestore:
/// `users/{uid}/exerciseStats/{exerciseId}` (written by the server at stamp time); the phone keeps
/// its own copy, updated when a session ends, so new bests work offline.
@Model
final class ExerciseStat {
    @Attribute(.unique) var exerciseId: String
    var bestWeightKg: Double
    var bestE1rmKg: Double
    var bestSetWeightKg: Double?
    var bestSetReps: Int?
    var lastPerformedAt: Date?
    var sessionCount: Int

    init(exerciseId: String) {
        self.exerciseId = exerciseId
        self.bestWeightKg = 0
        self.bestE1rmKg = 0
        self.bestSetWeightKg = nil
        self.bestSetReps = nil
        self.lastPerformedAt = nil
        self.sessionCount = 0
    }

    var best: StoredBest { StoredBest(weightKg: bestWeightKg, e1rmKg: bestE1rmKg) }
}
