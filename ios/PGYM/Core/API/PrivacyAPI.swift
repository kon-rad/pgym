import Foundation

/// The callable functions behind F6 Privacy and data and E3's Delete (card I8).
///
/// `deleteSession` is in `backend/src/index.ts`. `deletePhysiqueScores` and `deleteAllPhotos` are not
/// in the backend yet: the architecture's rule "Turning analysis off deletes stored scores" and F6's
/// "Delete all photos" need a server step, because the security rules block the phone from writing
/// `physique`, `photoKey` and `cardKey` and the phone holds no S3 key. Their contract, for the backend
/// card that adds them:
///
/// | Callable | Input | Does | Returns |
/// |---|---|---|---|
/// | `deletePhysiqueScores` | none | Deletes `physique` from every session of the caller | `{deleted: number}` |
/// | `deleteAllPhotos` | none | Deletes every S3 object under `users/{uid}/`, clears `photoKey` and `cardKey`; sessions, sets and proof numbers stay | `{deletedObjects: number}` |
@MainActor
protocol PrivacyAPI: AnyObject {
    func deletePhysiqueScores() async throws
    func deleteAllPhotos() async throws
    /// Deletes the session document and its two objects; the server recomputes counts and bests.
    func deleteSession(sessionID: String) async throws
}

@MainActor
final class HTTPSPrivacyAPI: PrivacyAPI {
    private let client: HTTPSClient

    init(client: HTTPSClient) { self.client = client }

    func deletePhysiqueScores() async throws {
        let _: DeletedScores = try await client.send("DELETE", path: "/api/physique-scores")
    }

    func deleteAllPhotos() async throws {
        // Proof photos and cards are local-only; DataControls removes those files next.
    }

    func deleteSession(sessionID: String) async throws {
        do {
            let _: DeleteSessionResponse = try await client.send("DELETE", path: "/api/sessions/\(sessionID)")
        } catch { throw HTTPSProofAPI.proofError(error) }
    }
}

private struct DeleteSessionResponse: Decodable { let sessionId: String; let deleted: Bool }
private struct DeletedScores: Decodable { let deleted: Int }

/// In memory: records every call. Tests set `failure` to make the next calls throw.
@MainActor
final class FakePrivacyAPI: PrivacyAPI {
    private(set) var deleteScoresCalls = 0
    private(set) var deletePhotosCalls = 0
    private(set) var deletedSessions: [String] = []
    var failure: Error?

    init() {}

    func deletePhysiqueScores() async throws {
        if let failure { throw failure }
        deleteScoresCalls += 1
    }

    func deleteAllPhotos() async throws {
        if let failure { throw failure }
        deletePhotosCalls += 1
    }

    func deleteSession(sessionID: String) async throws {
        if let failure { throw failure }
        deletedSessions.append(sessionID)
    }
}
