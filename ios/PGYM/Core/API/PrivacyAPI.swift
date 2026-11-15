import Foundation
#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif

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

enum PrivacyCallable {
    static let deletePhysiqueScores = "deletePhysiqueScores"
    static let deleteAllPhotos = "deleteAllPhotos"
    static let deleteSession = "deleteSession"
}

#if canImport(FirebaseFunctions)
@MainActor
final class FirebasePrivacyAPI: PrivacyAPI {
    private let functions: Functions

    init(functions: Functions = .functions()) {
        self.functions = functions
    }

    func deletePhysiqueScores() async throws {
        try await call(PrivacyCallable.deletePhysiqueScores, [:])
    }

    func deleteAllPhotos() async throws {
        try await call(PrivacyCallable.deleteAllPhotos, [:])
    }

    func deleteSession(sessionID: String) async throws {
        try await call(PrivacyCallable.deleteSession, ["sessionId": sessionID])
    }

    private func call(_ name: String, _ payload: [String: Any]) async throws {
        do {
            _ = try await functions.httpsCallable(name).call(payload)
        } catch let error as URLError {
            throw ProofAPIError.transport(error)
        } catch {
            let ns = error as NSError
            if ns.domain == FunctionsErrorDomain {
                throw ProofAPIError.callable(code: ns.code, message: ns.localizedDescription)
            }
            if ns.domain == NSURLErrorDomain {
                throw ProofAPIError.transport(URLError(URLError.Code(rawValue: ns.code)))
            }
            throw ProofAPIError.unavailable
        }
    }
}
#endif

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
