import SwiftUI

/// A number that matters, on Iron: mono label above, mono data value, optional unit.
public struct StatTile: View {
    private let label: String
    private let value: String
    private let unit: String?

    public init(label: String, value: String, unit: String? = nil) {
        self.label = label
        self.value = value
        self.unit = unit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.grid(2)) {
            Text(label)
                .pgymText(.label)
                .foregroundStyle(Color.steel)
            HStack(alignment: .firstTextBaseline, spacing: Spacing.grid(1)) {
                Text(value)
                    .font(.pgym(.data, size: 24))
                    .foregroundStyle(Color.chalk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let unit {
                    Text(unit)
                        .pgymText(.label)
                        .foregroundStyle(Color.steel)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.grid(4))
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.iron)
        )
        .accessibilityElement(children: .combine)
    }
}

struct StatTile_Previews: PreviewProvider {
    static var previews: some View {
        PreviewSurface {
            HStack(spacing: Spacing.cardGapMin) {
                StatTile(label: "Sets", value: "18")
                StatTile(label: "Lifted", value: "6,240", unit: "kg")
                StatTile(label: "Time", value: "52:10")
            }
        }
        .previewDisplayName("Stat tile")
    }
}
