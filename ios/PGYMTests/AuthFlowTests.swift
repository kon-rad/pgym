import XCTest
@testable import PGYM

/// One test's world: fake auth, users and functions wired into a fresh session.
@MainActor
private final class Fixture {
    static let year = 2026

    let auth: FakeAuthService
    let users = FakeUserRepository()
    let functions = FakeAccountFunctions()
    let session: AppSession

    init(currentUser: AuthUser? = nil, seed: [UserProfile] = []) {
        auth = FakeAuthService(currentUser: currentUser)
        for profile in seed { users.seed(profile) }
        session = AppSession(
            dependencies: .fake(auth: auth, users: users, functions: functions),
            currentYear: { Fixture.year },
            units: .kg,
            timezone: "Etc/UTC"
        )
    }
}

/// The sign-in gate and account deletion, against the fake auth layer. No network, no Firebase.
/// XCTest makes a new instance per test method, so each test gets its own fixture.
@MainActor
final class AuthFlowTests: XCTestCase {
    private var fixture: Fixture?
    private let year = 2026 // Fixture.year

    private var current: Fixture {
        if let fixture { return fixture }
        let made = Fixture()
        fixture = made
        return made
    }

    private var auth: FakeAuthService { current.auth }
    private var users: FakeUserRepository { current.users }
    private var functions: FakeAccountFunctions { current.functions }
    private var session: AppSession { current.session }

    // MARK: Done-when tests from the card

    /// First sign-in: A5, then `users/{uid}` is created exactly once, then onboarding.
    /// A double tap, a second submit and a later sign-in never create it again.
    func testFirstSignInCreatesUserDocumentOnce() async throws {
        auth.addEmailAccount(email: "new@example.com", password: "longenough")

        try await session.signIn(email: "new@example.com", password: "longenough")
        XCTAssertEqual(session.route, .yearOfBirth)
        XCTAssertTrue(users.created.isEmpty, "nothing is written before the year is known")

        let session = self.session
        async let first: Void = session.submitBirthYear(1990)
        async let second: Void = session.submitBirthYear(1990) // a double tap
        _ = try await (first, second)

        XCTAssertEqual(users.created.count, 1)
        XCTAssertEqual(users.createCalls, 1, "the second tap is ignored while the first saves")
        XCTAssertEqual(session.route, .onboarding)

        let doc = try XCTUnwrap(users.created.first)
        XCTAssertEqual(doc.uid, "email-new@example.com")
        XCTAssertEqual(doc.birthYear, 1990)
        XCTAssertEqual(doc.email, "new@example.com")
        XCTAssertEqual(doc.displayName, "new")
        XCTAssertEqual(doc.units, .kg)
        XCTAssertEqual(doc.timezone, "Etc/UTC")
        XCTAssertFalse(doc.physiqueConsent, "the score is opt-in, never on at creation")

        // A submit after routing on does nothing.
        try await session.submitBirthYear(1990)
        XCTAssertEqual(users.createCalls, 1)

        // Sign out and back in before onboarding: no second document, and onboarding resumes.
        try session.signOut()
        try await session.signIn(email: "new@example.com", password: "longenough")
        XCTAssertEqual(session.route, .onboarding)
        XCTAssertEqual(users.created.count, 1)
    }

    /// A user whose document has a birth year goes straight to the tabs: no A5, no onboarding.
    func testReturningUserSkipsOnboarding() async throws {
        let account = auth.addEmailAccount(email: "back@example.com", password: "longenough")
        users.seed(UserProfile(uid: account.uid, displayName: "Back", email: account.email, birthYear: 1988, createdAt: .now, goalPerWeek: 3))

        try await session.signIn(email: "back@example.com", password: "longenough")

        XCTAssertEqual(session.route, .main)
        XCTAssertEqual(users.createCalls, 0)
        XCTAssertTrue(users.birthYearUpdates.isEmpty)
        XCTAssertEqual(session.displayName, "Back")
    }

    /// A returning user restored from the keychain at launch also skips onboarding.
    func testRestoredSessionAtLaunchSkipsOnboarding() async {
        let user = AuthUser(uid: "kept", email: "kept@example.com", providers: [.google])
        fixture = Fixture(currentUser: user, seed: [UserProfile(uid: "kept", birthYear: 1995, goalPerWeek: 3)])

        XCTAssertEqual(session.route, .launching)
        await session.start()
        XCTAssertEqual(session.route, .main)
    }

    /// A document without a birth year routes to A5; saving fills in the year on that document
    /// and goes to the tabs, without creating a new one.
    func testMissingBirthYearRoutesToYearOfBirth() async throws {
        users.seed(UserProfile(uid: auth.googleUser.uid, displayName: "Sam", email: auth.googleUser.email, birthYear: nil, goalPerWeek: 3))

        try await session.signInWithGoogle()
        XCTAssertEqual(session.route, .yearOfBirth)

        try await session.submitBirthYear(1992)
        XCTAssertEqual(users.birthYearUpdates.count, 1)
        XCTAssertEqual(users.birthYearUpdates.first?.uid, auth.googleUser.uid)
        XCTAssertEqual(users.birthYearUpdates.first?.year, 1992)
        XCTAssertEqual(users.createCalls, 0)
        XCTAssertEqual(session.route, .main)
        XCTAssertEqual(session.profile?.birthYear, 1992)
    }

    /// Apple and Google never give an age, so a brand-new Apple user always sees A5.
    func testNewAppleUserRoutesToYearOfBirthAndKeepsAppleName() async throws {
        var name = PersonNameComponents()
        name.givenName = "Alex"
        name.familyName = "Kim"
        let credential = AppleSignInCredential(idToken: "token", rawNonce: "nonce", authorizationCode: "code", fullName: name)

        try await session.signInWithApple(credential)
        XCTAssertEqual(session.route, .yearOfBirth)

        try await session.submitBirthYear(2000)
        XCTAssertEqual(users.created.first?.displayName, credential.formattedName)
        XCTAssertEqual(session.route, .onboarding)
    }

    /// Delete account calls `deleteAccount`, signs out, and A1 shows "Your account is deleted."
    func testDeleteAccountCallsFunctionAndSignsOut() async throws {
        let account = auth.addEmailAccount(email: "gone@example.com", password: "longenough")
        users.seed(UserProfile(uid: account.uid, birthYear: 1990, goalPerWeek: 3))
        try await session.signIn(email: "gone@example.com", password: "longenough")
        XCTAssertEqual(session.route, .main)

        try await session.deleteAccount()

        XCTAssertEqual(functions.deleteAccountCalls, 1)
        XCTAssertEqual(auth.signOutCount, 1)
        XCTAssertNil(auth.currentUser)
        XCTAssertNil(session.user)
        XCTAssertNil(session.profile)
        XCTAssertEqual(session.route, .signedOut)
        XCTAssertEqual(session.notice, .accountDeleted)
        XCTAssertTrue(auth.revokedAppleCodes.isEmpty, "only Apple accounts have a token to revoke")
    }

    /// Apple users re-authenticate with Apple; the fresh code revokes the token before the function runs.
    func testDeleteAppleAccountRevokesAppleTokenThenCallsFunction() async throws {
        users.seed(UserProfile(uid: auth.appleUser.uid, birthYear: 1990, goalPerWeek: 3))
        try await session.signInWithApple(AppleSignInCredential(idToken: "t1", rawNonce: "n1", authorizationCode: "c1", fullName: nil))
        XCTAssertTrue(session.deletionNeedsAppleReauth)

        do {
            try await session.deleteAccount()
            XCTFail("an Apple account must sign in with Apple again first")
        } catch let error as AppSession.DeletionError {
            XCTAssertEqual(error, .appleReauthRequired)
        }
        XCTAssertEqual(functions.deleteAccountCalls, 0)
        XCTAssertEqual(session.route, .main)

        let fresh = AppleSignInCredential(idToken: "t2", rawNonce: "n2", authorizationCode: "fresh-code", fullName: nil)
        try await session.deleteAccount(appleCredential: fresh)

        XCTAssertEqual(auth.appleReauthCount, 1)
        XCTAssertEqual(auth.revokedAppleCodes, ["fresh-code"])
        XCTAssertEqual(functions.deleteAccountCalls, 1)
        XCTAssertEqual(auth.signOutCount, 1)
        XCTAssertEqual(session.route, .signedOut)
    }

    /// If the function fails, nothing changes on the phone: still signed in, on the tabs.
    func testDeleteAccountFailureKeepsUserSignedIn() async throws {
        let account = auth.addEmailAccount(email: "stay@example.com", password: "longenough")
        users.seed(UserProfile(uid: account.uid, birthYear: 1990, goalPerWeek: 3))
        try await session.signIn(email: "stay@example.com", password: "longenough")
        functions.nextError = URLError(.notConnectedToInternet)

        do {
            try await session.deleteAccount()
            XCTFail("expected the error to surface")
        } catch {}

        XCTAssertEqual(functions.deleteAccountCalls, 0)
        XCTAssertEqual(auth.signOutCount, 0)
        XCTAssertEqual(session.route, .main)
        XCTAssertNotNil(session.user)
        XCTAssertNil(session.notice)
    }

    /// F7's view model: DELETE must be typed; then it calls through to the session.
    func testDeleteViewModelNeedsTypedConfirmation() async {
        let account = auth.addEmailAccount(email: "vm@example.com", password: "longenough")
        users.seed(UserProfile(uid: account.uid, birthYear: 1990, goalPerWeek: 3))
        try? await session.signIn(email: "vm@example.com", password: "longenough")
        let model = DeleteAccountViewModel()

        model.confirmation = "delete"
        await model.deleteTapped(session: session)
        XCTAssertEqual(functions.deleteAccountCalls, 0)

        model.confirmation = "DELETE"
        await model.deleteTapped(session: session)
        XCTAssertEqual(functions.deleteAccountCalls, 1)
        XCTAssertEqual(session.route, .signedOut)
    }

    func testDeleteViewModelAsksAppleUsersToSignInAgain() async throws {
        users.seed(UserProfile(uid: auth.appleUser.uid, birthYear: 1990, goalPerWeek: 3))
        try await session.signInWithApple(AppleSignInCredential(idToken: "t", rawNonce: "n", authorizationCode: "c", fullName: nil))
        let model = DeleteAccountViewModel()
        model.confirmation = "DELETE"

        await model.deleteTapped(session: session)
        XCTAssertEqual(model.phase, .appleReauth)
        XCTAssertEqual(functions.deleteAccountCalls, 0)

        await model.appleReauthFinished(.failure(AuthFailure.cancelled), session: session)
        XCTAssertEqual(model.phase, .confirm)
        XCTAssertNil(model.errorText, "closing the Apple sheet is not an error")
    }

    // MARK: Sign-in edges

    func testSignOutReturnsToWelcome() async throws {
        let account = auth.addEmailAccount(email: "out@example.com", password: "longenough")
        users.seed(UserProfile(uid: account.uid, birthYear: 1990, goalPerWeek: 3))
        try await session.signIn(email: "out@example.com", password: "longenough")

        try session.signOut()
        XCTAssertEqual(session.route, .signedOut)
        XCTAssertNil(session.user)
        XCTAssertEqual(auth.signOutCount, 1)
    }

    func testCreateAccountSendsVerificationAndGoesToYearOfBirth() async throws {
        try await session.createAccount(email: "fresh@example.com", password: "longenough")

        XCTAssertEqual(auth.verificationEmailsSent, ["fresh@example.com"])
        XCTAssertEqual(session.verificationSentTo, "fresh@example.com")
        XCTAssertEqual(session.route, .yearOfBirth, "A5 does not wait for the link to be clicked")
        XCTAssertTrue(session.user?.needsEmailVerification == true)
    }

    func testUnderMinimumAgeStopsWithoutStoringAnything() async throws {
        try await session.createAccount(email: "kid@example.com", password: "longenough")
        try await session.submitBirthYear(year - AgePolicy.minimumAge + 1)

        XCTAssertEqual(session.route, .underMinimumAge)
        XCTAssertEqual(users.createCalls, 0)
    }

    func testProfileReadFailureShowsRetryThenRecovers() async throws {
        let account = auth.addEmailAccount(email: "flaky@example.com", password: "longenough")
        users.seed(UserProfile(uid: account.uid, birthYear: 1990, goalPerWeek: 3))
        users.nextError = URLError(.notConnectedToInternet)

        try await session.signIn(email: "flaky@example.com", password: "longenough")
        XCTAssertEqual(session.route, .profileUnavailable, "never guess A5 for a user who may already have a document")

        await session.retryProfile()
        XCTAssertEqual(session.route, .main)
    }

    func testRouteForProfile() {
        XCTAssertEqual(AppSession.route(for: nil, currentYear: year), .yearOfBirth)
        XCTAssertEqual(AppSession.route(for: UserProfile(uid: "a"), currentYear: year), .yearOfBirth)
        XCTAssertEqual(AppSession.route(for: UserProfile(uid: "a", birthYear: 1990, goalPerWeek: 3), currentYear: year), .main)
        XCTAssertEqual(AppSession.route(for: UserProfile(uid: "a", birthYear: 1990), currentYear: year), .onboarding,
                       "no weekly goal yet: onboarding was not finished")
        XCTAssertEqual(AppSession.route(for: UserProfile(uid: "a", birthYear: year - 5), currentYear: year), .underMinimumAge)
    }

    // MARK: Screen view models

    func testEmailViewModelChecksLocallyAndMapsErrors() async {
        let model = EmailAuthViewModel(mode: .create)
        model.email = "not-an-email"
        model.password = "longenough"
        await model.submit(session: session)
        XCTAssertEqual(model.errorText, AuthCopy.invalidEmail)

        model.email = "a@example.com"
        model.password = "short"
        await model.submit(session: session)
        XCTAssertEqual(model.errorText, AuthCopy.Email.passwordTooShort)
        XCTAssertEqual(session.route, .launching, "nothing reached the server")

        auth.addEmailAccount(email: "taken@example.com", password: "longenough")
        model.email = "taken@example.com"
        model.password = "longenough"
        await model.submit(session: session)
        XCTAssertEqual(model.errorText, AuthCopy.Email.emailInUse)
        XCTAssertTrue(model.offersSignIn)

        model.toggleMode()
        XCTAssertEqual(model.mode, .signIn)
        XCTAssertEqual(model.email, "taken@example.com", "the email carries over")
        model.password = "wrong-password"
        await model.submit(session: session)
        XCTAssertEqual(model.errorText, AuthCopy.Email.wrongCredentials)
    }

    func testResetPasswordNeverRevealsWhetherAccountExists() async {
        let model = ResetPasswordViewModel(email: "nobody@example.com")
        await model.send(session: session)
        XCTAssertEqual(model.sentTo, "nobody@example.com")
        XCTAssertNil(model.errorText)
        XCTAssertEqual(auth.passwordResetsSent, ["nobody@example.com"])

        let bad = ResetPasswordViewModel(email: "nope")
        await bad.send(session: session)
        XCTAssertNil(bad.sentTo)
        XCTAssertEqual(bad.errorText, AuthCopy.invalidEmail)
    }

    func testYearOfBirthViewModel() async {
        auth.addEmailAccount(email: "y@example.com", password: "longenough")
        try? await session.signIn(email: "y@example.com", password: "longenough")
        let model = YearOfBirthViewModel()

        XCTAssertEqual(YearOfBirthViewModel.sanitize("19a9 05"), "1990")
        model.text = "1899"
        await model.submit(session: session, currentYear: year)
        XCTAssertEqual(model.errorText, AuthCopy.YearOfBirth.checkYear)
        XCTAssertEqual(users.createCalls, 0)

        model.text = "1990"
        await model.submit(session: session, currentYear: year)
        XCTAssertNil(model.errorText)
        XCTAssertEqual(users.createCalls, 1)
        XCTAssertEqual(session.route, .onboarding)
    }
}

/// Pure helpers: nonce, error mapping, age and input rules.
@MainActor
final class AuthHelperTests: XCTestCase {
    func testNonceIsRandomAndUsesTheCharset() {
        let a = AppleNonce.random()
        let b = AppleNonce.random()
        XCTAssertEqual(a.count, 32)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(AppleNonce.charset.count, 64)
        XCTAssertTrue(a.allSatisfy { AppleNonce.charset.contains($0) })
    }

    /// Apple gets the SHA-256 hex of the raw nonce. Known vector for "abc" (FIPS 180-2).
    func testNonceHashIsLowercaseHexSHA256() {
        XCTAssertEqual(
            AppleNonce.sha256("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func testAppleCredentialParsing() throws {
        var name = PersonNameComponents()
        name.givenName = "Alex"
        let credential = try AppleSignInFlow.credential(
            identityToken: Data("jwt".utf8),
            authorizationCode: Data("code".utf8),
            fullName: name,
            rawNonce: "raw"
        )
        XCTAssertEqual(credential.idToken, "jwt")
        XCTAssertEqual(credential.rawNonce, "raw")
        XCTAssertEqual(credential.authorizationCode, "code")
        XCTAssertNotNil(credential.fullName)

        // Apple sends an empty name on every sign-in after the first: treat it as no name.
        let later = try AppleSignInFlow.credential(
            identityToken: Data("jwt".utf8), authorizationCode: nil, fullName: PersonNameComponents(), rawNonce: "raw"
        )
        XCTAssertNil(later.fullName)

        XCTAssertThrowsError(try AppleSignInFlow.credential(identityToken: Data("jwt".utf8), authorizationCode: nil, fullName: nil, rawNonce: nil))
        XCTAssertThrowsError(try AppleSignInFlow.credential(identityToken: nil, authorizationCode: nil, fullName: nil, rawNonce: "raw"))
    }

    func testErrorMapping() {
        func ns(_ domain: String, _ code: Int) -> NSError { NSError(domain: domain, code: code) }
        let firebase = AuthFailure.firebaseAuthDomain
        XCTAssertEqual(AuthFailure(ns(firebase, 17009)), .wrongCredentials)
        XCTAssertEqual(AuthFailure(ns(firebase, 17011)), .wrongCredentials)
        XCTAssertEqual(AuthFailure(ns(firebase, 17004)), .wrongCredentials)
        XCTAssertEqual(AuthFailure(ns(firebase, 17008)), .invalidEmail)
        XCTAssertEqual(AuthFailure(ns(firebase, 17007)), .emailAlreadyInUse)
        XCTAssertEqual(AuthFailure(ns(firebase, 17026)), .weakPassword)
        XCTAssertEqual(AuthFailure(ns(firebase, 17010)), .tooManyRequests)
        XCTAssertEqual(AuthFailure(ns(firebase, 17020)), .network)
        XCTAssertEqual(AuthFailure(ns(firebase, 17014)), .requiresRecentLogin)
        XCTAssertEqual(AuthFailure(ns(AuthFailure.googleSignInDomain, -5)), .cancelled)
        XCTAssertEqual(AuthFailure(ns(AuthFailure.appleAuthorizationDomain, 1001)), .cancelled)
        XCTAssertEqual(AuthFailure(ns(AuthFailure.appleAuthorizationDomain, 1000)), .unknown)
        XCTAssertEqual(AuthFailure(URLError(.notConnectedToInternet)), .network)
        XCTAssertEqual(AuthFailure(AuthFailure.emailAlreadyInUse), .emailAlreadyInUse)
    }

    func testYearCheck() {
        XCTAssertEqual(AgePolicy.check("1990", currentYear: 2026), .ok(1990))
        XCTAssertEqual(AgePolicy.check("1899", currentYear: 2026), .invalid)
        XCTAssertEqual(AgePolicy.check("2027", currentYear: 2026), .invalid)
        XCTAssertEqual(AgePolicy.check("199", currentYear: 2026), .invalid)
        XCTAssertEqual(AgePolicy.check("", currentYear: 2026), .invalid)
        XCTAssertEqual(AgePolicy.check("2020", currentYear: 2026), .tooYoung(2020))
        XCTAssertEqual(AgePolicy.check("\(2026 - AgePolicy.minimumAge)", currentYear: 2026), .ok(2026 - AgePolicy.minimumAge))
    }

    func testEmailAndPasswordRules() {
        XCTAssertTrue(EmailFormat.isPlausible("you@example.com"))
        XCTAssertTrue(EmailFormat.isPlausible(" you@example.co.uk "))
        XCTAssertFalse(EmailFormat.isPlausible("you@example"))
        XCTAssertFalse(EmailFormat.isPlausible("@example.com"))
        XCTAssertFalse(EmailFormat.isPlausible("you@@example.com"))
        XCTAssertFalse(EmailFormat.isPlausible("you example@x.com"))
        XCTAssertFalse(PasswordPolicy.isLongEnough("1234567"))
        XCTAssertTrue(PasswordPolicy.isLongEnough("12345678"))
    }

    func testNewProfileNeverWritesServerOwnedFields() {
        let draft = NewUserProfile(uid: "u", displayName: nil, email: "e@example.com", birthYear: 1990, units: .lb, timezone: "UTC")
        let fields = draft.firestoreFields
        for serverOnly in ["proofNumber", "stampedAt", "streakWeeks", "longestStreak", "passWeeks", "proofCount", "physique"] {
            XCTAssertNil(fields[serverOnly], serverOnly)
        }
        XCTAssertEqual(fields["birthYear"] as? Int, 1990)
        XCTAssertEqual(fields["units"] as? String, "lb")
        XCTAssertEqual(fields["physiqueConsent"] as? Bool, false)
        XCTAssertNil(fields["displayName"])
    }

    func testProviderMapping() {
        XCTAssertEqual(AuthProvider(firebaseProviderID: "apple.com"), .apple)
        XCTAssertEqual(AuthProvider(firebaseProviderID: "google.com"), .google)
        XCTAssertEqual(AuthProvider(firebaseProviderID: "password"), .email)
        XCTAssertNil(AuthProvider(firebaseProviderID: "phone"))
    }

    func testFallbackName() {
        XCTAssertEqual(AuthUser(uid: "1", email: "sam@example.com", providers: [.email]).fallbackName, "sam")
        XCTAssertEqual(AuthUser(uid: "1", email: "sam@example.com", displayName: "Sam Lee", providers: [.google]).fallbackName, "Sam Lee")
        XCTAssertNil(AuthUser(uid: "1", providers: [.apple]).fallbackName)
    }

    func testBackendSelection() {
        XCTAssertEqual(AppEnvironment.backend(arguments: ["-pgym-ui-test"], firebase: .configured(emulatorHost: nil)), .fake(signedIn: false))
        XCTAssertEqual(AppEnvironment.backend(arguments: ["-pgym-ui-test-signed-in"], firebase: .missingConfig), .fake(signedIn: true))
        XCTAssertEqual(AppEnvironment.backend(arguments: [], firebase: .configured(emulatorHost: "127.0.0.1")), .firebase)
        XCTAssertEqual(AppEnvironment.backend(arguments: [], firebase: .missingConfig), .fake(signedIn: false))
    }

    func testViewIDsTouchedByThisCard() {
        XCTAssertEqual(AuthFeature.viewIDs, ["A1", "A2", "A3", "A4", "A5", "F7"])
        XCTAssertEqual(WelcomeScreen.viewID, "A1")
        XCTAssertEqual(ResetPasswordSheet.viewID, "A4")
        XCTAssertEqual(YearOfBirthScreen.viewID, "A5")
        XCTAssertEqual(DeleteAccountScreen.viewID, "F7")
    }
}
