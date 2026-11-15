import DesignSystem
import SwiftUI

/// Mono upper-case label in Steel, used above every section in F2, F3 and D3.
struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .pgymText(.label)
            .foregroundStyle(Color.steel)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Minus, value, plus. 44 pt targets, mono value, adjustable for VoiceOver.
struct CountStepper: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 0) {
            stepButton("minus", enabled: value > range.lowerBound) { value -= 1 }
            Text("\(value)")
                .font(.pgym(.data, size: 17))
                .foregroundStyle(Color.chalk)
                .monospacedDigit()
                .frame(minWidth: 28)
                .contentTransition(.numericText())
            stepButton("plus", enabled: value < range.upperBound) { value += 1 }
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.setCell, style: .continuous).fill(Color.ink)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.setCell, style: .continuous)
                .strokeBorder(Color.rail, lineWidth: Stroke.border)
        )
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if value < range.upperBound { value += 1 }
            case .decrement: if value > range.lowerBound { value -= 1 }
            @unknown default: break
            }
        }
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(enabled ? Color.chalk : Color.rail)
                .frame(width: Spacing.touchTargetMin, height: Spacing.touchTargetMin)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Name over a mono "CHEST · BARBELL" line. Custom exercises get a small tag.
struct ExerciseLabel: View {
    let exercise: Exercise?
    let fallbackName: String

    init(_ exercise: Exercise?, fallbackName: String = "Unknown exercise") {
        self.exercise = exercise
        self.fallbackName = fallbackName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.grid(1)) {
            Text(exercise?.name ?? fallbackName)
                .font(.pgym(.bodyMedium, size: 17))
                .foregroundStyle(Color.chalk)
                .multilineTextAlignment(.leading)
            HStack(spacing: Spacing.grid(2)) {
                if let exercise {
                    Text(exercise.meta)
                        .pgymText(.label)
                        .foregroundStyle(Color.steel)
                    if exercise.isCustom {
                        Text("Yours")
                            .pgymText(.labelBold, size: 10)
                            .foregroundStyle(Color.ink)
                            .padding(.horizontal, Spacing.grid(1) + 2)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.chalk))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A filter chip. Selected: Plate fill with Ink text (never Chalk on Plate).
struct Chip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .pgymText(.labelBold)
                .foregroundStyle(isSelected ? Color.ink : Color.bone)
                .padding(.horizontal, Spacing.grid(3))
                .frame(minHeight: 36)
                .background(Capsule().fill(isSelected ? Color.plate : Color.iron))
                .overlay(Capsule().strokeBorder(isSelected ? Color.clear : Color.rail, lineWidth: Stroke.border))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(minHeight: Spacing.touchTargetMin)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Iron card background used by rows in F2 and F3.
struct IronCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Spacing.grid(4))
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.iron))
    }
}

extension View {
    func ironCard() -> some View { modifier(IronCard()) }

    /// A List row that shows a designed card instead of a system cell.
    func designedListRow(top: CGFloat = Spacing.grid(1) + 2, bottom: CGFloat = Spacing.grid(1) + 2) -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: top, leading: Spacing.screenMargin, bottom: bottom, trailing: Spacing.screenMargin))
    }
}
