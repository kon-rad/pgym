import Foundation

/// The callable Cloud Functions the proof flow uses (pgym-architecture.md, "Functions"; card I7):
/// `createUploadUrls`, `getPhotoUrls` and `stampSession`. Shapes mirror `backend/src/handlers.ts`.
///
/// The phone never holds an AWS key: it asks for presigned URLs and PUTs the files straight to S3
/// (or MinIO locally). Every call carries the Firebase ID token and, on the Firebase backend, an
/// App Check token (`FirebaseProofAPI`, `FirebaseBootstrap`).
enum API {
    static let stampSession = "stampSession"
    static let analyzePhotoInsight = "analyzePhotoInsight"

    /// `PHOTO_CONTENT_TYPE` in `backend/src/photoStore.ts`; part of the PUT signature.
    static let photoContentType = "image/jpeg"
    /// `MAX_UPLOAD_BYTES` in `backend/src/photoStore.ts`.
    static let maxUploadBytes = 8 * 1024 * 1024
    /// `MAX_KEYS_PER_CALL` in `backend/src/handlers.ts`.
    static let maxKeysPerCall = 60

    /// `users/{uid}/sessions/{sessionId}/photo.jpg` (pgym-architecture.md, "S3 layout").
    static func photoKey(uid: String, sessionID: String) -> String {
        "users/\(uid)/sessions/\(sessionID)/photo.jpg"
    }

    static func cardKey(uid: String, sessionID: String) -> String {
        "users/\(uid)/sessions/\(sessionID)/card.jpg"
    }

    /// Reads a callable's number, which arrives as `NSNumber`, `Int` or `Double`.
    static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        return nil
    }

    static func int(_ value: Any?) -> Int? {
        number(value).map { Int($0.rounded()) }
    }

    /// `Date.toISOString()` from the functions: "2026-11-15T13:17:04.512Z".
    static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }
}

/// One presigned PUT: the object key and the URL, valid `expiresInSec` (5 minutes on the server).
struct UploadTarget: Equatable, Sendable {
    var key: String
    var url: URL
}

/// `createUploadUrls` result.
struct UploadTargets: Equatable, Sendable {
    var photo: UploadTarget
    var card: UploadTarget
    var expiresInSec: Int

    init(photo: UploadTarget, card: UploadTarget, expiresInSec: Int) {
        self.photo = photo
        self.card = card
        self.expiresInSec = expiresInSec
    }

    /// From the callable's `{photo: {key, url}, card: {key, url}, expiresInSec}`.
    init?(callable data: [String: Any]) {
        func target(_ field: String) -> UploadTarget? {
            guard let map = data[field] as? [String: Any],
                  let key = map["key"] as? String,
                  let text = map["url"] as? String,
                  let url = URL(string: text)
            else { return nil }
            return UploadTarget(key: key, url: url)
        }
        guard let photo = target("photo"), let card = target("card") else { return nil }
        self.init(photo: photo, card: card, expiresInSec: API.int(data["expiresInSec"]) ?? 300)
    }
}

/// `getPhotoUrls` result: presigned GET links by key, valid `expiresInSec` (1 hour on the server).
struct SignedPhotoLinks: Equatable, Sendable {
    var urls: [String: URL]
    var expiresInSec: Int

    init(urls: [String: URL], expiresInSec: Int) {
        self.urls = urls
        self.expiresInSec = expiresInSec
    }

    init?(callable data: [String: Any]) {
        guard let raw = data["urls"] as? [String: Any] else { return nil }
        var urls: [String: URL] = [:]
        for (key, value) in raw {
            if let text = value as? String, let url = URL(string: text) { urls[key] = url }
        }
        self.init(urls: urls, expiresInSec: API.int(data["expiresInSec"]) ?? 3600)
    }
}

/// `stampSession` result (`StampResult` in `backend/src/handlers.ts`). Every value here is the
/// server's: the proof number, the time, the week and the streak. The phone stores it on the session
/// and shows it on D11; it never makes any of them up.
struct StampReceipt: Codable, Equatable, Sendable {
    var sessionId: String
    var proofNumber: Int
    var stampedAt: Date
    var weekKey: String
    var weekCount: Int
    var weekGoal: Int
    var streakWeeks: Int
    var longestStreak: Int
    var passWeeks: Int
    var proofCount: Int
    var setCount: Int
    var totalVolume: Double
    var durationSec: Int
    /// Exercise IDs that set a new best in this session, by the server's rule.
    var newBests: [String]
    /// The session was stamped by an earlier call (a retry after a kill): same number, nothing new.
    var alreadyStamped: Bool

    init(
        sessionId: String,
        proofNumber: Int,
        stampedAt: Date,
        weekKey: String,
        weekCount: Int,
        weekGoal: Int,
        streakWeeks: Int,
        longestStreak: Int,
        passWeeks: Int,
        proofCount: Int,
        setCount: Int,
        totalVolume: Double,
        durationSec: Int,
        newBests: [String],
        alreadyStamped: Bool
    ) {
        self.sessionId = sessionId
        self.proofNumber = proofNumber
        self.stampedAt = stampedAt
        self.weekKey = weekKey
        self.weekCount = weekCount
        self.weekGoal = weekGoal
        self.streakWeeks = streakWeeks
        self.longestStreak = longestStreak
        self.passWeeks = passWeeks
        self.proofCount = proofCount
        self.setCount = setCount
        self.totalVolume = totalVolume
        self.durationSec = durationSec
        self.newBests = newBests
        self.alreadyStamped = alreadyStamped
    }

    /// From the callable's map. Nil if the number or the time is missing: without both it is not a stamp.
    init?(callable data: [String: Any]) {
        guard let sessionId = data["sessionId"] as? String,
              let proofNumber = API.int(data["proofNumber"]), proofNumber > 0,
              let stampedAt = API.date(data["stampedAt"])
        else { return nil }
        self.init(
            sessionId: sessionId,
            proofNumber: proofNumber,
            stampedAt: stampedAt,
            weekKey: data["weekKey"] as? String ?? "",
            weekCount: API.int(data["weekCount"]) ?? 0,
            weekGoal: API.int(data["weekGoal"]) ?? 0,
            streakWeeks: API.int(data["streakWeeks"]) ?? 0,
            longestStreak: API.int(data["longestStreak"]) ?? 0,
            passWeeks: API.int(data["passWeeks"]) ?? 0,
            proofCount: API.int(data["proofCount"]) ?? 0,
            setCount: API.int(data["setCount"]) ?? 0,
            totalVolume: API.number(data["totalVolume"]) ?? 0,
            durationSec: API.int(data["durationSec"]) ?? 0,
            newBests: data["newBests"] as? [String] ?? [],
            alreadyStamped: data["alreadyStamped"] as? Bool ?? false
        )
    }

    /// The stamp as the card renderer takes it.
    var stampState: ProofStampState {
        .stamped(proofNumber: proofNumber, stampedAt: stampedAt, streakWeeks: streakWeeks, proofCount: proofCount)
    }
}

/// What can go wrong between the phone, the functions and S3, reduced to what the queue decides on.
enum ProofAPIError: Error, Equatable {
    /// No route to the server. Wait for the network; never counts as a failure.
    case offline
    /// No signed-in user, or the ID token was refused.
    case unauthenticated
    /// The session document is not in Firestore yet: sync it first.
    case notFound
    /// `createUploadUrls` on a session the server already stamped (a lost answer): stamp again for the
    /// same number.
    case alreadyStamped
    /// `stampSession` did not find both objects in the bucket.
    case notUploaded
    /// The server refused the request as malformed. Not retried.
    case invalid(String)
    /// The server or the connection failed. Retried with back-off.
    case unavailable
    /// The presigned URL was refused (403): expired or signed for another size. Renewed once.
    case uploadExpired
    /// The bucket refused the file for another reason. Not retried.
    case uploadRejected(status: Int)

    /// Worth another try later without anything changing on the phone.
    var isRetryable: Bool {
        switch self {
        case .offline, .notFound, .notUploaded, .unavailable, .uploadExpired, .alreadyStamped: true
        case .unauthenticated, .invalid, .uploadRejected: false
        }
    }

    /// Maps a callable error (Firebase `FunctionsErrorCode` raw value and message) to the cases above.
    /// Pure, so the mapping is tested without Firebase.
    static func callable(code: Int, message: String) -> ProofAPIError {
        switch code {
        case 16: return .unauthenticated // unauthenticated
        case 5: return .notFound // not-found
        case 9: // failed-precondition
            let text = message.lowercased()
            if text.contains("already stamped") { return .alreadyStamped }
            if text.contains("not been uploaded") { return .notUploaded }
            return .invalid(message)
        case 3, 7, 11, 12: return .invalid(message) // invalid-argument, permission-denied, out-of-range, unimplemented
        default: return .unavailable // unavailable, deadline-exceeded, internal, resource-exhausted, unknown
        }
    }

    /// URLSession errors that mean "no connection" rather than "the server failed".
    static func transport(_ error: URLError) -> ProofAPIError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff,
             .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return .offline
        default:
            return .unavailable
        }
    }
}

/// The three proof functions. Firebase in the app (`FirebaseProofAPI`), an in-memory server in tests
/// and in builds without Firebase (`FakeProofAPI`).
@MainActor
protocol ProofAPI: AnyObject {
    /// Two presigned PUT URLs for the caller's session, with the sizes fixed in the signature.
    func createUploadUrls(sessionID: String, photoBytes: Int, cardBytes: Int) async throws -> UploadTargets
    /// Presigned GET URLs for the caller's own keys (at most `API.maxKeysPerCall` per call).
    func getPhotoUrls(keys: [String]) async throws -> SignedPhotoLinks
    /// Server time, proof number, streak and stats. Idempotent per session: a retry returns the same number.
    func stampSession(sessionID: String) async throws -> StampReceipt
    /// Privacy-first stamp. The digest binds the receipt to exact local JPEG bytes; no media is sent.
    func stampSession(
        sessionID: String,
        photoSHA256: String,
        cardFormatVersion: Int,
        filter: String,
        proofImageCreated: Bool
    ) async throws -> StampReceipt
}
