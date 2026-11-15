import DesignSystem
import SwiftUI

/// F1 Profile, placeholder. Name and member-since come with sign-in (card I2); the links to
/// F2 to F9 come with card I8.
struct ProfileScreen: View {
    static let viewID = "F1"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.cardGap) {
                Text("Profile")
                    .pgymText(.display)
                    .foregroundStyle(Color.chalk)

                HStack(spacing: Spacing.cardGapMin) {
                    StatTile(label: "Proofs", value: "0")
                    StatTile(label: "Longest streak", value: "0", unit: "wk")
                }

                SecondaryButton("Settings") {}
                    .disabled(true)
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.top, Spacing.grid(4))
        }
        .background(Color.ink.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.\(Self.viewID)")
    }
}

struct ProfileScreen_Previews: PreviewProvider {
    static var previews: some View {
        let _ = FontRegistry.registerAll()
        ProfileScreen().preferredColorScheme(.dark)
    }
}
