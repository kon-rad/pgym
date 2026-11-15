import SwiftUI

/// The main button: Plate fill, Ink text in Anton 20 upper case, 56 pt high, radius 12.
/// One per screen. Plate means "do this"; never use it for a destructive action.
public struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .pgymText(.button)
            .foregroundStyle(isEnabled ? Color.ink : Color.steel)
            .frame(maxWidth: .infinity, minHeight: Spacing.mainButtonHeight)
            .background(
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .fill(isEnabled ? Color.plate : Color.rail)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
    }
}

/// Everything that is not the main action: Iron fill, Rail border, Chalk text in Archivo 500 17 pt, 48 pt high.
public struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.pgym(.bodyMedium, size: 17))
            .foregroundStyle(isEnabled ? Color.chalk : Color.steel)
            .frame(maxWidth: .infinity, minHeight: Spacing.secondaryButtonHeight)
            .background(
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .fill(configuration.isPressed ? Color.rail : Color.iron)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .strokeBorder(Color.rail, lineWidth: Stroke.border)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
    }
}

public extension ButtonStyle where Self == PrimaryButtonStyle {
    static var pgymPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

public extension ButtonStyle where Self == SecondaryButtonStyle {
    static var pgymSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

/// `PrimaryButton("Start session") { ... }`
public struct PrimaryButton: View {
    private let title: String
    private let action: () -> Void

    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(title, action: action).buttonStyle(.pgymPrimary)
    }
}

/// `SecondaryButton("Retake") { ... }`
public struct SecondaryButton: View {
    private let title: String
    private let action: () -> Void

    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(title, action: action).buttonStyle(.pgymSecondary)
    }
}

struct Buttons_Previews: PreviewProvider {
    static var previews: some View {
        PreviewSurface {
            VStack(spacing: Spacing.cardGap) {
                PrimaryButton("Start session") {}
                PrimaryButton("Stamp it") {}.disabled(true)
                SecondaryButton("Retake") {}
                SecondaryButton("Train anyway") {}.disabled(true)
            }
        }
        .previewDisplayName("Buttons")
    }
}
