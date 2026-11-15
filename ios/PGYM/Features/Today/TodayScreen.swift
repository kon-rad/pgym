import DesignSystem
import SwiftUI

/// C1 Today, placeholder. Shows the first-run state (C4) because there is no data layer yet.
/// Real content (streak stamp, live week rings, Next up card, last proof) is card I8.
struct TodayScreen: View {
    static let viewID = "C1"

    private let weekdays = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.cardGap) {
                Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .pgymText(.label)
                    .foregroundStyle(Color.steel)

                Text("Today")
                    .pgymText(.display)
                    .foregroundStyle(Color.chalk)

                HStack(spacing: 0) {
                    ForEach(Array(weekdays.enumerated()), id: \.offset) { _, day in
                        DayRing(day: day, state: .planned)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, Spacing.grid(2))

                VStack(alignment: .leading, spacing: Spacing.grid(3)) {
                    Text("Next up")
                        .pgymText(.label)
                        .foregroundStyle(Color.steel)
                    Text("Proof #001 is waiting.")
                        .pgymText(.title)
                        .foregroundStyle(Color.chalk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.grid(4))
                .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.iron))
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.top, Spacing.grid(4))
        }
        .safeAreaInset(edge: .bottom) {
            // The session flow (D1 onward) is card I5; the button is the shell's only Plate element.
            PrimaryButton("Start session") {}
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.bottom, Spacing.grid(2))
        }
        .background(Color.ink.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.\(Self.viewID)")
    }
}

struct TodayScreen_Previews: PreviewProvider {
    static var previews: some View {
        let _ = FontRegistry.registerAll()
        TodayScreen().preferredColorScheme(.dark)
    }
}
