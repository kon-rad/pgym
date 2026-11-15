import DesignSystem
import SwiftUI

/// The sign-in gate. Nothing past A1 to A5 is reachable without a signed-in user and a
/// `users/{uid}` with a birth year.
struct AppRootView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.ink.ignoresSafeArea()

            switch session.route {
            case .launching:
                LaunchView()
                    .transition(.opacity)
            case .signedOut:
                WelcomeScreen()
                    .transition(.opacity)
            case .yearOfBirth:
                YearOfBirthScreen()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .underMinimumAge:
                UnderMinimumAgeScreen()
                    .transition(.opacity)
            case .onboarding, .main:
                // `.onboarding` gets B1 to B5 in card I3; until then a new user lands on the tabs.
                RootTabView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            case .profileUnavailable:
                ProfileUnavailableScreen()
                    .transition(.opacity)
            }
        }
        .animation(Animation.pgymSpring(reduceMotion: reduceMotion), value: session.route)
        // A finished sign-in is a finished action: one success tap.
        .sensoryFeedback(.success, trigger: session.isSignedIn) { _, signedIn in signedIn }
        .task { await session.start() }
    }
}

/// While Firebase restores the saved sign-in: the mark on Ink, no spinner.
private struct LaunchView: View {
    var body: some View {
        PGYMMark()
            .frame(width: 88, height: 88)
            .accessibilityIdentifier("screen.launch")
    }
}
