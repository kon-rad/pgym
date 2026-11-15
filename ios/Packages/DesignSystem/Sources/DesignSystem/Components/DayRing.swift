import SwiftUI

/// One day in the week row on Today (C1): a ring with the day letter under it.
/// There is no "missed" state on purpose: the voice never uses guilt.
public struct DayRing: View {
    public enum Status: String, CaseIterable, Sendable {
        /// A planned gym day not yet trained: empty Rail ring.
        case planned
        /// Trained and stamped: Plate disc with an Ink check.
        case done
        /// Today, not yet trained: Chalk ring.
        case today
        /// Not a gym day: thin hairline ring.
        case rest
    }

    public static let diameter: CGFloat = 36

    private let day: String
    private let state: Status

    /// - Parameter day: the short day label, for example "M".
    public init(day: String, state: Status) {
        self.day = day
        self.state = state
    }

    @Environment(\.dynamicTypeSize) private var typeSize

    public var body: some View {
        VStack(spacing: Spacing.grid(2)) {
            ring.frame(width: Self.diameter, height: Self.diameter)
            // At the accessibility sizes the letters hide and the "3 OF 4 THIS WEEK" line carries the
            // meaning (pgym-flow-spec.md); a letter at that size would not fit a seventh of the row.
            if !typeSize.isAccessibilitySize {
                Text(day)
                    .pgymText(.label, size: 10)
                    .foregroundStyle(state == .today ? Color.chalk : Color.steel)
            }
        }
        .frame(minWidth: Spacing.touchTargetMin)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(day), \(accessibilityState)")
    }

    @ViewBuilder private var ring: some View {
        switch state {
        case .done:
            ZStack {
                Circle().fill(Color.plate)
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Color.ink)
            }
        case .today:
            Circle().strokeBorder(Color.chalk, lineWidth: Stroke.dayRing)
        case .planned:
            Circle().strokeBorder(Color.rail, lineWidth: Stroke.dayRing)
        case .rest:
            Circle().strokeBorder(Color.hairline, lineWidth: Stroke.hairline)
        }
    }

    private var accessibilityState: String {
        switch state {
        case .done: "trained"
        case .today: "today"
        case .planned: "gym day"
        case .rest: "rest day"
        }
    }
}

struct DayRing_Previews: PreviewProvider {
    static var previews: some View {
        PreviewSurface {
            HStack(spacing: 0) {
                DayRing(day: "M", state: .done)
                DayRing(day: "T", state: .rest)
                DayRing(day: "W", state: .done)
                DayRing(day: "T", state: .today)
                DayRing(day: "F", state: .planned)
                DayRing(day: "S", state: .rest)
                DayRing(day: "S", state: .rest)
            }
        }
        .previewDisplayName("Day ring")
    }
}
