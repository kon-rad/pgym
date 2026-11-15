import SwiftUI

/// The rubber stamp: "PROOF #042" over a streak line, Plate outline on whatever is behind it,
/// tilted 3 to 8 degrees. The only rotated element in the app.
public struct Stamp: View {
    private let proofNumber: Int?
    private let line: String?
    private let rotation: Double

    /// - Parameters:
    ///   - proofNumber: the server-assigned proof number, or nil while the stamp is pending
    ///     (the phone never makes up a number).
    ///   - line: the streak line, for example "WEEK 7 LOCKED".
    ///   - rotation: degrees, clamped into `Rotation.stampRange`.
    public init(proofNumber: Int?, line: String? = nil, rotation: Double = Rotation.proofCardStamp) {
        self.proofNumber = proofNumber
        self.line = line
        self.rotation = min(max(rotation, Rotation.stampRange.lowerBound), Rotation.stampRange.upperBound)
    }

    /// "PROOF #042"; numbers past 999 keep all their digits. "PROOF PENDING" without a number.
    public static func title(for proofNumber: Int?) -> String {
        guard let proofNumber, proofNumber >= 0 else { return "PROOF PENDING" }
        let digits = String(proofNumber)
        return "PROOF #" + String(repeating: "0", count: max(0, 3 - digits.count)) + digits
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.grid(1)) {
            Text(Self.title(for: proofNumber))
                .font(.pgym(.data, size: 17))
                .tracking(1)
            if let line {
                Text(line).pgymText(.labelBold, size: 10)
            }
        }
        .foregroundStyle(Color.plate)
        .padding(.horizontal, Spacing.grid(3))
        .padding(.vertical, Spacing.grid(2))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.stamp, style: .continuous)
                .strokeBorder(Color.plate, lineWidth: Stroke.stamp)
        )
        .rotationEffect(.degrees(rotation))
        .accessibilityElement(children: .combine)
    }
}

struct Stamp_Previews: PreviewProvider {
    static var previews: some View {
        PreviewSurface {
            VStack(spacing: Spacing.grid(10)) {
                Stamp(proofNumber: 42, line: "Week 7 locked")
                Stamp(proofNumber: 1)
                Stamp(proofNumber: nil, line: "Will sync", rotation: 8)
            }
        }
        .previewDisplayName("Stamp")
    }
}
