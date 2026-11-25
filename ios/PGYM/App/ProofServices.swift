import Foundation
import Observation
import SwiftData

/// The services behind stamping (card I7), built once at launch and passed down the environment:
/// the proof API, the upload-and-stamp queue, the consent flag, the score listener and the signed
/// image cache. Also holds which session's D11 is on screen.
///
/// | Backend | API and upload | Score | Consent write |
/// |---|---|---|---|
/// | Firebase (or the emulator) | Callables with App Check, URLSession PUT to S3 or MinIO | Firestore listener | `users/{uid}` merge |
/// | Fakes (no plist, UI tests) | `FakeProofAPI` + `FakeProofUploader` in memory | none arrives | kept on the phone |
@MainActor
@Observable
final class ProofServices {
    let api: ProofAPI
    let queue: ProofStampQueue
    let consent: PhysiqueConsent
    let physique: PhysiqueSource
    let images: SignedImageCache
    let store: ProofStore
    /// F6, E3 and E5: score deletion, photo deletion, session deletion (card I8).
    let controls: DataControls

    /// The session whose D11 is showing over the tabs. Nil when none.
    var completedSessionID: String?

    init(
        api: ProofAPI,
        queue: ProofStampQueue,
        consent: PhysiqueConsent,
        physique: PhysiqueSource,
        images: SignedImageCache,
        store: ProofStore = .standard,
        privacy: PrivacyAPI? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.api = api
        self.queue = queue
        self.consent = consent
        self.physique = physique
        self.images = images
        self.store = store
        self.controls = DataControls(
            api: privacy ?? FakePrivacyAPI(),
            consent: consent,
            physique: physique,
            store: store,
            images: images,
            defaults: defaults
        )
    }

    /// Stamp it on D8 ended the session: show D11 at once and start the upload (pgym-flow-spec.md D8,
    /// "goes to D11 at once").
    func sessionEndedWithProof(_ sessionID: String) {
        completedSessionID = sessionID
        queue.requestStamp()
    }

    /// Wires the queue's hooks. Called once at launch.
    func connect(
        sessionSync: SessionSyncQueue,
        account: AppSession,
        reminders: ReminderScheduler,
        purchases: PurchaseState? = nil,
        unit: @escaping @MainActor () -> WeightUnit
    ) {
        let consent = consent
        let store = store
        let images = images
        let queue = queue
        queue.beforeStamp = { await consent.flush() }
        queue.physiqueEnabled = {
            consent.isOn
                && (purchases?.canUse(.photoInsight) ?? true)
                && PhysiqueRules.isAdult(birthYear: account.profile?.birthYear, currentYear: AgePolicy.currentYear())
        }
        queue.restampCard = { session, receipt in
            let jpeg = try ProofFeature.restampCard(session: session, receipt: receipt, unit: unit(), store: store)
            if let key = session.cardKey { images.store(jpeg, for: key) }
            let preferences = ProofPreferences()
            if preferences.deleteOriginalAfterCard { store.removeOriginal(session.id) }
            if preferences.automaticallySaveCardsToPhotos {
                Task { try? await ProofPhotoSaver.save(jpeg) }
            }
        }
        queue.onStamped = { session, _ in
            let startedAt = session.startedAt
            Task { await reminders.sessionLogged(at: startedAt) }
        }
        sessionSync.onFlushed = { [weak queue] in queue?.requestStamp() }
    }

    /// Called after the current completion/share flow. Non-retained cards are temporary until here.
    func finishCompletionFlow(sessionID: String) {
        if !ProofPreferences().keepCardsOnPhone { store.removeCard(sessionID) }
        completedSessionID = nil
    }

    /// Picks the implementations for the backend chosen at launch.
    static func make(
        container: ModelContainer,
        useFirebase: Bool,
        isUITest: Bool,
        uid: @escaping @MainActor () -> String?,
        isOnline: @escaping @MainActor () -> Bool,
        sessionSync: SessionSyncQueue
    ) -> ProofServices {
        let store = ProofStore.standard
        var defaults = UserDefaults.standard
        if isUITest, let suite = UserDefaults(suiteName: "pgym-ui-test") {
            // UI tests start from an empty phone every run.
            suite.removePersistentDomain(forName: "pgym-ui-test")
            defaults = suite
        }
        #if canImport(FirebaseAuth) && canImport(FirebaseFirestore)
        if useFirebase {
            let client = HTTPSClient.live(tokenProvider: FirebaseAuthService())
            let api = HTTPSProofAPI(client: client)
            let engine = ProofStampEngine(api: api, uploader: URLSessionProofUploader(), store: store)
            let queue = ProofStampQueue(
                container: container,
                engine: engine,
                uid: uid,
                isOnline: isOnline,
                // createUploadUrls needs the document in Firestore with the end time.
                isSynced: { session in session.lastSyncedAt != nil && !session.needsSync },
                requestSessionSync: { sessionSync.requestSync() }
            )
            return ProofServices(
                api: api,
                queue: queue,
                consent: PhysiqueConsent(defaults: defaults, writer: FirestorePhysiqueConsentWriter()),
                physique: FirestorePhysiqueSource(),
                images: SignedImageCache(api: api),
                store: store,
                privacy: HTTPSPrivacyAPI(client: client),
                defaults: defaults
            )
        }
        #endif
        // Fakes: the whole flow can be clicked through on a simulator with no cloud account.
        let objects = FakeObjectStore()
        let api = FakeProofAPI(objects: objects)
        let engine = ProofStampEngine(api: api, uploader: FakeProofUploader(objects: objects), store: store)
        let queue = ProofStampQueue(container: container, engine: engine, uid: { uid() ?? "returning-user" }, isOnline: isOnline)
        return ProofServices(
            api: api,
            queue: queue,
            consent: PhysiqueConsent(defaults: defaults, writer: FakePhysiqueConsentWriter()),
            physique: FakePhysiqueSource(),
            images: SignedImageCache(api: api, directory: nil),
            store: store,
            privacy: FakePrivacyAPI(),
            defaults: defaults
        )
    }
}
