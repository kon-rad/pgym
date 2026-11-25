import Foundation

#if canImport(FirebaseCore)
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
#endif

/// Configures Firebase from a `GoogleService-Info.plist` that is NOT in git.
///
/// - No plist in the bundle: Firebase stays off and the app still launches (CI, a fresh clone).
/// - `PGYM_EMULATOR_HOST` set in the scheme's environment: Auth, Firestore and Functions
///   talk to the local Firebase emulator suite on that host instead of a real project.
///
/// See ios/README.md, "Firebase configuration".
enum FirebaseBootstrap {
    enum Outcome: Equatable {
        case configured(emulatorHost: String?)
        case missingConfig
    }

    static let plistName = "GoogleService-Info"
    static let emulatorHostKey = "PGYM_EMULATOR_HOST"

    /// The Firebase emulator suite's default ports. Keep in step with backend/firebase.json once it exists.
    enum EmulatorPort {
        static let auth = 9099
        static let firestore = 8080
    }

    /// Path of the config plist in `bundle`, if someone dropped one in.
    static func configPath(in bundle: Bundle) -> String? {
        bundle.path(forResource: plistName, ofType: "plist")
    }

    @discardableResult
    static func configure(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Outcome {
        guard let path = configPath(in: bundle) else { return .missingConfig }
        #if canImport(FirebaseCore)
        guard let options = FirebaseOptions(contentsOfFile: path) else { return .missingConfig }
        let host = environment[emulatorHostKey].flatMap { $0.isEmpty ? nil : $0 }
        if FirebaseApp.app() == nil {
            FirebaseApp.configure(options: options)
        }
        if let host {
            Auth.auth().useEmulator(withHost: host, port: EmulatorPort.auth)
            let settings = Firestore.firestore().settings
            settings.host = "\(host):\(EmulatorPort.firestore)"
            settings.isSSLEnabled = false
            Firestore.firestore().settings = settings
        }
        return .configured(emulatorHost: host)
        #else
        _ = path
        return .missingConfig
        #endif
    }
}
