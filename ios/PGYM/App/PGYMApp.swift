import DesignSystem
import SwiftData
import SwiftUI
import UserNotifications

@main
struct PGYMApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var session: AppSession
    @State private var network: NetworkMonitor
    @State private var services: AppServices
    @State private var sessionSync: SessionSyncQueue
    @State private var proofs: ProofServices
    private let dependencies: AuthDependencies
    private let notificationTaps = NotificationTapRouter()
    private let container: ModelContainer

    init() {
        FontRegistry.registerAll()
        let firebase = FirebaseBootstrap.configure()
        let arguments = ProcessInfo.processInfo.arguments
        let backend = AppEnvironment.backend(arguments: arguments, firebase: firebase)
        let dependencies = AppEnvironment.dependencies(for: backend)
        self.dependencies = dependencies
        let session = AppSession(dependencies: dependencies)
        _session = State(initialValue: session)
        let isUITest = arguments.contains(AppEnvironment.uiTestArgument)
            || arguments.contains(AppEnvironment.uiTestSignedInArgument)
        let network = isUITest ? NetworkMonitor(fixed: true) : NetworkMonitor()
        _network = State(initialValue: network)

        // UI tests start from an empty phone every run.
        container = Models.makeContainer(inMemory: isUITest)
        RoutineSyncSetup.configure(
            container: container,
            useFirestore: backend == .firebase,
            uid: { [session] in session.user?.uid }
        )
        let sessionSync = SessionSyncSetup.makeQueue(
            container: container,
            useFirestore: backend == .firebase,
            uid: { [session] in session.user?.uid },
            isOnline: { network.isOnline }
        )
        _sessionSync = State(initialValue: sessionSync)

        // UI tests never touch iOS notifications or leave state behind.
        let services = isUITest ? AppServices.inMemory() : AppServices.live()
        _services = State(initialValue: services)

        // Card I7: upload, stamp, consent, score and signed images.
        let proofs = ProofServices.make(
            container: container,
            useFirebase: backend == .firebase,
            isUITest: isUITest,
            uid: { [session] in session.user?.uid },
            isOnline: { network.isOnline },
            sessionSync: sessionSync
        )
        proofs.connect(
            sessionSync: sessionSync,
            account: session,
            reminders: services.reminders,
            unit: { [session] in WeightUnit.preferred(profile: session.profile?.units) }
        )
        _proofs = State(initialValue: proofs)
        // Set before launch finishes, so a tap that cold-starts the app is delivered.
        if !isUITest {
            UNUserNotificationCenter.current().delegate = notificationTaps
        }
        notificationTaps.onOpen = { identifier in
            Task { await services.reminders.notificationOpened(identifier) }
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(session)
                .environment(network)
                .environment(services)
                .environment(sessionSync)
                .environment(proofs)
                .task {
                    for identifier in notificationTaps.drain() {
                        await services.reminders.notificationOpened(identifier)
                    }
                }
                .preferredColorScheme(.dark)
                .onOpenURL { url in _ = dependencies.handleOpenURL(url) }
                // Routines and sessions saved while signed out or offline go up as soon as both change.
                .onChange(of: session.user?.uid) { _, uid in
                    if let uid {
                        RoutineSyncCoordinator.shared.requestSync()
                        sessionSync.requestSync()
                        proofs.consent.load(uid: uid, profileValue: session.profile?.physiqueConsent)
                        proofs.queue.requestStamp()
                        Task { await proofs.controls.retryPending() }
                    } else {
                        proofs.consent.reset()
                        proofs.images.removeAll()
                        proofs.completedSessionID = nil
                    }
                }
                .onChange(of: session.profile) { _, profile in
                    // The profile arrives after sign-in: take the server's consent flag.
                    if let uid = session.user?.uid {
                        proofs.consent.load(uid: uid, profileValue: profile?.physiqueConsent)
                    }
                }
                .onChange(of: network.isOnline) { _, online in
                    if online {
                        RoutineSyncCoordinator.shared.requestSync()
                        sessionSync.requestSync()
                        // Offline finishes stamp on reconnect, with the server's time.
                        Task {
                            await proofs.consent.flush()
                            proofs.queue.requestStamp()
                            // A score delete that could not reach the server goes now (card I8).
                            await proofs.controls.retryPending()
                        }
                    }
                }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                RoutineSyncCoordinator.shared.requestSync()
                sessionSync.requestSync()
                proofs.queue.requestStamp()
            }
        }
    }
}
