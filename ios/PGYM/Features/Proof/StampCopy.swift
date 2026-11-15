import Foundation

/// Strings for D9 Stamping, D10 Physique consent and D11 Session complete, from pgym-app-copy.md.
/// The voice: state what happened, no exclamation marks, no guilt, a lower score is never a warning.
enum StampCopy {
    // MARK: D9 Stamping (the stamp's pending state on D11, pgym-flow-spec.md)
    static let stampingTitle = "Stamping"
    static let stampingBody = "Uploading your photo and getting your number."
    static let stampingSlow = "Still uploading. The connection is slow."
    static let offlineTitle = "Saved"
    static let offlineBody = "No connection. Your card is saved and will be stamped when you are back online."
    static let offlineNote = "The time on the card is set by the server when it arrives."
    static let errorBody = "The upload stopped. Your card is saved on this phone."
    static let tryAgain = "Try again"
    /// After this long in `.uploading` or `.stamping`, the slow line shows.
    static let slowAfter: TimeInterval = 8

    // MARK: D10 Physique consent
    static let consentTitle = "Physique score"
    static let consentLead1 = "An AI estimate of your visible muscle and symmetry, from 0 to 100, with one training tip."
    static let consentLead2 = "It is compared only with your own earlier photos."
    static let consentSentLabel = "What is sent"
    static let consentSentBody = "This session's photo. Nothing else: not your name, email, age or sets."
    static let consentWhoLabel = "Who sees it"
    static let consentWho1 = "Google's Gemini model reads the photo and returns a score and a tip."
    static let consentWho2 = "PGYM keeps the score and tip in your account. Only you see them."
    static let consentWho3 = "They are never on your card and never shared by the app."
    static let consentWho4 = "An agent you give photo access to can read them too."
    // "Google does not use your photo to train its models." is held until card B2 confirms it in the
    // Gemini API terms (pgym-app-copy.md, D10). It is deliberately not in the build.
    static let consentOffLabel = "How to turn it off"
    static let consentOffBody = "Profile, then Privacy and data. Turning it off deletes every stored score and tip. Your photos and proofs stay."
    static let consentAge = "For people 18 and over."
    static let disclaimer = "An AI estimate from this photo. Not medical advice."
    static let consentTurnOn = "Turn on the score"
    static let consentNotNow = "Not now"
    static let consentUnder18 = "The physique score is for people 18 and over."
    static let consentContinue = "Continue"

    // MARK: D11 Session complete
    static func headlineLocked(week: Int) -> String { "Week \(week) locked." }
    static func headlineProgress(_ n: Int, of goal: Int) -> String { "\(n) of \(goal) this week." }
    static let headlineBonus = "Bonus session logged."
    static let sectionThisWeek = "This week"
    static let sectionScore = "Physique score, private"
    static func trendUp(_ delta: Int) -> String { "Up \(delta) from last time." }
    static let trendSame = "Same as last time."
    static func trendDown(_ delta: Int) -> String { "\(delta) lower than last time. Light and angle move this number." }
    static let trendFirst = "Your first score. The next ones compare with this."
    static let scorePending = "Scoring your photo."
    static let sectionTip = "Tip"
    static let sectionNewBests = "New bests"
    static func bestRow(exercise: String, weight: String, unit: String, reps: Int) -> String {
        "\(exercise): \(weight) \(unit) x \(reps)"
    }
    static let sectionTotal = "Total lifted"
    static let statSets = "Sets"
    static let statTime = "Time"
    static let shareProof = "Share proof"
    static let done = "Done"
    /// The D11 row that opens D10, shown once (pgym-flow-spec.md D10 "Entry"). The copy deck has no
    /// row string; it uses D10's title and main button, so no new copy is invented.
    static let consentRowTitle = "Physique score"
    static let consentRowAction = "Turn on the score"
}
