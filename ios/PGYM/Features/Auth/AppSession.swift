import Foundation
import Observation

/// Who is signed in and which part of the app they see. The sign-in gate in `AppRootView`
/// switches on `route`; every sign-in method ends in `didSignIn`, which reads `users/{uid}` and
/// decides between A5, onboarding and the tabs.
///
/// Rules (pgym-architecture.md, "Sign-in"; pgym-flow-spec.md, A1 to A5):
/// - No `users/{uid}` yet: A5 Year of birth, then create the document once, then onboarding.
/// - Document without a birth year: A5, then fill it in, then the tabs.
/// - Document with a birth year: a returning user goes straight to the tabs, no onboarding.
@MainActor
@Observable
final class AppSession {
    enum Route: Equatable {
        /// Restoring a saved sign-in at launch.
        case launching
        /// A1 to A4.
        case signedOut
        /// A5.
        case yearOfBirth
        /// A5's stop screen: younger than `AgePolicy.minimumAge`.
        case underMinimumAge
        /// B1 to B5, for a brand-new user. Card I3 builds the screens.
        case onboarding
        /// The tab shell.
        case main
        /// Signed in, but `users/{uid}` could not be read (no connection on a fresh install).
        case profileUnavailable
    }

    /// One-off lines shown on A1.
    enum Notice: Equatable {
        case accountDeleted
    }

    enum DeletionError: Error, Equatable {
        /// An Apple user must sign in with Apple again first: it proves it is them, and the fresh
        /// authorisation code is what revokes PGYM's Apple token.
        case appleReauthRequired
    }

    private(set) var route: Route = .launching
    private(set) var user: AuthUser?
    private(set) var profile: UserProfile?
    var notice: Notice?
    /// The address the verification link went to, shown once on A5 after creating an account.
    private(set) var verificationSentTo: String?
    /// True while A5 saves, so a double tap cannot create the document twice.
    private(set) var isSavingBirthYear = false

    let auth: AuthService
    let users: UserRepository
    let functions: AccountFunctions
    private let currentYear: () -> Int
    private let units: NewUserProfile.Units
    private let timezone: String

    init(
        dependencies: AuthDependencies,
        currentYear: @escaping () -> Int = { AgePolicy.currentYear() },
        units: NewUserProfile.Units = .default(),
        timezone: String = TimeZone.current.identifier
    ) {
        auth = dependencies.auth
        users = dependencies.users
        functions = dependencies.functions
        self.currentYear = currentYear
        self.units = units
        self.timezone = timezone
    }

    var isSignedIn: Bool { user != nil }

    /// Name for F1: the profile's, then Apple or Google's, then the email before the @.
    var displayName: String? {
        if let name = profile?.displayName, !name.isEmpty { return name }
        return user?.fallbackName
    }

    // MARK: Launch

    /// Restores a saved sign-in. Call once from the app's root view.
    func start() async {
        guard route == .launching else { return }
        if let saved = auth.currentUser {
            await didSignIn(saved)
        } else {
            route = .signedOut
        }
    }

    /// Tries `users/{uid}` again after `.profileUnavailable`.
    func retryProfile() async {
        guard let user else { route = .signedOut; return }
        await didSignIn(user)
    }

    // MARK: Sign in

    func signInWithApple(_ credential: AppleSignInCredential) async throws {
        let signedIn = try await auth.signInWithApple(credential)
        await didSignIn(signedIn)
    }

    func signInWithGoogle() async throws {
        let signedIn = try await auth.signInWithGoogle()
        await didSignIn(signedIn)
    }

    func signIn(email: String, password: String) async throws {
        let signedIn = try await auth.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
        await didSignIn(signedIn)
    }

    /// A2 in create mode: makes the account, sends the verification link and goes to A5 without
    /// waiting for the link to be clicked.
    func createAccount(email: String, password: String) async throws {
        let address = email.trimmingCharacters(in: .whitespaces)
        let created = try await auth.createAccount(email: address, password: password)
        // A failed send is not a failed sign-up: F1 offers "Send the link again".
        if (try? await auth.sendEmailVerification()) != nil {
            verificationSentTo = address
        }
        await didSignIn(created)
    }

    func sendPasswordReset(email: String) async throws {
        try await auth.sendPasswordReset(email: email.trimmingCharacters(in: .whitespaces))
    }

    func resendVerificationEmail() async throws {
        try await auth.sendEmailVerification()
    }

    /// Picks up a clicked verification link.
    func refreshUser() async {
        guard user != nil, let fresh = try? await auth.reloadUser() else { return }
        user = fresh
    }

    /// Every sign-in path ends here.
    func didSignIn(_ signedIn: AuthUser) async {
        user = signedIn
        notice = nil
        do {
            let loaded = try await users.fetchProfile(uid: signedIn.uid)
            profile = loaded
            route = Self.route(for: loaded, currentYear: currentYear())
        } catch {
            route = .profileUnavailable
        }
    }

    /// Where a signed-in user with this `users/{uid}` goes.
    static func route(for profile: UserProfile?, currentYear: Int) -> Route {
        guard let birthYear = profile?.birthYear else { return .yearOfBirth }
        if AgePolicy.age(birthYear: birthYear, currentYear: currentYear) < AgePolicy.minimumAge {
            return .underMinimumAge
        }
        // No weekly goal yet: onboarding was never finished (or the app was quit during it).
        return profile?.needsOnboarding == true ? .onboarding : .main
    }

    // MARK: A5

    /// Saves the year from A5. Creates `users/{uid}` if this is the first sign-in, or fills in the
    /// year on an existing document. The caller has already run `AgePolicy.check`.
    func submitBirthYear(_ year: Int) async throws {
        guard let user, route == .yearOfBirth, !isSavingBirthYear else { return }
        isSavingBirthYear = true
        defer { isSavingBirthYear = false }

        if AgePolicy.age(birthYear: year, currentYear: currentYear()) < AgePolicy.minimumAge {
            // Nothing is stored for someone under the minimum age.
            route = .underMinimumAge
            return
        }

        if var existing = profile {
            try await users.setBirthYear(year, uid: user.uid)
            existing.birthYear = year
            profile = existing
            route = existing.needsOnboarding ? .onboarding : .main
            return
        }

        let draft = NewUserProfile(
            uid: user.uid,
            displayName: user.fallbackName,
            email: user.email,
            birthYear: year,
            units: units,
            timezone: timezone
        )
        let createdNow = try await users.createProfileIfMissing(draft)
        // If another device created it first, read that one back instead of assuming ours won.
        profile = createdNow
            ? UserProfile(uid: user.uid, displayName: draft.displayName, email: draft.email, birthYear: year, createdAt: .now)
            : (try? await users.fetchProfile(uid: user.uid)) ?? UserProfile(uid: user.uid, birthYear: year)
        verificationSentTo = nil
        // A new document has no goal yet, so this is onboarding; another device's may have one.
        route = Self.route(for: profile, currentYear: currentYear())
    }

    /// The units B5 starts on: the phone's region (`NewUserProfile.Units.default`), or what the
    /// document already says.
    var startingUnits: NewUserProfile.Units { profile?.units ?? units }

    /// The time zone that decides which week a session falls in.
    var userTimezone: String { timezone }

    /// Onboarding's last step. Writes the answers to `users/{uid}`, then opens the tabs (the
    /// starter routines go through `RoutineStore`, card I4). Throws (and stays on onboarding)
    /// if the write fails; Firestore's
    /// offline cache normally accepts the write without a connection.
    func completeOnboarding(_ settings: OnboardingSettings) async throws {
        guard let user, route == .onboarding else { return }
        try await users.saveOnboarding(settings, uid: user.uid)
        var updated = profile ?? UserProfile(uid: user.uid)
        updated.goalPerWeek = settings.plan.goal
        updated.gymDays = settings.plan.orderedDays
        updated.reminderTime = settings.plan.time
        updated.units = settings.units
        profile = updated
        route = .main
    }

    // MARK: F4 and F5 (card I8)

    /// F4 Save: the plan the user last chose goes to `users/{uid}` (the server locks each week's goal
    /// when the week opens, so this week's target does not move). The same merge write as onboarding.
    func updatePlan(_ plan: WeeklyPlan) async throws {
        guard let user else { return }
        let units = profile?.units ?? startingUnits
        try await users.saveOnboarding(OnboardingSettings(plan: plan, units: units, timezone: timezone), uid: user.uid)
        var updated = profile ?? UserProfile(uid: user.uid)
        updated.goalPerWeek = plan.goal
        updated.gymDays = plan.orderedDays
        updated.reminderTime = plan.time
        profile = updated
    }

    /// F5 Units. Saved on the phone first (it works offline), then on `users/{uid}` with the plan the
    /// document already holds.
    func updateUnits(_ units: NewUserProfile.Units, defaults: UserDefaults = .standard) async throws {
        defaults.set(units.rawValue, forKey: WeightUnit.preferenceKey)
        guard let user else { return }
        var updated = profile ?? UserProfile(uid: user.uid)
        updated.units = units
        profile = updated
        guard let plan = updated.plan else { return }
        try await users.saveOnboarding(OnboardingSettings(plan: plan, units: units, timezone: timezone), uid: user.uid)
    }

    // MARK: Sign out and delete

    func signOut() throws {
        try auth.signOut()
        resetToSignedOut()
    }

    /// Whether F7 has to ask for a fresh Apple sign-in before deleting.
    var deletionNeedsAppleReauth: Bool {
        user?.providers.contains(.apple) == true
    }

    /// F7. For an Apple user, pass the credential from a fresh Apple sign-in: it re-authenticates,
    /// revokes PGYM's Apple token, then calls `deleteAccount`. On success the phone signs out and
    /// A1 says "Your account is deleted." On failure nothing changes on the phone.
    func deleteAccount(appleCredential: AppleSignInCredential? = nil) async throws {
        guard user != nil else { return }
        if deletionNeedsAppleReauth {
            guard let appleCredential else { throw DeletionError.appleReauthRequired }
            try await auth.reauthenticateWithApple(appleCredential)
            if let code = appleCredential.authorizationCode {
                try await auth.revokeAppleToken(authorizationCode: code)
            }
        }
        try await functions.deleteAccount()
        // The server already deleted the auth user; this clears the phone's copy. A failure here
        // must not leave the deleted account on screen.
        try? auth.signOut()
        resetToSignedOut()
        notice = .accountDeleted
    }

    private func resetToSignedOut() {
        user = nil
        profile = nil
        verificationSentTo = nil
        route = .signedOut
    }
}
