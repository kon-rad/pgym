import Foundation

/// Strings for F1, F4, F5, F6 and F8, from pgym-app-copy.md, "F. Profile tab".
enum ProfileCopy {
    // F1
    static func proofs(_ n: Int) -> String { n == 1 ? "1 proof" : "\(n) proofs" }
    static func longestStreak(_ weeks: Int) -> String { weeks == 1 ? "Longest streak: 1 week" : "Longest streak: \(weeks) weeks" }
    static let proofsLabel = "Proofs"
    static let longestLabel = "Longest streak"
    static let routines = "Routines"
    static let goalAndSchedule = "Goal and schedule"
    static let settings = "Settings"
    static let privacy = "Privacy and data"
    static let about = "About"

    // F4
    static let weeklyGoal = "Weekly goal"
    static func goalHint(current: Int) -> String { "A new goal starts next Monday. This week stays at \(current)." }
    static func pending(from day: String, goal: Int) -> String { "From \(day): \(goal) days a week." }
    static let gymDays = "Gym days"
    static let reminderTime = "Reminder time"
    static func tooMany(goal: Int) -> String { "That is more than \(goal). Untick one or raise the goal." }
    static func pickMore(_ n: Int) -> String { n == 1 ? "Pick 1 more day." : "Pick \(n) more days." }
    static let save = "Save"
    static let saved = "Saved."
    static let savedOffline = "Saved on this phone. It syncs when you are back online."

    // F5
    static let units = "Units"
    static let unitsCaption = "Past sessions show in the new unit."
    static let notifications = "Notifications"
    static let proofStorage = "Proof storage"
    static let keepProofCards = "Keep proof cards on this iPhone"
    static let autoSaveProofCards = "Automatically save proof cards to Photos"
    static let deleteOriginalPhoto = "Delete the photo after the card is created"
    static let gymReminders = "Gym day reminders"
    static let sundayNudge = "Sunday nudge"
    static let iosOff = "Notifications for PGYM are off in iOS Settings."
    static let openSettings = "Open Settings"
    static let accountEmail = "Account email"
    static let signOut = "Sign out"
    static let signOutTitle = "Sign out of PGYM?"
    static func unsynced(_ n: Int) -> String {
        n == 1
            ? "1 session has not synced yet. It syncs before you are signed out, so stay online for a moment."
            : "\(n) sessions have not synced yet. They sync before you are signed out, so stay online for a moment."
    }
    static let cancel = "Cancel"

    // F6
    static let physique = "Physique score"
    static let physiqueOn = "On. Only you see it."
    static let physiqueOff = "Off."
    static let under18 = "The physique score is for people 18 and over."
    static let deletePhotos = "Delete all photos"
    static func deletePhotosTitle(_ count: Int) -> String { "Delete all \(count) photos and cards?" }
    static let deletePhotosBody = "Your sets and proof numbers stay. This cannot be undone."
    static let deletePhotosConfirm = "Delete photos"
    static let photosDeleted = "Photos and cards deleted."
    static let export = "Export my data"
    static let exportBody = "A file with your profile, routines, sessions and sets."
    static let exportReady = "Your export is ready."
    static let shareFile = "Share file"
    static let exportFailed = "Could not export. Try again."
    static let deleteAccount = "Delete account"
    static let privacyPolicy = "Privacy policy"
    static let needsConnection = "Needs a connection."
    static let actionFailed = "That did not go through. Check your connection and try again."

    // F8
    static func version(_ version: String) -> String { "Version \(version)" }
    static let terms = "Terms of use"
    static let support = "Support"
    static let sourceCode = "Source code on GitHub"
    static let licence = "Open source under the MIT licence."
    static let footer = "Proof of gym."
}

/// Links on the landing site and the repo. The domain and the support address are placeholders until
/// they are chosen (AGENTS.md: `[DOMAIN]`); `example.com` is used so the links are valid URLs.
enum SiteLinks {
    static let terms = URL(string: "https://example.com/terms")!
    static let privacy = URL(string: "https://example.com/privacy")!
    static let support = URL(string: "https://example.com/support")!
    static let supportEmail = "support@example.com"
    static let source = URL(string: "https://github.com/kon-rad/pgym")!
}
