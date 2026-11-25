import Foundation
import XCTest
@testable import PGYM

@MainActor
final class HTTPSTransportTests: XCTestCase {
    private final class Tokens: IDTokenProvider {
        var calls = 0
        func freshIDToken() async throws -> String { calls += 1; return "fresh-token-\(calls)" }
    }
    private struct Reply: Codable, Equatable { let ok: Bool }

    func testEveryRequestUsesFreshBearerTokenAndConfiguredBaseURL() async throws {
        let tokens = Tokens()
        var requests: [URLRequest] = []
        let client = HTTPSClient(baseURL: URL(string: "https://api.example.test")!, tokenProvider: tokens) { request in
            requests.append(request)
            return (Data(#"{"ok":true}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let first: Reply = try await client.send("POST", path: "/api/sessions/stamp", json: ["sessionId": "session-1"])
        let second: Reply = try await client.send("DELETE", path: "/api/sessions/session-1")
        XCTAssertEqual(first, Reply(ok: true))
        XCTAssertEqual(second, Reply(ok: true))
        XCTAssertEqual(tokens.calls, 2)
        XCTAssertEqual(requests.map { $0.value(forHTTPHeaderField: "Authorization") }, ["Bearer fresh-token-1", "Bearer fresh-token-2"])
        XCTAssertEqual(requests.first?.url?.absoluteString, "https://api.example.test/api/sessions/stamp")
    }

    func testTypedServerAndOfflineErrors() async {
        let tokens = Tokens()
        let denied = HTTPSClient(baseURL: URL(string: "https://api.example.test")!, tokenProvider: tokens) { request in
            let body = Data(#"{"error":{"code":"unauthenticated","message":"expired"}}"#.utf8)
            return (body, HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!)
        }
        do { let _: Reply = try await denied.send("GET", path: "/private"); XCTFail("Expected authentication failure") }
        catch { XCTAssertEqual(error as? HTTPSClientError, .unauthenticated) }

        let offline = HTTPSClient(baseURL: URL(string: "https://api.example.test")!, tokenProvider: tokens) { _ in
            throw URLError(.notConnectedToInternet)
        }
        do { let _: Reply = try await offline.send("GET", path: "/private"); XCTFail("Expected offline") }
        catch { XCTAssertEqual(error as? HTTPSClientError, .offline) }
    }

    func testPhotoInsightUsesRawJPEGBearerRoute() async throws {
        let tokens = Tokens()
        var request: URLRequest?
        let client = HTTPSClient(baseURL: URL(string: "https://api.example.test")!, tokenProvider: tokens) { captured in
            request = captured
            return (Data(#"{"insight":"Strong setup."}"#.utf8), HTTPURLResponse(url: captured.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let insight = try await HTTPSProofAPI(client: client).analyzePhotoInsight(jpeg: Data([0xff, 0xd8, 0xff]))
        XCTAssertEqual(insight, "Strong setup.")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Content-Type"), "image/jpeg")
        XCTAssertEqual(request?.httpBody, Data([0xff, 0xd8, 0xff]))
    }
}
