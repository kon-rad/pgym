import Foundation

/// Strings for D6, D7, D8, D9 (pending) and D12, from pgym-app-copy.md. Text printed on the card image
/// itself follows pgym-proof-card-spec.md, which owns the card.
enum ProofCopy {
    // MARK: D6 Camera permission
    static let permissionTitle = "Choose your photo"
    static let permissionBody = "Take a new photo or choose one you already took. Your card uses the workout's verified proof number and time."
    static let permissionAllow = "Allow camera"
    static let permissionNotNow = "Not now"
    static let permissionDenied = "Camera access is off. Choose an existing photo or turn on camera access in Settings."
    static let openSettings = "Open Settings"
    static let saveWithoutProof = "Save without proof"

    // MARK: D7 Proof camera
    static let cameraHint = "For AI coaching, show your full body in even light. If comfortable, wear shorts and a sports bra or shorts without a shirt."
    static let timerOn = "3 s"
    static let timerOff = "Off"
    // pgym-flow-spec.md, "Accessibility": the shutter reads "Take proof photo".
    static let shutterLabel = "Take proof photo"
    static let shutterTimerLabel = "Take proof photo in 3 seconds"
    static let switchCameraLabel = "Switch camera"
    static let closeCameraLabel = "Close camera"
    static let cameraBusy = "The camera is busy. Close other camera apps and try again."
    static let timerLabel = "Timer"

    // MARK: D8 Proof card editor
    static let editorTitle = "Your card"
    static let sectionFilter = "Filter"
    static let filterIron = "Iron"
    static let filterChalk = "Chalk"
    static let filterPlate = "Plate"
    static let filterRaw = "Raw"
    static let sectionOnCard = "On the card"
    static let statSets = "Sets"
    static let statTotal = "Lifted"
    static let statTime = "Time"
    static let statTopLift = "Top lift"
    static let pickThree = "Pick 3."
    static let sectionSize = "Size"
    static let sizeFeed = "4:5 feed"
    static let sizeStory = "9:16 story"
    static let retake = "Retake"
    static let retakeHint = "A retake replaces this photo. It is still one proof."
    static let stampIt = "Stamp it"
    static let renderFailed = "Could not make the card. Try again."
    /// VoiceOver for the size buttons: "4:5" is read as a ratio, not a time.
    static func sizeLabel(_ size: ProofCardSize) -> String {
        switch size {
        case .feed: "Feed size, 4 by 5"
        case .story: "Story size, 9 by 16"
        }
    }

    // D9 Stamping strings live in StampCopy (card I7).

    // MARK: D12 Share
    static let shareProof = "Share proof"
    static let shareWaits = "Share opens once the card is stamped."
    static let saveToPhotos = "Save to Photos"
    static let savedToPhotos = "Saved to Photos"
    static let saveToPhotosFailed = "Photos access is off. Turn it on in Settings to save your card."

    /// VoiceOver label for the card preview, made from its content (pgym-flow-spec.md, "Accessibility").
    static func cardLabel(_ summary: ProofCardSummary, options: ProofCardOptions) -> String {
        let layout = ProofCardText.self
        var parts = ["Proof card", layout.sessionDisplayName(summary.sessionName).capitalized]
        switch summary.stamp {
        case .pending: parts.append("Proof pending")
        case let .stamped(number, _, _, _): parts.append("Proof \(number)")
        }
        for stat in options.stats.row {
            let cell = layout.statCell(stat, summary: summary)
            parts.append("\(cell.label.lowercased()) \(cell.value)\(cell.unit.map { " " + $0.lowercased() } ?? "")")
        }
        parts.append("\(options.filter.label) filter")
        return parts.joined(separator: ", ")
    }
}

enum PhysiqueAnalysisMessage {
    static func failure(_ error: Error) -> String {
        guard let error = error as? ProofAPIError else {
            return "AI analysis is temporarily unavailable. Try again later."
        }
        switch error {
        case .notFound:
            return "AI analysis is not ready on the server yet. Your proof is saved. Try again later."
        case .offline:
            return "Connect to the internet and try AI analysis again."
        case .unauthenticated:
            return "Sign in again, then retry analysis. If Pro is active on this iPhone, use Restore Purchases in Profile."
        case .invalid(let message):
            return message.isEmpty ? "This photo could not be scored. Try a clear, full-body photo in even light." : message
        default:
            return "AI analysis is temporarily unavailable. Your proof is saved. Try again later."
        }
    }
}
