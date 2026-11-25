import Foundation

/// In-memory auth, users collection and functions. Used by:
/// - the unit tests (they read the call counters),
/// - the UI tests (launch arguments in `AppEnvironment`),
/// - a build with no `GoogleService-Info.plist`, so every screen can be clicked through on a
///   simulator with no Firebase project. Nothing here touches the network.
@MainActor
final class FakeAuthService: AuthService {
    /// An account the fake knows: Apple and Google sign-ins map to one fixed user each.
    struct Account {
        var user: AuthUser
        var password: String?
    }

    private(set) var currentUser: AuthUser?
    var accounts: [String: Account] = [:] // keyed by uid

    /// The users Apple and Google sign in as.
    var appleUser = AuthUser(uid: "apple-user", email: "apple@example.com", providers: [.apple])
    var googleUser = AuthUser(uid: "google-user", email: "google@example.com", displayName: "Sam", providers: [.google])

    /// Set to make the next call fail with this error.
    var nextError: Error?

    private(set) var signOutCount = 0
    private(set) var verificationEmailsSent: [String] = []
    private(set) var passwordResetsSent: [String] = []
    private(set) var appleReauthCount = 0
    private(set) var revokedAppleCodes: [String] = []

    init(currentUser: AuthUser? = nil) {
        self.currentUser = currentUser
        if let currentUser { accounts[currentUser.uid] = Account(user: currentUser) }
    }

    private func failIfAsked() throws {
        if let error = nextError {
            nextError = nil
            throw error
        }
    }

    func signInWithApple(_ credential: AppleSignInCredential) async throws -> AuthUser {
        try failIfAsked()
        guard !credential.idToken.isEmpty, !credential.rawNonce.isEmpty else { throw AuthFailure.wrongCredentials }
        var user = accounts[appleUser.uid]?.user ?? appleUser
        if user.displayName == nil { user.displayName = credential.formattedName }
        accounts[user.uid] = Account(user: user)
        currentUser = user
        return user
    }

    func signInWithGoogle() async throws -> AuthUser {
        try failIfAsked()
        let user = accounts[googleUser.uid]?.user ?? googleUser
        accounts[user.uid] = Account(user: user)
        currentUser = user
        return user
    }

    func signIn(email: String, password: String) async throws -> AuthUser {
        try failIfAsked()
        let key = email.lowercased()
        guard let account = accounts.values.first(where: { $0.user.email?.lowercased() == key && $0.user.providers.contains(.email) }),
              account.password == password
        else { throw AuthFailure.wrongCredentials }
        currentUser = account.user
        return account.user
    }

    func createAccount(email: String, password: String) async throws -> AuthUser {
        try failIfAsked()
        guard EmailFormat.isPlausible(email) else { throw AuthFailure.invalidEmail }
        guard password.count >= 6 else { throw AuthFailure.weakPassword }
        let key = email.lowercased()
        if accounts.values.contains(where: { $0.user.email?.lowercased() == key }) { throw AuthFailure.emailAlreadyInUse }
        let user = AuthUser(uid: "email-\(key)", email: email, providers: [.email], isEmailVerified: false)
        accounts[user.uid] = Account(user: user, password: password)
        currentUser = user
        return user
    }

    /// Seeds an email account, as if it had been created on another day.
    @discardableResult
    func addEmailAccount(email: String, password: String, verified: Bool = true) -> AuthUser {
        let user = AuthUser(uid: "email-\(email.lowercased())", email: email, providers: [.email], isEmailVerified: verified)
        accounts[user.uid] = Account(user: user, password: password)
        return user
    }

    func sendEmailVerification() async throws {
        try failIfAsked()
        guard let email = currentUser?.email else { throw AuthFailure.unknown }
        verificationEmailsSent.append(email)
    }

    func sendPasswordReset(email: String) async throws {
        try failIfAsked()
        guard EmailFormat.isPlausible(email) else { throw AuthFailure.invalidEmail }
        passwordResetsSent.append(email)
    }

    func reauthenticateWithApple(_ credential: AppleSignInCredential) async throws {
        try failIfAsked()
        guard currentUser?.providers.contains(.apple) == true else { throw AuthFailure.wrongCredentials }
        appleReauthCount += 1
    }

    func revokeAppleToken(authorizationCode: String) async throws {
        try failIfAsked()
        revokedAppleCodes.append(authorizationCode)
    }

    func reloadUser() async throws -> AuthUser? {
        try failIfAsked()
        if let uid = currentUser?.uid { currentUser = accounts[uid]?.user }
        return currentUser
    }

    func freshIDToken() async throws -> String {
        try failIfAsked()
        guard currentUser != nil else { throw AuthFailure.wrongCredentials }
        return "fake-firebase-id-token"
    }

    func signOut() throws {
        try failIfAsked()
        signOutCount += 1
        currentUser = nil
    }

    /// Marks an email account verified, as if the link had been clicked.
    func markVerified(uid: String) {
        accounts[uid]?.user.isEmailVerified = true
    }

    /// Removes the account, as the server's deleteAccount does.
    func removeAccount(uid: String) {
        accounts[uid] = nil
    }
}

@MainActor
final class FakeUserRepository: UserRepository {
    private(set) var documents: [String: UserProfile] = [:]
    /// Every `users/{uid}` actually written by `createProfileIfMissing`.
    private(set) var created: [NewUserProfile] = []
    private(set) var createCalls = 0
    private(set) var birthYearUpdates: [(uid: String, year: Int)] = []
    var nextError: Error?
    var now: () -> Date = { .now }

    init(documents: [String: UserProfile] = [:]) {
        self.documents = documents
    }

    func seed(_ profile: UserProfile) {
        documents[profile.uid] = profile
    }

    func remove(uid: String) {
        documents[uid] = nil
    }

    private func failIfAsked() throws {
        if let error = nextError {
            nextError = nil
            throw error
        }
    }

    func fetchProfile(uid: String) async throws -> UserProfile? {
        try failIfAsked()
        return documents[uid]
    }

    func createProfileIfMissing(_ profile: NewUserProfile) async throws -> Bool {
        try failIfAsked()
        createCalls += 1
        guard documents[profile.uid] == nil else { return false }
        documents[profile.uid] = UserProfile(
            uid: profile.uid,
            displayName: profile.displayName,
            email: profile.email,
            birthYear: profile.birthYear,
            createdAt: now()
        )
        created.append(profile)
        return true
    }

    func setBirthYear(_ year: Int, uid: String) async throws {
        try failIfAsked()
        birthYearUpdates.append((uid, year))
        documents[uid, default: UserProfile(uid: uid)].birthYear = year
    }

    /// Every onboarding write, in order.
    private(set) var onboardingWrites: [(uid: String, settings: OnboardingSettings)] = []

    func saveOnboarding(_ settings: OnboardingSettings, uid: String) async throws {
        try failIfAsked()
        onboardingWrites.append((uid, settings))
        var doc = documents[uid, default: UserProfile(uid: uid)]
        doc.goalPerWeek = settings.plan.goal
        doc.gymDays = settings.plan.orderedDays
        doc.reminderTime = settings.plan.time
        doc.units = settings.units
        documents[uid] = doc
    }
}

@MainActor
final class FakeAccountFunctions: AccountFunctions {
    private(set) var deleteAccountCalls = 0
    var nextError: Error?
    /// Runs after a successful delete, so a test or the demo build can drop the user's data.
    var onDelete: (() -> Void)?

    init() {}

    func deleteAccount() async throws {
        if let error = nextError {
            nextError = nil
            throw error
        }
        deleteAccountCalls += 1
        onDelete?()
    }
}

extension AuthDependencies {
    /// Fakes wired together: a delete removes the account and the document.
    static func fake(
        auth: FakeAuthService = FakeAuthService(),
        users: FakeUserRepository = FakeUserRepository(),
        functions: FakeAccountFunctions = FakeAccountFunctions()
    ) -> AuthDependencies {
        functions.onDelete = { [weak auth, weak users] in
            guard let uid = auth?.currentUser?.uid else { return }
            auth?.removeAccount(uid: uid)
            users?.remove(uid: uid)
        }
        return AuthDependencies(auth: auth, users: users, functions: functions)
    }
}
