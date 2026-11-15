import Foundation

/// Every string on A1 to A5 and F7, from Areas/PGYM/copy/pgym-app-copy.md (the copy deck).
/// Where the deck has no line for a state the flow spec names, the flow spec's draft line is used
/// and marked "flow spec".
enum AuthCopy {
    // Shared
    static let noConnection = "No connection. Sign-in needs one." // flow spec, A1/A2/A4
    static let needsConnection = "Needs a connection." // flow spec, F7
    static let legal = "By continuing you agree to the Terms and the Privacy Policy."
    static let terms = "Terms"
    static let privacy = "Privacy Policy"
    static let emailLabel = "Email"
    static let emailPlaceholder = "you@example.com"
    static let passwordLabel = "Password"
    static let show = "Show"
    static let hide = "Hide"
    static let invalidEmail = "That does not look like an email address."
    static let genericFailure = "Sign-in did not go through. Try again."

    enum Welcome { // A1
        static let headline = "Proof of gym."
        static let subline = "Log your sets. Take one photo. Get a stamped card that says you showed up."
        static let google = "Continue with Google"
        static let email = "Use email instead"
        static let accountDeleted = "Your account is deleted."
        static let close = "Close"
    }

    enum Email { // A2 and A3
        static let signInTitle = "Sign in"
        static let signInButton = "Sign in"
        static let createTitle = "Create account"
        static let createButton = "Create account"
        static let switchToCreate = "Create account"
        static let switchToSignIn = "Sign in instead"
        static let forgot = "Forgot password"
        static let passwordHint = "At least \(PasswordPolicy.minimumLength) characters."
        static let wrongCredentials = "That email and password do not match."
        static let tooManyTries = "Too many tries. Wait a few minutes and try again."
        static let emailInUse = "There is already an account with that email. Sign in instead."
        static let passwordTooShort = "That password is too short."
    }

    enum Reset { // A4
        static let title = "Reset password"
        static let body = "Enter your email. We will send a link to set a new password."
        static let send = "Send link"
        static let sentTitle = "Link sent"
        static func sentBody(_ email: String) -> String {
            "If there is an account for \(email), a reset link is on its way."
        }
        static let sendAgain = "Send it again"
        static let back = "Back to sign in"
    }

    enum YearOfBirth { // A5
        static let title = "One question"
        static let body = "What year were you born? The AI score stays off for anyone under 18."
        static let label = "Year of birth"
        static let placeholder = "1990"
        static let button = "Continue"
        static let checkYear = "Check the year." // flow spec, A5 error
        static func tooYoung(_ minAge: Int = AgePolicy.minimumAge) -> String {
            "PGYM is for people aged \(minAge) and over."
        }
        static func checkInbox(_ email: String) -> String {
            "Check your inbox. We sent a link to \(email)."
        }
        static let signOut = "Sign out"
        static let couldNotSave = "Could not save. Check your connection and try again."
    }

    enum Profile { // F1 additions for sign-in
        static func memberSince(_ month: String) -> String { "Member since \(month)" }
        static let accountEmail = "Account email"
        static let notVerified = "Not verified."
        static let resend = "Send the link again"
        static func linkSent(_ email: String) -> String { "Check your inbox. We sent a link to \(email)." }
        static let signOut = "Sign out"
        static let signOutTitle = "Sign out of PGYM?"
        static let cancel = "Cancel"
        static let deleteAccount = "Delete account"
        static let couldNotLoad = "Could not load your profile."
        static let retry = "Retry"
    }

    enum Delete { // F7
        static let title = "Delete account"
        static let intro = "This deletes your account and everything in it:"
        static let items = [
            "Every photo and card",
            "Every session, set and routine",
            "Your scores and tips",
            "Your agent tokens",
            "Your sign-in",
        ]
        static let shared = "Cards you already shared stay wherever you posted them. PGYM cannot remove those."
        static let apple = "If you signed in with Apple, PGYM's access to your Apple ID is removed too."
        static let confirmLabel = "Type DELETE to confirm"
        static let confirmWord = "DELETE"
        static let button = "Delete my account"
        static let reauth = "Sign in again before deleting. It keeps someone else from doing this."
        static let progress = "Deleting your account."
        static let failed = "The account was not deleted. Check your connection and try again."
    }
}
