import DesignSystem
import SwiftUI

/// The sign-in gate. Nothing past A1 to A5 is reachable without a signed-in user and a
/// `users/{uid}` with a birth year.
struct AppRootView: View {
    @Environment(AppSession.self) private var session
    @Environment(AppServices.self) private var services
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

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
            case .onboarding:
                OnboardingFlowView()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .main:
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
        .onChange(of: session.route) { _, route in
            Task { await syncReminders(route: route) }
        }
        .onChange(of: scenePhase) { _, phase in
            // The day moved on or reminders fired while away: count them and plan again.
            guard phase == .active, session.route == .main else { return }
            Task { await services.reminders.reschedule() }
        }
    }

    /// Keeps the phone's reminders in step with who is signed in.
    private func syncReminders(route: AppSession.Route) async {
        switch route {
        case .signedOut:
            services.reminders.reset()
        case .main:
            // A new phone or a reinstall: take this week's plan from `users/{uid}`.
            await services.reminders.adoptIfMissing(session.profile?.plan, remindersEnabled: true)
            await services.reminders.reschedule()
        default:
            break
        }
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
