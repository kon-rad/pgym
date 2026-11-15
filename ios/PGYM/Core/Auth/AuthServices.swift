import Foundation

/// The auth layer. `FirebaseAuthService` is the real one; `FakeAuthService` backs the unit tests,
/// the UI tests and a build with no Firebase config. Nothing above this protocol imports Firebase.
@MainActor
protocol AuthService: AnyObject {
    /// The user Firebase restored from the keychain at launch, if any.
    var currentUser: AuthUser? { get }

    /// Signs in with an Apple identity token and the raw nonce whose hash Apple signed.
    func signInWithApple(_ credential: AppleSignInCredential) async throws -> AuthUser
    /// Presents Google's sheet, then signs in to Firebase with the Google credential.
    func signInWithGoogle() async throws -> AuthUser
    func signIn(email: String, password: String) async throws -> AuthUser
    func createAccount(email: String, password: String) async throws -> AuthUser
    /// Sends the verification link to the current email user.
    func sendEmailVerification() async throws
    /// Sends a reset link. Succeeds whether or not the account exists, so A4 never reveals it.
    func sendPasswordReset(email: String) async throws
    /// Fresh Apple sign-in for the current user, before deleting the account.
    func reauthenticateWithApple(_ credential: AppleSignInCredential) async throws
    /// Revokes the app's Sign in with Apple token (App Store guideline 5.1.1(v), via Firebase).
    func revokeAppleToken(authorizationCode: String) async throws
    /// Re-reads the user from the server (for example after the verification link was clicked).
    func reloadUser() async throws -> AuthUser?
    func signOut() throws
}

/// `users/{uid}` in Firestore.
@MainActor
protocol UserRepository: AnyObject {
    /// The profile, or nil if the document does not exist yet.
    func fetchProfile(uid: String) async throws -> UserProfile?
    /// Creates `users/{uid}` only if it does not exist. Returns true if this call created it.
    /// Two calls for the same user write once (a transaction in the Firestore implementation).
    func createProfileIfMissing(_ profile: NewUserProfile) async throws -> Bool
    /// Fills in a missing birth year on an existing document.
    func setBirthYear(_ year: Int, uid: String) async throws
    /// Onboarding's answers: goal, gym days, reminder time, units, time zone. A merge write.
    func saveOnboarding(_ settings: OnboardingSettings, uid: String) async throws
    /// Writes routines under `users/{uid}/routines/{id}`. Fixed IDs, so a retry overwrites.
    func saveRoutines(_ routines: [RoutineDraft], uid: String) async throws
}

/// The callable Cloud Functions sign-in needs (pgym-architecture.md, "Functions").
@MainActor
protocol AccountFunctions: AnyObject {
    /// `deleteAccount`: deletes every S3 object, every document and the auth user, server side.
    func deleteAccount() async throws
}

/// Everything the app's auth flow needs, built once at launch.
@MainActor
struct AuthDependencies {
    let auth: AuthService
    let users: UserRepository
    let functions: AccountFunctions
    /// Routes a URL to the Google Sign-In SDK. Returns true if it was Google's.
    var handleOpenURL: (URL) -> Bool = { _ in false }
}
