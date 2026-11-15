import DesignSystem
import SwiftData
import SwiftUI

@main
struct PGYMApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var session: AppSession
    @State private var network: NetworkMonitor
    private let dependencies: AuthDependencies
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
        _network = State(initialValue: isUITest ? NetworkMonitor(fixed: true) : NetworkMonitor())

        // UI tests start from an empty phone every run.
        container = Models.makeContainer(inMemory: isUITest)
        RoutineSyncSetup.configure(
            container: container,
            useFirestore: backend == .firebase,
            uid: { [session] in session.user?.uid }
        )
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(session)
                .environment(network)
                .preferredColorScheme(.dark)
                .onOpenURL { url in _ = dependencies.handleOpenURL(url) }
                // Routines saved while signed out or offline go up as soon as both change.
                .onChange(of: session.user?.uid) { _, uid in
                    if uid != nil { RoutineSyncCoordinator.shared.requestSync() }
                }
                .onChange(of: network.isOnline) { _, online in
                    if online { RoutineSyncCoordinator.shared.requestSync() }
                }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { RoutineSyncCoordinator.shared.requestSync() }
        }
    }
}
