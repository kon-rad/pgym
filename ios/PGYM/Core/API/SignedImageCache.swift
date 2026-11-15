import CryptoKit
import Foundation

/// Proof photos and cards from S3, through short-lived signed links (pgym-architecture.md, "S3 layout":
/// presigned GET valid 1 hour, "the app caches images on the phone").
///
/// Cached by object key, never by URL: every `getPhotoUrls` call signs a new URL for the same object.
/// Three layers: memory, then a file in Caches (protected until first unlock, removed by iOS when space
/// runs low), then the network. Links are fetched in batches and reused until two minutes before they
/// expire; a 403 renews the link once. Two views asking for the same key share one download.
@MainActor
final class SignedImageCache {
    typealias Fetch = (URL) async throws -> (Data, Int)

    /// A link is renewed this long before it expires.
    static let renewMargin: TimeInterval = 120

    private let api: ProofAPI
    private let fetch: Fetch
    private let directory: URL?
    private let now: () -> Date
    private let memory = NSCache<NSString, NSData>()
    private var links: [String: (url: URL, expiresAt: Date)] = [:]
    private var inFlight: [String: Task<Data, Error>] = [:]

    /// Downloads made, for tests.
    private(set) var downloads = 0

    init(
        api: ProofAPI,
        directory: URL? = SignedImageCache.defaultDirectory,
        now: @escaping () -> Date = { .now },
        fetch: @escaping Fetch = { try await SignedImageCache.urlSessionFetch($0) }
    ) {
        self.api = api
        self.directory = directory
        self.now = now
        self.fetch = fetch
        memory.totalCostLimit = 64 * 1024 * 1024
    }

    nonisolated static var defaultDirectory: URL? {
        try? FileManager.default
            .url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("SignedPhotos", isDirectory: true)
    }

    nonisolated static func urlSessionFetch(_ url: URL) async throws -> (Data, Int) {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch let error as URLError {
            throw ProofAPIError.transport(error)
        }
    }

    /// The image bytes for `key`, from the fastest place that has them.
    func data(for key: String) async throws -> Data {
        if let cached = memory.object(forKey: key as NSString) { return cached as Data }
        if let file = file(for: key), let data = try? Data(contentsOf: file) {
            memory.setObject(data as NSData, forKey: key as NSString, cost: data.count)
            return data
        }
        if let running = inFlight[key] { return try await running.value }
        let task = Task { @MainActor [unowned self] in try await self.download(key) }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        return try await task.value
    }

    /// Signs every key that has no fresh link yet, in batches of `API.maxKeysPerCall`. Lists call this
    /// once for what they show, so scrolling does not make one call per cell.
    func prefetchLinks(_ keys: [String]) async throws {
        let stale = Array(Set(keys.filter { !hasFreshLink($0) && !isCached($0) })).sorted()
        var start = 0
        while start < stale.count {
            let batch = Array(stale[start..<min(start + API.maxKeysPerCall, stale.count)])
            try await sign(batch)
            start += API.maxKeysPerCall
        }
    }

    /// Bytes already on the phone (memory or disk): no network needed.
    func isCached(_ key: String) -> Bool {
        if memory.object(forKey: key as NSString) != nil { return true }
        guard let file = file(for: key) else { return false }
        return FileManager.default.fileExists(atPath: file.path)
    }

    /// Puts bytes the phone already has (the card it just rendered) under their key.
    func store(_ data: Data, for key: String) {
        memory.setObject(data as NSData, forKey: key as NSString, cost: data.count)
        writeFile(data, for: key)
    }

    /// Account deleted or signed out: nothing of this user's stays.
    func removeAll() {
        memory.removeAllObjects()
        links = [:]
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func hasFreshLink(_ key: String) -> Bool {
        guard let link = links[key] else { return false }
        return link.expiresAt.timeIntervalSince(now()) > Self.renewMargin
    }

    private func sign(_ keys: [String]) async throws {
        let signed = try await api.getPhotoUrls(keys: keys)
        let expiresAt = now().addingTimeInterval(TimeInterval(signed.expiresInSec))
        for (key, url) in signed.urls { links[key] = (url, expiresAt) }
    }

    private func signedURL(_ key: String) async throws -> URL {
        if !hasFreshLink(key) { try await sign([key]) }
        guard let url = links[key]?.url else { throw ProofAPIError.notFound }
        return url
    }

    private func download(_ key: String) async throws -> Data {
        var url = try await signedURL(key)
        downloads += 1
        var (data, status) = try await fetch(url)
        if status == 403 {
            // Expired early or revoked: sign again, once.
            links[key] = nil
            url = try await signedURL(key)
            downloads += 1
            (data, status) = try await fetch(url)
        }
        guard (200..<300).contains(status), !data.isEmpty else {
            throw status == 404 ? ProofAPIError.notFound : ProofAPIError.unavailable
        }
        store(data, for: key)
        return data
    }

    private func file(for key: String) -> URL? {
        guard let directory else { return nil }
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest + ".jpg")
    }

    private func writeFile(_ data: Data, for key: String) {
        guard let directory, let file = file(for: key) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try? data.write(to: file, options: .atomic)
        #endif
    }
}
