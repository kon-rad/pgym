import CoreText
import Foundation

/// Registers the bundled fonts with CoreText for this process.
///
/// The fonts live in this package's bundle, not the app's, so `UIAppFonts` in Info.plist
/// cannot see them. Call `FontRegistry.registerAll()` once at launch; previews call it too.
public enum FontRegistry {
    public struct Failure: Error, Equatable, Sendable {
        public let face: FontFace
        public let reason: String
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var registered = false

    /// Registers every `FontFace`. Safe to call more than once.
    /// Returns the faces that could not be registered (empty on success).
    @discardableResult
    public static func registerAll() -> [Failure] {
        lock.lock()
        defer { lock.unlock() }
        guard !registered else { return [] }
        var failures: [Failure] = []
        for face in FontFace.allCases {
            guard let url = url(for: face) else {
                failures.append(Failure(face: face, reason: "missing from bundle"))
                continue
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                let cfError = error?.takeRetainedValue()
                // Already registered (for example by a second test host) is fine.
                if let cfError, CFErrorGetCode(cfError) == CTFontManagerError.alreadyRegistered.rawValue {
                    continue
                }
                failures.append(Failure(face: face, reason: cfError.map { "\($0)" } ?? "unknown"))
            }
        }
        registered = failures.isEmpty
        return failures
    }

    /// Location of a face's TTF in the package bundle.
    public static func url(for face: FontFace) -> URL? {
        Bundle.module.url(forResource: face.fileName, withExtension: "ttf", subdirectory: "Fonts")
    }

    /// The OFL licence texts that ship next to the fonts.
    public static var licenceURLs: [URL] {
        ["OFL-Anton", "OFL-Archivo", "OFL-JetBrainsMono"].compactMap {
            Bundle.module.url(forResource: $0, withExtension: "txt", subdirectory: "Fonts")
        }
    }
}
