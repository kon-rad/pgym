import Foundation
import SwiftData

#if canImport(FirebaseFirestore)
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseFunctions

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
        _ = try await Functions.functions().httpsCallable("deleteSession").call(["sessionId": sessionID])
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
#endif

/// Wires session sync to Firebase when Firebase is configured and a user is signed in; otherwise
/// sessions stay queued on the phone and sync once both are true.
enum SessionSyncSetup {
    @MainActor
    static func makeQueue(container: ModelContainer, isOnline: @escaping () -> Bool) -> SessionSyncQueue {
        #if canImport(FirebaseFirestore)
        let firebaseOn = FirebaseApp.app() != nil
        return SessionSyncQueue(
            container: container,
            engine: firebaseOn ? SessionSyncEngine(remote: FirestoreSessionRemote()) : nil,
            uid: { FirebaseApp.app() != nil ? Auth.auth().currentUser?.uid : nil },
            isOnline: isOnline
        )
        #else
        return SessionSyncQueue(container: container, engine: nil, uid: { nil }, isOnline: isOnline)
        #endif
    }
}
