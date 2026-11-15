import Foundation
import Observation

/// `users/{uid}/sessions/{sessionId}.physique` as `analyzePhysique` writes it (backend/src/physique.ts):
/// either a score with an optional tip, or a refusedReason, never both.
struct PhysiqueRecord: Equatable, Sendable {
    var score: Int?
    var tip: String?
    var refusedReason: String?
    var analyzedAt: Date?

    init(score: Int? = nil, tip: String? = nil, refusedReason: String? = nil, analyzedAt: Date? = nil) {
        self.score = score
        self.tip = tip
        self.refusedReason = refusedReason
        self.analyzedAt = analyzedAt
    }

    /// From the Firestore map. Nil for anything that is not a map.
    init?(firestore value: Any?) {
        guard let map = value as? [String: Any] else { return nil }
        let reason = (map["refusedReason"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let score = API.number(map["score"]).map { min(100, max(0, Int($0.rounded()))) }
        let tip = (map["tip"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            score: reason == nil ? score : nil,
            tip: reason == nil ? ((tip?.isEmpty ?? true) ? nil : tip) : nil,
            refusedReason: reason,
            analyzedAt: map["analyzedAt"] as? Date
        )
    }

    /// A score the app may show: a number and no refusal.
    var isScored: Bool { score != nil && refusedReason == nil }
}

/// A live listener. `cancel()` stops it; so does releasing it.
final class PhysiqueObservation {
    private var stop: (() -> Void)?

    init(stop: @escaping () -> Void) {
        self.stop = stop
    }

    func cancel() {
        stop?()
        stop = nil
    }

    deinit { cancel() }
}

/// Where the score comes from: a Firestore listener on the session in the app, a fake in tests.
@MainActor
protocol PhysiqueSource: AnyObject {
    /// Calls `onChange` with the session's `physique` now and on every change; nil while there is none.
    func observe(uid: String, sessionID: String, onChange: @escaping @MainActor (PhysiqueRecord?) -> Void) -> PhysiqueObservation
    /// The most recent score of an earlier session, for the trend line. Nil when there is none.
    func previousScore(uid: String, before stampedAt: Date, excluding sessionID: String) async -> Int?
}

/// Writes the consent flag: `users/{uid}.physiqueConsent` and `physiqueConsentAt` (server time).
@MainActor
protocol PhysiqueConsentWriting: AnyObject {
    func setPhysiqueConsent(_ on: Bool, uid: String) async throws
}

/// The physique score rules on the phone (pgym-design.md, "The physique score"; flow spec D10, D11).
enum PhysiqueRules {
    /// Same rule as the server's `isAdult`: born in year Y counts as 18 from 1 January of Y + 19.
    static func isAdult(birthYear: Int?, currentYear: Int) -> Bool {
        guard let birthYear else { return false }
        return currentYear - birthYear > AgePolicy.physiqueScoreAge
    }
}

/// The consent flag on this phone. Off is the default. Turning it on is saved here at once and sent to
/// `users/{uid}` as soon as there is a connection (flow spec D10, "Offline"), and always before the next
/// stamp, so the server queues the score for it. D10 is offered once (`offerShown`).
@MainActor
@Observable
final class PhysiqueConsent {
    private(set) var isOn = false
    private(set) var offerShown = false
    /// Changed on the phone, not yet in Firestore.
    private(set) var needsUpload = false

    private let defaults: UserDefaults
    @ObservationIgnored private var writer: PhysiqueConsentWriting?
    @ObservationIgnored private var uid: String?

    init(defaults: UserDefaults = .standard, writer: PhysiqueConsentWriting? = nil) {
        self.defaults = defaults
        self.writer = writer
    }

    private func key(_ name: String, _ uid: String) -> String { "pgym.physique.\(uid).\(name)" }

    /// Loads this user's state. `profileValue` is `users/{uid}.physiqueConsent`; a change still waiting
    /// to be sent wins over it.
    func load(uid: String, profileValue: Bool?) {
        self.uid = uid
        offerShown = defaults.bool(forKey: key("offerShown", uid))
        needsUpload = defaults.bool(forKey: key("needsUpload", uid))
        if needsUpload {
            isOn = defaults.bool(forKey: key("isOn", uid))
        } else {
            isOn = profileValue ?? defaults.bool(forKey: key("isOn", uid))
            defaults.set(isOn, forKey: key("isOn", uid))
        }
    }

    func setWriter(_ writer: PhysiqueConsentWriting?) {
        self.writer = writer
    }

    /// D10 Turn on the score.
    func turnOn() async {
        set(true)
        await flush()
    }

    /// F6 and E5's off switch (card I8). The server deletes the stored scores.
    func turnOff() async {
        set(false)
        await flush()
    }

    /// D10 Not now, or the D11 row seen: the offer does not come back. The switch stays in F6.
    func markOfferShown() {
        guard let uid else { return }
        offerShown = true
        defaults.set(true, forKey: key("offerShown", uid))
    }

    /// Sends a change made on the phone. Quietly keeps it for later when it cannot be sent.
    func flush() async {
        guard needsUpload, let uid, let writer else { return }
        let value = isOn
        do {
            // Firestore holds an offline write until the server acknowledges it; do not let that hold
            // up the stamp queue. The SDK still sends it later, and so does the next flush.
            let sent = try await withThrowingTaskGroup(of: Bool.self) { group -> Bool in
                group.addTask { @MainActor in
                    try await writer.setPhysiqueConsent(value, uid: uid)
                    return true
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    return false
                }
                defer { group.cancelAll() }
                return try await group.next() ?? false
            }
            guard sent, self.uid == uid, isOn == value else { return }
            needsUpload = false
            defaults.set(false, forKey: key("needsUpload", uid))
        } catch {
            // Offline or refused: stays queued; the next stamp or reconnect sends it.
        }
    }

    /// Signed out: nothing of this user's stays in memory.
    func reset() {
        uid = nil
        isOn = false
        offerShown = false
        needsUpload = false
    }

    private func set(_ on: Bool) {
        guard let uid else { return }
        isOn = on
        needsUpload = true
        offerShown = true
        defaults.set(on, forKey: key("isOn", uid))
        defaults.set(true, forKey: key("needsUpload", uid))
        defaults.set(true, forKey: key("offerShown", uid))
    }
}

/// In memory: tests deliver a score or a refusal by hand; builds without Firebase never deliver one.
@MainActor
final class FakePhysiqueSource: PhysiqueSource {
    private var handlers: [String: [Int: @MainActor (PhysiqueRecord?) -> Void]] = [:]
    private var records: [String: PhysiqueRecord] = [:]
    private var nextID = 0
    var previous: Int?

    func observe(uid: String, sessionID: String, onChange: @escaping @MainActor (PhysiqueRecord?) -> Void) -> PhysiqueObservation {
        nextID += 1
        let id = nextID
        handlers[sessionID, default: [:]][id] = onChange
        onChange(records[sessionID])
        return PhysiqueObservation { [weak self] in
            Task { @MainActor in self?.handlers[sessionID]?[id] = nil }
        }
    }

    func previousScore(uid: String, before stampedAt: Date, excluding sessionID: String) async -> Int? {
        previous
    }

    /// What `analyzePhysique` would write.
    func deliver(_ record: PhysiqueRecord, for sessionID: String) {
        records[sessionID] = record
        for handler in (handlers[sessionID] ?? [:]).values { handler(record) }
    }

    var listenerCount: Int { handlers.values.reduce(0) { $0 + $1.count } }
}

@MainActor
final class FakePhysiqueConsentWriter: PhysiqueConsentWriting {
    private(set) var writes: [Bool] = []
    var failure: Error?

    func setPhysiqueConsent(_ on: Bool, uid: String) async throws {
        if let failure { throw failure }
        writes.append(on)
    }
}
