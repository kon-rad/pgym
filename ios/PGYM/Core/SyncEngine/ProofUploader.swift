import Foundation

/// PUTs one file to a presigned URL. URLSession in the app, `FakeProofUploader` in tests.
@MainActor
protocol ProofUploading: AnyObject {
    /// Uploads `file` with `contentType` (part of the signature). `progress` gets 0...1 for this file.
    /// Throws `ProofAPIError`: `.offline`, `.unavailable`, `.uploadExpired` (403) or `.uploadRejected`.
    func upload(file: URL, to url: URL, contentType: String, progress: @escaping @MainActor (Double) -> Void) async throws
}

/// Direct upload to S3 (or MinIO) with URLSession. The file is streamed from disk, so a 2048 px photo
/// never sits in memory twice; the content length comes from the file and matches the size the
/// server signed (`createUploadUrls` gets the exact byte counts).
@MainActor
final class URLSessionProofUploader: ProofUploading {
    private let session: URLSession

    init(session: URLSession = URLSession(configuration: .default)) {
        self.session = session
    }

    func upload(file: URL, to url: URL, contentType: String, progress: @escaping @MainActor (Double) -> Void) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        let delegate = UploadProgressDelegate(onProgress: progress)
        let response: URLResponse
        do {
            let result = try await session.upload(for: request, fromFile: file, delegate: delegate)
            response = result.1
        } catch let error as URLError {
            throw ProofAPIError.transport(error)
        } catch {
            throw ProofAPIError.unavailable
        }
        guard let http = response as? HTTPURLResponse else { throw ProofAPIError.unavailable }
        try Self.check(status: http.statusCode)
        progress(1)
    }

    /// 2xx is done; 403 is an expired or mismatched signature (renew the URL); other 4xx are refused;
    /// 5xx is the bucket failing (retry).
    static func check(status: Int) throws {
        switch status {
        case 200..<300: return
        case 403: throw ProofAPIError.uploadExpired
        case 400..<500: throw ProofAPIError.uploadRejected(status: status)
        default: throw ProofAPIError.unavailable
        }
    }
}

/// Forwards URLSession's byte counts to the main actor as a fraction.
private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    private let onProgress: @MainActor (Double) -> Void

    init(onProgress: @escaping @MainActor (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        let fraction = min(1, Double(totalBytesSent) / Double(totalBytesExpectedToSend))
        let report = onProgress
        Task { @MainActor in report(fraction) }
    }
}
