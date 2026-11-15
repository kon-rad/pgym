import DesignSystem
import SwiftUI

/// One set row on D2, left to right: set number, LAST, weight, reps, check. Cells are 44 pt high.
/// Done is shown by the filled Plate check and Chalk values, not by colour alone. At the
/// accessibility text sizes the row reflows to two lines and LAST moves into the weight hint.
struct SetRowView: View {
    let set: SessionSet
    let unit: WeightUnit
    let editing: KeypadField?
    let onWeight: () -> Void
    let onReps: () -> Void
    let onCheck: () -> Void
    let onDetail: () -> Void
    let onStepWeight: (Int) -> Void
    let onStepReps: (Int) -> Void
    let onCopyToNext: () -> Void
    let onDelete: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var weightText: String {
        guard let kg = set.weightKg else { return "" }
        if kg == 0 { return SessionCopy.bodyweight }
        return unit.format(kg: kg)
    }

    private var repsText: String { set.reps.map { String($0) } ?? "" }

    private var lastText: String? {
        guard let w = set.lastWeightKg, let r = set.lastReps else { return nil }
        return "\(w == 0 ? SessionCopy.bodyweight : unit.format(kg: w)) x \(r)"
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.grid(2)) {
                    HStack {
                        number
                        if let lastText {
                            Text(lastText).font(.pgym(.data, size: 15)).foregroundStyle(Color.steel)
                        }
                        Spacer()
                        bestTag
                    }
                    HStack(spacing: Spacing.grid(2)) {
                        weightCell(showUnit: true)
                        repsCell(showUnit: true)
                        check
                    }
                }
            } else {
                HStack(spacing: Spacing.grid(2)) {
                    number.frame(width: 32, alignment: .leading)
                    Text(lastText ?? "-")
                        .font(.pgym(.data, size: 15))
                        .foregroundStyle(Color.steel)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityHidden(true)
                    weightCell(showUnit: false).frame(width: 84)
                    repsCell(showUnit: false).frame(width: 60)
                    check
                }
                .overlay(alignment: .topLeading) { bestTag.offset(x: 0, y: -14) }
            }
        }
        .padding(.vertical, Spacing.grid(1))
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.4, perform: onDetail)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("d2.set.\(set.n)")
    }

    private var number: some View {
        HStack(spacing: Spacing.grid(1)) {
            Text("\(set.n)")
                .font(.pgym(.data, size: 17))
                .foregroundStyle(set.done ? Color.chalk : Color.bone)
            if set.type == .warmup {
                Text("W").pgymText(.labelBold, size: 10).foregroundStyle(Color.steel)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private var bestTag: some View {
        if set.isNewBest {
            Text(SessionCopy.newBest)
                .pgymText(.labelBold, size: 10)
                .foregroundStyle(Color.ink)
                .padding(.horizontal, Spacing.grid(2))
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.plate))
                .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
                .accessibilityLabel(SessionCopy.a11yNewBest)
                .accessibilityIdentifier("d2.set.\(set.n).best")
        }
    }

    private func cell(_ text: String, unitLabel: String?, active: Bool) -> some View {
        HStack(spacing: Spacing.grid(1)) {
            Text(text.isEmpty ? "-" : text)
                .font(.pgym(.data, size: 17))
                .foregroundStyle(text.isEmpty ? Color.steel : (set.done ? Color.chalk : Color.bone))
                .monospacedDigit()
                .contentTransition(.numericText())
            if let unitLabel {
                Text(unitLabel).pgymText(.label).foregroundStyle(Color.steel)
            }
        }
        .frame(maxWidth: .infinity, minHeight: Spacing.touchTargetMin)
        .background(RoundedRectangle(cornerRadius: Radius.setCell, style: .continuous).fill(Color.ink))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.setCell, style: .continuous)
                .strokeBorder(active ? Color.chalk : Color.rail, lineWidth: active ? 2 : Stroke.border)
        )
        .contentShape(RoundedRectangle(cornerRadius: Radius.setCell, style: .continuous))
    }

    private func weightCell(showUnit: Bool) -> some View {
        Button(action: onWeight) {
            cell(weightText, unitLabel: showUnit ? unit.label : nil, active: editing == .weight)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(SessionCopy.a11yWeight(set: set.n))
        .accessibilityValue(set.weightKg.map { $0 == 0 ? "Bodyweight" : unit.spoken(unit.displayValue(kg: $0)) } ?? SessionCopy.a11yEmptyWeight)
        .accessibilityHint(lastHint ?? "")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onStepWeight(1)
            case .decrement: onStepWeight(-1)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("d2.set.\(set.n).weight")
    }

    private func repsCell(showUnit: Bool) -> some View {
        Button(action: onReps) {
            cell(repsText, unitLabel: showUnit ? SessionCopy.reps : nil, active: editing == .reps)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(SessionCopy.a11yReps(set: set.n))
        .accessibilityValue(repsText)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onStepReps(1)
            case .decrement: onStepReps(-1)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("d2.set.\(set.n).reps")
    }

    private var lastHint: String? {
        guard let w = set.lastWeightKg, let r = set.lastReps else { return nil }
        return SessionCopy.a11yLastHint(weight: unit.spoken(unit.displayValue(kg: w)), reps: r)
    }

    private var check: some View {
        Button(action: onCheck) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.setCell, style: .continuous)
                    .fill(set.done ? Color.plate : Color.clear)
                RoundedRectangle(cornerRadius: Radius.setCell, style: .continuous)
                    .strokeBorder(set.done ? Color.plate : Color.rail, lineWidth: 2)
                Image(systemName: "checkmark")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(set.done ? Color.ink : Color.rail)
                    .scaleEffect(set.done || reduceMotion ? 1 : 0.85)
            }
            .frame(width: Spacing.touchTargetMin, height: Spacing.touchTargetMin)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(SessionCopy.a11yCheck(set: set.n, done: set.done))
        .accessibilityAddTraits(set.done ? [.isSelected] : [])
        .accessibilityAction(named: SessionCopy.a11yCopyToNext, onCopyToNext)
        .accessibilityAction(named: SessionCopy.a11ySetDetail, onDetail)
        .accessibilityAction(named: SessionCopy.a11yDeleteSet, onDelete)
        .accessibilityIdentifier("d2.set.\(set.n).check")
    }
}

/// The rest bar above Finish: count-down in mono, minus 15 s, plus 15 s, Skip. Drawn from the end
/// instant, so it is right after a lock or a relaunch.
struct RestBar: View {
    let endsAt: Date
    let total: Int
    let onAdjust: (Int) -> Void
    let onSkip: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = max(0, Int(endsAt.timeIntervalSince(context.date).rounded(.up)))
            let progress = total > 0 ? Double(left) / Double(total) : 0
            VStack(spacing: Spacing.grid(2)) {
                HStack(spacing: Spacing.grid(3)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(SessionCopy.rest).pgymText(.label).foregroundStyle(Color.steel)
                        Text(Self.clock(left))
                            .font(.pgym(.data, size: 24))
                            .foregroundStyle(Color.chalk)
                            .monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(SessionCopy.a11yRestLeft(SessionCopy.a11yRestSpoken(left)))
                    .accessibilityIdentifier("d2.rest.clock")
                    Spacer()
                    pill(SessionCopy.minus15, id: "d2.rest.minus") { onAdjust(-15) }
                    pill(SessionCopy.plus15, id: "d2.rest.plus") { onAdjust(15) }
                    pill(SessionCopy.skip, id: "d2.rest.skip", action: onSkip)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.rail)
                        Capsule().fill(Color.chalk).frame(width: proxy.size.width * progress)
                    }
                }
                .frame(height: 4)
                .accessibilityHidden(true)
            }
            .padding(Spacing.grid(3))
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.iron))
        }
    }

    static func clock(_ seconds: Int) -> String {
        "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }

    private func pill(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.pgym(.bodyMedium, size: 15))
                .foregroundStyle(Color.chalk)
                .padding(.horizontal, Spacing.grid(3))
                .frame(minHeight: Spacing.touchTargetMin)
                .background(Capsule().fill(Color.ink))
                .overlay(Capsule().strokeBorder(Color.rail, lineWidth: Stroke.border))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

/// A one-line toast at the top of D2 ("Session resumed. Started 18:02.", "Rest done.").
struct SessionToast: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.pgym(.bodyMedium, size: 15))
            .foregroundStyle(Color.chalk)
            .padding(.horizontal, Spacing.grid(4))
            .padding(.vertical, Spacing.grid(2) + 2)
            .background(Capsule().fill(Color.iron))
            .overlay(Capsule().strokeBorder(Color.rail, lineWidth: Stroke.border))
            .accessibilityIdentifier("d2.toast")
    }
}

/// Elapsed time from the start instant, so it is right after a kill: "52:10", or "1:02:10".
enum SessionClock {
    static func elapsed(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return "\(h):" + String(format: "%02d:%02d", m, s) }
        return "\(m):" + String(format: "%02d", s)
    }
}

/// Moment the app process started, to tell a resumed session from one started just now.
enum AppLaunch {
    static let date = Date()
}
