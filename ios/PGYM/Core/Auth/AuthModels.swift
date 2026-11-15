import Foundation

/// The sign-in methods in pgym-architecture.md, "Sign-in".
enum AuthProvider: String, CaseIterable, Sendable {
    case apple
    case google
    case email

    /// Firebase's provider ID for this method (`UserInfo.providerID`).
    var firebaseProviderID: String {
        switch self {
        case .apple: "apple.com"
        case .google: "google.com"
        case .email: "password"
        }
    }

    init?(firebaseProviderID: String) {
        guard let match = Self.allCases.first(where: { $0.firebaseProviderID == firebaseProviderID }) else {
            return nil
        }
        self = match
    }
}

/// The signed-in user as the app sees it. Built from Firebase's `User` in the live service and
/// by hand in the fakes, so nothing above the auth layer imports Firebase.
struct AuthUser: Equatable, Sendable {
    let uid: String
    var email: String?
    var displayName: String?
    var providers: Set<AuthProvider>
    var isEmailVerified: Bool

    init(
        uid: String,
        email: String? = nil,
        displayName: String? = nil,
        providers: Set<AuthProvider>,
        isEmailVerified: Bool = true
    ) {
        self.uid = uid
        self.email = email
        self.displayName = displayName
        self.providers = providers
        self.isEmailVerified = isEmailVerified
    }

    /// Email accounts that have not clicked the link yet. Apple and Google addresses count as verified.
    var needsEmailVerification: Bool {
        providers == [.email] && !isEmailVerified
    }

    /// F1 "Pre-filled: name from Apple or Google, or the email's part before the @."
    var fallbackName: String? {
        if let displayName, !displayName.trimmingCharacters(in: .whitespaces).isEmpty { return displayName }
        guard let email, let at = email.firstIndex(of: "@"), at > email.startIndex else { return nil }
        return String(email[..<at])
    }
}

/// What Sign in with Apple hands back, reduced to what Firebase and the revoke call need.
struct AppleSignInCredential: Equatable, Sendable {
    /// The identity token (a JWT) as a UTF-8 string.
    let idToken: String
    /// The nonce before hashing. Apple saw only its SHA-256; Firebase checks the two match.
    let rawNonce: String
    /// Short-lived code, used once to revoke the Apple token when the account is deleted.
    let authorizationCode: String?
    /// Apple sends the name only on the very first authorisation for this app.
    let fullName: PersonNameComponents?

    /// "Sam Lee", or nil when Apple sent no name.
    var formattedName: String? {
        guard let fullName else { return nil }
        let name = PersonNameComponentsFormatter.localizedString(from: fullName, style: .default)
        return name.isEmpty ? nil : name
    }
}

/// `users/{uid}` as read back from Firestore. Only the fields sign-in cares about; the rest of the
/// document (goal, schedule, streak counters) belongs to onboarding and the functions.
struct UserProfile: Equatable, Sendable {
    let uid: String
    var displayName: String?
    var email: String?
    var birthYear: Int?
    var createdAt: Date?
}

/// The fields the phone writes when it creates `users/{uid}` after A5.
/// Server-owned fields (streakWeeks, longestStreak, passWeeks, proofCount, physique) are never here:
/// the security rules block them from the client (pgym-architecture.md, "Data model").
struct NewUserProfile: Equatable, Sendable {
    let uid: String
    var displayName: String?
    var email: String?
    var birthYear: Int
    var units: Units
    var timezone: String
    /// Always false at creation. The score is opt-in (D10), never on by default.
    var physiqueConsent: Bool = false

    enum Units: String, Sendable {
        case kg, lb

        /// kg everywhere except US-measure locales. B5 lets the user change it.
        static func `default`(for locale: Locale = .current) -> Units {
            locale.measurementSystem == .us ? .lb : .kg
        }
    }

    /// The Firestore field map, without `createdAt` (the repository adds the server timestamp).
    var firestoreFields: [String: Any] {
        var fields: [String: Any] = [
            "birthYear": birthYear,
            "units": units.rawValue,
            "timezone": timezone,
            "physiqueConsent": physiqueConsent,
        ]
        if let displayName { fields["displayName"] = displayName }
        if let email { fields["email"] = email }
        return fields
    }
}

/// Every way sign-in can fail, in words the screens can map to copy. Firebase, Google and Apple
/// errors are translated in `AuthFailure.init(_:)`, so no screen looks at an NSError code.
enum AuthFailure: Error, Equatable {
    /// The user closed the Apple or Google sheet. Not an error: the screen shows nothing.
    case cancelled
    /// Wrong password or unknown email. One case on purpose: the screen never says which.
    case wrongCredentials
    case invalidEmail
    case emailAlreadyInUse
    case weakPassword
    case tooManyRequests
    case network
    /// Firebase wants a fresh sign-in before a sensitive change.
    case requiresRecentLogin
    /// No Firebase project or Google client ID in this build.
    case notConfigured
    case unknown

    // Firebase Auth error codes (FIRAuthErrorCode). Kept as numbers so this file does not
    // depend on how a given SDK version spells the enum.
    static let firebaseAuthDomain = "FIRAuthErrorDomain"
    static let googleSignInDomain = "com.google.GIDSignIn"
    static let appleAuthorizationDomain = "com.apple.AuthenticationServices.AuthorizationError"

    init(_ error: Error) {
        if let failure = error as? AuthFailure {
            self = failure
            return
        }
        let ns = error as NSError
        switch ns.domain {
        case Self.firebaseAuthDomain:
            switch ns.code {
            case 17004, 17009, 17011: self = .wrongCredentials // invalidCredential, wrongPassword, userNotFound
            case 17008: self = .invalidEmail
            case 17007: self = .emailAlreadyInUse
            case 17026: self = .weakPassword
            case 17010: self = .tooManyRequests
            case 17020: self = .network
            case 17014: self = .requiresRecentLogin
            case 17012: self = .cancelled // webContextCancelled
            default: self = .unknown
            }
        case Self.googleSignInDomain:
            self = ns.code == -5 ? .cancelled : .unknown // kGIDSignInErrorCodeCanceled
        case Self.appleAuthorizationDomain:
            self = ns.code == 1001 ? .cancelled : .unknown // ASAuthorizationError.canceled
        case NSURLErrorDomain:
            self = .network
        default:
            self = .unknown
        }
    }
}

/// Minimum age and the year-of-birth rules for A5.
enum AgePolicy {
    /// The app's minimum age. **Undecided** (pgym-flow-spec.md open question 5, README open
    /// decision 4); 13 is the copy deck's sample value. Change it here and nowhere else.
    static let minimumAge = 13
    /// The physique score needs 18 or over (pgym-design.md).
    static let physiqueScoreAge = 18
    static let earliestYear = 1900

    enum YearCheck: Equatable {
        case ok(Int)
        /// Not four digits, before 1900 or in the future: "Check the year."
        case invalid
        /// Younger than `minimumAge`: the stop screen.
        case tooYoung(Int)
    }

    static func currentYear(now: Date = .now, calendar: Calendar = .current) -> Int {
        calendar.component(.year, from: now)
    }

    /// Age from the year alone, taken as the age reached this calendar year. Only the year is
    /// stored, so a birthday later this year is not knowable; this errs one year old.
    static func age(birthYear: Int, currentYear: Int) -> Int {
        currentYear - birthYear
    }

    static func check(_ text: String, currentYear: Int) -> YearCheck {
        let digits = text.trimmingCharacters(in: .whitespaces)
        guard digits.count == 4, digits.allSatisfy(\.isASCII), let year = Int(digits),
              (earliestYear...currentYear).contains(year)
        else { return .invalid }
        return age(birthYear: year, currentYear: currentYear) < minimumAge ? .tooYoung(year) : .ok(year)
    }
}

/// Plain email shape check before calling Firebase, so a typo gets an instant answer.
enum EmailFormat {
    static func isPlausible(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard let at = trimmed.firstIndex(of: "@"), at > trimmed.startIndex else { return false }
        let domain = trimmed[trimmed.index(after: at)...]
        guard !domain.contains("@"), !trimmed.contains(" ") else { return false }
        guard let dot = domain.lastIndex(of: "."), dot > domain.startIndex else { return false }
        return domain.distance(from: dot, to: domain.endIndex) > 2
    }
}

/// Password rule shown in create mode. `{min}` in the copy deck is not decided; 8 is its sample.
/// Firebase's own floor is 6, so 8 is always accepted by the server.
enum PasswordPolicy {
    static let minimumLength = 8

    static func isLongEnough(_ password: String) -> Bool {
        password.count >= minimumLength
    }
}
