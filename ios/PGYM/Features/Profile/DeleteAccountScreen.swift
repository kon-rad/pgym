import AuthenticationServices
import DesignSystem
import Observation
import SwiftUI

/// F7's logic: the typed confirmation, the Apple re-sign-in step, and the call itself.
@MainActor
@Observable
final class DeleteAccountViewModel {
    enum Phase: Equatable {
        case confirm
        /// Apple users sign in with Apple once more; that also yields the code that revokes the token.
        case appleReauth
        case deleting
    }

    var confirmation = ""
    private(set) var phase: Phase = .confirm
    private(set) var errorText: String?

    var isConfirmed: Bool {
        confirmation.trimmingCharacters(in: .whitespaces) == AuthCopy.Delete.confirmWord
    }

    func deleteTapped(session: AppSession) async {
        guard isConfirmed, phase == .confirm else { return }
        errorText = nil
        if session.deletionNeedsAppleReauth {
            phase = .appleReauth
            return
        }
        await run(session: session, appleCredential: nil)
    }

    func appleReauthFinished(_ result: Result<AppleSignInCredential, Error>, session: AppSession) async {
        switch result {
        case .success(let credential):
            await run(session: session, appleCredential: credential)
        case .failure(let error):
            // Closing the Apple sheet goes back to the confirm step without a message.
            phase = .confirm
            errorText = AuthFailure(error) == .cancelled ? nil : AuthCopy.Delete.failed
        }
    }

    func cancelReauth() {
        phase = .confirm
    }

    private func run(session: AppSession, appleCredential: AppleSignInCredential?) async {
        phase = .deleting
        do {
            try await session.deleteAccount(appleCredential: appleCredential)
            // The session is now signed out; the root view shows A1 with "Your account is deleted."
        } catch {
            phase = .confirm
            errorText = AuthCopy.Delete.failed
        }
    }
}

/// F7 Delete account. In the app, as Apple requires (App Store guideline 5.1.1(v)).
struct DeleteAccountScreen: View {
    static let viewID = "F7"

    @Environment(AppSession.self) private var session
    @Environment(NetworkMonitor.self) private var network
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var model = DeleteAccountViewModel()
    @State private var appleFlow = AppleSignInFlow()
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.grid(6)) {
                Text(AuthCopy.Delete.title)
                    .pgymText(.display, size: 56)
                    .foregroundStyle(Color.chalk)
                    .accessibilityAddTraits(.isHeader)

                whatGoes

                Text(AuthCopy.Delete.shared)
                    .pgymText(.body, size: 15)
                    .foregroundStyle(Color.steel)
                    .fixedSize(horizontal: false, vertical: true)

                if session.deletionNeedsAppleReauth {
                    Text(AuthCopy.Delete.apple)
                        .pgymText(.body, size: 15)
                        .foregroundStyle(Color.steel)
                        .fixedSize(horizontal: false, vertical: true)
                }

                AuthField(
                    label: AuthCopy.Delete.confirmLabel,
                    text: $model.confirmation,
                    placeholder: AuthCopy.Delete.confirmWord,
                    kind: .confirmation,
                    isFocused: fieldFocused,
                    identifier: "f7.confirm"
                )
                .focused($fieldFocused)
                .disabled(model.phase != .confirm)

                actions
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.top, Spacing.grid(4))
            .padding(.bottom, Spacing.grid(8))
            .animation(Animation.pgymSpring(reduceMotion: reduceMotion), value: model.phase)
            .animation(Animation.pgymSpring(reduceMotion: reduceMotion), value: model.errorText)
        }
        .background(Color.ink.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.ink, for: .navigationBar)
        // "Loading: button progress, screen locked."
        .navigationBarBackButtonHidden(model.phase == .deleting)
        .interactiveDismissDisabled(model.phase == .deleting)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.\(Self.viewID)")
    }

    private var whatGoes: some View {
        VStack(alignment: .leading, spacing: Spacing.grid(3)) {
            Text(AuthCopy.Delete.intro)
                .pgymText(.body, size: 17)
                .foregroundStyle(Color.bone)
            ForEach(AuthCopy.Delete.items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: Spacing.grid(3)) {
                    Rectangle()
                        .fill(Color.steel)
                        .frame(width: 8, height: Stroke.dayRing)
                        .accessibilityHidden(true)
                    Text(item)
                        .pgymText(.bodyMedium, size: 17)
                        .foregroundStyle(Color.chalk)
                }
            }
        }
        .padding(Spacing.grid(4))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.iron))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var actions: some View {
        if !network.isOnline {
            InlineNote(text: AuthCopy.needsConnection, identifier: "f7.offline")
        } else if let error = model.errorText {
            InlineNote(text: error, identifier: "f7.error")
        }

        switch model.phase {
        case .confirm, .deleting:
            Button {
                fieldFocused = false
                Task { await model.deleteTapped(session: session) }
            } label: {
                ZStack {
                    Text(AuthCopy.Delete.button).opacity(model.phase == .deleting ? 0 : 1)
                    if model.phase == .deleting {
                        HStack(spacing: Spacing.grid(3)) {
                            ProgressView().tint(Color.chalk)
                            Text(AuthCopy.Delete.progress)
                        }
                    }
                }
            }
            .buttonStyle(DestructiveButtonStyle())
            .disabled(!model.isConfirmed || !network.isOnline || model.phase == .deleting)
            .accessibilityIdentifier("f7.delete")

        case .appleReauth:
            VStack(alignment: .leading, spacing: Spacing.grid(3)) {
                InlineNote(text: AuthCopy.Delete.reauth, tone: .info, identifier: "f7.reauth")
                SignInWithAppleButton(.signIn) { request in
                    // No name or email needed: this only proves it is the same Apple ID.
                    appleFlow.prepare(request, scopes: [])
                } onCompletion: { result in
                    let credential = Result { try appleFlow.credential(from: result) }
                    Task { await model.appleReauthFinished(credential, session: session) }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: Spacing.mainButtonHeight)
                .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                .disabled(!network.isOnline)
                .accessibilityIdentifier("f7.appleReauth")

                Button(AuthCopy.Profile.cancel) { model.cancelReauth() }
                    .font(.pgym(.bodyMedium, size: 15))
                    .foregroundStyle(Color.chalk)
                    .frame(minHeight: Spacing.touchTargetMin)
            }
        }
    }
}

struct DeleteAccountScreen_Previews: PreviewProvider {
    static var previews: some View {
        let _ = FontRegistry.registerAll()
        NavigationStack { DeleteAccountScreen() }
            .environment(AppSession(dependencies: .fake()))
            .environment(NetworkMonitor(fixed: true))
            .preferredColorScheme(.dark)
    }
}
