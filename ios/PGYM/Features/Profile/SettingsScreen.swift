import DesignSystem
import SwiftUI
import UIKit

/// F5 Settings: units, notifications, account email and sign out. Every switch is saved on the phone
/// first and works offline.
struct SettingsScreen: View {
    static let viewID = "F5"

    @Environment(AppSession.self) private var session
    @Environment(AppServices.self) private var services
    @Environment(SessionSyncQueue.self) private var sync
    @Environment(NetworkMonitor.self) private var network
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    @State private var units: NewUserProfile.Units = .kg
    @State private var confirmingSignOut = false
    @State private var signingOut = false
    @State private var verificationSent = false
    @State private var changedTick = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.grid(6)) {
                ScreenTitle(text: ProfileCopy.settings, size: 44)
                unitsSection
                notificationsSection
                accountSection
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.top, Spacing.grid(2))
            .padding(.bottom, Spacing.grid(8))
        }
        .background(Color.ink.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: changedTick)
        .task {
            units = session.profile?.units ?? NewUserProfile.Units(rawValue: WeightUnit.preferred().rawValue) ?? .kg
            // Refreshes the iOS permission state as well.
            await services.reminders.reschedule()
        }
        .confirmationDialog(ProfileCopy.signOutTitle, isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button(ProfileCopy.signOut, role: .destructive) { Task { await signOut() } }
            Button(ProfileCopy.cancel, role: .cancel) {}
        } message: {
            if sync.pendingCount > 0 { Text(ProfileCopy.unsynced(sync.pendingCount)) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.\(Self.viewID)")
    }

    // MARK: Units

    private var unitsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.grid(3)) {
            SectionLabel(ProfileCopy.units)
            HStack(spacing: Spacing.grid(2)) {
                ForEach(NewUserProfile.Units.allCases, id: \.self) { option in
                    Button {
                        guard option != units else { return }
                        withAnimation(Animation.pgymSpring(reduceMotion: reduceMotion)) { units = option }
                        changedTick += 1
                        Task { try? await session.updateUnits(option) }
                    } label: {
                        Text(option.rawValue.uppercased())
                            .font(.pgym(.data, size: 17))
                            .foregroundStyle(units == option ? Color.ink : Color.chalk)
                            .frame(maxWidth: .infinity, minHeight: Spacing.secondaryButtonHeight)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                                    .fill(units == option ? Color.plate : Color.iron)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                                    .strokeBorder(units == option ? Color.plate : Color.rail, lineWidth: Stroke.border)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option == .kg ? "Kilograms" : "Pounds")
                    .accessibilityAddTraits(units == option ? [.isButton, .isSelected] : .isButton)
                    .accessibilityIdentifier("f5.units.\(option.rawValue)")
                }
            }
            Text(ProfileCopy.unitsCaption)
                .pgymText(.body, size: 13)
                .foregroundStyle(Color.steel)
        }
    }

    // MARK: Notifications

    private var notificationsSection: some View {
        let reminders = services.reminders
        return VStack(alignment: .leading, spacing: Spacing.grid(3)) {
            SectionLabel(ProfileCopy.notifications)
            VStack(spacing: 0) {
                toggleRow(ProfileCopy.gymReminders, isOn: reminders.state.remindersEnabled, id: "f5.reminders") { on in
                    Task {
                        if on && !reminders.isAuthorized { await reminders.requestAuthorization() }
                        await reminders.setRemindersEnabled(on)
                    }
                }
                Rectangle().fill(Color.hairline).frame(height: Stroke.hairline)
                toggleRow(ProfileCopy.sundayNudge, isOn: reminders.state.sundayNudgeEnabled, id: "f5.nudge") { on in
                    Task { await reminders.setSundayNudgeEnabled(on) }
                }
            }
            .padding(.horizontal, Spacing.grid(4))
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.iron))

            if !reminders.isAuthorized && (reminders.state.remindersEnabled || reminders.state.sundayNudgeEnabled) {
                HStack {
                    Text(ProfileCopy.iosOff)
                        .pgymText(.body, size: 15)
                        .foregroundStyle(Color.bone)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(ProfileCopy.openSettings) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .font(.pgym(.bodyMedium, size: 15))
                    .foregroundStyle(Color.chalk)
                    .frame(minHeight: Spacing.touchTargetMin)
                    .accessibilityIdentifier("f5.openSettings")
                }
                .accessibilityIdentifier("f5.iosOff")
            }
        }
    }

    private func toggleRow(_ title: String, isOn: Bool, id: String, onChange: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { isOn }, set: { value in
            changedTick += 1
            onChange(value)
        })) {
            Text(title)
                .font(.pgym(.bodyMedium, size: 17))
                .foregroundStyle(Color.chalk)
        }
        .tint(Color.plate)
        .frame(minHeight: Spacing.touchTargetMin + Spacing.grid(2))
        .accessibilityIdentifier(id)
    }

    // MARK: Account

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: Spacing.grid(3)) {
            SectionLabel(ProfileCopy.accountEmail)
            if let email = session.user?.email {
                Text(email)
                    .pgymText(.bodyMedium, size: 17)
                    .foregroundStyle(Color.chalk)
                    .accessibilityIdentifier("f5.email")
            }
            if session.user?.needsEmailVerification == true, let email = session.user?.email {
                InlineNote(
                    text: verificationSent ? AuthCopy.Profile.linkSent(email) : AuthCopy.Profile.notVerified,
                    tone: .info,
                    identifier: "f5.verification"
                )
                if !verificationSent {
                    Button(AuthCopy.Profile.resend) {
                        Task {
                            if (try? await session.resendVerificationEmail()) != nil {
                                withAnimation(Animation.pgymSpring(reduceMotion: reduceMotion)) { verificationSent = true }
                            }
                        }
                    }
                    .font(.pgym(.bodyMedium, size: 15))
                    .foregroundStyle(Color.chalk)
                    .frame(minHeight: Spacing.touchTargetMin)
                }
            }
            Button(ProfileCopy.signOut) { confirmingSignOut = true }
                .buttonStyle(.pgymSecondary)
                .disabled(signingOut)
                .padding(.top, Spacing.grid(2))
                .accessibilityIdentifier("f5.signOut")
        }
    }

    /// Unsynced sessions go up first when there is a connection (copy deck F5: "They sync before you
    /// are signed out").
    private func signOut() async {
        signingOut = true
        defer { signingOut = false }
        if sync.pendingCount > 0 && network.isOnline {
            sync.requestSync()
            await sync.waitUntilIdle()
        }
        try? session.signOut()
    }
}
