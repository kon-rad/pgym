import DesignSystem
import SwiftUI

/// B2 Gym days and time: seven day toggles, Monday first, pre-filled with a spread that matches
/// the goal; one time for every day. Continue stays off until the count matches the goal.
struct GymDaysScreen: View {
    static let viewID = "B2"

    let model: OnboardingModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        OnboardingScreen(viewID: Self.viewID) {
            OnboardingTitle(text: OnboardingCopy.Days.title)

            Text(OnboardingCopy.Days.body(goal: model.goal))
                .pgymText(.body, size: 17)
                .foregroundStyle(Color.bone)

            VStack(alignment: .leading, spacing: Spacing.grid(3)) {
                HStack(spacing: Spacing.grid(1)) {
                    ForEach(Weekday.allCases, id: \.self) { day in
                        DayToggle(day: day, isOn: model.draft.days.contains(day)) {
                            model.toggle(day)
                        }
                    }
                }
                .sensoryFeedback(.selection, trigger: model.draft.days)

                HStack {
                    Text(model.counterText)
                        .pgymText(.labelBold, size: 12)
                        .foregroundStyle(model.daysMatchGoal ? Color.plate : Color.steel)
                        .contentTransition(.numericText(value: Double(model.pickedCount)))
                        .accessibilityIdentifier("b2.counter")
                    Spacer()
                }
                .animation(Animation.pgymSpring(reduceMotion: reduceMotion), value: model.pickedCount)

                if model.isOverGoal {
                    InlineNote(text: OnboardingCopy.Days.tooMany(goal: model.goal), identifier: "b2.tooMany")
                } else if !model.daysMatchGoal {
                    Text(OnboardingCopy.Days.pickMore(model.goal - model.pickedCount))
                        .pgymText(.body, size: 15)
                        .foregroundStyle(Color.bone)
                        .transition(.opacity)
                        .accessibilityIdentifier("b2.pickMore")
                }
            }
            .animation(Animation.pgymSpring(reduceMotion: reduceMotion), value: model.isOverGoal)

            TimeCard(time: model.draft.time) { model.setTime($0) }
        } footer: {
            Button(OnboardingCopy.Days.button) { model.continueFromDays() }
                .buttonStyle(.pgymPrimary)
                .disabled(!model.daysMatchGoal)
                .accessibilityIdentifier("b2.continue")
            OnboardingLink(title: OnboardingCopy.Days.changeGoal, identifier: "b2.changeGoal") {
                model.changeGoal()
            }
        }
    }
}

/// One day: a tall pill with the three-letter name. On: Plate with Ink text.
struct DayToggle: View {
    let day: Weekday
    let isOn: Bool
    var identifierPrefix = "b2"
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.grid(2)) {
                Text(day.short)
                    .pgymText(.labelBold, size: 11)
                Image(systemName: isOn ? "checkmark" : "plus")
                    .font(.system(size: 13, weight: .heavy))
                    .contentTransition(.symbolEffect(.replace))
            }
            .foregroundStyle(isOn ? Color.ink : Color.bone)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(
                RoundedRectangle(cornerRadius: Radius.setCell, style: .continuous)
                    .fill(isOn ? Color.plate : Color.iron)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.setCell, style: .continuous)
                    .strokeBorder(isOn ? Color.plate : Color.rail, lineWidth: Stroke.border)
            )
            .animation(Animation.pgymSpring(reduceMotion: reduceMotion), value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.full)
        .accessibilityValue(isOn ? "Gym day" : "Rest day")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("\(identifierPrefix).day.\(day.rawValue)")
    }
}

/// "Usual time" with a wheel, on an Iron card.
struct TimeCard: View {
    let time: ReminderTime
    var label: String = OnboardingCopy.Days.timeLabel
    var identifier = "b2.time"
    let onChange: (ReminderTime) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.grid(2)) {
            Text(label)
                .pgymText(.label)
                .foregroundStyle(Color.steel)
                .accessibilityHidden(true)
            DatePicker(
                label,
                selection: Binding(get: { Self.date(for: time) }, set: { onChange(Self.time(for: $0)) }),
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .colorScheme(.dark)
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .clipped()
            .accessibilityIdentifier(identifier)
        }
        .padding(Spacing.grid(4))
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.iron))
    }

    private static func date(for time: ReminderTime) -> Date {
        Calendar.current.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: .now) ?? .now
    }

    private static func time(for date: Date) -> ReminderTime {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return ReminderTime(hour: parts.hour ?? 18, minute: parts.minute ?? 0)
    }
}
