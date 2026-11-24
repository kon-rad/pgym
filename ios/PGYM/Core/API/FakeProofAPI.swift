import Foundation

/// A bucket in memory: the keys that have been PUT. Shared by `FakeProofUploader` (writes) and
/// `FakeProofAPI` (checks before stamping), the way S3 sits between the phone and the functions.
@MainActor
final class FakeObjectStore {
    private(set) var objects: [String: Int] = [:]

    func put(key: String, bytes: Int) { objects[key] = bytes }
    func has(_ key: String) -> Bool { objects[key] != nil }
}

/// The three proof functions in memory, with the server's rules: upload URLs only for a session that is
/// not stamped yet, a stamp only once both objects exist, the next proof number, the server's own clock,
/// and the same answer for a second stamp of the same session.
///
/// Used by the tests, and by builds without Firebase (fresh clone, UI tests) so every screen after
/// Stamp it can be reached on a simulator. It is never used with a real Firebase project.
@MainActor
final class FakeProofAPI: ProofAPI {
    static let host = "pgym-local.invalid"

    let objects: FakeObjectStore
    var uid: String
    /// The server clock. Tests set it apart from the phone's to prove which one the card shows.
    var now: () -> Date
    var weekGoal: Int
    /// Sessions already stamped this week before the first call.
    var weekCountBefore: Int
    var streakClosed: Int

    /// Errors to throw from the next calls, in order.
    var createFailures: [ProofAPIError] = []
    var stampFailures: [ProofAPIError] = []
    var linkFailures: [ProofAPIError] = []

    private(set) var createCalls: [String] = []
    private(set) var stampCalls: [String] = []
    private(set) var linkCalls: [[String]] = []
    private(set) var receipts: [String: StampReceipt] = [:]
    private var lastProofNumber: Int
    private var urlSerial = 0

    init(
        objects: FakeObjectStore = FakeObjectStore(),
        uid: String = "returning-user",
        now: @escaping () -> Date = { .now },
        lastProofNumber: Int = 0,
        weekGoal: Int = 4,
        weekCountBefore: Int = 0,
        streakClosed: Int = 0
    ) {
        self.objects = objects
        self.uid = uid
        self.now = now
        self.lastProofNumber = lastProofNumber
        self.weekGoal = weekGoal
        self.weekCountBefore = weekCountBefore
        self.streakClosed = streakClosed
    }

    /// Successful stamps that made a new number (a retry of a stamped session is not one).
    var newStampCount: Int { receipts.count }

    func createUploadUrls(sessionID: String, photoBytes: Int, cardBytes: Int) async throws -> UploadTargets {
        createCalls.append(sessionID)
        if !createFailures.isEmpty { throw createFailures.removeFirst() }
        if receipts[sessionID] != nil { throw ProofAPIError.alreadyStamped }
        guard photoBytes > 0, cardBytes > 0, photoBytes <= API.maxUploadBytes, cardBytes <= API.maxUploadBytes else {
            throw ProofAPIError.invalid("bytes")
        }
        return UploadTargets(
            photo: UploadTarget(key: API.photoKey(uid: uid, sessionID: sessionID), url: signedURL(API.photoKey(uid: uid, sessionID: sessionID), method: "PUT")),
            card: UploadTarget(key: API.cardKey(uid: uid, sessionID: sessionID), url: signedURL(API.cardKey(uid: uid, sessionID: sessionID), method: "PUT")),
            expiresInSec: 300
        )
    }

    func getPhotoUrls(keys: [String]) async throws -> SignedPhotoLinks {
        linkCalls.append(keys)
        if !linkFailures.isEmpty { throw linkFailures.removeFirst() }
        guard !keys.isEmpty, keys.count <= API.maxKeysPerCall else { throw ProofAPIError.invalid("keys") }
        let prefix = "users/\(uid)/"
        guard keys.allSatisfy({ $0.hasPrefix(prefix) }) else { throw ProofAPIError.invalid("permission-denied") }
        var urls: [String: URL] = [:]
        for key in Set(keys) { urls[key] = signedURL(key, method: "GET") }
        return SignedPhotoLinks(urls: urls, expiresInSec: 3600)
    }

    func stampSession(sessionID: String) async throws -> StampReceipt {
        try await stampSession(sessionID: sessionID, photoSHA256: String(repeating: "0", count: 64), cardFormatVersion: 1, filter: "iron", proofImageCreated: true)
    }

    func stampSession(sessionID: String, photoSHA256: String, cardFormatVersion: Int, filter: String, proofImageCreated: Bool) async throws -> StampReceipt {
        stampCalls.append(sessionID)
        if !stampFailures.isEmpty { throw stampFailures.removeFirst() }
        if var existing = receipts[sessionID] {
            existing.alreadyStamped = true
            return existing
        }
        guard photoSHA256.count == 64, cardFormatVersion == 1, proofImageCreated,
              ["iron", "chalk", "plate", "raw"].contains(filter)
        else { throw ProofAPIError.invalid("proof metadata") }
        lastProofNumber += 1
        let weekCount = weekCountBefore + receipts.count + 1
        let hit = weekCount >= weekGoal
        let receipt = StampReceipt(
            sessionId: sessionID,
            proofNumber: lastProofNumber,
            stampedAt: now(),
            weekKey: "",
            weekCount: weekCount,
            weekGoal: weekGoal,
            streakWeeks: streakClosed + (hit ? 1 : 0),
            longestStreak: streakClosed + (hit ? 1 : 0),
            passWeeks: 0,
            proofCount: lastProofNumber,
            setCount: 0,
            totalVolume: 0,
            durationSec: 0,
            newBests: [],
            alreadyStamped: false
        )
        receipts[sessionID] = receipt
        return receipt
    }

    private func signedURL(_ key: String, method: String) -> URL {
        urlSerial += 1
        // A new signature every call, like the real presigner, so caches must key on the object key.
        return URL(string: "https://\(Self.host)/\(key)?X-Method=\(method)&X-Signature=\(urlSerial)")!
    }

    /// The object key a fake signed URL points at.
    static func key(from url: URL) -> String {
        String(url.path.dropFirst())
    }
}

/// PUTs into a `FakeObjectStore`. Tests queue failures to prove the retry.
@MainActor
final class FakeProofUploader: ProofUploading {
    let objects: FakeObjectStore
    /// Errors to throw from the next uploads, in order.
    var failures: [ProofAPIError] = []
    private(set) var attempts: [String] = []

    init(objects: FakeObjectStore) {
        self.objects = objects
    }

    func upload(file: URL, to url: URL, contentType: String, progress: @escaping @MainActor (Double) -> Void) async throws {
        let key = FakeProofAPI.key(from: url)
        attempts.append(key)
        if !failures.isEmpty { throw failures.removeFirst() }
        let bytes = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0
        progress(0.5)
        objects.put(key: key, bytes: bytes)
        progress(1)
    }
}
