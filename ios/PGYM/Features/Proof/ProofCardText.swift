import CoreText
import DesignSystem
import Foundation

/// The card's fonts at pixel sizes. The card ignores Dynamic Type: it is an image at a fixed size.
enum ProofCardFont {
    static func anton(_ size: CGFloat) -> CTFont {
        make(.antonRegular, size)
    }

    static func mono(_ size: CGFloat) -> CTFont {
        make(.jetBrainsMonoBold, size)
    }

    private static func make(_ face: FontFace, _ size: CGFloat) -> CTFont {
        FontRegistry.registerAll()
        return CTFontCreateWithName(face.postScriptName as CFString, size, nil)
    }
}

/// A run of text in one font: the unit of measuring and drawing on the card.
struct ProofTextRun {
    var text: String
    var font: CTFont
    var tracking: CGFloat = 0

    func line(color: CGColor? = nil) -> CTLine {
        var attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTKernAttributeName as String): tracking,
        ]
        if let color {
            attributes[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = color
        }
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes) as CFAttributedString)
    }

    /// Advance width in px. Tracking after the last glyph is not ink, so it is not counted.
    var width: CGFloat {
        guard !text.isEmpty else { return 0 }
        let advance = CGFloat(CTLineGetTypographicBounds(line(), nil, nil, nil))
        return max(0, advance - tracking)
    }
}

/// Pure text rules of the card (pgym-proof-card-spec.md, "Text rules"). No drawing here, so every rule
/// is unit-tested on its own.
enum ProofCardText {
    static let posix = Locale(identifier: "en_US_POSIX")

    // MARK: Session name

    /// The D8 field caps input at 40 characters.
    static let sessionNameMaxCharacters = 40
    /// Text column of the lower block, x 64 to 1016.
    static let lowerBlockWidth: CGFloat = 952
    /// The last name line's baseline on the 4:5 card; the block is bottom-anchored.
    static let lastNameBaseline: CGFloat = 1124

    struct NameStep: Equatable {
        var size: CGFloat
        var pitch: CGFloat
    }

    /// 112 / 108, then 96 / 92, then 80 / 77.
    static let nameSteps = [NameStep(size: 112, pitch: 108), NameStep(size: 96, pitch: 92), NameStep(size: 80, pitch: 77)]

    struct SessionNameFit: Equatable {
        var lines: [String]
        var step: NameStep
        var truncated: Bool

        /// Baselines on the 4:5 card (add the size's y offset for 9:16).
        var baselines: [CGFloat] {
            lines.count == 2 ? [lastNameBaseline - step.pitch, lastNameBaseline] : [lastNameBaseline]
        }

        /// The timestamp sits 24 px above the first line's cap height.
        var timestampBaseline: CGFloat {
            (baselines.first ?? lastNameBaseline) - step.size - 24
        }
    }

    /// Upper case (POSIX), trimmed, at most 40 characters; "SESSION" when empty.
    static func sessionDisplayName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let capped = String(trimmed.prefix(sessionNameMaxCharacters)).trimmingCharacters(in: .whitespaces)
        let collapsed = capped.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.isEmpty ? "SESSION" : collapsed.uppercased(with: posix)
    }

    /// Two lines at 112 px, then 96, then 80, then an ellipsis on line 2.
    static func fitSessionName(_ raw: String, maxWidth: CGFloat = lowerBlockWidth) -> SessionNameFit {
        let name = sessionDisplayName(raw)
        let words = name.split(separator: " ").map(String.init)
        for step in nameSteps {
            let font = ProofCardFont.anton(step.size)
            if let lines = wrap(words, font: font, maxWidth: maxWidth), lines.count <= 2 {
                return SessionNameFit(lines: lines, step: step, truncated: false)
            }
        }
        // Step 4: keep line 1, cut line 2 with an ellipsis.
        let step = nameSteps[nameSteps.count - 1]
        let font = ProofCardFont.anton(step.size)
        let (first, rest) = firstLine(words, font: font, maxWidth: maxWidth)
        let second = truncate(rest, font: font, maxWidth: maxWidth)
        return SessionNameFit(lines: second.isEmpty ? [first] : [first, second], step: step, truncated: true)
    }

    /// Greedy wrap at spaces. Nil when one word alone is wider than the column.
    private static func wrap(_ words: [String], font: CTFont, maxWidth: CGFloat) -> [String]? {
        var lines: [String] = []
        var current = ""
        for word in words {
            let candidate = current.isEmpty ? word : current + " " + word
            if ProofTextRun(text: candidate, font: font).width <= maxWidth {
                current = candidate
            } else {
                guard ProofTextRun(text: word, font: font).width <= maxWidth else { return nil }
                lines.append(current)
                current = word
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    /// The longest run of whole words that fits; one over-long word is cut by character.
    private static func firstLine(_ words: [String], font: CTFont, maxWidth: CGFloat) -> (String, String) {
        var line = ""
        var used = 0
        for word in words {
            let candidate = line.isEmpty ? word : line + " " + word
            guard ProofTextRun(text: candidate, font: font).width <= maxWidth else { break }
            line = candidate
            used += 1
        }
        if used == 0, let word = words.first {
            let head = longestPrefix(of: word, font: font, maxWidth: maxWidth, suffix: "")
            let tail = String(word.dropFirst(head.count))
            return (head, ([tail] + words.dropFirst()).filter { !$0.isEmpty }.joined(separator: " "))
        }
        return (line, words.dropFirst(used).joined(separator: " "))
    }

    /// Fits `text` on one line: whole words with "…", else by character with "…".
    static func truncate(_ text: String, font: CTFont, maxWidth: CGFloat, tracking: CGFloat = 0) -> String {
        guard !text.isEmpty else { return "" }
        if ProofTextRun(text: text, font: font, tracking: tracking).width <= maxWidth { return text }
        let words = text.split(separator: " ").map(String.init)
        var best = ""
        var line = ""
        for word in words {
            line = line.isEmpty ? word : line + " " + word
            if ProofTextRun(text: line + "…", font: font, tracking: tracking).width <= maxWidth { best = line } else { break }
        }
        if !best.isEmpty { return best + "…" }
        return longestPrefix(of: text, font: font, maxWidth: maxWidth, suffix: "…", tracking: tracking)
    }

    private static func longestPrefix(of text: String, font: CTFont, maxWidth: CGFloat, suffix: String, tracking: CGFloat = 0) -> String {
        var count = text.count
        while count > 1 {
            let candidate = String(text.prefix(count)).trimmingCharacters(in: .whitespaces) + suffix
            if ProofTextRun(text: candidate, font: font, tracking: tracking).width <= maxWidth { return candidate }
            count -= 1
        }
        return String(text.prefix(1)) + suffix
    }

    // MARK: Timestamp

    /// "SUN 15 NOV 2026 · 18:47" in the session's zone. Pending cards add " · NOT STAMPED".
    static func timestamp(_ stamp: ProofStampState, timezone: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = posix
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: timezone) ?? .current
        formatter.dateFormat = "EEE d MMM yyyy '·' HH:mm"
        switch stamp {
        case let .pending(phoneTime):
            return formatter.string(from: phoneTime).uppercased(with: posix) + " · NOT STAMPED"
        case let .stamped(_, stampedAt, _, _):
            return formatter.string(from: stampedAt).uppercased(with: posix)
        }
    }

    // MARK: Stamp

    /// "#042", "#1000"; "#---" while pending.
    static func proofNumber(_ stamp: ProofStampState) -> String {
        guard case let .stamped(number, _, _, _) = stamp else { return "#---" }
        let digits = String(max(0, number))
        return "#" + String(repeating: "0", count: max(0, 3 - digits.count)) + digits
    }

    /// Line 3 of the stamp. Never mentions a miss: a gap reads NEW STREAK.
    static func streakLine(_ stamp: ProofStampState) -> String {
        switch stamp {
        case .pending:
            return "PENDING"
        case let .stamped(_, _, streak, count):
            if count <= 1 { return "FIRST PROOF" }
            if streak <= 0 { return "NEW STREAK" }
            return streak == 1 ? "1 WEEK RUNNING" : "\(streak) WEEKS RUNNING"
        }
    }

    // MARK: Stat row

    static let statColumnWidth: CGFloat = 296
    static let statValueSizes: [CGFloat] = [60, 52, 44]
    static let unitSize: CGFloat = 24
    static let unitTracking: CGFloat = 2
    static let unitGap: CGFloat = 8
    static let labelSize: CGFloat = 22
    static let labelTracking: CGFloat = 2

    struct StatCell: Equatable {
        var value: String
        var unit: String?
        var label: String
        /// Numeric value, for abbreviation when the text does not fit.
        var number: Double?
    }

    static func statCell(_ stat: ProofCardStat, summary: ProofCardSummary) -> StatCell {
        let unit = summary.unit.label
        switch stat {
        case .sets:
            return StatCell(value: "\(summary.setCount)", unit: nil, label: summary.setCount == 1 ? "SET" : "SETS", number: nil)
        case .total:
            let total = totalValue(kg: summary.totalKg, unit: summary.unit)
            return StatCell(value: grouped(total), unit: unit, label: "TOTAL LIFTED", number: Double(total))
        case .time:
            return StatCell(value: duration(summary.duration), unit: nil, label: "TIME", number: nil)
        case .topLift:
            guard let top = summary.topLift else {
                return StatCell(value: "-", unit: nil, label: "TOP LIFT", number: nil)
            }
            let name = top.exerciseName.trimmingCharacters(in: .whitespaces).uppercased(with: posix)
            let label = truncate(name.isEmpty ? "TOP LIFT" : name, font: ProofCardFont.mono(labelSize), maxWidth: statColumnWidth, tracking: labelTracking)
            guard top.weightKg > 0 else {
                return StatCell(value: "BW×\(top.reps)", unit: nil, label: label, number: nil)
            }
            return StatCell(value: "\(topLiftWeight(kg: top.weightKg, unit: summary.unit))×\(top.reps)", unit: unit, label: label, number: nil)
        }
    }

    /// Whole units: kg as is, lb at 2.20462 lb per kg, both rounded.
    static func totalValue(kg: Double, unit: WeightUnit) -> Int {
        switch unit {
        case .kg: Int(max(0, kg).rounded())
        case .lb: Int((max(0, kg) * 2.20462).rounded())
        }
    }

    /// "102.5" or "100" for kg (one decimal only when not zero); whole pounds for lb.
    static func topLiftWeight(kg: Double, unit: WeightUnit) -> String {
        switch unit {
        case .kg:
            let tenths = (kg * 10).rounded() / 10
            return tenths == tenths.rounded() ? String(Int(tenths)) : String(format: "%.1f", locale: posix, tenths)
        case .lb:
            return String(Int((kg * 2.20462).rounded()))
        }
    }

    /// "6,240": comma thousands on every card, whatever the phone's locale.
    static func grouped(_ value: Int) -> String {
        let digits = String(abs(value))
        var out = ""
        for (index, char) in digits.reversed().enumerated() {
            if index > 0, index % 3 == 0 { out.append(",") }
            out.append(char)
        }
        return (value < 0 ? "-" : "") + String(out.reversed())
    }

    /// "h:mm", minutes rounded down.
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(0, seconds) / 60)
        let mm = minutes % 60
        return "\(minutes / 60):" + (mm < 10 ? "0\(mm)" : "\(mm)")
    }

    /// "1.2M", "12.5K".
    static func abbreviated(_ value: Double) -> String {
        func one(_ v: Double) -> String {
            let r = (v * 10).rounded() / 10
            return r == r.rounded() ? String(Int(r)) : String(format: "%.1f", locale: posix, r)
        }
        if value >= 1_000_000 { return one(value / 1_000_000) + "M" }
        if value >= 1_000 { return one(value / 1_000) + "K" }
        return one(value)
    }

    struct FittedValue: Equatable {
        var value: String
        var size: CGFloat
        var width: CGFloat
    }

    /// Value plus unit run inside 296 px: shrink the value to 52, then 44, then abbreviate.
    /// The unit run never shrinks.
    static func fitStatValue(_ cell: StatCell) -> FittedValue {
        let unitWidth = cell.unit.map { ProofTextRun(text: $0, font: ProofCardFont.mono(unitSize), tracking: unitTracking).width + unitGap } ?? 0
        func measure(_ value: String, _ size: CGFloat) -> CGFloat {
            ProofTextRun(text: value, font: ProofCardFont.mono(size)).width + unitWidth
        }
        for size in statValueSizes {
            let width = measure(cell.value, size)
            if width <= statColumnWidth { return FittedValue(value: cell.value, size: size, width: width) }
        }
        let smallest = statValueSizes[statValueSizes.count - 1]
        if let number = cell.number {
            let short = abbreviated(number)
            return FittedValue(value: short, size: smallest, width: measure(short, smallest))
        }
        let cut = truncate(cell.value, font: ProofCardFont.mono(smallest), maxWidth: statColumnWidth - unitWidth)
        return FittedValue(value: cut, size: smallest, width: measure(cut, smallest))
    }

    /// The stamp's number: 56 px, shrunk in 4 px steps to 40 px to fit the 164 px column.
    static func stampNumberSize(_ text: String, maxWidth: CGFloat = 164) -> CGFloat {
        var size: CGFloat = 56
        while size > 40, ProofTextRun(text: text, font: ProofCardFont.anton(size)).width > maxWidth {
            size -= 4
        }
        return size
    }
}
