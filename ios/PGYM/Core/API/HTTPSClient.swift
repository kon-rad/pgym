import Foundation

enum HTTPSConfiguration {
    static let defaultBaseURL = URL(string: "https://pgym.konradgnat.com")!

    static func baseURL(bundle: Bundle = .main) -> URL {
        guard let value = bundle.object(forInfoDictionaryKey: "PGYM_API_BASE_URL") as? String,
              let url = URL(string: value), !value.isEmpty
        else { return defaultBaseURL }
        return url
    }
}

enum HTTPSClientError: Error, Equatable {
    case offline
    case unauthenticated
    case notFound
    case conflict(String)
    case invalid(String)
    case rateLimited
    case server(status: Int, message: String)
    case malformedResponse
}

struct HTTPSErrorEnvelope: Decodable {
    struct Detail: Decodable { let code: String; let message: String }
    let error: Detail
}

@MainActor
protocol IDTokenProvider: AnyObject {
    func freshIDToken() async throws -> String
}

extension AuthService {
    func asTokenProvider() -> IDTokenProvider { AuthTokenProvider(auth: self) }
}

@MainActor
private final class AuthTokenProvider: IDTokenProvider {
    private let auth: AuthService
    init(auth: AuthService) { self.auth = auth }
    func freshIDToken() async throws -> String { try await auth.freshIDToken() }
}

@MainActor
final class HTTPSClient {
    typealias DataLoader = (URLRequest) async throws -> (Data, URLResponse)

    let baseURL: URL
    private let tokenProvider: IDTokenProvider
    private let load: DataLoader
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(baseURL: URL, tokenProvider: IDTokenProvider, load: @escaping DataLoader) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.load = load
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    static func live(tokenProvider: IDTokenProvider, baseURL: URL = HTTPSConfiguration.baseURL()) -> HTTPSClient {
        HTTPSClient(baseURL: baseURL, tokenProvider: tokenProvider) { request in
            try await URLSession.shared.data(for: request)
        }
    }

    func send<Response: Decodable>(
        _ method: String,
        path: String,
        json: (any Encodable)? = nil,
        body: Data? = nil,
        contentType: String = "application/json",
        response: Response.Type = Response.self
    ) async throws -> Response {
        let token: String
        do { token = try await tokenProvider.freshIDToken() }
        catch { throw HTTPSClientError.unauthenticated }
        guard let url = URL(string: path, relativeTo: baseURL) else { throw HTTPSClientError.invalid(path) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let json { request.httpBody = try encoder.encode(AnyEncodable(json)); request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if let body { request.httpBody = body; request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        let data: Data
        let raw: URLResponse
        do { (data, raw) = try await load(request) }
        catch let error as URLError { throw Self.transport(error) }
        catch { throw HTTPSClientError.server(status: 0, message: error.localizedDescription) }
        guard let http = raw as? HTTPURLResponse else { throw HTTPSClientError.malformedResponse }
        guard (200..<300).contains(http.statusCode) else { throw Self.serverError(status: http.statusCode, data: data, decoder: decoder) }
        if Response.self == EmptyResponse.self, data.isEmpty { return EmptyResponse() as! Response }
        do { return try decoder.decode(Response.self, from: data) }
        catch { throw HTTPSClientError.malformedResponse }
    }

    private static func serverError(status: Int, data: Data, decoder: JSONDecoder) -> HTTPSClientError {
        let detail = try? decoder.decode(HTTPSErrorEnvelope.self, from: data).error
        let message = detail?.message ?? HTTPURLResponse.localizedString(forStatusCode: status)
        switch status {
        case 400: return .invalid(message)
        case 401, 403: return .unauthenticated
        case 404: return .notFound
        case 409: return .conflict(message)
        case 429: return .rateLimited
        default: return .server(status: status, message: message)
        }
    }

    private static func transport(_ error: URLError) -> HTTPSClientError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .cannotFindHost,
             .cannotConnectToHost, .dnsLookupFailed, .internationalRoamingOff: return .offline
        default: return .server(status: 0, message: error.localizedDescription)
        }
    }
}

struct EmptyResponse: Codable { init() {} }

private struct AnyEncodable: Encodable {
    let encodeBody: (Encoder) throws -> Void
    init(_ value: any Encodable) { encodeBody = value.encode }
    func encode(to encoder: Encoder) throws { try encodeBody(encoder) }
}

@MainActor
final class HTTPSAccountService: AccountFunctions {
    private let client: HTTPSClient
    init(client: HTTPSClient) { self.client = client }
    func deleteAccount() async throws { let _: EmptyResponse = try await client.send("DELETE", path: "/api/account") }
}
