import CoreGraphics
import DesignSystem
import ImageIO
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import PGYM

/// Card I7: upload, stamp, the offline pending stamp, consent and the score on D11, the API client's
/// parsing and the signed image cache. Everything runs against `FakeProofAPI`, `FakeProofUploader` and
/// `FakePhysiqueSource`; nothing touches the network, Firebase, S3 or a vision model.
@MainActor
final class StampingTests: XCTestCase {
    private let uid = "u1"
    private let phoneEnd = Date(timeIntervalSince1970: 1_800_003_600)
    /// The server's clock, deliberately not the phone's.
    private let serverNow = Date(timeIntervalSince1970: 1_800_090_000)

    private var containers: [ModelContainer] = []
    private var roots: [URL] = []

    override func tearDown() {
        for root in roots { try? FileManager.default.removeItem(at: root) }
        roots = []
        containers = []
        super.tearDown()
    }

    // MARK: Fixtures

    private func makeContainer() -> ModelContainer {
        let container = Models.makeContainer(inMemory: true)
        containers.append(container)
        return container
    }

    private func makeStore() -> ProofStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("stamp-\(UUID().uuidString)")
        roots.append(root)
        return ProofStore(root: root)
    }

    /// A session ended with Stamp it: bench press 100 x 5 and 90 x 10, a warm-up, and its two files.
    private func endedSession(in context: ModelContext, store: ProofStore, realFiles: Bool = false) throws -> WorkoutSession {
        let start = phoneEnd.addingTimeInterval(-3600)
        let session = WorkoutSession(routineId: nil, routineName: "Push A", startedAt: start, timezone: "Europe/London")
        context.insert(session)
        let exercise = SessionExercise(exerciseId: "barbell-bench-press", name: "Bench press", order: 0, targetSets: 3, targetReps: 5)
        context.insert(exercise)
        session.exercises.append(exercise)
        for (n, weight, reps, type) in [(1, 60.0, 10, SetType.warmup), (2, 100.0, 5, .working), (3, 90.0, 10, .working)] {
            let set = SessionSet(n: n, weightKg: weight, reps: reps, type: type)
            set.done = true
            context.insert(set)
            exercise.sets.append(set)
        }
        try context.save()
        if realFiles {
            let photo = try testPhoto()
            try store.savePhoto(try jpeg(photo), for: session.id)
            let summary = ProofCardSummary(session: session, unit: .kg, stamp: .pending(phoneTime: phoneEnd), now: phoneEnd)
            _ = try ProofFeature.stamp(photo: photo, summary: summary, options: ProofCardOptions(), sessionID: session.id, tappedAt: phoneEnd, store: store)
        } else {
            try store.savePhoto(Data(repeating: 0xAB, count: 4096), for: session.id)
            try store.saveCard(Data(repeating: 0xCD, count: 2048), record: ProofStore.CardRecord(options: ProofCardOptions(), stampTappedAt: phoneEnd), for: session.id)
        }
        try SessionStore(context: context).finish(session, withProof: true, now: phoneEnd)
        XCTAssertTrue(session.awaitsStamp)
        return session
    }

    private struct Rig {
        let container: ModelContainer
        let store: ProofStore
        let objects: FakeObjectStore
        let api: FakeProofAPI
        let uploader: FakeProofUploader
        let queue: ProofStampQueue
    }

    /// The queue as the app builds it, on fakes, with no real waiting. `online` is read on every run.
    private func makeRig(online: @escaping @MainActor () -> Bool = { true }, retryDelays: [TimeInterval] = [1, 1, 1]) -> Rig {
        let container = makeContainer()
        let store = makeStore()
        let objects = FakeObjectStore()
        let serverNow = serverNow
        let api = FakeProofAPI(objects: objects, uid: self.uid, now: { serverNow }, lastProofNumber: 41, weekGoal: 4, weekCountBefore: 2, streakClosed: 6)
        let uploader = FakeProofUploader(objects: objects)
        let engine = ProofStampEngine(api: api, uploader: uploader, store: store, uploadAttempts: 3, uploadRetryDelays: [0], sleep: { _ in })
        let uid = self.uid
        let queue = ProofStampQueue(
            container: container,
            engine: engine,
            uid: { uid },
            isOnline: online,
            retryDelays: retryDelays,
            sleep: { _ in }
        )
        return Rig(container: container, store: store, objects: objects, api: api, uploader: uploader, queue: queue)
    }

    private func testPhoto() throws -> CGImage {
        let bundle = Bundle(for: Self.self)
        let url = bundle.url(forResource: "proof-test-photo", withExtension: "png")
            ?? bundle.url(forResource: "proof-test-photo", withExtension: "png", subdirectory: "Fixtures")
        let found = try XCTUnwrap(url, "proof-test-photo.png is missing from the test bundle")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(found as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func jpeg(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func modelInputs(
        session: WorkoutSession,
        phase: StampPhase? = nil,
        consentOn: Bool,
        isAdult: Bool = true,
        offerShown: Bool = false,
        physique: PhysiqueRecord? = nil,
        previousScore: Int? = nil
    ) -> SessionCompleteModel.Inputs {
        SessionCompleteModel.Inputs(
            session: session,
            unit: .kg,
            phase: phase,
            workingFor: 0,
            consentOn: consentOn,
            isAdult: isAdult,
            offerShown: offerShown,
            physique: physique,
            previousScore: previousScore,
            doneDays: [.mon],
            gymDays: [.mon, .wed, .fri, .sat],
            today: .mon
        )
    }

    // MARK: Done-when 1: a failed upload retries and then stamps once

    func testFailedUploadRetriesThenStampsOnce() async throws {
        let rig = makeRig()
        let session = try endedSession(in: rig.container.mainContext, store: rig.store)
        // The photo fails twice (a dropped connection at the gym), then goes up.
        rig.uploader.failures = [.unavailable, .unavailable]

        rig.queue.requestStamp()
        await rig.queue.waitUntilIdle()

        XCTAssertEqual(rig.uploader.attempts.count, 4, "two failed photo PUTs, then photo and card")
        XCTAssertEqual(rig.api.stampCalls, [session.id], "stampSession is called exactly once, after both files are up")
        XCTAssertEqual(rig.api.newStampCount, 1)
        XCTAssertTrue(rig.objects.has(API.photoKey(uid: uid, sessionID: session.id)))
        XCTAssertTrue(rig.objects.has(API.cardKey(uid: uid, sessionID: session.id)))
        XCTAssertEqual(session.status, .stamped)
        XCTAssertEqual(session.proofNumber, 42)
        XCTAssertEqual(session.stampedAt, serverNow)
        XCTAssertEqual(session.cardKey, "users/u1/sessions/\(session.id)/card.jpg")
        XCTAssertEqual(rig.queue.phase(for: session.id), .stamped)
        XCTAssertFalse(session.awaitsStamp)
    }

    func testUploadThatKeepsFailingIsRetriedByTheQueueAndStillStampsOnce() async throws {
        let rig = makeRig()
        let session = try endedSession(in: rig.container.mainContext, store: rig.store)
        // Three failures use up the engine's tries for the photo; the queue backs off and runs again.
        rig.uploader.failures = [.unavailable, .unavailable, .unavailable]

        rig.queue.requestStamp()
        await rig.queue.waitUntilIdle()

        XCTAssertEqual(rig.api.createCalls.count, 2, "a second run after the back-off")
        XCTAssertEqual(rig.api.stampCalls, [session.id], "no stamp while a file is missing; one stamp after")
        XCTAssertEqual(session.proofNumber, 42)
        XCTAssertEqual(session.stampFailures, 0)
    }

    func testRefusedUploadGivesUpWithoutStampingAndTryAgainStamps() async throws {
        let rig = makeRig()
        let session = try endedSession(in: rig.container.mainContext, store: rig.store)
        rig.uploader.failures = [.uploadRejected(status: 400)]

        rig.queue.requestStamp()
        await rig.queue.waitUntilIdle()
        XCTAssertEqual(rig.queue.phase(for: session.id), .failed)
        XCTAssertTrue(rig.api.stampCalls.isEmpty)
        XCTAssertNil(session.proofNumber)
        XCTAssertTrue(session.awaitsStamp, "the session and its files stay on the phone")

        let failed = SessionCompleteModel(modelInputs(session: session, phase: .failed, consentOn: false))
        XCTAssertEqual(failed.stampArea, .failed)
        XCTAssertFalse(failed.canShare)

        rig.queue.retry(sessionID: session.id)
        await rig.queue.waitUntilIdle()
        XCTAssertEqual(rig.api.stampCalls, [session.id])
        XCTAssertEqual(session.proofNumber, 42)
    }

    func testExpiredUploadURLIsRenewedOnce() async throws {
        let rig = makeRig()
        let session = try endedSession(in: rig.container.mainContext, store: rig.store)
        rig.uploader.failures = [.uploadExpired]

        rig.queue.requestStamp()
        await rig.queue.waitUntilIdle()

        XCTAssertEqual(rig.api.createCalls.count, 2, "one renewal of the presigned URLs")
        XCTAssertEqual(rig.api.stampCalls.count, 1)
        XCTAssertEqual(session.status, .stamped)
    }

    func testRetryAfterALostStampAnswerGetsTheSameNumber() async throws {
        let rig = makeRig()
        let session = try endedSession(in: rig.container.mainContext, store: rig.store)
        rig.queue.requestStamp()
        await rig.queue.waitUntilIdle()
        XCTAssertEqual(session.proofNumber, 42)

        // The app was killed before the answer was saved: the phone still thinks it is waiting.
        session.status = .draft
        session.proofNumber = nil
        session.stampedAt = nil
        rig.queue.retry(sessionID: session.id)
        rig.queue.requestStamp()
        await rig.queue.waitUntilIdle()

        XCTAssertEqual(session.proofNumber, 42, "stampSession is idempotent per session")
        XCTAssertEqual(rig.api.newStampCount, 1, "never a second proof number")
        XCTAssertEqual(rig.uploader.attempts.count, 2, "createUploadUrls says already stamped; nothing is uploaded twice")
    }

    // MARK: Done-when 2: an offline finish is stamped after reconnect with the server's time

    func testOfflineFinishIsStampedAfterReconnectWithTheServersTime() async throws {
        var online = false
        let rig = makeRig(online: { online })
        let session = try endedSession(in: rig.container.mainContext, store: rig.store, realFiles: true)
        let pendingCard = try XCTUnwrap(rig.store.cardData(session.id))
        var restamped: [StampReceipt] = []
        let store = rig.store
        rig.queue.restampCard = { session, receipt in
            restamped.append(receipt)
            try ProofFeature.restampCard(session: session, receipt: receipt, unit: .kg, store: store)
        }

        // Offline: nothing is sent, the card stays PENDING with the phone's time.
        rig.queue.requestStamp()
        await rig.queue.waitUntilIdle()
        XCTAssertEqual(rig.queue.phase(for: session.id), .offline)
        XCTAssertTrue(rig.api.createCalls.isEmpty)
        XCTAssertTrue(rig.uploader.attempts.isEmpty)
        XCTAssertNil(session.proofNumber)
        XCTAssertNil(session.stampedAt)
        XCTAssertEqual(session.endedAt, phoneEnd)
        let offline = SessionCompleteModel(modelInputs(session: session, phase: .offline, consentOn: false))
        XCTAssertEqual(offline.stampArea, .offline)
        XCTAssertEqual(offline.headline, StampCopy.offlineTitle)
        XCTAssertFalse(offline.canShare, "only a stamped card is shared")
        XCTAssertNil(offline.score)

        // Back online.
        online = true
        rig.queue.requestStamp()
        await rig.queue.waitUntilIdle()

        XCTAssertEqual(rig.api.stampCalls, [session.id])
        XCTAssertEqual(session.status, .stamped)
        XCTAssertEqual(session.stampedAt, serverNow, "the server's time, not the phone's")
        XCTAssertNotEqual(session.stampedAt, session.endedAt)
        XCTAssertEqual(session.endedAt, phoneEnd, "the session still ends when Stamp it was tapped")

        // The card is re-rendered with the server's number and time.
        XCTAssertEqual(restamped.map(\.stampedAt), [serverNow])
        let stampedCard = try XCTUnwrap(rig.store.cardData(session.id))
        XCTAssertNotEqual(stampedCard, pendingCard)
        let receipt = try XCTUnwrap(session.stampReceipt)
        let summary = ProofFeature.stampedSummary(session: session, receipt: receipt, unit: .kg)
        let timestamp = ProofCardText.timestamp(summary.stamp, timezone: summary.timezone)
        XCTAssertEqual(timestamp, ProofCardText.timestamp(.stamped(proofNumber: 42, stampedAt: serverNow, streakWeeks: 0, proofCount: 0), timezone: "Europe/London"))
        XCTAssertFalse(timestamp.contains("NOT STAMPED"))
        XCTAssertEqual(ProofCardText.proofNumber(summary.stamp), "#042")

        let model = SessionCompleteModel(modelInputs(session: session, phase: .stamped, consentOn: false))
        XCTAssertEqual(model.stampArea, .stamped(proofNumber: 42, timestamp: timestamp))
        XCTAssertEqual(model.headline, "3 of 4 this week.")
        XCTAssertTrue(model.canShare)
    }

    func testStampWaitsForTheSessionDocumentAndAsksForASync() async throws {
        var synced = false
        var syncRequests = 0
        let container = makeContainer()
        let store = makeStore()
        let objects = FakeObjectStore()
        let api = FakeProofAPI(objects: objects, uid: self.uid)
        let engine = ProofStampEngine(api: api, uploader: FakeProofUploader(objects: objects), store: store, sleep: { _ in })
        let uid = self.uid
        let queue = ProofStampQueue(
            container: container, engine: engine, uid: { uid },
            isSynced: { _ in synced }, requestSessionSync: { syncRequests += 1 },
            retryDelays: [], sleep: { _ in }
        )
        let session = try endedSession(in: container.mainContext, store: store)

        queue.requestStamp()
        await queue.waitUntilIdle()
        XCTAssertTrue(api.createCalls.isEmpty, "createUploadUrls needs the document in Firestore")
        XCTAssertEqual(syncRequests, 1)
        XCTAssertEqual(queue.phase(for: session.id), .waiting)

        synced = true
        queue.requestStamp()
        await queue.waitUntilIdle()
        XCTAssertEqual(session.status, .stamped)
    }

    func testStampedSessionIsNeverWrittenBackBySessionSync() async throws {
        let rig = makeRig()
        let session = try endedSession(in: rig.container.mainContext, store: rig.store)
        rig.queue.requestStamp()
        await rig.queue.waitUntilIdle()
        XCTAssertEqual(session.status, .stamped)
        XCTAssertEqual(SessionDocument(session: session).status, "draft", "the phone never writes stamped")
        XCTAssertFalse(try ProofStampQueue.pending(in: rig.container.mainContext).contains { $0.id == session.id })
    }

    // MARK: Done-when 3: no score UI appears without consent

    func testNoScoreUIWithoutConsent() async throws {
        let rig = makeRig()
        let session = try endedSession(in: rig.container.mainContext, store: rig.store)
        rig.queue.physiqueEnabled = { false }
        rig.queue.requestStamp()
        await rig.queue.waitUntilIdle()
        XCTAssertEqual(session.physiqueRequested, false)

        let scored = PhysiqueRecord(score: 71, tip: "Add two sets of rows each week.")
        // Consent off: nothing, not even when a score is somehow there.
        XCTAssertNil(SessionCompleteModel(modelInputs(session: session, consentOn: false)).score)
        XCTAssertNil(SessionCompleteModel(modelInputs(session: session, consentOn: false, physique: scored)).score)
        // Consent turned on after this stamp: the server never analysed this session, so no waiting
        // skeleton either.
        XCTAssertNil(SessionCompleteModel(modelInputs(session: session, consentOn: true)).score)
        // Under 18: never, whatever the flags.
        session.physiqueRequested = true
        XCTAssertNil(SessionCompleteModel(modelInputs(session: session, consentOn: true, isAdult: false, physique: scored)).score)
        // Consent on, adult, stamped with the score on: the block shows.
        XCTAssertEqual(SessionCompleteModel(modelInputs(session: session, consentOn: true)).score, .pending)
        // Turned off later: gone again.
        XCTAssertNil(SessionCompleteModel(modelInputs(session: session, consentOn: false, physique: scored)).score)
    }

    func testConsentOfferRowShowsOnceToAdultsOnlyAndNotOnTheFirstProof() async throws {
        let rig = makeRig()
        let session = try endedSession(in: rig.container.mainContext, store: rig.store)
        rig.queue.requestStamp()
        await rig.queue.waitUntilIdle()
        XCTAssertEqual(session.proofNumber, 42)

        XCTAssertTrue(SessionCompleteModel(modelInputs(session: session, consentOn: false)).showsConsentOffer)
        XCTAssertFalse(SessionCompleteModel(modelInputs(session: session, consentOn: false, offerShown: true)).showsConsentOffer)
        XCTAssertFalse(SessionCompleteModel(modelInputs(session: session, consentOn: false, isAdult: false)).showsConsentOffer)
        XCTAssertFalse(SessionCompleteModel(modelInputs(session: session, consentOn: true)).showsConsentOffer)

        var first = try XCTUnwrap(session.stampReceipt)
        first.proofCount = 1
        session.stampReceipt = first
        XCTAssertFalse(SessionCompleteModel(modelInputs(session: session, consentOn: false)).showsConsentOffer, "never in the first loop")
    }

    func testConsentTurnedOnOfflineIsSentBeforeTheNextStamp() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "pgym-stamping-\(UUID().uuidString)"))
        let writer = FakePhysiqueConsentWriter()
        writer.failure = ProofAPIError.offline
        let consent = PhysiqueConsent(defaults: defaults, writer: writer)
        consent.load(uid: uid, profileValue: nil)
        XCTAssertFalse(consent.isOn, "off is the default")

        await consent.turnOn()
        XCTAssertTrue(consent.isOn, "saved on the phone at once")
        XCTAssertTrue(consent.needsUpload)
        XCTAssertTrue(consent.offerShown)
        // A profile read while the change waits does not undo it.
        consent.load(uid: uid, profileValue: false)
        XCTAssertTrue(consent.isOn)

        let rig = makeRig()
        let session = try endedSession(in: rig.container.mainContext, store: rig.store)
        var order: [String] = []
        writer.failure = nil
        rig.queue.beforeStamp = {
            await consent.flush()
            order.append("consent:\(writer.writes)")
        }
        rig.queue.physiqueEnabled = { consent.isOn }
        rig.queue.onStamped = { _, _ in order.append("stamped") }
        rig.queue.requestStamp()
        await rig.queue.waitUntilIdle()

        XCTAssertEqual(order, ["consent:[true]", "stamped"], "the server sees consent before the stamp, so it queues the score")
        XCTAssertFalse(consent.needsUpload)
        XCTAssertEqual(session.physiqueRequested, true)
    }

    // MARK: Done-when 4: a refused analysis shows no score and no error

    func testRefusedAnalysisShowsNoScoreAndNoError() async throws {
        let rig = makeRig()
        let session = try endedSession(in: rig.container.mainContext, store: rig.store)
        rig.queue.physiqueEnabled = { true }
        rig.queue.requestStamp()
        await rig.queue.waitUntilIdle()
        XCTAssertEqual(session.physiqueRequested, true)

        // The listener delivers what analyzePhysique wrote.
        let source = FakePhysiqueSource()
        var delivered: PhysiqueRecord??
        let observation = source.observe(uid: uid, sessionID: session.id) { delivered = .some($0) }
        XCTAssertEqual(delivered, .some(nil), "nothing yet")
        XCTAssertEqual(SessionCompleteModel(modelInputs(session: session, consentOn: true, physique: nil)).score, .pending)

        for reason in ["no_person", "several_people", "face_only", "unreadable", "apparent_minor", "failure", "daily_limit"] {
            let raw: [String: Any] = ["refusedReason": reason, "model": "fake", "score": 64, "tip": "should never show"]
            let record = try XCTUnwrap(PhysiqueRecord(firestore: raw))
            XCTAssertNil(record.score, "a refusal never carries a score")
            XCTAssertNil(record.tip)
            source.deliver(record, for: session.id)
            let model = SessionCompleteModel(modelInputs(session: session, consentOn: true, physique: delivered ?? nil))
            XCTAssertNil(model.score, "\(reason): no score block, no reason line, no error on D11")
            XCTAssertEqual(model.stampArea, .stamped(
                proofNumber: 42,
                timestamp: ProofCardText.timestamp(.stamped(proofNumber: 42, stampedAt: serverNow, streakWeeks: 0, proofCount: 0), timezone: "Europe/London")
            ))
            XCTAssertTrue(model.canShare, "the session still counts and still shares")
        }
        observation.cancel()
    }

    func testScoreArrivesThroughTheListenerWithTrendAndTip() async throws {
        let rig = makeRig()
        let session = try endedSession(in: rig.container.mainContext, store: rig.store)
        rig.queue.physiqueEnabled = { true }
        rig.queue.requestStamp()
        await rig.queue.waitUntilIdle()

        let source = FakePhysiqueSource()
        var latest: PhysiqueRecord?
        let observation = source.observe(uid: uid, sessionID: session.id) { latest = $0 }
        source.deliver(PhysiqueRecord(score: 68, tip: "Rest 2 to 3 minutes between heavy sets."), for: session.id)
        XCTAssertEqual(
            SessionCompleteModel(modelInputs(session: session, consentOn: true, physique: latest, previousScore: 66)).score,
            .scored(score: 68, trend: "Up 2 from last time.", tip: "Rest 2 to 3 minutes between heavy sets.")
        )
        XCTAssertEqual(SessionCompleteModel.trend(score: 64, previous: 66), "2 lower than last time. Light and angle move this number.")
        XCTAssertEqual(SessionCompleteModel.trend(score: 66, previous: 66), StampCopy.trendSame)
        XCTAssertEqual(SessionCompleteModel.trend(score: 66, previous: nil), StampCopy.trendFirst)
        observation.cancel()
    }

    // MARK: D11 content

    func testSessionCompleteShowsStatsBestsAndHeadlines() async throws {
        let rig = makeRig()
        let session = try endedSession(in: rig.container.mainContext, store: rig.store)
        rig.queue.requestStamp()
        await rig.queue.waitUntilIdle()
        var receipt = try XCTUnwrap(session.stampReceipt)
        receipt.newBests = ["barbell-bench-press"]
        receipt.setCount = 2
        receipt.totalVolume = 1400
        session.stampReceipt = receipt

        let model = SessionCompleteModel(modelInputs(session: session, consentOn: false))
        XCTAssertEqual(model.stats, [
            .init(label: "Sets", value: "2", unit: nil),
            .init(label: "Total lifted", value: "1,400", unit: "kg"),
            .init(label: "Time", value: ProofCardText.duration(3600), unit: nil),
        ])
        // 90 x 10 is the better set by estimated one-rep max.
        XCTAssertEqual(model.newBests, ["Bench press: 90 kg x 10"])
        XCTAssertEqual(model.weekRings.map { $0.status }, [.done, .rest, .planned, .rest, .planned, .planned, .rest])

        XCTAssertEqual(SessionCompleteModel.headline(receipt: withWeek(receipt, count: 4, goal: 4, streak: 7), area: .offline), "Week 7 locked.")
        XCTAssertEqual(SessionCompleteModel.headline(receipt: withWeek(receipt, count: 5, goal: 4, streak: 7), area: .offline), "Bonus session logged.")
        XCTAssertEqual(SessionCompleteModel.headline(receipt: withWeek(receipt, count: 1, goal: 3, streak: 0), area: .offline), "1 of 3 this week.")
        XCTAssertEqual(SessionCompleteModel.headline(receipt: nil, area: .working(progress: 0.4, slow: false)), "Stamping")
    }

    private func withWeek(_ receipt: StampReceipt, count: Int, goal: Int, streak: Int) -> StampReceipt {
        var copy = receipt
        copy.weekCount = count
        copy.weekGoal = goal
        copy.streakWeeks = streak
        return copy
    }

    func testCopyHasNoExclamationMarksOrGuilt() {
        let strings = [
            StampCopy.stampingBody, StampCopy.stampingSlow, StampCopy.offlineBody, StampCopy.errorBody,
            StampCopy.consentLead1, StampCopy.consentOffBody, StampCopy.trendDown(3), StampCopy.scorePending,
        ]
        for string in strings {
            XCTAssertFalse(string.contains("!"), string)
            XCTAssertFalse(string.lowercased().contains("missed"), string)
            XCTAssertFalse(string.lowercased().contains("broke"), string)
        }
    }

    // MARK: API client

    func testStampReceiptParsesTheCallableAnswer() throws {
        let data: [String: Any] = [
            "sessionId": "s1", "proofNumber": NSNumber(value: 42), "stampedAt": "2026-11-15T18:47:03.512Z",
            "weekKey": "2026-W46", "weekCount": 3, "weekGoal": 4, "streakWeeks": 6, "longestStreak": 9,
            "passWeeks": 1, "proofCount": 42, "setCount": 18, "totalVolume": 6240.5, "durationSec": 4360,
            "newBests": ["barbell-bench-press"], "alreadyStamped": false,
        ]
        let receipt = try XCTUnwrap(StampReceipt(callable: data))
        XCTAssertEqual(receipt.proofNumber, 42)
        XCTAssertEqual(receipt.stampedAt.timeIntervalSince1970, 1_794_768_423.512, accuracy: 0.001)
        XCTAssertEqual(receipt.totalVolume, 6240.5)
        XCTAssertEqual(receipt.newBests, ["barbell-bench-press"])
        XCTAssertNil(StampReceipt(callable: ["sessionId": "s1", "stampedAt": "2026-11-15T18:47:03Z"]), "no number, no stamp")
        XCTAssertNil(StampReceipt(callable: ["sessionId": "s1", "proofNumber": 3]), "no server time, no stamp")

        let targets = try XCTUnwrap(UploadTargets(callable: [
            "photo": ["key": "users/u/sessions/s/photo.jpg", "url": "http://localhost:9000/b/photo?sig=1"],
            "card": ["key": "users/u/sessions/s/card.jpg", "url": "http://localhost:9000/b/card?sig=2"],
            "expiresInSec": 300,
        ]))
        XCTAssertEqual(targets.photo.key, "users/u/sessions/s/photo.jpg")
        XCTAssertEqual(targets.expiresInSec, 300)
        let links = try XCTUnwrap(SignedPhotoLinks(callable: ["urls": ["k": "https://x.invalid/k"], "expiresInSec": 3600]))
        XCTAssertEqual(links.urls["k"]?.absoluteString, "https://x.invalid/k")
    }

    func testCallableErrorsMapToWhatTheQueueDecidesOn() {
        XCTAssertEqual(ProofAPIError.callable(code: 9, message: "This session is already stamped."), .alreadyStamped)
        XCTAssertEqual(ProofAPIError.callable(code: 9, message: "The photo has not been uploaded."), .notUploaded)
        XCTAssertEqual(ProofAPIError.callable(code: 5, message: "No such session."), .notFound)
        XCTAssertEqual(ProofAPIError.callable(code: 16, message: "Sign in first."), .unauthenticated)
        XCTAssertEqual(ProofAPIError.callable(code: 14, message: "unavailable"), .unavailable)
        XCTAssertEqual(ProofAPIError.transport(URLError(.notConnectedToInternet)), .offline)
        XCTAssertEqual(ProofAPIError.transport(URLError(.timedOut)), .unavailable)
        XCTAssertFalse(ProofAPIError.invalid("x").isRetryable)
        XCTAssertTrue(ProofAPIError.notFound.isRetryable)
        XCTAssertNoThrow(try URLSessionProofUploader.check(status: 200))
        XCTAssertThrowsError(try URLSessionProofUploader.check(status: 403)) { XCTAssertEqual($0 as? ProofAPIError, .uploadExpired) }
        XCTAssertThrowsError(try URLSessionProofUploader.check(status: 413)) { XCTAssertEqual($0 as? ProofAPIError, .uploadRejected(status: 413)) }
        XCTAssertThrowsError(try URLSessionProofUploader.check(status: 503)) { XCTAssertEqual($0 as? ProofAPIError, .unavailable) }
        XCTAssertEqual(API.photoKey(uid: "u", sessionID: "s"), "users/u/sessions/s/photo.jpg")
    }

    // MARK: Signed image cache

    func testImageCacheSignsOnceDownloadsOnceAndKeysByObjectNotURL() async throws {
        let api = FakeProofAPI(uid: uid)
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        var fetched: [URL] = []
        var statuses: [Int] = []
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("signed-\(UUID().uuidString)")
        roots.append(directory)
        let cache = SignedImageCache(api: api, directory: directory, now: { clock }) { url in
            fetched.append(url)
            let status = statuses.isEmpty ? 200 : statuses.removeFirst()
            return (Data("jpeg:\(FakeProofAPI.key(from: url))".utf8), status)
        }
        let key = API.cardKey(uid: uid, sessionID: "s1")

        let first = try await cache.data(for: key)
        let second = try await cache.data(for: key)
        XCTAssertEqual(first, second)
        XCTAssertEqual(api.linkCalls.count, 1)
        XCTAssertEqual(fetched.count, 1, "the second read comes from memory")

        // A new cache over the same folder (a relaunch) reads the disk, no network.
        let relaunched = SignedImageCache(api: api, directory: directory, now: { clock }) { _ in
            XCTFail("should not download")
            return (Data(), 500)
        }
        let fromDisk = try await relaunched.data(for: key)
        XCTAssertEqual(fromDisk, first)

        // Another key an hour later: the old link set is stale, a 403 renews once.
        clock = clock.addingTimeInterval(3600)
        statuses = [403, 200]
        let other = API.photoKey(uid: uid, sessionID: "s1")
        _ = try await cache.data(for: other)
        XCTAssertEqual(api.linkCalls.count, 3, "signed, then signed again after the 403")
        XCTAssertNotEqual(fetched[1], fetched[2], "a new signature for the same object")

        // Prefetch signs in one batch and skips what is cached.
        try await cache.prefetchLinks([key, other, API.photoKey(uid: uid, sessionID: "s2"), API.cardKey(uid: uid, sessionID: "s2")])
        XCTAssertEqual(api.linkCalls.last?.count, 2)

        cache.removeAll()
        XCTAssertFalse(cache.isCached(key))
    }
}
