import Foundation
import SwiftData

#if canImport(FirebaseFirestore)
import FirebaseCore
import FirebaseFirestore

/// `users/{uid}/sessions/{sessionId}` in Firestore. The security rules let a user write only their own
/// drafts and finished sessions, never a stamped one and never a server field (backend/firestore.rules).
final class FirestoreSessionRemote: SessionRemote {
    private func user(_ uid: String) -> DocumentReference {
        Firestore.firestore().collection("users").document(uid)
    }

    func upsert(_ document: SessionDocument, uid: String) async throws {
        // Merge, so fields the server added (proofNumber, stampedAt, physique...) are never touched.
        try await user(uid).collection("sessions").document(document.id).setData(document.firestoreData, merge: true)
    }

    func delete(sessionID: String, uid: String) async throws {
        let client = await HTTPSClient.live(tokenProvider: FirebaseAuthService())
        let _: DeleteRemoteSessionResponse = try await client.send("DELETE", path: "/api/sessions/\(sessionID)")
    }

    func fetchExerciseStats(uid: String) async throws -> [RemoteExerciseStat] {
        let snapshot = try await user(uid).collection("exerciseStats").getDocuments()
        return snapshot.documents.map { doc in
            let data = doc.data()
            let bestSet = data["bestSet"] as? [String: Any]
            return RemoteExerciseStat(
                exerciseId: doc.documentID,
                bestWeight: Self.double(data["bestWeight"]) ?? 0,
                bestE1rm: Self.double(data["bestE1rm"]) ?? 0,
                bestSetWeight: Self.double(bestSet?["weight"]),
                bestSetReps: Self.double(bestSet?["reps"]).map { Int($0) },
                lastPerformedAt: (data["lastPerformedAt"] as? Timestamp)?.dateValue(),
                sessionCount: Self.double(data["sessionCount"]).map { Int($0) } ?? 0
            )
        }
    }

    private static func double(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        return nil
    }
}

private struct DeleteRemoteSessionResponse: Decodable { let sessionId: String; let deleted: Bool }
#endif

/// Wires session sync to Firestore when the app runs on the Firebase backend; with the fake auth
/// backend (fresh clone, CI, UI tests) sessions stay queued on the phone. Sync waits for a signed-in
/// user. Same rule as `RoutineSyncSetup`.
enum SessionSyncSetup {
    @MainActor
    static func makeQueue(
        container: ModelContainer,
        useFirestore: Bool,
        uid: @escaping @MainActor () -> String?,
        isOnline: @escaping @MainActor () -> Bool
    ) -> SessionSyncQueue {
        #if canImport(FirebaseFirestore)
        let engine = useFirestore && FirebaseApp.app() != nil ? SessionSyncEngine(remote: FirestoreSessionRemote()) : nil
        #else
        let engine: SessionSyncEngine? = nil
        #endif
        return SessionSyncQueue(container: container, engine: engine, uid: uid, isOnline: isOnline)
    }
}
