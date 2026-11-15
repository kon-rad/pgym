import DesignSystem
import SwiftUI

/// B1 Weekly goal: the commitment. Five big numbers, 2 to 6, none picked at first; the sentence
/// "I will train 4 days a week." updates live; B5's units chip; Lock it in.
struct WeeklyGoalScreen: View {
    static let viewID = "B1"

    let model: OnboardingModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lockedIn = 0

    var body: some View {
        OnboardingScreen(viewID: Self.viewID) {
            OnboardingTitle(text: OnboardingCopy.Goal.title)

            HStack(spacing: Spacing.grid(2)) {
                ForEach(Array(GoalPolicy.range), id: \.self) { goal in
                    GoalTile(goal: goal, isSelected: model.draft.goal == goal) {
                        model.pickGoal(goal)
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: model.draft.goal)

            CommitmentSentence(goal: model.draft.goal)
                .animation(Animation.pgymSpring(reduceMotion: reduceMotion), value: model.draft.goal)

            Text(OnboardingCopy.Goal.hint)
                .pgymText(.body, size: 15)
                .foregroundStyle(Color.steel)
                .fixedSize(horizontal: false, vertical: true)

            UnitsChip(units: model.draft.units) { model.toggleUnits() }
        } footer: {
            Button(OnboardingCopy.Goal.button) {
                lockedIn += 1
                model.lockIn()
            }
            .buttonStyle(.pgymPrimary)
            .disabled(!model.canLockIn)
            .accessibilityIdentifier("b1.lockIn")
            .sensoryFeedback(.success, trigger: lockedIn)
        }
    }
}

/// One number on B1. Picked: Plate with Ink text, a little larger. Otherwise Iron with a Rail edge.
private struct GoalTile: View {
    let goal: Int
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.grid(1)) {
                Text("\(goal)")
                    .pgymText(.display, size: 44)
                Text(OnboardingCopy.Goal.optionCaption)
                    .pgymText(.label, size: 10)
                    .opacity(isSelected ? 1 : 0)
            }
            .foregroundStyle(isSelected ? Color.ink : Color.chalk)
            .frame(maxWidth: .infinity, minHeight: 88)
            .background(
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .fill(isSelected ? Color.plate : Color.iron)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .strokeBorder(isSelected ? Color.plate : Color.rail, lineWidth: Stroke.border)
            )
            .scaleEffect(isSelected && !reduceMotion ? 1.06 : 1)
            .animation(Animation.pgymSpring(reduceMotion: reduceMotion), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(goal) days a week")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("b1.goal.\(goal)")
    }
}

/// "I will train 4 days a week." The number is in Plate; it rolls when it changes.
private struct CommitmentSentence: View {
    let goal: Int?

    var body: some View {
        Group {
            if let goal {
                (Text("I will train ") + Text("\(goal)").foregroundColor(Color.plate) + Text(" days a week."))
                    .contentTransition(.numericText(value: Double(goal)))
                    .accessibilityLabel(OnboardingCopy.Goal.commitment(goal))
            } else {
                Text(OnboardingCopy.Goal.commitmentEmpty)
                    .foregroundStyle(Color.steel)
            }
        }
        .font(.pgym(.title, size: 19))
        .foregroundStyle(Color.chalk)
        .padding(Spacing.grid(4))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.iron))
        .overlay(alignment: .leading) {
            Rectangle().fill(goal == nil ? Color.rail : Color.plate).frame(width: 4)
                .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityIdentifier("b1.commitment")
    }
}

/// B5 Units, as the flow spec's one-tap chip on B1: "Weights in kg. Change".
struct UnitsChip: View {
    static let viewID = "B5"

    let units: NewUserProfile.Units
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: Spacing.grid(2)) {
                Image(systemName: "scalemass")
                    .foregroundStyle(Color.steel)
                Text(OnboardingCopy.Units.chip(units))
                    .pgymText(.bodyMedium, size: 15)
                    .foregroundStyle(Color.chalk)
                    .contentTransition(.interpolate)
                Text(OnboardingCopy.Units.change)
                    .pgymText(.labelBold, size: 11)
                    .foregroundStyle(Color.plate)
            }
            .padding(.horizontal, Spacing.grid(4))
            .frame(minHeight: Spacing.touchTargetMin)
            .background(Capsule().fill(Color.iron))
            .overlay(Capsule().strokeBorder(Color.rail, lineWidth: Stroke.border))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: units)
        .accessibilityLabel(OnboardingCopy.Units.accessibility(units))
        .accessibilityHint(OnboardingCopy.Units.accessibilityHint)
        .accessibilityIdentifier("screen.\(Self.viewID)")
    }
}
