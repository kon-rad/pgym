import DesignSystem
import SwiftUI

/// B4 First routine: three starters, the one that fits the goal pre-selected and tagged, or
/// Build my own. The main button saves everything and opens Today.
struct FirstRoutineScreen: View {
    static let viewID = "B4"

    let model: OnboardingModel

    @Environment(AppSession.self) private var session
    @Environment(AppServices.self) private var services
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var finished = 0

    var body: some View {
        OnboardingScreen(viewID: Self.viewID) {
            if model.showsRemindersDeclined {
                InlineNote(text: OnboardingCopy.Reminders.declined, tone: .problem, identifier: "b4.remindersOff")
            }

            OnboardingTitle(text: OnboardingCopy.Routine.title)

            VStack(spacing: Spacing.cardGap) {
                ForEach(StarterRoutine.allCases) { starter in
                    StarterCard(
                        starter: starter,
                        isSelected: model.selectedStarter == starter,
                        fitsTag: starter == model.suggestedStarter ? OnboardingCopy.Routine.fits(goal: model.goal) : nil
                    ) {
                        model.pickStarter(starter)
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: model.selectedStarter)

            Text(OnboardingCopy.Routine.hint)
                .pgymText(.body, size: 15)
                .foregroundStyle(Color.steel)

            if let error = model.errorText {
                InlineNote(text: error, identifier: "b4.error")
            }
        } footer: {
            LoadingPrimaryButton(title: OnboardingCopy.Routine.button, isLoading: model.isSaving, identifier: "b4.use") {
                Task {
                    await model.finish(session: session, scheduler: services.reminders)
                    if model.errorText == nil { finished += 1 }
                }
            }
            .sensoryFeedback(.success, trigger: finished)
            OnboardingLink(title: OnboardingCopy.Routine.buildOwn, identifier: "b4.buildOwn") {
                Task { await model.finish(buildOwn: true, session: session, scheduler: services.reminders) }
            }
            .disabled(model.isSaving)
        }
        .animation(Animation.pgymSpring(reduceMotion: reduceMotion), value: model.errorText)
    }
}

/// One starter: name, how many workouts rotate, the first exercises, and the "Fits 4 days" tag.
private struct StarterCard: View {
    let starter: StarterRoutine
    let isSelected: Bool
    let fitsTag: String?
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Spacing.grid(3)) {
                VStack(alignment: .leading, spacing: Spacing.grid(2)) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.grid(2)) {
                        Text(starter.title)
                            .pgymText(.title)
                            .foregroundStyle(Color.chalk)
                        if let fitsTag {
                            Text(fitsTag)
                                .pgymText(.labelBold, size: 10)
                                .foregroundStyle(Color.ink)
                                .padding(.horizontal, Spacing.grid(2))
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.plate))
                        }
                    }
                    Text(starter.caption)
                        .pgymText(.body, size: 15)
                        .foregroundStyle(Color.bone)
                    Text(starter.summary)
                        .pgymText(.label, size: 10)
                        .foregroundStyle(Color.steel)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.plate : Color.rail)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(Spacing.grid(4))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.iron))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(isSelected ? Color.plate : Color.rail, lineWidth: isSelected ? 2 : Stroke.border)
            )
            .animation(Animation.pgymSpring(reduceMotion: reduceMotion), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("b4.starter.\(starter.rawValue)")
    }
}
