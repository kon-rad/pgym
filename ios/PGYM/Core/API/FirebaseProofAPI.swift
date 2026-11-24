import Foundation

#if canImport(FirebaseFunctions)
import FirebaseCore
import FirebaseFunctions

/// `ProofAPI` on Firebase callable functions. The Functions SDK attaches the user's ID token and,
/// because App Check is configured at launch (`FirebaseBootstrap`, `PGYMAppCheckProviderFactory`),
/// an App Check token to every call; the functions enforce App Check outside the emulator
/// (`backend/src/index.ts`).
@MainActor
final class FirebaseProofAPI: ProofAPI {
    private let functions: Functions

    init(functions: Functions = .functions()) {
        self.functions = functions
    }

    func createUploadUrls(sessionID: String, photoBytes: Int, cardBytes: Int) async throws -> UploadTargets {
        throw ProofAPIError.invalid("Remote proof uploads are retired.")
    }

    func getPhotoUrls(keys: [String]) async throws -> SignedPhotoLinks {
        throw ProofAPIError.invalid("Remote proof reads are retired.")
    }

    func stampSession(sessionID: String) async throws -> StampReceipt {
        throw ProofAPIError.invalid("Proof metadata is required.")
    }

    func stampSession(sessionID: String, photoSHA256: String, cardFormatVersion: Int, filter: String, proofImageCreated: Bool) async throws -> StampReceipt {
        let data = try await call(API.stampSession, [
            "sessionId": sessionID,
            "photoSHA256": photoSHA256,
            "cardFormatVersion": cardFormatVersion,
            "filter": filter,
            "proofImageCreated": proofImageCreated,
        ])
        guard let receipt = StampReceipt(callable: data) else { throw ProofAPIError.invalid(API.stampSession) }
        return receipt
    }

    func analyzePhotoInsight(jpeg: Data) async throws -> String {
        guard jpeg.count <= 4 * 1024 * 1024 else { throw ProofAPIError.invalid("Reduced photo is too large.") }
        let data = try await call(API.analyzePhotoInsight, ["consent": true, "imageBase64": jpeg.base64EncodedString()])
        guard let insight = data["insight"] as? String, !insight.isEmpty else { throw ProofAPIError.invalid(API.analyzePhotoInsight) }
        return insight
    }

    private func call(_ name: String, _ payload: [String: Any]) async throws -> [String: Any] {
        let result: HTTPSCallableResult
        do {
            result = try await functions.httpsCallable(name).call(payload)
        } catch {
            throw Self.map(error)
        }
        guard let data = result.data as? [String: Any] else { throw ProofAPIError.invalid(name) }
        return data
    }

    private static func map(_ error: Error) -> ProofAPIError {
        if let urlError = error as? URLError { return ProofAPIError.transport(urlError) }
        let ns = error as NSError
        if ns.domain == FunctionsErrorDomain {
            return ProofAPIError.callable(code: ns.code, message: ns.localizedDescription)
        }
        if ns.domain == NSURLErrorDomain {
            return ProofAPIError.transport(URLError(URLError.Code(rawValue: ns.code)))
        }
        return .unavailable
    }
}
#endif

#if canImport(FirebaseAppCheck)
import FirebaseAppCheck
import FirebaseCore

/// App Check for the callable functions: App Attest on a device, the debug provider on the simulator
/// and against the local emulator (which does not enforce App Check). Set before `FirebaseApp.configure`.
///
/// The debug provider prints a debug token to the console on first run; register it in the Firebase
/// console (App Check, Manage debug tokens) to call a real project from the simulator.
final class PGYMAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    private let useDebugProvider: Bool

    init(useDebugProvider: Bool) {
        self.useDebugProvider = useDebugProvider
    }

    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        if useDebugProvider {
            return AppCheckDebugProvider(app: app)
        }
        return AppAttestProvider(app: app)
    }
}
#endif
