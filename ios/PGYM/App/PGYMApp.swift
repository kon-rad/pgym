import DesignSystem
import SwiftData
import SwiftUI

@main
struct PGYMApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let container: ModelContainer

    init() {
        FontRegistry.registerAll()
        FirebaseBootstrap.configure()
        // UI tests start from an empty phone every run.
        container = Models.makeContainer(inMemory: ProcessInfo.processInfo.arguments.contains(Models.uiTestingArgument))
        RoutineSyncSetup.configure(container: container)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { RoutineSyncCoordinator.shared.requestSync() }
        }
    }
}
