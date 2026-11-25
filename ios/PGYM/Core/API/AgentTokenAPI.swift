import Foundation

struct AgentToken: Decodable, Equatable, Sendable {
    let tokenId: String
    let token: String
    let prefix: String
    let name: String
    let scopes: [String]
    let createdAt: String
    let expiresAt: String?
}

@MainActor
final class AgentTokenAPI {
    private struct CreateBody: Encodable {
        let name: String
        let scopes: [String]
        let expiresInDays: Int?
    }
    private struct RevokeResponse: Decodable { let tokenId: String; let revokedAt: String }
    private let client: HTTPSClient
    init(client: HTTPSClient) { self.client = client }

    func create(name: String = "My agent") async throws -> AgentToken {
        try await client.send("POST", path: "/api/agent-tokens", json: CreateBody(
            name: name, scopes: ["read:profile", "read:sessions", "read:stats"], expiresInDays: 90
        ))
    }
    func revoke(id: String) async throws {
        let _: RevokeResponse = try await client.send("DELETE", path: "/api/agent-tokens/\(id)")
    }
}
