import DesignSystem
import SwiftUI

/// B3 Reminders: why one reminder per gym day, a drawn preview of it, the three rules, then the
/// iOS prompt. iOS gives no custom text on its prompt, so the reason has to be here.
struct RemindersScreen: View {
    static let viewID = "B3"

    let model: OnboardingModel

    @Environment(AppServices.self) private var services
    @State private var asking = false

    var body: some View {
        OnboardingScreen(viewID: Self.viewID) {
            OnboardingTitle(text: OnboardingCopy.Reminders.title)

            NotificationPreview(title: model.previewTitle, message: model.previewBody)

            Text(OnboardingCopy.Reminders.body(time: model.draft.time.formatted()))
                .pgymText(.body, size: 17)
                .foregroundStyle(Color.bone)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Spacing.grid(3)) {
                Rule(symbol: "moon.zzz", text: OnboardingCopy.Reminders.quiet)
                Rule(symbol: "speaker.zzz", text: OnboardingCopy.Reminders.backOff)
            }
        } footer: {
            LoadingPrimaryButton(title: OnboardingCopy.Reminders.button, isLoading: asking, identifier: "b3.turnOn") {
                guard !asking else { return }
                asking = true
                Task {
                    await model.turnOnReminders(services.reminders)
                    asking = false
                }
            }
            OnboardingLink(title: OnboardingCopy.Reminders.skip, identifier: "b3.skip") {
                model.skipReminders()
            }
        }
    }
}

/// A lock-screen style banner: the app mark, PGYM, "now", then the real reminder title and body.
private struct NotificationPreview: View {
    let title: String
    let message: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.grid(3)) {
            PGYMMark()
                .frame(width: 36, height: 36)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.ink))
            VStack(alignment: .leading, spacing: Spacing.grid(1)) {
                HStack {
                    Text(OnboardingCopy.Reminders.previewApp)
                        .pgymText(.labelBold, size: 11)
                        .foregroundStyle(Color.steel)
                    Spacer()
                    Text(OnboardingCopy.Reminders.previewWhen)
                        .pgymText(.label, size: 10)
                        .foregroundStyle(Color.steel)
                }
                Text(title)
                    .pgymText(.bodyMedium, size: 16)
                    .foregroundStyle(Color.chalk)
                Text(message)
                    .pgymText(.body, size: 15)
                    .foregroundStyle(Color.bone)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.grid(4))
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.iron))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.rail, lineWidth: Stroke.hairline))
        .offset(y: shown || reduceMotion ? 0 : -16)
        .opacity(shown || reduceMotion ? 1 : 0)
        .onAppear {
            withAnimation(Animation.pgymSpring(reduceMotion: reduceMotion)?.delay(0.15)) { shown = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Example reminder. \(title). \(message)")
        .accessibilityIdentifier("b3.preview")
    }
}

private struct Rule: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.grid(3)) {
            Image(systemName: symbol)
                .foregroundStyle(Color.plate)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .pgymText(.body, size: 16)
                .foregroundStyle(Color.chalk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
