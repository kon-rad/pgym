import AuthenticationServices
import CryptoKit
import Foundation
import Security

/// The nonce for Sign in with Apple, done the way Firebase requires:
/// 1. make a random raw nonce on the phone,
/// 2. send only its SHA-256 (hex) to Apple in the request,
/// 3. send the raw nonce to Firebase with the identity token; Firebase hashes it and checks it
///    matches the `nonce` claim Apple signed. A replayed token fails because the raw nonce is
///    new for every request and never leaves the phone except to Firebase.
enum AppleNonce {
    static let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
    static let length = 32

    /// A random nonce from the system's secure generator.
    static func random(length: Int = AppleNonce.length) -> String {
        precondition(length > 0)
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            // SecRandomCopyBytes does not fail on iOS in practice; fall back to the system RNG,
            // which is also cryptographically secure on Apple platforms.
            var rng = SystemRandomNumberGenerator()
            bytes = (0..<length).map { _ in UInt8.random(in: .min ... .max, using: &rng) }
        }
        // 256 is a multiple of the 64-character set, so the modulo adds no bias.
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    /// Lower-case hex SHA-256, the form Apple puts in the token's `nonce` claim.
    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Holds the raw nonce between the Apple request and its completion, and turns the result into
/// an `AppleSignInCredential`. One per screen that shows a Sign in with Apple button.
@MainActor
final class AppleSignInFlow {
    private(set) var rawNonce: String?

    init() {}

    /// Called from `SignInWithAppleButton`'s request closure.
    func prepare(_ request: ASAuthorizationAppleIDRequest, scopes: [ASAuthorization.Scope] = [.fullName, .email]) {
        let nonce = AppleNonce.random()
        rawNonce = nonce
        request.requestedScopes = scopes
        request.nonce = AppleNonce.sha256(nonce)
    }

    /// Called from the button's completion closure. Throws `AuthFailure.cancelled` when the user
    /// closed the sheet.
    func credential(from result: Result<ASAuthorization, Error>) throws -> AppleSignInCredential {
        defer { rawNonce = nil }
        switch result {
        case .failure(let error):
            throw AuthFailure(error)
        case .success(let authorization):
            guard let apple = authorization.credential as? ASAuthorizationAppleIDCredential else {
                throw AuthFailure.unknown
            }
            return try Self.credential(
                identityToken: apple.identityToken,
                authorizationCode: apple.authorizationCode,
                fullName: apple.fullName,
                rawNonce: rawNonce
            )
        }
    }

    /// The pure part, tested without a real Apple sheet.
    nonisolated static func credential(
        identityToken: Data?,
        authorizationCode: Data?,
        fullName: PersonNameComponents?,
        rawNonce: String?
    ) throws -> AppleSignInCredential {
        // A completion without a pending nonce means the request did not come from `prepare`.
        guard let rawNonce, !rawNonce.isEmpty else { throw AuthFailure.unknown }
        guard let identityToken, let token = String(data: identityToken, encoding: .utf8), !token.isEmpty else {
            throw AuthFailure.unknown
        }
        let code = authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        let hasName = fullName.map { ($0.givenName ?? "").isEmpty == false || ($0.familyName ?? "").isEmpty == false } ?? false
        return AppleSignInCredential(
            idToken: token,
            rawNonce: rawNonce,
            authorizationCode: code,
            fullName: hasName ? fullName : nil
        )
    }
}
