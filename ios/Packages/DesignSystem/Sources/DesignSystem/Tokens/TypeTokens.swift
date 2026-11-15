import SwiftUI

/// The three bundled faces (all SIL Open Font Licence 1.1, licences in Resources/Fonts).
/// Raw values are PostScript names, which is what `Font.custom` and CoreText look up.
public enum FontFace: String, CaseIterable, Sendable {
    case antonRegular = "Anton-Regular"
    case archivoRegular = "Archivo-Regular"
    case archivoMedium = "Archivo-Medium"
    case archivoBold = "Archivo-Bold"
    case jetBrainsMonoRegular = "JetBrainsMono-Regular"
    case jetBrainsMonoBold = "JetBrainsMono-Bold"

    public var postScriptName: String { rawValue }
    /// File name inside `Resources/Fonts`, without extension.
    public var fileName: String { rawValue }
}

/// The type roles in pgym-design-style.md, "Type".
public enum TypeRole: String, CaseIterable, Sendable {
    /// Anton 400, 44 to 76 pt, upper case, line height 0.95 to 1.0. Screen titles, card headline, hero numbers.
    case display
    /// Anton 400, 20 pt, upper case, tracking 1. Main button only.
    case button
    /// Archivo 700, 19 pt. Exercise names.
    case title
    /// Archivo 400, 15 to 17 pt, line height 1.45.
    case body
    /// Archivo 500, 15 to 17 pt, line height 1.45.
    case bodyMedium
    /// JetBrains Mono 400, 10 to 12 pt, upper case, tracking 1 to 1.5. Section labels, units.
    case label
    /// JetBrains Mono 700, 10 to 12 pt, upper case, tracking 1 to 1.5.
    case labelBold
    /// JetBrains Mono 700, 15 to 24 pt. Weights, reps, timers, timestamps.
    case data

    public var face: FontFace {
        switch self {
        case .display, .button: .antonRegular
        case .title: .archivoBold
        case .body: .archivoRegular
        case .bodyMedium: .archivoMedium
        case .label: .jetBrainsMonoRegular
        case .labelBold, .data: .jetBrainsMonoBold
        }
    }

    /// Allowed point sizes from the style guide.
    public var sizeRange: ClosedRange<CGFloat> {
        switch self {
        case .display: 44...76
        case .button: 20...20
        case .title: 19...19
        case .body, .bodyMedium: 15...17
        case .label, .labelBold: 10...12
        case .data: 15...24
        }
    }

    /// The size used when a call site does not pick one.
    public var defaultSize: CGFloat {
        switch self {
        case .display: 56
        case .button: 20
        case .title: 19
        case .body, .bodyMedium: 16
        case .label, .labelBold: 11
        case .data: 17
        }
    }

    /// Letter spacing in points.
    public var tracking: CGFloat {
        switch self {
        case .button: 1
        case .label, .labelBold: 1.2
        default: 0
        }
    }

    /// Line height as a multiple of the point size.
    public var lineHeight: CGFloat {
        switch self {
        case .display: 0.95
        case .body, .bodyMedium: 1.45
        default: 1.2
        }
    }

    public var isUppercase: Bool {
        switch self {
        case .display, .button, .label, .labelBold: true
        default: false
        }
    }

    /// Dynamic Type anchor. Archivo and the mono scale with the system setting;
    /// Anton titles scale less (the style guide allows one step, then wrap).
    public var textStyle: Font.TextStyle {
        switch self {
        case .display: .largeTitle
        case .button: .title3
        case .title: .headline
        case .body, .bodyMedium: .body
        case .label, .labelBold: .caption2
        case .data: .body
        }
    }

    /// The largest Dynamic Type size the role follows. Anton display titles scale one step past the
    /// default and then wrap (pgym-flow-spec.md, "Dynamic Type at the largest size"); everything else
    /// follows the system all the way to Accessibility XXXL.
    public var maxDynamicTypeSize: DynamicTypeSize {
        switch self {
        case .display: .xLarge
        default: .accessibility5
        }
    }
}

public extension Font {
    /// A PGYM type role at its default size, or at `size` clamped into the role's range.
    static func pgym(_ role: TypeRole, size: CGFloat? = nil) -> Font {
        let s = size.map { min(max($0, role.sizeRange.lowerBound), role.sizeRange.upperBound) } ?? role.defaultSize
        return .custom(role.face.postScriptName, size: s, relativeTo: role.textStyle)
    }
}

private struct PGYMTextModifier: ViewModifier {
    let role: TypeRole
    let size: CGFloat?

    func body(content: Content) -> some View {
        let s = size ?? role.defaultSize
        content
            .font(.pgym(role, size: size))
            .tracking(role.tracking)
            .textCase(role.isUppercase ? .uppercase : nil)
            // SwiftUI cannot tighten below the font's own line height, so roles under 1.0 get 0.
            .lineSpacing(max(0, s * (role.lineHeight - 1)))
            .dynamicTypeSize(...role.maxDynamicTypeSize)
    }
}

public extension View {
    /// Applies face, size, tracking, case and line spacing for a type role.
    func pgymText(_ role: TypeRole, size: CGFloat? = nil) -> some View {
        modifier(PGYMTextModifier(role: role, size: size))
    }
}
