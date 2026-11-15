import Foundation

#if canImport(FirebaseFirestore)
import FirebaseFirestore

/// The score arrives a few seconds after the stamp (pgym-architecture.md, "Flow: finishing a
/// session", step 7): a snapshot listener on the session document, reading only `physique`.
@MainActor
final class FirestorePhysiqueSource: PhysiqueSource {
    private func sessions(_ uid: String) -> CollectionReference {
        Firestore.firestore().collection("users").document(uid).collection("sessions")
    }

    func observe(uid: String, sessionID: String, onChange: @escaping @MainActor (PhysiqueRecord?) -> Void) -> PhysiqueObservation {
        let registration = sessions(uid).document(sessionID).addSnapshotListener { snapshot, _ in
            let record = Self.record(snapshot?.data()?["physique"])
            Task { @MainActor in onChange(record) }
        }
        return PhysiqueObservation { registration.remove() }
    }

    func previousScore(uid: String, before stampedAt: Date, excluding sessionID: String) async -> Int? {
        let query = sessions(uid)
            .whereField("stampedAt", isLessThan: Timestamp(date: stampedAt))
            .order(by: "stampedAt", descending: true)
            .limit(to: 10)
        guard let snapshot = try? await query.getDocuments() else { return nil }
        for document in snapshot.documents where document.documentID != sessionID {
            if let record = Self.record(document.data()["physique"]), record.isScored {
                return record.score
            }
        }
        return nil
    }

    nonisolated static func record(_ value: Any?) -> PhysiqueRecord? {
        guard var map = value as? [String: Any] else { return nil }
        if let at = map["analyzedAt"] as? Timestamp { map["analyzedAt"] = at.dateValue() }
        return PhysiqueRecord(firestore: map)
    }
}

/// `users/{uid}.physiqueConsent` and `physiqueConsentAt`. The security rules allow both from the
/// owner (`backend/firestore.rules`, `validUser`); the server reads the flag before every analysis.
@MainActor
final class FirestorePhysiqueConsentWriter: PhysiqueConsentWriting {
    func setPhysiqueConsent(_ on: Bool, uid: String) async throws {
        try await Firestore.firestore().collection("users").document(uid).setData(
            ["physiqueConsent": on, "physiqueConsentAt": FieldValue.serverTimestamp()],
            merge: true
        )
    }
}
#endif
