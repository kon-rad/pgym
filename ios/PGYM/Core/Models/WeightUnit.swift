import Foundation

/// The unit weights are shown and typed in. Weights are always stored in kilograms
/// (pgym-architecture.md, "Data model"); this type converts at the edge of the screen only.
///
/// No drift: a stored value is never rewritten from what is displayed. A weight changes only when
/// the user changes it, and a value typed in pounds is stored as the exact kilogram equivalent, so
/// showing it again gives back the same pounds (`displayValue(kg: kilograms(fromDisplay: x)) == x`).
enum WeightUnit: String, Codable, CaseIterable, Sendable {
    case kg, lb

    /// Exact, by definition of the international pound.
    static let kilogramsPerPound = 0.45359237

    /// UserDefaults key for the user's choice (B5 and F5 write it; card I3 and I8).
    static let preferenceKey = "pgym.units"

    /// The saved choice, or kg everywhere except US-measure locales.
    static func preferred(defaults: UserDefaults = .standard, locale: Locale = .current) -> WeightUnit {
        if let raw = defaults.string(forKey: preferenceKey), let unit = WeightUnit(rawValue: raw) {
            return unit
        }
        return locale.measurementSystem == .us ? .lb : .kg
    }

    /// One tap on plus or minus: 2.5 kg or 5 lb (pgym-flow-spec.md, "The keypad").
    var step: Double {
        switch self {
        case .kg: 2.5
        case .lb: 5
        }
    }

    /// Display precision: 2 decimals for kg (1.25 kg plates exist), 1 for lb.
    var fractionDigits: Int {
        switch self {
        case .kg: 2
        case .lb: 1
        }
    }

    /// "KG" or "LB" for column headers.
    var label: String { rawValue.uppercased() }

    /// Spoken in full for VoiceOver (never "kg").
    func spoken(_ value: Double) -> String {
        let text = Self.format(value, fractionDigits: fractionDigits)
        switch self {
        case .kg: return "\(text) kilograms"
        case .lb: return "\(text) pounds"
        }
    }

    /// Kilograms to this unit, rounded to the display precision.
    func displayValue(kg: Double) -> Double {
        let raw: Double
        switch self {
        case .kg: raw = kg
        case .lb: raw = kg / Self.kilogramsPerPound
        }
        return Self.round(raw, fractionDigits: fractionDigits)
    }

    /// A value typed or stepped in this unit, to kilograms for storage. Not rounded: rounding here
    /// is what would make 100 lb come back as 99.9 lb.
    func kilograms(fromDisplay value: Double) -> Double {
        switch self {
        case .kg: return value
        case .lb: return value * Self.kilogramsPerPound
        }
    }

    /// One step up or down from a stored weight, returned in kilograms. Never below zero.
    func stepped(kg: Double?, by steps: Int) -> Double {
        let current = displayValue(kg: kg ?? 0)
        let next = max(0, current + Double(steps) * step)
        return kilograms(fromDisplay: Self.round(next, fractionDigits: fractionDigits))
    }

    /// "80", "102.5", "45.36": no trailing zeros.
    func format(kg: Double) -> String {
        Self.format(displayValue(kg: kg), fractionDigits: fractionDigits)
    }

    /// Big totals ("6,240") with grouping and no decimals.
    func formatTotal(kg: Double) -> String {
        let value = displayValue(kg: kg)
        return Int(value.rounded()).formatted(.number.grouping(.automatic))
    }

    static func round(_ value: Double, fractionDigits: Int) -> Double {
        let scale = pow(10, Double(fractionDigits))
        return (value * scale).rounded() / scale
    }

    static func format(_ value: Double, fractionDigits: Int) -> String {
        let rounded = round(value, fractionDigits: fractionDigits)
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        var text = String(format: "%.\(fractionDigits)f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// Parses keypad input ("102.5", "102,5"). Nil for empty or not a number.
    static func parse(_ text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite, value >= 0 else { return nil }
        return value
    }
}
