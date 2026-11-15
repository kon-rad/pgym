import Foundation

/// Every string on D1, D2, D4 and D5, from pgym-app-copy.md ("D. Session"). Display strings are
/// written in sentence case; the type role upper-cases them.
enum SessionCopy {
    static let emptySessionName = "Empty session"

    // MARK: D1 Pick routine
    static let pickTitle = "Start a session"
    static let nextUp = "Next up"
    static let otherRoutines = "Other routines"
    static let emptySessionCaption = "Add exercises as you go."
    static let cancel = "Cancel"
    static let editRoutines = "Edit routines"
    static let noRoutines = "No routines yet."

    static func routineMeta(exercises: Int, lastDone: String?) -> String {
        let count = exercises == 1 ? "1 exercise" : "\(exercises) exercises"
        guard let lastDone else { return count }
        return "\(count), last done \(lastDone)"
    }

    // MARK: D2 Active session
    static let done = "Done"
    static let set = "Set"
    static let last = "Last"
    static let reps = "Reps"
    static let newBest = "New best"
    static let addSet = "Add set"
    static let addExercise = "Add exercise"
    static let rest = "Rest"
    static let skip = "Skip"
    static let minus15 = "-15 s"
    static let plus15 = "+15 s"
    static let restDone = "Rest done."
    static let upNext = "Up next"
    static let finish = "Finish and take proof"
    static let finishHint = "Log one set to finish."
    static let offline = "Offline. Sets are saved on this phone and will sync."
    static let noExercises = "No exercises yet."
    static let saveFailed = "Could not save this set. Free some space and try again."
    static let restLength = "Rest timer length"
    static let menu = "Session menu"
    static let close = "Leave session"
    static let bodyweight = "BW"
    static let logSet = "Log set"
    static let weightKey = "Weight"
    static let repsKey = "Reps"

    static func previous(weight: String, reps: Int) -> String { "Last: \(weight) x \(reps)" }
    static func lastTime(_ sets: [String]) -> String { "Last time: " + sets.joined(separator: ", ") }
    static func resumed(at time: String) -> String { "Session resumed. Started \(time)." }
    /// "Bench press 3 x 8, top 80 kg"
    static func doneSummary(name: String, sets: Int, reps: Int?, top: String?) -> String {
        var text = name + " \(sets) x \(reps ?? 0)"
        if let top { text += ", top \(top)" }
        return text
    }
    static func restSeconds(_ seconds: Int) -> String {
        seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    // Rest notification (lock screen).
    static let restNotificationTitle = "Rest done."
    static func restNotificationBody(exercise: String?, set: Int?) -> String {
        guard let exercise else { return "Next set when you are ready." }
        if let set { return "Next: \(exercise), set \(set)." }
        return "Next: \(exercise)."
    }

    // MARK: D2 accessibility (pgym-flow-spec.md, "Accessibility")
    static func a11yWeight(set: Int) -> String { "Set \(set), weight" }
    static func a11yReps(set: Int) -> String { "Set \(set), reps" }
    static func a11yCheck(set: Int, done: Bool) -> String { done ? "Set \(set) done" : "Mark set \(set) done" }
    static func a11yLastHint(weight: String, reps: Int) -> String { "Last time \(weight) for \(reps)." }
    static func a11yLogged(set: Int, rest: String) -> String { "Set \(set) logged. Rest \(rest)." }
    static let a11yNewBest = "New best"
    static let a11yEmptyWeight = "No weight yet"
    static func a11yRestLeft(_ text: String) -> String { "Rest, \(text) left" }
    static func a11yRestSpoken(_ seconds: Int) -> String {
        let m = seconds / 60, s = seconds % 60
        switch (m, s) {
        case (0, _): return "\(s) seconds"
        case (_, 0): return m == 1 ? "1 minute" : "\(m) minutes"
        default: return "\(m) minute\(m == 1 ? "" : "s") \(s)"
        }
    }
    static let a11yCopyToNext = "Copy to next set"
    static let a11ySetDetail = "Set detail"
    static let a11yDeleteSet = "Delete set"
    // Card I9 accessibility pass.
    static func a11yElapsed(_ spoken: String) -> String { "Session time, \(spoken)" }
    static let a11yMakeCurrentHint = "Opens this exercise to log its sets."
    static let a11yMinus15 = "Rest 15 seconds less"
    static let a11yPlus15 = "Rest 15 seconds more"
    static let a11ySkipRest = "Skip rest"

    // MARK: Keypad
    static func keypadWeightHeader(_ unit: WeightUnit) -> String { "Weight, \(unit.rawValue)" }
    static let keypadRepsHeader = "Reps"
    static func a11yStep(_ step: String, unit: WeightUnit, up: Bool) -> String {
        "\(up ? "plus" : "minus") \(step) \(unit == .kg ? "kilograms" : "pounds")"
    }
    static func a11yRepStep(up: Bool) -> String { up ? "plus 1 rep" : "minus 1 rep" }
    static let a11yDelete = "Delete"
    static let a11yDecimal = "Decimal point"

    // MARK: D4 Set detail
    static func setTitle(_ n: Int) -> String { "Set \(n)" }
    static func setSubtitle(_ n: Int, exercise: String) -> String { "Set \(n), \(exercise)" }
    static let type = "Type"
    static let warmupHint = "Warm-up sets do not count toward total lifted."
    static let effort = "Effort (RPE)"
    static let addEffort = "Add effort rating"
    static let effortHint = "How hard, 1 to 10. Optional."
    static let clearEffort = "Clear"
    static let notePlaceholder = "Add a note"
    static let deleteSet = "Delete set"
    static let save = "Save"

    // MARK: D5 Leave session?
    static let leaveTitle = "Leave this session?"
    static func leaveBody(sets: Int) -> String {
        sets == 0 ? "Nothing logged yet." : "Your \(sets) \(sets == 1 ? "set is" : "sets are") saved on this phone."
    }
    static let keepGoing = "Keep going"
    static let saveWithoutProof = "Save without proof"
    static let saveWithoutProofCaption = "A session without a photo does not count toward your week."
    static let discardSession = "Discard session"
    static func discardTitle(sets: Int) -> String { sets == 1 ? "Discard 1 set?" : "Discard \(sets) sets?" }
    static let discardBody = "This cannot be undone."
    static let discard = "Discard"
}
