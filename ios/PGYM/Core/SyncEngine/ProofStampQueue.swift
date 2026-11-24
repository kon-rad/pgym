import Foundation
import Observation
import SwiftData
import CryptoKit

/// Where one session's stamp is, for D11's stamp area (D9's states, pgym-flow-spec.md "D9 Stamping").
enum StampPhase: Equatable, Sendable {
    /// Queued: waiting for the session to reach Firestore, or for its turn.
    case waiting
    /// No connection. The card is saved and stamps on reconnect or next launch.
    case offline
    /// Photo and card going up, 0...1 over both files by size.
    case uploading(Double)
    /// Both files are up; waiting for `stampSession`.
    case stamping
    /// The server answered.
    case stamped
    /// The queue gave up (upload refused, or retries used up). Try again starts over.
    case failed
}

enum StampError: Error, Equatable {
    /// `photo.jpg` or `card.jpg` is missing from `Proofs/{sessionId}/`.
    case missingFiles
}

/// Uploads one session's photo and card to the presigned URLs and asks the server to stamp it
/// (pgym-architecture.md, "Flow: finishing a session", steps 3 to 5).
///
/// Each file is retried a few times on a retryable failure; an expired URL is renewed once. The
/// stamp is asked for only after both files are up, so a failed upload never costs a proof number,
/// and `stampSession` is idempotent per session on the server, so a retry after a kill gets the same
/// number back.
@MainActor
final class ProofStampEngine {
    let api: ProofAPI
    let uploader: ProofUploading
    let store: ProofStore
    /// Tries per file, the first included.
    let uploadAttempts: Int
    /// Pause before the second, third... try of one file.
    let uploadRetryDelays: [TimeInterval]
    private let sleep: (TimeInterval) async -> Void
    private(set) var insights: [String: String] = [:]

    init(
        api: ProofAPI,
        uploader: ProofUploading,
        store: ProofStore,
        uploadAttempts: Int = 3,
        uploadRetryDelays: [TimeInterval] = [1, 3],
        sleep: @escaping (TimeInterval) async -> Void = { seconds in
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        }
    ) {
        self.api = api
        self.uploader = uploader
        self.store = store
        self.uploadAttempts = max(1, uploadAttempts)
        self.uploadRetryDelays = uploadRetryDelays
        self.sleep = sleep
    }

    func stamp(sessionID: String, analyze: Bool = false, phase: @escaping @MainActor (StampPhase) -> Void) async throws -> StampReceipt {
        let photo = store.photoURL(sessionID)
        guard let photoData = try? Data(contentsOf: photo), store.hasCard(sessionID),
              let record = store.record(sessionID) else {
            throw StampError.missingFiles
        }
        phase(.stamping)
        if analyze, let insight = try? await api.analyzePhotoInsight(jpeg: photoData) {
            insights[sessionID] = insight
        }
        let digest = SHA256.hash(data: photoData).map { String(format: "%02x", $0) }.joined()
        return try await api.stampSession(
            sessionID: sessionID,
            photoSHA256: digest,
            cardFormatVersion: 1,
            filter: record.options.filter.rawValue,
            proofImageCreated: true
        )
    }

    private func put(
        _ file: URL,
        which: KeyPath<UploadTargets, UploadTarget>,
        targets: inout UploadTargets,
        sessionID: String,
        photoBytes: Int,
        cardBytes: Int,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws {
        var failures = 0
        var renewed = false
        while true {
            do {
                try await uploader.upload(file: file, to: targets[keyPath: which].url, contentType: API.photoContentType, progress: progress)
                return
            } catch ProofAPIError.uploadExpired where !renewed {
                // The 5-minute URL ran out (a slow first file, or a retry): sign again, once.
                renewed = true
                targets = try await api.createUploadUrls(sessionID: sessionID, photoBytes: photoBytes, cardBytes: cardBytes)
            } catch let error as ProofAPIError where error != .offline && error.isRetryable && failures + 1 < uploadAttempts {
                failures += 1
                progress(0)
                await sleep(uploadRetryDelays.isEmpty ? 0 : uploadRetryDelays[min(failures - 1, uploadRetryDelays.count - 1)])
            }
        }
    }

    static func size(of file: URL) -> Int? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let size = (attributes[.size] as? NSNumber)?.intValue, size > 0
        else { return nil }
        return size
    }
}

/// Runs the engine for every session waiting for its stamp, one at a time, oldest first. The queue is
/// the sessions themselves (`awaitsStamp`: ended with a card, not stamped), so it survives a kill.
///
/// Triggered when Stamp it ends a session, when the network comes back, when the session sync has
/// written a session, and when the app comes to the front. Offline it waits without counting a failure;
/// otherwise it retries with back-off and gives up to `.failed` (D9's "Try again") after the last delay.
@MainActor
@Observable
final class ProofStampQueue {
    /// Per session, for D11. Missing means nothing is running for it right now.
    private(set) var phases: [String: StampPhase] = [:]
    /// Completed runs, for tests.
    private(set) var runs = 0

    private let container: ModelContainer
    @ObservationIgnored private var engine: ProofStampEngine?
    @ObservationIgnored private var uid: @MainActor () -> String?
    @ObservationIgnored private var isOnline: @MainActor () -> Bool
    /// The session document is in Firestore with its end time, so `createUploadUrls` will find it.
    @ObservationIgnored private var isSynced: @MainActor (WorkoutSession) -> Bool
    @ObservationIgnored private var requestSessionSync: @MainActor () -> Void
    /// Runs before each stamp: sends a consent change made offline, so the server queues the score.
    @ObservationIgnored var beforeStamp: @MainActor () async -> Void = {}
    /// The physique score is on and the user is 18 or over, as far as the phone knows.
    @ObservationIgnored var physiqueEnabled: @MainActor () -> Bool = { false }
    /// Re-renders `card.jpg` with the server's number and time. Errors leave the pending card on disk.
    @ObservationIgnored var restampCard: @MainActor (WorkoutSession, StampReceipt) throws -> Void = { _, _ in }
    /// After the stamp is saved: reminders, haptics.
    @ObservationIgnored var onStamped: @MainActor (WorkoutSession, StampReceipt) -> Void = { _, _ in }

    let retryDelays: [TimeInterval]
    private let sleep: (TimeInterval) async -> Void
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var again = false

    init(
        container: ModelContainer,
        engine: ProofStampEngine?,
        uid: @escaping @MainActor () -> String?,
        isOnline: @escaping @MainActor () -> Bool = { true },
        isSynced: @escaping @MainActor (WorkoutSession) -> Bool = { _ in true },
        requestSessionSync: @escaping @MainActor () -> Void = {},
        retryDelays: [TimeInterval] = [2, 5, 15, 30, 60],
        sleep: @escaping (TimeInterval) async -> Void = { seconds in
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        }
    ) {
        self.container = container
        self.engine = engine
        self.uid = uid
        self.isOnline = isOnline
        self.isSynced = isSynced
        self.requestSessionSync = requestSessionSync
        self.retryDelays = retryDelays
        self.sleep = sleep
    }

    /// Sessions waiting for their stamp, oldest first.
    static func pending(in context: ModelContext) throws -> [WorkoutSession] {
        let draft = SessionStatus.draft.rawValue
        return try context.fetch(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.statusRaw == draft && $0.endedAt != nil },
            sortBy: [SortDescriptor(\WorkoutSession.startedAt)]
        ))
    }

    func phase(for sessionID: String) -> StampPhase? { phases[sessionID] }

    /// Asks for a run. Calls while one is running fold into one more round.
    func requestStamp() {
        if task != nil {
            again = true
            return
        }
        task = Task { @MainActor [weak self] in
            // A request that came in while the last pass was ending gets its own pass.
            repeat {
                self?.again = false
                await self?.run()
            } while self?.again == true
            self?.task = nil
        }
    }

    /// D9's Try again: clears the given-up state and runs again.
    func retry(sessionID: String) {
        if phases[sessionID] == .failed { phases[sessionID] = .waiting }
        requestStamp()
    }

    /// Waits for the running stamp, retries included. For tests.
    func waitUntilIdle() async {
        while let running = task {
            await running.value
        }
    }

    private func run() async {
        var delayIndex = 0
        repeat {
            again = false
            runs += 1
            guard let engine, let uid = uid() else { break }
            let context = container.mainContext
            let sessions = ((try? Self.pending(in: context)) ?? []).filter { phases[$0.id] != .failed }
            guard !sessions.isEmpty else { break }
            guard isOnline() else {
                for session in sessions { phases[session.id] = .offline }
                break
            }
            var retryLater = false
            for session in sessions {
                if session.isDeleted || !session.awaitsStamp { continue }
                let id = session.id
                guard isSynced(session) else {
                    // createUploadUrls needs the document; the sync queue calls back once it is written.
                    phases[id] = .waiting
                    requestSessionSync()
                    continue
                }
                await beforeStamp()
                let scoreRequested = physiqueEnabled()
                do {
                    let receipt = try await engine.stamp(sessionID: id, analyze: scoreRequested) { [weak self] phase in
                        self?.phases[id] = phase
                    }
                    session.physiqueTip = engine.insights[id]
                    apply(receipt, to: session, uid: uid, scoreRequested: scoreRequested, context: context)
                } catch {
                    let apiError = error as? ProofAPIError
                    if apiError == .offline || !isOnline() {
                        phases[id] = .offline
                        // Everything else waits for the network too.
                        for other in sessions where other.awaitsStamp && phases[other.id] != .stamped {
                            phases[other.id] = .offline
                        }
                        refresh(context)
                        return
                    }
                    session.stampFailures = (session.stampFailures ?? 0) + 1
                    try? context.save()
                    if let apiError, apiError.isRetryable, delayIndex < retryDelays.count {
                        phases[id] = .waiting
                        retryLater = true
                    } else {
                        phases[id] = .failed
                    }
                }
            }
            if retryLater, delayIndex < retryDelays.count {
                await sleep(retryDelays[delayIndex])
                delayIndex += 1
                again = true
            }
        } while again
    }

    /// Saves the server's answer on the session and swaps the card for the stamped one.
    private func apply(_ receipt: StampReceipt, to session: WorkoutSession, uid: String, scoreRequested: Bool, context: ModelContext) {
        session.proofNumber = receipt.proofNumber
        session.stampedAt = receipt.stampedAt
        session.photoKey = nil
        session.cardKey = nil
        session.stampReceipt = receipt
        // A retry of a session stamped earlier keeps what was decided at that first stamp.
        if session.physiqueRequested == nil { session.physiqueRequested = scoreRequested }
        session.stampFailures = 0
        // The proof is the server's now; the sync queue never writes a stamped session.
        session.status = .stamped
        try? context.save()
        try? restampCard(session, receipt)
        phases[session.id] = .stamped
        onStamped(session, receipt)
    }

    private func refresh(_ context: ModelContext) {
        try? context.save()
    }

    /// Swaps in the live services once the backend and the user are known.
    func configure(
        engine: ProofStampEngine?,
        uid: @escaping @MainActor () -> String?,
        isOnline: @escaping @MainActor () -> Bool,
        isSynced: @escaping @MainActor (WorkoutSession) -> Bool,
        requestSessionSync: @escaping @MainActor () -> Void
    ) {
        self.engine = engine
        self.uid = uid
        self.isOnline = isOnline
        self.isSynced = isSynced
        self.requestSessionSync = requestSessionSync
        requestStamp()
    }
}
