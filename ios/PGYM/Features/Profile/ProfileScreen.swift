import DesignSystem
import SwiftData
import SwiftUI

/// F1 Profile: name, member since, proof count and longest streak, and the way into every setting.
/// The account rows (email, sign out) live in F5 and Delete account in F6, where the flow spec puts
/// them (card I8). Local only: works offline.
struct ProfileScreen: View {
    static let viewID = "F1"

    @Environment(AppSession.self) private var session
    @Query(RoutineStore.activeDescriptor) private var routines: [Routine]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    @State private var path: [ProfileRoute] = []

    var body: some View {
        let facts = StreakFacts.make(sessions: SessionSnapshot.all(sessions), profile: session.profile, now: .now, timeZone: .current)
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.cardGap) {
                    header

                    HStack(spacing: Spacing.cardGapMin) {
                        StatTile(label: ProfileCopy.proofsLabel, value: "\(facts.proofCount)")
                            .accessibilityIdentifier("f1.proofs")
                        StatTile(label: ProfileCopy.longestLabel, value: "\(facts.longestStreak)", unit: facts.longestStreak == 1 ? "week" : "weeks")
                            .accessibilityIdentifier("f1.longest")
                    }

                    links
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.top, Spacing.grid(4))
                .padding(.bottom, Spacing.grid(8))
            }
            .background(Color.ink.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("screen.\(Self.viewID)")
            .navigationDestination(for: ProfileRoute.self) { route in
                switch route {
                case .routines: RoutinesScreen()
                case .goal: GoalScheduleScreen()
                case .settings: SettingsScreen()
                case .privacy: PrivacyDataScreen()
                case .about: AboutScreen()
                case .deleteAccount: DeleteAccountScreen()
                }
            }
            .task { await session.refreshUser() }
        }
        .tint(Color.chalk)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.grid(2)) {
            Text((session.displayName ?? "Profile").uppercased())
                .pgymText(.display)
                .foregroundStyle(Color.chalk)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .accessibilityAddTraits(.isHeader)

            if let month = memberSince {
                Text(AuthCopy.Profile.memberSince(month).uppercased())
                    .pgymText(.label)
                    .foregroundStyle(Color.steel)
            }
        }
    }

    private var memberSince: String? {
        guard let created = session.profile?.createdAt else { return nil }
        return created.formatted(.dateTime.month(.wide).year())
    }

    /// The F1 rows from pgym-app-copy.md. Agent access (F9) is its own card and is not linked yet.
    private var links: some View {
        VStack(spacing: Spacing.grid(2)) {
            row(.routines, title: ProfileCopy.routines, detail: routines.isEmpty ? nil : "\(routines.count)", id: "profile.routines")
            row(.goal, title: ProfileCopy.goalAndSchedule, detail: session.profile?.goalPerWeek.map { "\($0)/wk" }, id: "profile.goal")
            row(.settings, title: ProfileCopy.settings, detail: nil, id: "profile.settings")
            row(.privacy, title: ProfileCopy.privacy, detail: nil, id: "profile.privacy")
            row(.about, title: ProfileCopy.about, detail: nil, id: "profile.about")
        }
        .padding(.top, Spacing.grid(2))
    }

    private func row(_ route: ProfileRoute, title: String, detail: String?, id: String) -> some View {
        NavigationLink(value: route) {
            LinkRow(title: title, detail: detail)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

enum ProfileRoute: Hashable {
    case routines
    case goal
    case settings
    case privacy
    case about
    case deleteAccount
}

struct ProfileScreen_Previews: PreviewProvider {
    static var previews: some View {
        let _ = FontRegistry.registerAll()
        ProfileScreen()
            .environment(AppSession(dependencies: .fake()))
            .environment(NetworkMonitor(fixed: true))
            .modelContainer(Models.makeContainer(inMemory: true))
            .preferredColorScheme(.dark)
    }
}
