import SwiftUI

/// Every colour in pgym-design-style.md, "Colour". Dark only in v1.
///
/// Rules the tokens carry (enforced by review, checked in tests where a number exists):
/// - Plate carries Ink text, never Chalk text.
/// - Plate means "done" or "do this". It is never an error colour.
/// - One Plate button per screen.
public enum ColorToken: String, CaseIterable, Sendable {
    /// `#0B0B0C` App background, text on Chalk and on Plate.
    case ink
    /// `#17171A` Cards and raised surfaces on Ink.
    case iron
    /// `#34343A` Borders, empty day rings, dividers.
    case rail
    /// `#26262B` Hairlines (the thin variant of Rail).
    case hairline
    /// `#A3A3AC` Secondary labels on Ink.
    case steel
    /// `#C9C7C1` Body copy on Ink.
    case bone
    /// `#F2EFE8` Primary text on Ink; the light card surface.
    case chalk
    /// `#FF4D1F` The one accent: stamps, done states, the main button.
    case plate
    /// `#2A2A2F` Placeholder behind a photo while it loads.
    case photo

    /// The sRGB value as `0xRRGGBB`.
    public var hex: UInt32 {
        switch self {
        case .ink: 0x0B0B0C
        case .iron: 0x17171A
        case .rail: 0x34343A
        case .hairline: 0x26262B
        case .steel: 0xA3A3AC
        case .bone: 0xC9C7C1
        case .chalk: 0xF2EFE8
        case .plate: 0xFF4D1F
        case .photo: 0x2A2A2F
        }
    }

    public var color: Color { Color(hex: hex) }

    /// WCAG 2.x relative luminance of the token.
    public var relativeLuminance: Double {
        func channel(_ shift: UInt32) -> Double {
            let c = Double((hex >> shift) & 0xFF) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }

    /// WCAG contrast ratio between two tokens (1 to 21).
    public static func contrast(_ a: ColorToken, _ b: ColorToken) -> Double {
        let (l1, l2) = (a.relativeLuminance, b.relativeLuminance)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }
}

public extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// `Color.ink`, `.foregroundStyle(.chalk)` and so on.
public extension ShapeStyle where Self == Color {
    static var ink: Color { ColorToken.ink.color }
    static var iron: Color { ColorToken.iron.color }
    static var rail: Color { ColorToken.rail.color }
    static var hairline: Color { ColorToken.hairline.color }
    static var steel: Color { ColorToken.steel.color }
    static var bone: Color { ColorToken.bone.color }
    static var chalk: Color { ColorToken.chalk.color }
    static var plate: Color { ColorToken.plate.color }
    static var photo: Color { ColorToken.photo.color }
}
