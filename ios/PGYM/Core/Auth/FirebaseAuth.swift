#if canImport(FirebaseAuth)
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseFunctions
import Foundation
import GoogleSignIn
import UIKit

/// `AuthService` on Firebase Authentication: Apple (with the nonce), Google, email and password.
@MainActor
final class FirebaseAuthService: AuthService {
    private let auth: Auth

    init(auth: Auth = .auth()) {
        self.auth = auth
    }

    var currentUser: AuthUser? {
        auth.currentUser.map(Self.makeUser)
    }

    static func makeUser(_ user: User) -> AuthUser {
        AuthUser(
            uid: user.uid,
            email: user.email,
            displayName: user.displayName,
            providers: Set(user.providerData.compactMap { AuthProvider(firebaseProviderID: $0.providerID) }),
            isEmailVerified: user.isEmailVerified
        )
    }

    private func run<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch {
            throw AuthFailure(error)
        }
    }

    // MARK: Apple

    func signInWithApple(_ credential: AppleSignInCredential) async throws -> AuthUser {
        try await run {
            let firebaseCredential = OAuthProvider.appleCredential(
                withIDToken: credential.idToken,
                rawNonce: credential.rawNonce,
                fullName: credential.fullName
            )
            let result = try await auth.signIn(with: firebaseCredential)
            // Apple sends the name once. Keep it on the Firebase user so a reinstall still has it.
            if result.user.displayName == nil, let name = credential.formattedName {
                let change = result.user.createProfileChangeRequest()
                change.displayName = name
                try? await change.commitChanges()
            }
            var user = Self.makeUser(result.user)
            if user.displayName == nil { user.displayName = credential.formattedName }
            return user
        }
    }

    func reauthenticateWithApple(_ credential: AppleSignInCredential) async throws {
        try await run {
            guard let user = auth.currentUser else { throw AuthFailure.unknown }
            let firebaseCredential = OAuthProvider.appleCredential(
                withIDToken: credential.idToken,
                rawNonce: credential.rawNonce,
                fullName: credential.fullName
            )
            _ = try await user.reauthenticate(with: firebaseCredential)
        }
    }

    func revokeAppleToken(authorizationCode: String) async throws {
        try await run {
            try await auth.revokeToken(withAuthorizationCode: authorizationCode)
        }
    }

    // MARK: Google

    func signInWithGoogle() async throws -> AuthUser {
        try await run {
            guard let clientID = FirebaseApp.app()?.options.clientID, !clientID.isEmpty else {
                throw AuthFailure.notConfigured
            }
            guard let presenter = Self.topViewController() else { throw AuthFailure.unknown }
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let idToken = result.user.idToken?.tokenString else { throw AuthFailure.unknown }
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
            let signedIn = try await auth.signIn(with: credential)
            return Self.makeUser(signedIn.user)
        }
    }

    /// The view controller Google's sheet is presented from.
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }

    // MARK: Email

    func signIn(email: String, password: String) async throws -> AuthUser {
        try await run {
            let result = try await auth.signIn(withEmail: email, password: password)
            return Self.makeUser(result.user)
        }
    }

    func createAccount(email: String, password: String) async throws -> AuthUser {
        try await run {
            let result = try await auth.createUser(withEmail: email, password: password)
            return Self.makeUser(result.user)
        }
    }

    func sendEmailVerification() async throws {
        try await run {
            guard let user = auth.currentUser else { throw AuthFailure.unknown }
            try await user.sendEmailVerification()
        }
    }

    func sendPasswordReset(email: String) async throws {
        do {
            try await auth.sendPasswordReset(withEmail: email)
        } catch {
            let failure = AuthFailure(error)
            // Never reveal whether the account exists: an unknown email is a success to the user.
            if failure == .wrongCredentials { return }
            throw failure
        }
    }

    func reloadUser() async throws -> AuthUser? {
        try await run {
            guard let user = auth.currentUser else { return nil }
            try await user.reload()
            return auth.currentUser.map(Self.makeUser)
        }
    }

    func signOut() throws {
        do {
            try auth.signOut()
        } catch {
            throw AuthFailure(error)
        }
        GIDSignIn.sharedInstance.signOut()
    }

    /// Hands Google's redirect URL back to its SDK.
    static func handleOpenURL(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }
}

/// `users/{uid}` on Cloud Firestore.
@MainActor
final class FirestoreUserRepository: UserRepository {
    private let db: Firestore

    init(db: Firestore = .firestore()) {
        self.db = db
    }

    private func document(_ uid: String) -> DocumentReference {
        db.collection("users").document(uid)
    }

    func fetchProfile(uid: String) async throws -> UserProfile? {
        let snapshot = try await document(uid).getDocument()
        guard snapshot.exists, let data = snapshot.data() else { return nil }
        return UserProfile(
            uid: uid,
            displayName: data["displayName"] as? String,
            email: data["email"] as? String,
            birthYear: (data["birthYear"] as? NSNumber)?.intValue,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue(),
            goalPerWeek: (data["goalPerWeek"] as? NSNumber)?.intValue,
            gymDays: (data["gymDays"] as? [String])?.compactMap(Weekday.init(rawValue:)),
            reminderTime: (data["reminderTime"] as? String).flatMap(ReminderTime.init(string:)),
            units: (data["units"] as? String).flatMap(NewUserProfile.Units.init(rawValue:)),
            streakWeeks: (data["streakWeeks"] as? NSNumber)?.intValue,
            proofCount: (data["proofCount"] as? NSNumber)?.intValue
        )
    }

    func saveOnboarding(_ settings: OnboardingSettings, uid: String) async throws {
        try await document(uid).setData(settings.firestoreFields, merge: true)
    }

    func saveRoutines(_ routines: [RoutineDraft], uid: String) async throws {
        let batch = db.batch()
        for routine in routines {
            let ref = document(uid).collection("routines").document(routine.id)
            batch.setData(routine.firestoreFields, forDocument: ref)
        }
        try await batch.commit()
    }

    func createProfileIfMissing(_ profile: NewUserProfile) async throws -> Bool {
        let ref = document(profile.uid)
        var fields = profile.firestoreFields
        fields["createdAt"] = FieldValue.serverTimestamp()
        let payload = fields
        // A transaction, so two devices (or a double tap) finishing A5 at once write one document.
        let result = try await db.runTransaction { transaction, errorPointer -> Any? in
            do {
                let snapshot = try transaction.getDocument(ref)
                if snapshot.exists { return false }
                transaction.setData(payload, forDocument: ref)
                return true
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
        return (result as? Bool) ?? false
    }

    func setBirthYear(_ year: Int, uid: String) async throws {
        try await document(uid).setData(["birthYear": year], merge: true)
    }
}

/// The callable functions, on Cloud Functions for Firebase.
@MainActor
final class FirebaseAccountFunctions: AccountFunctions {
    private let functions: Functions

    init(functions: Functions = .functions()) {
        self.functions = functions
    }

    func deleteAccount() async throws {
        _ = try await functions.httpsCallable("deleteAccount").call()
    }
}

extension AuthDependencies {
    /// The real services. Only valid after `FirebaseBootstrap.configure` returned `.configured`.
    static func firebase() -> AuthDependencies {
        AuthDependencies(
            auth: FirebaseAuthService(),
            users: FirestoreUserRepository(),
            functions: FirebaseAccountFunctions(),
            handleOpenURL: { FirebaseAuthService.handleOpenURL($0) }
        )
    }
}
#endif
