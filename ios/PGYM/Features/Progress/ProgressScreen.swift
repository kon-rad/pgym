import DesignSystem
import SwiftUI

/// E1 Progress, placeholder: empty-state numbers. Real content (12-week bars, proof wall
/// preview, lifts with bests) is card I8. The physique score is not shown until it exists and
/// the user has opted in.
struct ProgressScreen: View {
    static let viewID = "E1"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.cardGap) {
                Text("Progress")
                    .pgymText(.display)
                    .foregroundStyle(Color.chalk)

                HStack(spacing: Spacing.cardGapMin) {
                    StatTile(label: "Proofs", value: "0")
                    StatTile(label: "Streak", value: "0", unit: "wk")
                }

                Text("Your proof wall starts with the first session.")
                    .pgymText(.body)
                    .foregroundStyle(Color.bone)
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.top, Spacing.grid(4))
        }
        .background(Color.ink.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.\(Self.viewID)")
    }
}

struct ProgressScreen_Previews: PreviewProvider {
    static var previews: some View {
        let _ = FontRegistry.registerAll()
        ProgressScreen().preferredColorScheme(.dark)
    }
}
