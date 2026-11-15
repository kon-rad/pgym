import DesignSystem
import SwiftUI

/// The three tabs from pgym-app-views.md, "Navigation". A session (D) runs full screen
/// over this shell. Sign-in (A) gates it through `AppRootView`; onboarding (B) is card I3.
enum AppTab: String, CaseIterable, Identifiable {
    case today, progress, profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .progress: "Progress"
        case .profile: "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "calendar"
        case .progress: "chart.bar.fill"
        case .profile: "person.crop.circle"
        }
    }

    /// The view ID in pgym-app-views.md for the tab's root screen.
    var viewID: String {
        switch self {
        case .today: "C1"
        case .progress: "E1"
        case .profile: "F1"
        }
    }
}

struct RootTabView: View {
    @State private var selection: AppTab = .today

    var body: some View {
        TabView(selection: $selection) {
            ForEach(AppTab.allCases) { tab in
                screen(for: tab)
                    .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                    .tag(tab)
                    #if os(iOS)
                    .toolbarBackground(Color.ink, for: .tabBar)
                    .toolbarBackground(.visible, for: .tabBar)
                    #endif
            }
        }
        .tint(Color.chalk)
        // D2 runs full screen over the tabs whenever a session is open (card I5).
        .sessionHost()
    }

    @ViewBuilder private func screen(for tab: AppTab) -> some View {
        switch tab {
        case .today: TodayScreen()
        case .progress: ProgressScreen()
        case .profile: ProfileScreen()
        }
    }
}

struct RootTabView_Previews: PreviewProvider {
    static var previews: some View {
        let _ = FontRegistry.registerAll()
        let container = Models.makeContainer(inMemory: true)
        RootTabView()
            .environment(AppSession(dependencies: .fake()))
            .environment(NetworkMonitor(fixed: true))
            .environment(SessionSyncQueue(container: container, engine: nil, uid: { nil }))
            .modelContainer(container)
            .preferredColorScheme(.dark)
    }
}
