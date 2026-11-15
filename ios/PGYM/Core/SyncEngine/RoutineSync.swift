import Foundation
import SwiftData

/// The Firestore shape of `users/{uid}/routines/{routineId}` (pgym-architecture.md, "Data model"):
/// name, order, exercises: [{exerciseId, targetSets, targetReps}].
///
/// Two fields beyond the architecture table, both additive (see card I4's PR):
/// - `updatedAt`, so two phones can settle which edit is newer.
/// - `name` on an exercise entry, only for custom exercises, so a routine that uses one still reads
///   right on a phone that has not got the custom exercise yet.
struct RoutineDocument: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        var exerciseId: String
        var targetSets: Int
        var targetReps: Int
        var name: String?
    }

    var id: String
    var name: String
    var order: Int
    var exercises: [Entry]
    var updatedAt: Date

    init(id: String, name: String, order: Int, exercises: [Entry], updatedAt: Date) {
        self.id = id
        self.name = name
        self.order = order
        self.exercises = exercises
        self.updatedAt = updatedAt
    }

    init(routine: Routine, library: ExerciseLibrary) {
        self.init(
            id: routine.id,
            name: routine.name,
            order: routine.order,
            exercises: routine.exercises.map { item in
                let custom = library.exercise(id: item.exerciseId).flatMap { $0.isCustom ? $0.name : nil }
                return Entry(exerciseId: item.exerciseId, targetSets: item.targetSets, targetReps: item.targetReps, name: custom)
            },
            updatedAt: routine.updatedAt
        )
    }

    /// Dictionary for `setData`. Dates stay `Date`; the Firestore SDK stores them as timestamps.
    var firestoreData: [String: Any] {
        [
            "name": name,
            "order": order,
            "updatedAt": updatedAt,
            "exercises": exercises.map { entry -> [String: Any] in
                var map: [String: Any] = [
                    "exerciseId": entry.exerciseId,
                    "targetSets": entry.targetSets,
                    "targetReps": entry.targetReps,
                ]
                if let name = entry.name { map["name"] = name }
                return map
            },
        ]
    }

    /// Reads a document. `date` converts the SDK's timestamp type, so this file needs no Firebase import.
    /// A malformed document returns nil and is skipped, never crashes the sync.
    init?(id: String, data: [String: Any], date: (Any?) -> Date?) {
        guard let name = data["name"] as? String else { return nil }
        let order = (data["order"] as? Int) ?? (data["order"] as? NSNumber)?.intValue ?? 0
        let raw = data["exercises"] as? [[String: Any]] ?? []
        let entries: [Entry] = raw.compactMap { map in
            guard let exerciseId = map["exerciseId"] as? String else { return nil }
            let sets = (map["targetSets"] as? Int) ?? (map["targetSets"] as? NSNumber)?.intValue ?? RoutineItem.defaultSets
            let reps = (map["targetReps"] as? Int) ?? (map["targetReps"] as? NSNumber)?.intValue ?? RoutineItem.defaultReps
            return Entry(exerciseId: exerciseId, targetSets: sets, targetReps: reps, name: map["name"] as? String)
        }
        self.init(id: id, name: name, order: order, exercises: entries, updatedAt: date(data["updatedAt"]) ?? .distantPast)
    }

    var items: [RoutineItem] {
        exercises.map { RoutineItem(exerciseId: $0.exerciseId, targetSets: $0.targetSets, targetReps: $0.targetReps) }
    }
}

/// Where routines go. Firestore in the app, a fake in tests.
protocol RoutineRemote: AnyObject {
    func upsert(_ document: RoutineDocument, uid: String) async throws
    func delete(routineID: String, uid: String) async throws
    func fetchAll(uid: String) async throws -> [RoutineDocument]
}

/// Pushes local routine changes to Firestore and pulls changes made on another phone.
///
/// Offline-first: every edit is saved on the phone first with `needsSync`; this runs when there is a
/// signed-in user and simply tries again next time if the network is down. Conflicts: the newer
/// `updatedAt` wins, per routine.
@MainActor
final class RoutineSyncEngine {
    struct Report: Equatable {
        var pushed = 0
        var deleted = 0
        var pulled = 0
        var removedLocally = 0
    }

    let remote: RoutineRemote

    init(remote: RoutineRemote) {
        self.remote = remote
    }

    func sync(context: ModelContext, uid: String, library: ExerciseLibrary, now: Date = .now) async throws -> Report {
        var report = try await push(context: context, uid: uid, library: library, now: now)
        let pulled = try await pull(context: context, uid: uid, now: now)
        report.pulled = pulled.pulled
        report.removedLocally = pulled.removedLocally
        return report
    }

    /// Writes every routine with `needsSync`, and deletes tombstones remotely then locally.
    func push(context: ModelContext, uid: String, library: ExerciseLibrary, now: Date = .now) async throws -> Report {
        var report = Report()
        let pending = try context.fetch(FetchDescriptor<Routine>(predicate: #Predicate<Routine> { $0.needsSync == true }))
        for routine in pending {
            if routine.isTombstone {
                try await remote.delete(routineID: routine.id, uid: uid)
                context.delete(routine)
                report.deleted += 1
            } else {
                let editedAt = routine.updatedAt
                try await remote.upsert(RoutineDocument(routine: routine, library: library), uid: uid)
                // An edit made while the write was in flight keeps its flag for the next round.
                if routine.updatedAt == editedAt {
                    routine.needsSync = false
                }
                routine.lastSyncedAt = now
                report.pushed += 1
            }
            try context.save()
        }
        return report
    }

    /// Applies remote routines that are newer than the phone's copy, and removes routines that were
    /// synced before but are gone from Firestore (deleted on another phone).
    func pull(context: ModelContext, uid: String, now: Date = .now) async throws -> Report {
        var report = Report()
        let documents = try await remote.fetchAll(uid: uid)
        let locals = try context.fetch(FetchDescriptor<Routine>())
        var byID: [String: Routine] = [:]
        for routine in locals { byID[routine.id] = routine }

        for document in documents {
            if let local = byID[document.id] {
                // A local edit not yet pushed and at least as new as the remote copy wins.
                if local.needsSync && local.updatedAt >= document.updatedAt { continue }
                if local.name != document.name || local.order != document.order
                    || local.exercises.map(Self.key) != document.items.map(Self.key)
                    || local.isTombstone {
                    local.name = document.name
                    local.order = document.order
                    local.exercises = document.items
                    local.deletedAt = nil
                    local.updatedAt = document.updatedAt
                    report.pulled += 1
                }
                local.needsSync = false
                local.lastSyncedAt = now
            } else {
                let routine = Routine(
                    id: document.id,
                    name: document.name,
                    order: document.order,
                    exercises: document.items,
                    now: document.updatedAt
                )
                routine.needsSync = false
                routine.lastSyncedAt = now
                context.insert(routine)
                report.pulled += 1
            }
        }

        let remoteIDs = Set(documents.map(\.id))
        for local in locals where !remoteIDs.contains(local.id) && local.lastSyncedAt != nil && !local.needsSync {
            context.delete(local)
            report.removedLocally += 1
        }
        try context.save()
        return report
    }

    /// Compares items without the local row IDs.
    private static func key(_ item: RoutineItem) -> String {
        "\(item.exerciseId)|\(item.targetSets)|\(item.targetReps)"
    }
}

/// Runs a sync when something changed or the app came to the front, one at a time.
/// Does nothing until a user is signed in (card I2) and Firebase is configured.
@MainActor
final class RoutineSyncCoordinator {
    static let shared = RoutineSyncCoordinator()

    private var container: ModelContainer?
    private var engine: RoutineSyncEngine?
    private var uidProvider: () -> String? = { nil }
    private var running = false
    private var again = false

    func configure(container: ModelContainer, remote: RoutineRemote?, uid: @escaping () -> String?) {
        self.container = container
        self.engine = remote.map(RoutineSyncEngine.init(remote:))
        self.uidProvider = uid
    }

    func requestSync() {
        guard let container, let engine, let uid = uidProvider() else { return }
        if running {
            again = true
            return
        }
        running = true
        Task { @MainActor in
            repeat {
                again = false
                let context = container.mainContext
                let custom = (try? CustomExerciseStore(context: context).all())?.map(\.exercise) ?? []
                // A failed sync leaves `needsSync` set; the next request retries. Nothing is shown to
                // the user: routines work fully offline.
                _ = try? await engine.sync(context: context, uid: uid, library: ExerciseLibrary(custom: custom))
            } while again
            running = false
        }
    }
}
