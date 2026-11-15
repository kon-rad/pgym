import DesignSystem
import SwiftData
import SwiftUI

@main
struct PGYMApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var session: AppSession
    @State private var network: NetworkMonitor
    @State private var sessionSync: SessionSyncQueue
    private let dependencies: AuthDependencies
    private let container: ModelContainer

    init() {
        FontRegistry.registerAll()
        let firebase = FirebaseBootstrap.configure()
        let arguments = ProcessInfo.processInfo.arguments
        let backend = AppEnvironment.backend(arguments: arguments, firebase: firebase)
        let dependencies = AppEnvironment.dependencies(for: backend)
        self.dependencies = dependencies
        _session = State(initialValue: AppSession(dependencies: dependencies))
        let isUITest = arguments.contains(AppEnvironment.uiTestArgument)
            || arguments.contains(AppEnvironment.uiTestSignedInArgument)
        let network = isUITest ? NetworkMonitor(fixed: true) : NetworkMonitor()
        _network = State(initialValue: network)

        // UI tests get a fresh store each launch so one test's session never leaks into the next.
        let container = Models.makeContainer(inMemory: isUITest)
        self.container = container
        RoutineSyncSetup.configure(container: container)
        _sessionSync = State(initialValue: SessionSyncSetup.makeQueue(container: container, isOnline: { network.isOnline }))
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(session)
                .environment(network)
                .environment(sessionSync)
                .preferredColorScheme(.dark)
                .onOpenURL { url in _ = dependencies.handleOpenURL(url) }
                .onChange(of: network.isOnline) { _, online in
                    // Queued sessions go out as soon as the gym's signal comes back.
                    if online { sessionSync.requestSync() }
                }
                .onChange(of: session.isSignedIn) { _, signedIn in
                    if signedIn { sessionSync.requestSync() }
                }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                RoutineSyncCoordinator.shared.requestSync()
                sessionSync.requestSync()
            }
        }
    }
}
