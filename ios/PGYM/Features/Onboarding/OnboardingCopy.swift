import Foundation

/// Every onboarding string, from the copy deck (`copy/pgym-app-copy.md`, "B. Onboarding") and
/// pgym-flow-spec.md where the flow spec changed a screen. Strings marked "inferred" are not in
/// either note.
enum OnboardingCopy {
    static func step(_ n: Int, of total: Int) -> String { "Step \(n) of \(total)" }
    static let back = "Back"
    static let couldNotSave = "Could not save. Try again."

    enum Goal { // B1
        static let title = "How many days a week?"
        static let optionCaption = "days"
        static func commitment(_ goal: Int) -> String { "I will train \(goal) days a week." }
        /// Before a number is picked. Inferred.
        static let commitmentEmpty = "Pick a number."
        static let hint = "You can change this later. A change starts the next week."
        static let button = "Lock it in"
    }

    enum Units { // B5, the chip on B1 (flow spec)
        static func chip(_ units: NewUserProfile.Units) -> String { "Weights in \(units.rawValue)" }
        static let change = "Change"
        static let body = "Set from your phone's region. Tap to change."
        static func accessibility(_ units: NewUserProfile.Units) -> String {
            units == .kg ? "Weights in kilograms" : "Weights in pounds"
        }
        static let accessibilityHint = "Switches between kilograms and pounds."
    }

    enum Days { // B2
        static let title = "Which days, what time?"
        static func body(goal: Int) -> String { "Pick \(goal) days." }
        static func counter(picked: Int, goal: Int) -> String { "\(picked) of \(goal) picked" }
        static let timeLabel = "Usual time"
        static func tooMany(goal: Int) -> String { "That is more than \(goal). Untick one or raise the goal." }
        /// Flow spec B2.
        static func pickMore(_ n: Int) -> String { n == 1 ? "Pick 1 more day." : "Pick \(n) more days." }
        static let changeGoal = "Change the goal"
        static let button = "Continue"
    }

    enum Reminders { // B3
        static let title = "One reminder per gym day"
        static func body(time: String) -> String {
            "At \(time) on your gym days, PGYM sends one line: the routine and what it does for your week."
        }
        static let quiet = "Nothing on rest days. Nothing once the session is logged."
        /// Flow spec B3, rule 3. Inferred wording.
        static let backOff = "Ignore five in a row and they go quiet: one line a week instead."
        static let previewApp = "PGYM"
        static let previewWhen = "now"
        static let button = "Turn on reminders"
        static let skip = "Skip for now"
        static let declined = "Reminders are off. Turn them on in Settings any time."
    }

    enum Routine { // B4
        static let title = "Pick a starting routine"
        static func fits(goal: Int) -> String { "Fits \(goal) days" }
        static let buildOwn = "Build my own"
        static let hint = "Every routine can be edited later."
        static let button = "Use this routine"
    }
}
