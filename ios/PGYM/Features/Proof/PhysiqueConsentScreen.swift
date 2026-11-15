import DesignSystem
import SwiftUI

/// D10 Physique consent. A sheet, shown once from a row on D11 (and later from F6, card I8): what is
/// sent, who sees it, how to turn it off, the disclaimer, Turn on the score and Not now.
/// Off is the default and Not now is the easy way out (pgym-app-copy.md, "Physique consent screen").
/// Under 18 by year of birth: the title, the lead and the age line with Continue, nothing to turn on.
struct PhysiqueConsentScreen: View {
    static let viewID = "D10"

    let isAdult: Bool
    var onTurnOn: () -> Void
    var onNotNow: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.grid(6)) {
                    Text(StampCopy.consentTitle)
                        .pgymText(.display, size: 44)
                        .foregroundStyle(Color.chalk)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, Spacing.grid(8))
                    VStack(alignment: .leading, spacing: Spacing.grid(2)) {
                        paragraph(StampCopy.consentLead1, color: .chalk)
                        paragraph(StampCopy.consentLead2, color: .bone)
                    }
                    if isAdult {
                        section(StampCopy.consentSentLabel, [StampCopy.consentSentBody])
                        section(StampCopy.consentWhoLabel, [StampCopy.consentWho1, StampCopy.consentWho2, StampCopy.consentWho3, StampCopy.consentWho4])
                        section(StampCopy.consentOffLabel, [StampCopy.consentOffBody])
                        paragraph(StampCopy.consentAge, color: .bone)
                        Text(StampCopy.disclaimer)
                            .pgymText(.body, size: 13)
                            .foregroundStyle(Color.steel)
                    } else {
                        paragraph(StampCopy.consentUnder18, color: .bone)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.bottom, Spacing.grid(6))
            }
            VStack(spacing: Spacing.grid(2)) {
                if isAdult {
                    PrimaryButton(StampCopy.consentTurnOn, action: onTurnOn)
                        .accessibilityIdentifier("d10.turnOn")
                    Button(StampCopy.consentNotNow, action: onNotNow)
                        .font(.pgym(.bodyMedium, size: 17))
                        .foregroundStyle(Color.chalk)
                        .frame(maxWidth: .infinity, minHeight: Spacing.touchTargetMin)
                        .accessibilityIdentifier("d10.notNow")
                } else {
                    SecondaryButton(StampCopy.consentContinue, action: onNotNow)
                        .accessibilityIdentifier("d10.continue")
                }
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.vertical, Spacing.grid(3))
        }
        .background(Color.ink.ignoresSafeArea())
        .accessibilityIdentifier(Self.viewID)
    }

    private func paragraph(_ text: String, color: Color) -> some View {
        Text(text)
            .pgymText(.body, size: 17)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func section(_ label: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.grid(2)) {
            Text(label.uppercased())
                .pgymText(.label)
                .foregroundStyle(Color.steel)
                .accessibilityAddTraits(.isHeader)
            ForEach(lines, id: \.self) { line in
                paragraph(line, color: .bone)
            }
        }
    }
}

struct PhysiqueConsentScreen_Previews: PreviewProvider {
    static var previews: some View {
        PhysiqueConsentScreen(isAdult: true, onTurnOn: {}, onNotNow: {})
            .previewDisplayName("D10")
        PhysiqueConsentScreen(isAdult: false, onTurnOn: {}, onNotNow: {})
            .previewDisplayName("D10 under 18")
    }
}
