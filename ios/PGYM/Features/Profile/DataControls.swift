import Foundation
import Observation
import SwiftData

/// The user's controls over their data (F6, E3, E5; card I8): the physique switch, deleting photos,
/// deleting one session and the phone's copy of the scores.
///
/// Turning analysis off (pgym-architecture.md: "Turning analysis off deletes stored scores"):
/// 1. the scores leave the phone at once, so no screen shows them again;
/// 2. `users/{uid}.physiqueConsent` goes false, so the server stops scoring new proofs;
/// 3. the HTTPS service has nothing to delete because insights are transient and never persisted.
@MainActor
@Observable
final class DataControls {
    private(set) var scoreErasePending: Bool

    let api: PrivacyAPI
    let consent: PhysiqueConsent
    let physique: PhysiqueSource
    let store: ProofStore
    let images: SignedImageCache?
    private let defaults: UserDefaults

    static let erasePendingKey = "pgym.privacy.scoreErasePending"

    init(
        api: PrivacyAPI,
        consent: PhysiqueConsent,
        physique: PhysiqueSource,
        store: ProofStore,
        images: SignedImageCache?,
        defaults: UserDefaults = .standard
    ) {
        self.api = api
        self.consent = consent
        self.physique = physique
        self.store = store
        self.images = images
        self.defaults = defaults
        scoreErasePending = defaults.bool(forKey: Self.erasePendingKey)
    }

    // MARK: Physique

    /// E5 and F6: off, and every stored score deleted. Returns false when the server step has to wait
    /// for a connection (the phone is already clear and the switch is already off).
    @discardableResult
    func turnOffAnalysis(context: ModelContext) async -> Bool {
        Self.clearScores(in: context)
        await consent.turnOff()
        setErasePending(true)
        do {
            try await api.deletePhysiqueScores()
            setErasePending(false)
            return true
        } catch {
            return false
        }
    }

    /// Sends a server delete that could not be sent before. Quiet on failure.
    func retryPending() async {
        guard scoreErasePending else { return }
        if (try? await api.deletePhysiqueScores()) != nil {
            setErasePending(false)
        }
    }

    /// Removes every score, tip and refusal from the phone. Returns how many sessions had one.
    @discardableResult
    static func clearScores(in context: ModelContext) -> Int {
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        var cleared = 0
        for session in sessions where session.hasPhysique {
            session.applyPhysique(nil)
            cleared += 1
        }
        try? context.save()
        return cleared
    }

    /// Copies every stamped session's score from the server to the phone. Only while the switch is on
    /// and no delete is waiting, so a score that is being deleted never comes back.
    func refreshScores(uid: String, context: ModelContext) async throws {
        guard consent.isOn, !scoreErasePending else { return }
        let records = try await physique.allRecords(uid: uid)
        // The switch may have gone off while the request was out.
        guard consent.isOn, !scoreErasePending else { return }
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        for session in sessions where session.status == .stamped {
            let record = records[session.id]
            if record != session.physique { session.applyPhysique(record) }
        }
        try? context.save()
    }

    // MARK: Photos and sessions

    /// F6 Delete all photos. Proof media is local-only, so the phone drops its copies of stamped
    /// cards. Sets, sessions and proof numbers stay. A card still waiting for its stamp keeps its files.
    @discardableResult
    func deleteAllPhotos(context: ModelContext) async throws -> Int {
        try await api.deleteAllPhotos()
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        var removed = 0
        for session in sessions where session.status == .stamped {
            if session.cardKey != nil || session.photoKey != nil || store.hasCard(session.id) || store.hasPhoto(session.id) {
                removed += 1
            }
            store.remove(session.id)
            session.photoKey = nil
            session.cardKey = nil
        }
        images?.removeAll()
        try? context.save()
        return removed
    }

    /// E3 Delete. A session Firestore has goes through `deleteSession` (which also deletes its photo
    /// and card and recomputes the week); one that never left the phone is deleted here only.
    func deleteSession(_ session: WorkoutSession, context: ModelContext) async throws {
        if session.lastSyncedAt != nil || session.status == .stamped {
            try await api.deleteSession(sessionID: session.id)
        }
        store.remove(session.id)
        context.delete(session)
        try context.save()
    }

    /// Photos and cards F6 would delete: every stamped proof with a card.
    static func photoCount(_ sessions: [SessionSnapshot]) -> Int {
        sessions.filter { $0.status == .stamped && $0.cardKey != nil }.count
    }

    private func setErasePending(_ pending: Bool) {
        scoreErasePending = pending
        defaults.set(pending, forKey: Self.erasePendingKey)
    }
}

/// F6 Export my data: one JSON file with the profile, routines, sessions and sets
/// (pgym-app-copy.md, F6). Built from the phone's store; weights in kilograms, as stored.
struct DataExport: Encodable {
    struct Profile: Encodable {
        var displayName: String?
        var email: String?
        var birthYear: Int?
        var units: String?
        var goalPerWeek: Int?
        var gymDays: [String]?
        var reminderTime: String?
        var createdAt: Date?
        var streakWeeks: Int?
        var longestStreak: Int?
        var proofCount: Int?
        var physiqueConsent: Bool
    }

    struct RoutineExercise: Encodable {
        var exerciseId: String
        var targetSets: Int
        var targetReps: Int
    }

    struct RoutineEntry: Encodable {
        var id: String
        var name: String
        var order: Int
        var exercises: [RoutineExercise]
    }

    struct SetEntry: Encodable {
        var n: Int
        var weightKg: Double?
        var reps: Int?
        var type: String
        var done: Bool
        var rpe: Int?
        var note: String?
    }

    struct ExerciseEntry: Encodable {
        var exerciseId: String
        var name: String
        var sets: [SetEntry]
    }

    struct Physique: Encodable {
        var score: Int?
        var tip: String?
        var refusedReason: String?
    }

    struct SessionEntry: Encodable {
        var id: String
        var routineId: String?
        var routineName: String
        var startedAt: Date
        var endedAt: Date?
        var timezone: String
        var weekKey: String
        var status: String
        var proofNumber: Int?
        var stampedAt: Date?
        var setCount: Int
        var totalVolumeKg: Double
        var exercises: [ExerciseEntry]
        var physique: Physique?
    }

    var format = "pgym-export"
    var version = 1
    var exportedAt: Date
    var weightUnitStored = "kg"
    var profile: Profile?
    var routines: [RoutineEntry]
    var sessions: [SessionEntry]

    @MainActor
    static func make(profile: UserProfile?, physiqueConsent: Bool, routines: [Routine], sessions: [WorkoutSession], now: Date = .now) -> DataExport {
        DataExport(
            exportedAt: now,
            profile: profile.map {
                Profile(
                    displayName: $0.displayName,
                    email: $0.email,
                    birthYear: $0.birthYear,
                    units: $0.units?.rawValue,
                    goalPerWeek: $0.goalPerWeek,
                    gymDays: $0.gymDays?.map(\.rawValue),
                    reminderTime: $0.reminderTime?.storageValue,
                    createdAt: $0.createdAt,
                    streakWeeks: $0.streakWeeks,
                    longestStreak: $0.longestStreak,
                    proofCount: $0.proofCount,
                    physiqueConsent: physiqueConsent
                )
            },
            routines: routines.filter { !$0.isTombstone }.sorted { $0.order < $1.order }.map { routine in
                RoutineEntry(
                    id: routine.id,
                    name: routine.name,
                    order: routine.order,
                    exercises: routine.exercises.map { RoutineExercise(exerciseId: $0.exerciseId, targetSets: $0.targetSets, targetReps: $0.targetReps) }
                )
            },
            sessions: sessions
                .filter { $0.status != .discarded }
                .sorted { $0.startedAt < $1.startedAt }
                .map { session in
                    let totals = session.totals
                    return SessionEntry(
                        id: session.id,
                        routineId: session.routineId,
                        routineName: session.routineName,
                        startedAt: session.startedAt,
                        endedAt: session.endedAt,
                        timezone: session.timezone,
                        weekKey: session.weekKey,
                        status: session.status.rawValue,
                        proofNumber: session.proofNumber,
                        stampedAt: session.stampedAt,
                        setCount: totals.setCount,
                        totalVolumeKg: totals.volumeKg,
                        exercises: session.orderedExercises.map { exercise in
                            ExerciseEntry(
                                exerciseId: exercise.exerciseId,
                                name: exercise.name,
                                sets: exercise.orderedSets.map {
                                    SetEntry(n: $0.n, weightKg: $0.weightKg, reps: $0.reps, type: $0.type.rawValue, done: $0.done, rpe: $0.rpe, note: $0.note.isEmpty ? nil : $0.note)
                                }
                            )
                        },
                        physique: session.hasPhysique
                            ? Physique(score: session.physiqueScore, tip: session.physiqueTip, refusedReason: session.physiqueRefusedReason)
                            : nil
                    )
                }
        )
    }

    func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// "pgym-export-2026-11-15.json".
    static func fileName(now: Date = .now, timeZone: TimeZone = .current) -> String {
        let day = PlanCalendar(timeZone: timeZone).dayKey(for: now)
        return "pgym-export-\(day).json"
    }

    /// Writes the file into a folder of its own in the temporary directory, ready for the share sheet.
    func write(to directory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("Export", isDirectory: true)) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(Self.fileName(now: exportedAt))
        try json().write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
}
