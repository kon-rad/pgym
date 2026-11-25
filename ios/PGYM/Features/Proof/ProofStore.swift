import CoreGraphics
import DesignSystem
import Foundation

/// The proof's files on the phone, one folder per session:
/// `Application Support/Proofs/{sessionId}/photo.jpg`, `card.jpg` and `card.json`.
///
/// The photo is saved the moment it is taken and the card the moment Stamp it is tapped, so a kill at
/// any point loses nothing (pgym-flow-spec.md, "When the app is killed mid-session"). Card I7 uploads
/// both files to the same names under `users/{uid}/sessions/{sessionId}/` and re-renders the card when
/// `stampSession` returns. Both files are already clean: no EXIF, no GPS.
struct ProofStore {
    /// What Stamp it recorded next to the card, so the card can be re-rendered with the server's values.
    struct CardRecord: Codable, Equatable {
        var options: ProofCardOptions
        /// When Stamp it was tapped: the session's end, and the phone time on the pending card.
        var stampTappedAt: Date
    }

    let root: URL
    private var fileManager: FileManager { .default }

    static var standard: ProofStore {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return ProofStore(root: base.appendingPathComponent("Proofs", isDirectory: true))
    }

    func folder(_ sessionID: String) -> URL {
        root.appendingPathComponent(sessionID, isDirectory: true)
    }

    func photoURL(_ sessionID: String) -> URL { folder(sessionID).appendingPathComponent("photo.jpg") }
    func cardURL(_ sessionID: String) -> URL { folder(sessionID).appendingPathComponent("card.jpg") }
    private func recordURL(_ sessionID: String) -> URL { folder(sessionID).appendingPathComponent("card.json") }

    func hasPhoto(_ sessionID: String) -> Bool { fileManager.fileExists(atPath: photoURL(sessionID).path) }
    func hasCard(_ sessionID: String) -> Bool { fileManager.fileExists(atPath: cardURL(sessionID).path) }

    /// Saves the clean photo. A retake replaces it (still one proof) and drops any card made from it.
    func savePhoto(_ jpeg: Data, for sessionID: String) throws {
        try prepare(sessionID)
        try write(jpeg, to: photoURL(sessionID))
        try? fileManager.removeItem(at: cardURL(sessionID))
        try? fileManager.removeItem(at: recordURL(sessionID))
    }

    func loadPhoto(_ sessionID: String) -> CGImage? {
        guard let data = try? Data(contentsOf: photoURL(sessionID)) else { return nil }
        return ProofImageIO.decode(data)
    }

    func saveCard(_ jpeg: Data, record: CardRecord, for sessionID: String) throws {
        try prepare(sessionID)
        try write(jpeg, to: cardURL(sessionID))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try write(try encoder.encode(record), to: recordURL(sessionID))
    }

    func cardData(_ sessionID: String) -> Data? {
        try? Data(contentsOf: cardURL(sessionID))
    }

    func record(_ sessionID: String) -> CardRecord? {
        guard let data = try? Data(contentsOf: recordURL(sessionID)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CardRecord.self, from: data)
    }

    /// Drops the card but keeps the photo (Retake from the saved state is not offered; used by tests).
    func removeCard(_ sessionID: String) {
        try? fileManager.removeItem(at: cardURL(sessionID))
        try? fileManager.removeItem(at: recordURL(sessionID))
    }

    func removeOriginal(_ sessionID: String) {
        try? fileManager.removeItem(at: photoURL(sessionID))
    }

    /// Removes everything for a session (discarded, or deleted with the account).
    func remove(_ sessionID: String) {
        try? fileManager.removeItem(at: folder(sessionID))
    }

    private func prepare(_ sessionID: String) throws {
        try fileManager.createDirectory(at: folder(sessionID), withIntermediateDirectories: true)
    }

    private func write(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
}

/// What the user picked last time: camera, timer, filter, size and stat row
/// (D7 and D8 "Pre-filled"). Front camera, timer off, Iron and 4:5 the first time.
struct ProofPreferences {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private enum Key {
        static let backCamera = "pgym.proof.backCamera"
        static let timer = "pgym.proof.timer"
        static let options = "pgym.proof.cardOptions"
        static let keepCards = "pgym.proof.keepCards"
        static let autoSavePhotos = "pgym.proof.autoSavePhotos"
        static let deleteOriginal = "pgym.proof.deleteOriginal"
    }

    var usesBackCamera: Bool {
        get { defaults.bool(forKey: Key.backCamera) }
        nonmutating set { defaults.set(newValue, forKey: Key.backCamera) }
    }

    var timerOn: Bool {
        get { defaults.bool(forKey: Key.timer) }
        nonmutating set { defaults.set(newValue, forKey: Key.timer) }
    }

    var cardOptions: ProofCardOptions {
        get {
            guard let data = defaults.data(forKey: Key.options),
                  let options = try? JSONDecoder().decode(ProofCardOptions.self, from: data)
            else { return ProofCardOptions() }
            return options
        }
        nonmutating set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.options)
        }
    }

    /// Local media defaults. Photos stay on the phone for later optional analysis and score-card sharing.
    var keepCardsOnPhone: Bool {
        get { defaults.object(forKey: Key.keepCards) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.keepCards) }
    }

    var automaticallySaveCardsToPhotos: Bool {
        get { defaults.object(forKey: Key.autoSavePhotos) as? Bool ?? false }
        nonmutating set { defaults.set(newValue, forKey: Key.autoSavePhotos) }
    }

    var deleteOriginalAfterCard: Bool {
        get { defaults.object(forKey: Key.deleteOriginal) as? Bool ?? false }
        nonmutating set { defaults.set(newValue, forKey: Key.deleteOriginal) }
    }
}
