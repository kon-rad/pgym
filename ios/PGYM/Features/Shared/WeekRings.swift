import DesignSystem
import SwiftUI

/// The seven day rings on C1 and D11 as one VoiceOver element (pgym-flow-spec.md, "Accessibility"):
/// "This week, 3 of 4. Monday done, Tuesday done, Wednesday rest, Thursday today, not done."
/// At the accessibility text sizes `DayRing` hides its letters; the count line carries the meaning.
struct WeekRings: View {
    typealias Entry = (day: Weekday, status: DayRing.Status)

    let days: [Entry]
    var count: Int?
    var goal: Int?
    var identifier: String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, entry in
                DayRing(day: String(entry.day.short.prefix(1)), state: entry.status)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WeekRingSpeech.label(days: days, count: count, goal: goal))
        .accessibilityIdentifier(identifier)
    }
}

/// What VoiceOver reads for the week row. A pure function so the wording is tested.
enum WeekRingSpeech {
    static func status(_ status: DayRing.Status) -> String {
        switch status {
        case .done: "done"
        case .today: "today, not done"
        case .planned: "gym day"
        case .rest: "rest"
        }
    }

    static func label(days: [WeekRings.Entry], count: Int?, goal: Int?) -> String {
        let list = days.map { "\($0.day.full) \(status($0.status))" }.joined(separator: ", ")
        if let count, let goal, goal > 0 {
            return "This week, \(count) of \(goal). \(list)."
        }
        return "This week. \(list)."
    }
}
