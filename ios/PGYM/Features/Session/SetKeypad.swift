import DesignSystem
import SwiftUI

enum KeypadField: Equatable {
    case weight, reps
}

/// The in-app keypad's text, without any view. The value is selected when the keypad opens, so the
/// first digit replaces it: typing 85 over 80 gives 85, not 8085 (pgym-flow-spec.md, "The keypad").
struct KeypadState: Equatable {
    var setID: String
    var field: KeypadField
    var text: String
    /// The text the keypad opened with. If it is unchanged at commit, nothing is written, so a weight
    /// shown in pounds is never rewritten from its rounded display value.
    var original: String
    var replacesOnType: Bool = true

    static let maxLength = 6

    init(setID: String, field: KeypadField, text: String) {
        self.setID = setID
        self.field = field
        self.text = text
        self.original = text
    }

    var isEdited: Bool { text != original }

    mutating func type(_ digit: Int) {
        guard (0...9).contains(digit) else { return }
        if replacesOnType { text = "" }
        replacesOnType = false
        if text == "0" { text = "" }
        guard text.count < Self.maxLength else { return }
        if let dot = text.firstIndex(of: "."), text.distance(from: dot, to: text.endIndex) > 2 { return }
        text += String(digit)
    }

    mutating func decimal() {
        guard field == .weight else { return }
        if replacesOnType { text = "" }
        replacesOnType = false
        guard !text.contains(".") else { return }
        text = text.isEmpty ? "0." : text + "."
    }

    mutating func backspace() {
        if replacesOnType {
            text = ""
            replacesOnType = false
            return
        }
        if !text.isEmpty { text.removeLast() }
    }

    /// Plus or minus one step in the shown unit (2.5 kg, 5 lb, 1 rep). Never below zero.
    mutating func step(_ direction: Int, unit: WeightUnit) {
        replacesOnType = true
        switch field {
        case .weight:
            let current = WeightUnit.parse(text) ?? 0
            let next = max(0, current + Double(direction) * unit.step)
            text = WeightUnit.format(next, fractionDigits: unit.fractionDigits)
        case .reps:
            let current = Int(text) ?? 0
            text = String(max(0, current + direction))
        }
    }

    /// The typed weight in kilograms; nil when the field is empty.
    func weightKg(unit: WeightUnit) -> Double? {
        WeightUnit.parse(text).map { unit.kilograms(fromDisplay: WeightUnit.round($0, fractionDigits: unit.fractionDigits)) }
    }

    var reps: Int? { Int(text) }
}

/// The keypad: rises from the bottom so every key is in thumb reach. Header with the value, a step
/// row, digits, and a bottom row with the other field and Log set.
struct SetKeypad: View {
    @Binding var state: KeypadState
    let unit: WeightUnit
    let onSwitchField: () -> Void
    let onLogSet: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var keyHeight: CGFloat { typeSize.isAccessibilitySize ? 64 : 52 }

    var body: some View {
        VStack(spacing: Spacing.grid(2)) {
            header
            stepRow
            digits
            bottomRow
        }
        .padding(.horizontal, Spacing.grid(3))
        .padding(.top, Spacing.grid(3))
        .padding(.bottom, Spacing.grid(2))
        .background(
            UnevenRoundedRectangle(topLeadingRadius: Radius.card, topTrailingRadius: Radius.card, style: .continuous)
                .fill(Color.iron)
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) {
            Rectangle().fill(Color.hairline).frame(height: Stroke.hairline)
        }
        .sensoryFeedback(.selection, trigger: state.text)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("d2.keypad")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(state.field == .weight ? SessionCopy.keypadWeightHeader(unit) : SessionCopy.keypadRepsHeader)
                .pgymText(.label)
                .foregroundStyle(Color.steel)
            Spacer()
            Text(state.text.isEmpty ? "0" : state.text)
                .font(.pgym(.data, size: 24))
                .foregroundStyle(state.text.isEmpty ? Color.steel : Color.chalk)
                .padding(.horizontal, Spacing.grid(2))
                .background(
                    RoundedRectangle(cornerRadius: Radius.stamp, style: .continuous)
                        .fill(state.replacesOnType && !state.text.isEmpty ? Color.rail : Color.clear)
                )
                .contentTransition(.numericText())
                .accessibilityIdentifier("d2.keypad.value")
        }
        .padding(.horizontal, Spacing.grid(1))
    }

    private var stepRow: some View {
        HStack(spacing: Spacing.grid(2)) {
            if state.field == .weight {
                let step = WeightUnit.format(unit.step, fractionDigits: unit.fractionDigits)
                key("-\(step)", label: SessionCopy.a11yStep(step, unit: unit, up: false), repeats: true) { state.step(-1, unit: unit) }
                key("+\(step)", label: SessionCopy.a11yStep(step, unit: unit, up: true), repeats: true) { state.step(1, unit: unit) }
            } else {
                key("-1", label: SessionCopy.a11yRepStep(up: false), repeats: true) { state.step(-1, unit: unit) }
                key("+1", label: SessionCopy.a11yRepStep(up: true), repeats: true) { state.step(1, unit: unit) }
            }
        }
    }

    private var digits: some View {
        VStack(spacing: Spacing.grid(2)) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: Spacing.grid(2)) {
                    ForEach(1...3, id: \.self) { col in
                        let digit = row * 3 + col
                        key("\(digit)", label: "\(digit)") { state.type(digit) }
                    }
                }
            }
            HStack(spacing: Spacing.grid(2)) {
                if state.field == .weight {
                    key(".", label: SessionCopy.a11yDecimal) { state.decimal() }
                } else {
                    Color.clear.frame(maxWidth: .infinity, minHeight: keyHeight)
                }
                key("0", label: "0") { state.type(0) }
                Button { state.backspace() } label: {
                    Image(systemName: "delete.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.chalk)
                        .frame(maxWidth: .infinity, minHeight: keyHeight)
                        .background(keyShape.fill(Color.ink))
                        .contentShape(keyShape)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(SessionCopy.a11yDelete)
            }
        }
    }

    private var bottomRow: some View {
        HStack(spacing: Spacing.grid(2)) {
            Button(state.field == .weight ? SessionCopy.repsKey : SessionCopy.weightKey, action: onSwitchField)
                .buttonStyle(.pgymSecondary)
                .frame(maxWidth: 120)
                .accessibilityIdentifier("d2.keypad.switch")
            Button(SessionCopy.logSet, action: onLogSet)
                .buttonStyle(.pgymPrimary)
                .accessibilityIdentifier("d2.keypad.log")
        }
    }

    private var keyShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.setCell, style: .continuous)
    }

    private func key(_ title: String, label: String, repeats: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.pgym(.data, size: 20))
                .foregroundStyle(Color.chalk)
                .frame(maxWidth: .infinity, minHeight: keyHeight)
                .background(keyShape.fill(Color.ink))
                .overlay(keyShape.strokeBorder(Color.hairline, lineWidth: Stroke.hairline))
                .contentShape(keyShape)
        }
        .buttonStyle(KeyPressStyle())
        .buttonRepeatBehavior(repeats ? .enabled : .automatic)
        .accessibilityLabel(label)
    }
}

/// A key dims while held: feedback without a colour that could read as an error.
private struct KeyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
