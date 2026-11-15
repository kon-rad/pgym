import DesignSystem
import SwiftUI

/// D4 Set detail: the rare per-set fields behind a long press, so they never slow the normal path.
/// Warm-up or working, an optional effort rating (hidden until asked for), a note, and Delete set.
struct SetDetailSheet: View {
    static let viewID = "D4"

    enum Result: Equatable {
        case save(type: SetType, rpe: Int?, note: String)
        case delete
    }

    /// Read once at init: after Delete set the model is gone, and the sheet must not touch it while
    /// it animates away.
    private let number: Int
    private let exerciseName: String
    let onDone: (Result) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var type: SetType
    @State private var rpe: Int?
    @State private var showsEffort: Bool
    @State private var note: String
    @FocusState private var noteFocused: Bool

    init(set: SessionSet, onDone: @escaping (Result) -> Void) {
        self.number = set.n
        self.exerciseName = set.exercise?.name ?? ""
        self.onDone = onDone
        _type = State(initialValue: set.type)
        _rpe = State(initialValue: set.rpe)
        _showsEffort = State(initialValue: set.rpe != nil)
        _note = State(initialValue: set.note)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.cardGap) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Spacing.grid(1)) {
                    Text(SessionCopy.setTitle(number))
                        .pgymText(.display, size: 44)
                        .foregroundStyle(Color.chalk)
                        .accessibilityAddTraits(.isHeader)
                    Text(SessionCopy.setSubtitle(number, exercise: exerciseName))
                        .pgymText(.label)
                        .foregroundStyle(Color.steel)
                }
                Spacer()
                Button(SessionCopy.cancel) { dismiss() }
                    .font(.pgym(.bodyMedium, size: 17))
                    .foregroundStyle(Color.bone)
                    .frame(minHeight: Spacing.touchTargetMin)
            }

            VStack(alignment: .leading, spacing: Spacing.grid(2)) {
                SectionLabel(SessionCopy.type)
                HStack(spacing: Spacing.grid(2)) {
                    ForEach([SetType.working, SetType.warmup], id: \.self) { option in
                        Chip(title: option.label, isSelected: type == option) {
                            withAnimation(Animation.pgymSpring(reduceMotion: reduceMotion)) { type = option }
                        }
                        .accessibilityIdentifier("d4.type.\(option.rawValue)")
                    }
                }
                Text(SessionCopy.warmupHint)
                    .font(.pgym(.body, size: 15))
                    .foregroundStyle(Color.steel)
            }

            VStack(alignment: .leading, spacing: Spacing.grid(2)) {
                if showsEffort {
                    HStack {
                        SectionLabel(SessionCopy.effort)
                        Spacer()
                        Button(SessionCopy.clearEffort) {
                            withAnimation(Animation.pgymSpring(reduceMotion: reduceMotion)) {
                                rpe = nil
                                showsEffort = false
                            }
                        }
                        .font(.pgym(.bodyMedium, size: 15))
                        .foregroundStyle(Color.bone)
                        .frame(minHeight: Spacing.touchTargetMin)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.grid(2)) {
                            ForEach(1...10, id: \.self) { value in
                                Chip(title: "\(value)", isSelected: rpe == value) { rpe = value }
                                    .accessibilityLabel("Effort \(value) of 10")
                            }
                        }
                    }
                    Text(SessionCopy.effortHint)
                        .font(.pgym(.body, size: 15))
                        .foregroundStyle(Color.steel)
                } else {
                    Button {
                        withAnimation(Animation.pgymSpring(reduceMotion: reduceMotion)) { showsEffort = true }
                    } label: {
                        Label(SessionCopy.addEffort, systemImage: "plus")
                            .font(.pgym(.bodyMedium, size: 15))
                            .foregroundStyle(Color.chalk)
                            .frame(minHeight: Spacing.touchTargetMin)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("d4.addEffort")
                }
            }

            TextField(SessionCopy.notePlaceholder, text: $note, axis: .vertical)
                .font(.pgym(.body, size: 17))
                .foregroundStyle(Color.chalk)
                .lineLimit(1...4)
                .focused($noteFocused)
                .padding(Spacing.grid(3))
                .background(RoundedRectangle(cornerRadius: Radius.input, style: .continuous).fill(Color.iron))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.input, style: .continuous)
                        .strokeBorder(noteFocused ? Color.chalk : Color.rail, lineWidth: Stroke.border)
                )
                .accessibilityIdentifier("d4.note")

            Spacer(minLength: 0)

            Button(SessionCopy.deleteSet, role: .destructive) {
                onDone(.delete)
                dismiss()
            }
            .font(.pgym(.bodyMedium, size: 15))
            .foregroundStyle(Color.chalk)
            .frame(maxWidth: .infinity, minHeight: Spacing.touchTargetMin)
            .accessibilityIdentifier("d4.delete")

            PrimaryButton(SessionCopy.save) {
                onDone(.save(type: type, rpe: showsEffort ? rpe : nil, note: note.trimmingCharacters(in: .whitespacesAndNewlines)))
                dismiss()
            }
            .accessibilityIdentifier("d4.save")
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.top, Spacing.grid(6))
        .padding(.bottom, Spacing.grid(2))
        .background(Color.ink.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.\(Self.viewID)")
    }
}
