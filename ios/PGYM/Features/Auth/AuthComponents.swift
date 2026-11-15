import DesignSystem
import SwiftUI

/// The text field used on every sign-in screen: mono label above, Iron well, Rail border that
/// turns Chalk while focused. No system-grey form rows.
struct AuthField: View {
    enum Kind {
        case email
        case password(isNew: Bool)
        case year
        /// Plain text in capitals, for "Type DELETE to confirm".
        case confirmation
    }

    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var kind: Kind
    var isFocused: Bool = false
    var identifier: String

    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.grid(2)) {
            Text(label)
                .pgymText(.label)
                .foregroundStyle(Color.steel)
                .accessibilityHidden(true)

            HStack(spacing: Spacing.grid(2)) {
                input
                    .font(kind.isYear ? Font.pgym(.data, size: 24) : Font.pgym(.body, size: 17))
                    .foregroundStyle(Color.chalk)
                    .tint(Color.plate)
                    .accessibilityLabel(label)
                    .accessibilityIdentifier(identifier)

                if case .password = kind {
                    Button(revealed ? AuthCopy.hide : AuthCopy.show) { revealed.toggle() }
                        .font(.pgym(.bodyMedium, size: 15))
                        .foregroundStyle(Color.bone)
                        .frame(minWidth: Spacing.touchTargetMin, minHeight: Spacing.touchTargetMin)
                        .accessibilityLabel(revealed ? "Hide password" : "Show password")
                }
            }
            .padding(.horizontal, Spacing.grid(4))
            .frame(minHeight: Spacing.mainButtonHeight)
            .background(
                RoundedRectangle(cornerRadius: Radius.input, style: .continuous)
                    .fill(Color.iron)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.input, style: .continuous)
                    .strokeBorder(isFocused ? Color.chalk : Color.rail, lineWidth: Stroke.border)
            )
        }
    }

    @ViewBuilder private var input: some View {
        switch kind {
        case .email:
            TextField("", text: $text, prompt: prompt)
                .keyboardType(.emailAddress)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
        case .password(let isNew):
            Group {
                if revealed {
                    TextField("", text: $text, prompt: prompt)
                } else {
                    SecureField("", text: $text, prompt: prompt)
                }
            }
            .textContentType(isNew ? UITextContentType.newPassword : UITextContentType.password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.go)
        case .year:
            TextField("", text: $text, prompt: prompt)
                .keyboardType(.numberPad)
                .monospacedDigit()
        case .confirmation:
            TextField("", text: $text, prompt: prompt)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.done)
        }
    }

    private var prompt: Text? {
        placeholder.isEmpty ? nil : Text(placeholder).foregroundStyle(Color.steel)
    }
}

private extension AuthField.Kind {
    var isYear: Bool {
        if case .year = self { return true }
        return false
    }
}

/// A one-line message under a form. Problems are stated plainly in Chalk with a Steel mark;
/// nothing in this app is red (AGENTS.md, "Positive only").
struct InlineNote: View {
    enum Tone { case info, problem }

    let text: String
    var tone: Tone = .problem
    var identifier: String = "auth.note"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.grid(2)) {
            Image(systemName: tone == .problem ? "exclamationmark.circle" : "envelope")
                .foregroundStyle(Color.steel)
                .accessibilityHidden(true)
            Text(text)
                .pgymText(.body, size: 15)
                .foregroundStyle(tone == .problem ? Color.chalk : Color.bone)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

/// The Plate main button with a progress mark inside it while its action runs.
struct LoadingPrimaryButton: View {
    let title: String
    var isLoading: Bool
    var identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(isLoading ? 0 : 1)
                if isLoading {
                    ProgressView().tint(Color.ink)
                }
            }
        }
        .buttonStyle(.pgymPrimary)
        .accessibilityLabel(title)
        .accessibilityValue(isLoading ? "In progress" : "")
        .accessibilityIdentifier(identifier)
    }
}

/// F7's destructive button: Chalk outline on Iron. Plate is never used for danger.
struct DestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.pgym(.bodyMedium, size: 17))
            .foregroundStyle(isEnabled ? Color.chalk : Color.steel)
            .frame(maxWidth: .infinity, minHeight: Spacing.mainButtonHeight)
            .background(
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .fill(configuration.isPressed ? Color.rail : Color.iron)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .strokeBorder(isEnabled ? Color.chalk : Color.rail, lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
    }
}

/// The terms line under the sign-in buttons. Links go to the landing site; the domain is a
/// placeholder until it is chosen.
struct LegalLine: View {
    static let termsURL = URL(string: "https://example.com/terms")!
    static let privacyURL = URL(string: "https://example.com/privacy")!

    var body: some View {
        Text(attributed)
            .pgymText(.body, size: 15)
            .foregroundStyle(Color.steel)
            .tint(Color.bone)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private var attributed: AttributedString {
        var line = AttributedString(AuthCopy.legal)
        if let range = line.range(of: AuthCopy.terms) {
            line[range].link = Self.termsURL
        }
        if let range = line.range(of: AuthCopy.privacy) {
            line[range].link = Self.privacyURL
        }
        return line
    }
}

/// Spring for state changes, or none when Reduce Motion is on. Under 600 ms (AGENTS.md).
extension Animation {
    static func pgymSpring(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85)
    }
}

/// The PGYM mark from pgym-logo-spec.md (master cut): plate rim, inner lip, one cut through both,
/// a check that leaves through the cut, tilted 8 degrees. Drawn in the spec's 800-unit box.
struct PGYMMark: View {
    var color: Color = .plate

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 800
            context.translateBy(x: size.width / 2, y: size.height / 2)
            context.scaleBy(x: scale, y: scale)
            context.rotate(by: .degrees(-Rotation.logoMark))

            // Cut from -66 to -18 degrees (SVG angles, y down); the rings run the other way round.
            context.stroke(Self.arc(radius: 300, from: -18, to: 294), with: .color(color),
                           style: StrokeStyle(lineWidth: 72, lineCap: .butt))
            context.stroke(Self.arc(radius: 228, from: -18, to: 294), with: .color(color),
                           style: StrokeStyle(lineWidth: 22, lineCap: .butt))

            var check = Path()
            check.move(to: CGPoint(x: -136, y: 12))
            check.addLine(to: CGPoint(x: -44, y: 104))
            check.addLine(to: CGPoint(x: 245, y: -252.7))
            context.stroke(check, with: .color(color),
                           style: StrokeStyle(lineWidth: 76, lineCap: .round, lineJoin: .round))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// An arc as a polyline, so the direction is the same as the SVG's on a y-down canvas.
    static func arc(radius: CGFloat, from start: Double, to end: Double) -> Path {
        var path = Path()
        let steps = 120
        for i in 0...steps {
            let degrees = start + (end - start) * Double(i) / Double(steps)
            let radians = degrees * .pi / 180
            let point = CGPoint(x: radius * cos(radians), y: radius * sin(radians))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}
