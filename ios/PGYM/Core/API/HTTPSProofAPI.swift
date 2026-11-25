import Foundation

@MainActor
final class HTTPSProofAPI: ProofAPI {
    private struct StampBody: Encodable {
        let sessionId: String
        let photoSHA256: String
        let cardFormatVersion: Int
        let filter: String
        let proofImageCreated: Bool
    }
    private struct InsightResponse: Decodable { let insight: String }
    private let client: HTTPSClient

    init(client: HTTPSClient) { self.client = client }

    func createUploadUrls(sessionID: String, photoBytes: Int, cardBytes: Int) async throws -> UploadTargets {
        throw ProofAPIError.invalid("Proof media stays on this iPhone.")
    }
    func getPhotoUrls(keys: [String]) async throws -> SignedPhotoLinks {
        throw ProofAPIError.invalid("Proof media stays on this iPhone.")
    }
    func stampSession(sessionID: String) async throws -> StampReceipt {
        throw ProofAPIError.invalid("Proof metadata is required.")
    }
    func stampSession(sessionID: String, photoSHA256: String, cardFormatVersion: Int, filter: String, proofImageCreated: Bool) async throws -> StampReceipt {
        do {
            return try await client.send("POST", path: "/api/sessions/stamp", json: StampBody(
                sessionId: sessionID, photoSHA256: photoSHA256, cardFormatVersion: cardFormatVersion,
                filter: filter, proofImageCreated: proofImageCreated
            ))
        } catch { throw Self.proofError(error) }
    }
    func analyzePhotoInsight(jpeg: Data) async throws -> String {
        guard jpeg.count <= 1_500_000 else { throw ProofAPIError.invalid("Reduced photo is too large.") }
        do {
            let result: InsightResponse = try await client.send("POST", path: "/api/photo-insight", body: jpeg, contentType: "image/jpeg")
            return result.insight
        } catch { throw Self.proofError(error) }
    }

    static func proofError(_ error: Error) -> ProofAPIError {
        guard let error = error as? HTTPSClientError else { return .unavailable }
        switch error {
        case .offline: return .offline
        case .unauthenticated: return .unauthenticated
        case .notFound: return .notFound
        case .conflict(let message):
            if message.localizedCaseInsensitiveContains("already stamped") { return .alreadyStamped }
            if message.localizedCaseInsensitiveContains("not been uploaded") { return .notUploaded }
            return .invalid(message)
        case .invalid(let message): return .invalid(message)
        case .rateLimited, .server, .malformedResponse: return .unavailable
        }
    }
}
