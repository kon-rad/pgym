import Foundation
import SwiftData

#if canImport(FirebaseFirestore)
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore

/// `users/{uid}/routines/{routineId}` in Firestore. The security rules let a user read and write only
/// their own routines (backend/firestore.rules).
final class FirestoreRoutineRemote: RoutineRemote {
    private func collection(_ uid: String) -> CollectionReference {
        Firestore.firestore().collection("users").document(uid).collection("routines")
    }

    func upsert(_ document: RoutineDocument, uid: String) async throws {
        try await collection(uid).document(document.id).setData(document.firestoreData)
    }

    func delete(routineID: String, uid: String) async throws {
        try await collection(uid).document(routineID).delete()
    }

    func fetchAll(uid: String) async throws -> [RoutineDocument] {
        let snapshot = try await collection(uid).getDocuments()
        return snapshot.documents.compactMap { doc in
            RoutineDocument(id: doc.documentID, data: doc.data()) { value in
                (value as? Timestamp)?.dateValue() ?? (value as? Date)
            }
        }
    }
}
#endif

/// Wires routine sync to Firebase when Firebase is configured and a user is signed in; otherwise
/// routines stay on the phone and sync starts by itself once both are true.
enum RoutineSyncSetup {
    @MainActor
    static func configure(container: ModelContainer) {
        #if canImport(FirebaseFirestore)
        let firebaseOn = FirebaseApp.app() != nil
        RoutineSyncCoordinator.shared.configure(
            container: container,
            remote: firebaseOn ? FirestoreRoutineRemote() : nil,
            uid: { FirebaseApp.app() != nil ? Auth.auth().currentUser?.uid : nil }
        )
        #else
        RoutineSyncCoordinator.shared.configure(container: container, remote: nil, uid: { nil })
        #endif
    }
}
