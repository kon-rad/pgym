import CoreGraphics

/// Spacing from pgym-design-style.md, "Shape and spacing". Everything sits on a 4 pt grid.
public enum Spacing {
    /// The grid unit.
    public static let grid: CGFloat = 4
    /// Left and right screen margin.
    public static let screenMargin: CGFloat = 20
    /// Gap between cards: 14 to 20 pt.
    public static let cardGapMin: CGFloat = 14
    public static let cardGap: CGFloat = 16
    public static let cardGapMax: CGFloat = 20
    /// Minimum touch target.
    public static let touchTargetMin: CGFloat = 44
    /// Height of the main (Plate) button, which sits at the bottom within thumb reach.
    public static let mainButtonHeight: CGFloat = 56
    /// Height of the secondary button (on the grid, above the touch minimum).
    public static let secondaryButtonHeight: CGFloat = 48

    /// `n` grid units.
    public static func grid(_ n: Int) -> CGFloat { CGFloat(n) * grid }
}

/// Corner radii from pgym-design-style.md, "Shape and spacing".
public enum Radius {
    public static let card: CGFloat = 16
    public static let button: CGFloat = 12
    public static let input: CGFloat = 12
    public static let setCell: CGFloat = 10
    /// Photos keep a small radius so they read as prints.
    public static let photo: CGFloat = 6
    public static let stamp: CGFloat = 6
}

/// Stroke widths. Hairlines use `ColorToken.hairline`, borders use `ColorToken.rail`.
public enum Stroke {
    public static let hairline: CGFloat = 1
    public static let border: CGFloat = 1
    public static let stamp: CGFloat = 2.5
    public static let dayRing: CGFloat = 3
}

/// The stamp is the only thing that is ever rotated.
public enum Rotation {
    /// Allowed stamp tilt, in degrees.
    public static let stampRange: ClosedRange<Double> = 3...8
    /// The stamp on the proof card.
    public static let proofCardStamp: Double = 4
    /// The logo mark.
    public static let logoMark: Double = 8
}

/// The proof card from pgym-design-style.md, "The proof card". Rendering is card I6.
public enum ProofCardSpec {
    /// 4:5 feed size, in pixels.
    public static let feedSize = CGSize(width: 1080, height: 1350)
    /// 9:16 story size, in pixels. Same layout with more space above.
    public static let storySize = CGSize(width: 1080, height: 1920)
    /// Flat Ink scrim opacity.
    public static let scrimOpacity: Double = 0.7
    /// Share of the card height, from the bottom, covered by the scrim.
    public static let scrimCoverage: Double = 0.55
    /// The session name never runs past this many lines.
    public static let titleMaxLines = 2
    /// Numbers on the stat row.
    public static let statCount = 3
}

/// The four photo filters. Applied to the photo only, never to the text.
public enum ProofFilter: String, CaseIterable, Sendable {
    /// Black and white, contrast up, light grain. The default.
    case iron
    /// Slightly warm, contrast down, matte.
    case chalk
    /// Black and white with a Plate duotone wash.
    case plate
    /// No filter.
    case raw

    public static let `default`: ProofFilter = .iron
}
