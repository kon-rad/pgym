import DesignSystem
import SwiftUI

@main
struct PGYMApp: App {
    @State private var session: AppSession
    @State private var network: NetworkMonitor
    private let dependencies: AuthDependencies

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
        _network = State(initialValue: isUITest ? NetworkMonitor(fixed: true) : NetworkMonitor())
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(session)
                .environment(network)
                .preferredColorScheme(.dark)
                .onOpenURL { url in _ = dependencies.handleOpenURL(url) }
        }
    }
}
