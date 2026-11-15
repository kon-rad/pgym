import Foundation

/// Picks the auth services at launch.
///
/// | Situation | Services |
/// |---|---|
/// | Launch argument `-pgym-ui-test` | Fakes, signed out (UI tests) |
/// | Launch argument `-pgym-ui-test-signed-in` | Fakes, a returning user already signed in (UI tests) |
/// | `GoogleService-Info.plist` present | Firebase (real project, or the emulator via `PGYM_EMULATOR_HOST`) |
/// | No plist (fresh clone, CI) | Fakes, so every screen can still be reached on a simulator |
enum AppEnvironment {
    static let uiTestArgument = "-pgym-ui-test"
    static let uiTestSignedInArgument = "-pgym-ui-test-signed-in"

    enum Backend: Equatable {
        case firebase
        case fake(signedIn: Bool)
    }

    static func backend(arguments: [String], firebase: FirebaseBootstrap.Outcome) -> Backend {
        if arguments.contains(uiTestSignedInArgument) { return .fake(signedIn: true) }
        if arguments.contains(uiTestArgument) { return .fake(signedIn: false) }
        if case .configured = firebase { return .firebase }
        return .fake(signedIn: false)
    }

    @MainActor
    static func dependencies(for backend: Backend) -> AuthDependencies {
        switch backend {
        case .firebase:
            #if canImport(FirebaseAuth)
            return .firebase()
            #else
            return .fake()
            #endif
        case .fake(let signedIn):
            guard signedIn else { return .fake() }
            let user = AuthUser(uid: "returning-user", email: "returning@example.com", displayName: "Sam", providers: [.email])
            let auth = FakeAuthService(currentUser: user)
            let users = FakeUserRepository()
            // Onboarding already done: a returning user lands on the tabs.
            users.seed(UserProfile(
                uid: user.uid, displayName: "Sam", email: user.email, birthYear: 1990, createdAt: .now,
                goalPerWeek: 4, gymDays: [.mon, .tue, .thu, .fri], reminderTime: .default, units: .kg
            ))
            return .fake(auth: auth, users: users)
        }
    }
}
