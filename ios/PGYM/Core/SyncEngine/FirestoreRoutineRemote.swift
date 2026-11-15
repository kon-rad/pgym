import Foundation
import SwiftData

#if canImport(FirebaseFirestore)
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

/// Wires routine sync to Firestore when the app runs on the Firebase backend; with the fake auth
/// backend (fresh clone, CI, UI tests) routines stay on the phone. Sync waits for a signed-in user.
enum RoutineSyncSetup {
    @MainActor
    static func configure(container: ModelContainer, useFirestore: Bool, uid: @escaping @MainActor () -> String?) {
        #if canImport(FirebaseFirestore)
        let remote: RoutineRemote? = useFirestore && FirebaseApp.app() != nil ? FirestoreRoutineRemote() : nil
        #else
        let remote: RoutineRemote? = nil
        #endif
        RoutineSyncCoordinator.shared.configure(container: container, remote: remote, uid: uid)
    }
}
