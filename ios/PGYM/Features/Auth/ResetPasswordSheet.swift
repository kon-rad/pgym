import DesignSystem
import Observation
import SwiftUI

/// A4 Reset password, as a sheet over A2. The confirmation never says whether the account exists.
@MainActor
@Observable
final class ResetPasswordViewModel {
    var email: String
    private(set) var isSending = false
    private(set) var sentTo: String?
    private(set) var errorText: String?

    init(email: String = "") {
        self.email = email
    }

    func send(session: AppSession) async {
        guard !isSending else { return }
        let address = email.trimmingCharacters(in: .whitespaces)
        guard EmailFormat.isPlausible(address) else {
            errorText = AuthCopy.invalidEmail
            return
        }
        errorText = nil
        isSending = true
        defer { isSending = false }
        do {
            try await session.sendPasswordReset(email: address)
            sentTo = address
        } catch {
            switch AuthFailure(error) {
            case .invalidEmail: errorText = AuthCopy.invalidEmail
            case .network: errorText = AuthCopy.noConnection
            case .tooManyRequests: errorText = AuthCopy.Email.tooManyTries
            // Anything else could hint at whether the account exists; show the same confirmation.
            default: sentTo = address
            }
        }
    }
}

struct ResetPasswordSheet: View {
    static let viewID = "A4"

    @Environment(AppSession.self) private var session
    @Environment(NetworkMonitor.self) private var network
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var model: ResetPasswordViewModel
    @FocusState private var emailFocused: Bool

    init(email: String) {
        _model = State(initialValue: ResetPasswordViewModel(email: email))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.grid(6)) {
            if let sentTo = model.sentTo {
                sent(sentTo)
                    .transition(.opacity)
            } else {
                form
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.top, Spacing.grid(8))
        .padding(.bottom, Spacing.grid(4))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.ink.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.ink)
        .animation(Animation.pgymSpring(reduceMotion: reduceMotion), value: model.sentTo)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.\(Self.viewID)")
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Spacing.grid(5)) {
            Text(AuthCopy.Reset.title)
                .pgymText(.display, size: 44)
                .foregroundStyle(Color.chalk)
                .accessibilityAddTraits(.isHeader)

            Text(AuthCopy.Reset.body)
                .pgymText(.body, size: 17)
                .foregroundStyle(Color.bone)
                .fixedSize(horizontal: false, vertical: true)

            AuthField(
                label: AuthCopy.emailLabel,
                text: $model.email,
                placeholder: AuthCopy.emailPlaceholder,
                kind: .email,
                isFocused: emailFocused,
                identifier: "reset.email"
            )
            .focused($emailFocused)
            .onSubmit { Task { await model.send(session: session) } }
            .disabled(model.isSending)

            if !network.isOnline {
                InlineNote(text: AuthCopy.noConnection)
            } else if let error = model.errorText {
                InlineNote(text: error, identifier: "reset.error")
            }

            LoadingPrimaryButton(title: AuthCopy.Reset.send, isLoading: model.isSending, identifier: "reset.send") {
                Task { await model.send(session: session) }
            }
            .disabled(model.email.isEmpty || !network.isOnline)
        }
        .onAppear { emailFocused = model.email.isEmpty }
    }

    private func sent(_ address: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.grid(5)) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Color.plate)
                .accessibilityHidden(true)

            Text(AuthCopy.Reset.sentTitle)
                .pgymText(.display, size: 44)
                .foregroundStyle(Color.chalk)
                .accessibilityAddTraits(.isHeader)

            Text(AuthCopy.Reset.sentBody(address))
                .pgymText(.body, size: 17)
                .foregroundStyle(Color.bone)
                .fixedSize(horizontal: false, vertical: true)

            PrimaryButton(AuthCopy.Reset.back) { dismiss() }
                .accessibilityIdentifier("reset.done")

            Button(AuthCopy.Reset.sendAgain) {
                Task { await model.send(session: session) }
            }
            .font(.pgym(.bodyMedium, size: 15))
            .foregroundStyle(Color.chalk)
            .frame(minHeight: Spacing.touchTargetMin)
            .disabled(model.isSending || !network.isOnline)
        }
        .sensoryFeedback(.success, trigger: model.sentTo)
    }
}
