import DesignSystem
import SwiftData
import SwiftUI

/// Screens reachable from F1. Card I4 adds Routines (F2); I8 adds the rest.
enum ProfileRoute: Hashable {
    case routines
}

/// F1 Profile. Name and member-since come with sign-in (card I2); the links to F4 to F9 come with card I8.
struct ProfileScreen: View {
    static let viewID = "F1"

    @Query(RoutineStore.activeDescriptor) private var routines: [Routine]
    @State private var path: [ProfileRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.cardGap) {
                    Text("Profile")
                        .pgymText(.display)
                        .foregroundStyle(Color.chalk)

                    HStack(spacing: Spacing.cardGapMin) {
                        StatTile(label: "Proofs", value: "0")
                        StatTile(label: "Longest streak", value: "0", unit: "wk")
                    }

                    VStack(spacing: Spacing.grid(2)) {
                        NavigationLink(value: ProfileRoute.routines) {
                            ProfileLinkRow(
                                title: "Routines",
                                detail: routines.isEmpty ? nil : "\(routines.count)"
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("profile.routines")
                    }
                    .padding(.top, Spacing.grid(2))

                    SecondaryButton("Settings") {}
                        .disabled(true)
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.top, Spacing.grid(4))
            }
            .background(Color.ink.ignoresSafeArea())
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("screen.\(Self.viewID)")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ProfileRoute.self) { route in
                switch route {
                case .routines: RoutinesScreen()
                }
            }
        }
        .tint(Color.chalk)
    }
}

/// A link row on F1: title, an optional mono count, a chevron.
private struct ProfileLinkRow: View {
    let title: String
    let detail: String?

    var body: some View {
        HStack {
            Text(title)
                .font(.pgym(.bodyMedium, size: 17))
                .foregroundStyle(Color.chalk)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.pgym(.data, size: 15))
                    .foregroundStyle(Color.steel)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.steel)
                .accessibilityHidden(true)
        }
        .frame(minHeight: Spacing.touchTargetMin)
        .padding(.horizontal, Spacing.grid(4))
        .padding(.vertical, Spacing.grid(1))
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.iron))
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct ProfileScreen_Previews: PreviewProvider {
    static var previews: some View {
        let _ = FontRegistry.registerAll()
        ProfileScreen()
            .modelContainer(Models.makeContainer(inMemory: true))
            .preferredColorScheme(.dark)
    }
}
