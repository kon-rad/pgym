import DesignSystem
import Observation
import SwiftUI

/// A2 Email sign-in, and A3 Create account as its create mode (pgym-flow-spec.md merges A3 into
/// A2: same two fields, and the year of birth is asked on A5 for every sign-in method).
@MainActor
@Observable
final class EmailAuthViewModel {
    enum Field { case email, password }

    var mode: EmailSignInScreen.Mode
    var email = ""
    var password = ""
    private(set) var isWorking = false
    private(set) var errorText: String?
    /// "Sign in instead" under the email-in-use error.
    private(set) var offersSignIn = false

    init(mode: EmailSignInScreen.Mode = .signIn) {
        self.mode = mode
    }

    var title: String { mode == .signIn ? AuthCopy.Email.signInTitle : AuthCopy.Email.createTitle }
    var buttonTitle: String { mode == .signIn ? AuthCopy.Email.signInButton : AuthCopy.Email.createButton }
    var canSubmit: Bool { !email.isEmpty && !password.isEmpty && !isWorking }

    /// Switches mode in place; the typed email carries over.
    func toggleMode() {
        mode = mode == .signIn ? .create : .signIn
        errorText = nil
        offersSignIn = false
    }

    /// Checks that need no server. Returns the message to show, or nil.
    func localProblem() -> String? {
        if !EmailFormat.isPlausible(email) { return AuthCopy.invalidEmail }
        if mode == .create, !PasswordPolicy.isLongEnough(password) { return AuthCopy.Email.passwordTooShort }
        return nil
    }

    func submit(session: AppSession) async {
        guard canSubmit else { return }
        if let problem = localProblem() {
            errorText = problem
            return
        }
        errorText = nil
        offersSignIn = false
        isWorking = true
        defer { isWorking = false }
        do {
            switch mode {
            case .signIn: try await session.signIn(email: email, password: password)
            case .create: try await session.createAccount(email: email, password: password)
            }
        } catch {
            let failure = AuthFailure(error)
            errorText = Self.message(for: failure)
            offersSignIn = failure == .emailAlreadyInUse
        }
    }

    /// The copy deck's line for each failure. Wrong email and wrong password read the same.
    static func message(for failure: AuthFailure) -> String? {
        switch failure {
        case .cancelled: nil
        case .wrongCredentials: AuthCopy.Email.wrongCredentials
        case .invalidEmail: AuthCopy.invalidEmail
        case .emailAlreadyInUse: AuthCopy.Email.emailInUse
        case .weakPassword: AuthCopy.Email.passwordTooShort
        case .tooManyRequests: AuthCopy.Email.tooManyTries
        case .network: AuthCopy.noConnection
        case .requiresRecentLogin, .notConfigured, .unknown: AuthCopy.genericFailure
        }
    }
}

struct EmailSignInScreen: View {
    enum Mode: Hashable { case signIn, create }

    /// A2 in sign-in mode, A3 in create mode.
    var viewID: String { model.mode == .signIn ? "A2" : "A3" }

    @Environment(AppSession.self) private var session
    @Environment(NetworkMonitor.self) private var network
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var model: EmailAuthViewModel
    @State private var showingReset = false
    @FocusState private var focus: EmailAuthViewModel.Field?

    init(initialMode: Mode = .signIn) {
        _model = State(initialValue: EmailAuthViewModel(mode: initialMode))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.grid(6)) {
                Text(model.title)
                    .pgymText(.display, size: 56)
                    .foregroundStyle(Color.chalk)
                    .accessibilityAddTraits(.isHeader)
                    .contentTransition(.opacity)

                VStack(alignment: .leading, spacing: Spacing.grid(4)) {
                    AuthField(
                        label: AuthCopy.emailLabel,
                        text: $model.email,
                        placeholder: AuthCopy.emailPlaceholder,
                        kind: .email,
                        isFocused: focus == .email,
                        identifier: "auth.email"
                    )
                    .focused($focus, equals: .email)
                    .onSubmit { focus = .password }

                    VStack(alignment: .leading, spacing: Spacing.grid(2)) {
                        AuthField(
                            label: AuthCopy.passwordLabel,
                            text: $model.password,
                            kind: .password(isNew: model.mode == .create),
                            isFocused: focus == .password,
                            identifier: "auth.password"
                        )
                        .focused($focus, equals: .password)
                        .onSubmit { Task { await model.submit(session: session) } }

                        if model.mode == .create {
                            Text(AuthCopy.Email.passwordHint)
                                .pgymText(.label)
                                .foregroundStyle(Color.steel)
                        }
                    }
                }
                .disabled(model.isWorking)

                if !network.isOnline {
                    InlineNote(text: AuthCopy.noConnection, identifier: "auth.offline")
                } else if let error = model.errorText {
                    VStack(alignment: .leading, spacing: Spacing.grid(1)) {
                        InlineNote(text: error, identifier: "auth.error")
                        if model.offersSignIn {
                            Button(AuthCopy.Email.switchToSignIn) { model.toggleMode() }
                                .font(.pgym(.bodyMedium, size: 15))
                                .foregroundStyle(Color.chalk)
                                .frame(minHeight: Spacing.touchTargetMin)
                        }
                    }
                }

                LoadingPrimaryButton(
                    title: model.buttonTitle,
                    isLoading: model.isWorking,
                    identifier: "auth.submit"
                ) {
                    Task { await model.submit(session: session) }
                }
                .disabled(!model.canSubmit || !network.isOnline)

                HStack {
                    Button(model.mode == .signIn ? AuthCopy.Email.switchToCreate : AuthCopy.Email.switchToSignIn) {
                        model.toggleMode()
                    }
                    .accessibilityIdentifier("auth.toggleMode")
                    Spacer()
                    if model.mode == .signIn {
                        Button(AuthCopy.Email.forgot) { showingReset = true }
                            .accessibilityIdentifier("auth.forgot")
                    }
                }
                .font(.pgym(.bodyMedium, size: 15))
                .foregroundStyle(Color.chalk)
                .frame(minHeight: Spacing.touchTargetMin)
                .disabled(model.isWorking)

                if model.mode == .create {
                    LegalLine()
                }
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.top, Spacing.grid(4))
            .padding(.bottom, Spacing.grid(8))
            .animation(Animation.pgymSpring(reduceMotion: reduceMotion), value: model.mode)
            .animation(Animation.pgymSpring(reduceMotion: reduceMotion), value: model.errorText)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.ink.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.ink, for: .navigationBar)
        .navigationBarBackButtonHidden(model.isWorking)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.\(viewID)")
        .sheet(isPresented: $showingReset) {
            ResetPasswordSheet(email: model.email)
        }
        .onAppear { focus = .email }
    }
}

struct EmailSignInScreen_Previews: PreviewProvider {
    static var previews: some View {
        let _ = FontRegistry.registerAll()
        NavigationStack { EmailSignInScreen(initialMode: .create) }
            .environment(AppSession(dependencies: .fake()))
            .environment(NetworkMonitor(fixed: true))
            .preferredColorScheme(.dark)
    }
}
