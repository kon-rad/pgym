/// Sign-in, views A1 to A5, and account deletion (F7). Card I2.
///
/// | ID | Screen | Type |
/// |---|---|---|
/// | A1 | Welcome | `WelcomeScreen` |
/// | A2 | Email sign-in | `EmailSignInScreen`, sign-in mode |
/// | A3 | Create account with email | `EmailSignInScreen`, create mode (merged into A2 by the flow spec) |
/// | A4 | Reset password | `ResetPasswordSheet` |
/// | A5 | Year of birth | `YearOfBirthScreen`, plus `UnderMinimumAgeScreen` |
/// | F7 | Delete account | `DeleteAccountScreen` (in Features/Profile) |
///
/// State and routing: `AppSession`. Services: Core/Auth (`AuthService`, `UserRepository`,
/// `AccountFunctions`, with HTTPS and fake implementations).
enum AuthFeature {
    static let viewIDs = ["A1", "A2", "A3", "A4", "A5", "F7"]
}
