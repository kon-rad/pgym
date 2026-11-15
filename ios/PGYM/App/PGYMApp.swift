import DesignSystem
import SwiftUI

@main
struct PGYMApp: App {
    init() {
        FontRegistry.registerAll()
        FirebaseBootstrap.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .preferredColorScheme(.dark)
        }
    }
}
