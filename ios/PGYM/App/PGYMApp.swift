import DesignSystem
import SwiftUI
import UserNotifications

@main
struct PGYMApp: App {
    @State private var session: AppSession
    @State private var network: NetworkMonitor
    @State private var services: AppServices
    private let dependencies: AuthDependencies
    private let notificationTaps = NotificationTapRouter()

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
        // UI tests never touch iOS notifications or leave state behind.
        let services = isUITest ? AppServices.inMemory() : AppServices.live()
        _services = State(initialValue: services)
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
                .task {
                    for identifier in notificationTaps.drain() {
                        await services.reminders.notificationOpened(identifier)
                    }
                }
                .preferredColorScheme(.dark)
                .onOpenURL { url in _ = dependencies.handleOpenURL(url) }
        }
    }
}
