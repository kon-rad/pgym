import AuthenticationServices
import DesignSystem
import SwiftUI

/// A1 Welcome. One tap to sign in: Apple, Google, or email (A2).
/// Apple's button keeps Apple's own white style, so this screen has no Plate button.
struct WelcomeScreen: View {
    static let viewID = "A1"

    @Environment(AppSession.self) private var session
    @Environment(NetworkMonitor.self) private var network
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var appleFlow = AppleSignInFlow()
    @State private var busy: AuthProvider?
    @State private var errorText: String?
    @State private var appeared = false
    @State private var path: [AuthRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationDestination(for: AuthRoute.self) { route in
                    switch route {
                    case .email(let mode): EmailSignInScreen(initialMode: mode)
                    }
                }
        }
        .tint(Color.chalk)
    }

    private var content: some View {
        ZStack {
            Color.ink.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                if session.notice == .accountDeleted {
                    deletedBanner
                        .padding(.top, Spacing.grid(2))
                }

                Spacer(minLength: Spacing.grid(6))

                hero

                Spacer(minLength: Spacing.grid(8))

                buttons
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.bottom, Spacing.grid(4))
        }
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.\(Self.viewID)")
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.7)) { appeared = true }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: Spacing.grid(5)) {
            PGYMMark()
                .frame(width: 96, height: 96)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.6)
                .opacity(appeared || reduceMotion ? 1 : 0)

            Text(AuthCopy.Welcome.headline)
                .pgymText(.display, size: 76)
                .foregroundStyle(Color.chalk)
                .minimumScaleFactor(0.6)
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)

            Text(AuthCopy.Welcome.subline)
                .pgymText(.body, size: 17)
                .foregroundStyle(Color.bone)
                .fixedSize(horizontal: false, vertical: true)

            Stamp(proofNumber: 1)
                .padding(.top, Spacing.grid(2))
                .opacity(appeared || reduceMotion ? 1 : 0)
                .offset(y: appeared || reduceMotion ? 0 : 12)
                .accessibilityHidden(true)
        }
    }

    private var buttons: some View {
        VStack(spacing: Spacing.grid(3)) {
            SignInWithAppleButton(.continue) { request in
                appleFlow.prepare(request)
            } onCompletion: { result in
                Task { await finishApple(result) }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: Spacing.mainButtonHeight)
            .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
            .overlay {
                if busy == .apple {
                    RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                        .fill(Color.chalk)
                        .overlay(ProgressView().tint(Color.ink))
                }
            }
            .disabled(!network.isOnline || busy != nil)
            .opacity(network.isOnline ? 1 : 0.5)
            .accessibilityIdentifier("auth.apple")

            Button {
                Task { await signInWithGoogle() }
            } label: {
                HStack(spacing: Spacing.grid(3)) {
                    if busy == .google {
                        ProgressView().tint(Color.chalk)
                    } else {
                        Text("G")
                            .font(.pgym(.title, size: 19))
                            .accessibilityHidden(true)
                        Text(AuthCopy.Welcome.google)
                    }
                }
            }
            .buttonStyle(GoogleButtonStyle())
            .disabled(!network.isOnline || busy != nil)
            .accessibilityLabel(AuthCopy.Welcome.google)
            .accessibilityIdentifier("auth.google")

            Button(AuthCopy.Welcome.email) {
                session.notice = nil
                path.append(.email(.signIn))
            }
            .font(.pgym(.bodyMedium, size: 17))
            .foregroundStyle(Color.chalk)
            .frame(minHeight: Spacing.touchTargetMin)
            .disabled(busy != nil)
            .accessibilityIdentifier("auth.useEmail")

            if !network.isOnline {
                InlineNote(text: AuthCopy.noConnection, identifier: "auth.offline")
            } else if let errorText {
                InlineNote(text: errorText, identifier: "auth.error")
            }

            LegalLine()
                .padding(.top, Spacing.grid(1))
        }
        .animation(Animation.pgymSpring(reduceMotion: reduceMotion), value: errorText)
        .animation(Animation.pgymSpring(reduceMotion: reduceMotion), value: network.isOnline)
    }

    private var deletedBanner: some View {
        HStack(spacing: Spacing.grid(3)) {
            Text(AuthCopy.Welcome.accountDeleted)
                .pgymText(.bodyMedium, size: 15)
                .foregroundStyle(Color.chalk)
            Spacer()
            Button(AuthCopy.Welcome.close) { session.notice = nil }
                .font(.pgym(.bodyMedium, size: 15))
                .foregroundStyle(Color.bone)
                .frame(minHeight: Spacing.touchTargetMin)
        }
        .padding(.horizontal, Spacing.grid(4))
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.iron))
        .accessibilityIdentifier("auth.accountDeleted")
    }

    // MARK: Actions

    private func finishApple(_ result: Result<ASAuthorization, Error>) async {
        errorText = nil
        do {
            let credential = try appleFlow.credential(from: result)
            busy = .apple
            defer { busy = nil }
            try await session.signInWithApple(credential)
        } catch {
            show(error)
        }
    }

    private func signInWithGoogle() async {
        errorText = nil
        session.notice = nil
        busy = .google
        defer { busy = nil }
        do {
            try await session.signInWithGoogle()
        } catch {
            show(error)
        }
    }

    private func show(_ error: Error) {
        switch AuthFailure(error) {
        case .cancelled: errorText = nil // a cancel is not an error
        case .network: errorText = AuthCopy.noConnection
        default: errorText = AuthCopy.genericFailure
        }
    }
}

/// Destinations inside the signed-out stack.
enum AuthRoute: Hashable {
    case email(EmailSignInScreen.Mode)
}

/// Continue with Google: Chalk outline on Ink, so it pairs with Apple's white button without
/// taking the screen's accent.
private struct GoogleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.pgym(.bodyMedium, size: 17))
            .foregroundStyle(isEnabled ? Color.chalk : Color.steel)
            .frame(maxWidth: .infinity, minHeight: Spacing.mainButtonHeight)
            .background(
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .fill(configuration.isPressed ? Color.rail : Color.iron)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .strokeBorder(Color.rail, lineWidth: Stroke.border)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
    }
}

struct WelcomeScreen_Previews: PreviewProvider {
    static var previews: some View {
        let _ = FontRegistry.registerAll()
        WelcomeScreen()
            .environment(AppSession(dependencies: .fake()))
            .environment(NetworkMonitor(fixed: true))
            .preferredColorScheme(.dark)
    }
}
