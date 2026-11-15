import DesignSystem
import SwiftUI

/// A starter as a card: title, caption, the exercises in one line, and an optional "Fits 4 days" tag.
/// Used by the B4 picker below and by the F2 empty state.
struct StarterRoutineCard: View {
    let starter: StarterRoutine
    let library: ExerciseLibrary
    let isSelected: Bool
    var fitsGoal: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.grid(2)) {
            HStack(alignment: .firstTextBaseline) {
                Text(starter.title)
                    .pgymText(.title)
                    .foregroundStyle(Color.chalk)
                Spacer(minLength: Spacing.grid(2))
                if let fitsGoal {
                    Text("Fits \(fitsGoal) days")
                        .pgymText(.labelBold, size: 10)
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, Spacing.grid(2))
                        .padding(.vertical, Spacing.grid(1))
                        .background(Capsule().fill(Color.plate))
                }
            }
            Text(starter.caption)
                .pgymText(.label)
                .foregroundStyle(Color.steel)
            Text(starter.exerciseLine(using: library))
                .font(.pgym(.body, size: 15))
                .foregroundStyle(Color.bone)
                .lineLimit(1)
        }
        .ironCard()
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(isSelected ? Color.plate : Color.clear, lineWidth: Stroke.stamp)
        )
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(starter.title). \(starter.caption)\(fitsGoal.map { " Fits \($0) days." } ?? "")")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// B4 content: pick one of the three starters and use it. Card I3 places this in onboarding (B4);
/// F2 shows it as a sheet. Strings: pgym-app-copy.md B4.
struct StarterRoutinePicker: View {
    static let viewID = "B4"

    let library: ExerciseLibrary
    /// The user's weekly goal, when known, to preselect and tag the starter that fits it.
    let weeklyGoal: Int?
    /// Opens F3 to build a routine from scratch. Hidden when nil.
    let onBuildOwn: (() -> Void)?
    let onUse: (StarterRoutine) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: StarterRoutine?

    init(
        library: ExerciseLibrary,
        weeklyGoal: Int? = nil,
        onBuildOwn: (() -> Void)? = nil,
        onUse: @escaping (StarterRoutine) -> Void
    ) {
        self.library = library
        self.weeklyGoal = weeklyGoal
        self.onBuildOwn = onBuildOwn
        self.onUse = onUse
    }

    private var suggested: StarterRoutine? { weeklyGoal.map(StarterRoutine.suggested(forGoal:)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.cardGapMin) {
                Text("Pick a starting routine")
                    .pgymText(.display, size: 44)
                    .foregroundStyle(Color.chalk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, Spacing.grid(2))

                ForEach(StarterRoutine.all) { starter in
                    Button {
                        withAnimation(Animation.pgymSpring(reduceMotion: reduceMotion)) { selection = starter }
                    } label: {
                        StarterRoutineCard(
                            starter: starter,
                            library: library,
                            isSelected: selection == starter,
                            fitsGoal: starter == suggested ? weeklyGoal : nil
                        )
                    }
                    .buttonStyle(.plain)
                }

                if let onBuildOwn {
                    Button("Build my own", action: onBuildOwn)
                        .font(.pgym(.bodyMedium, size: 17))
                        .foregroundStyle(Color.chalk)
                        .frame(maxWidth: .infinity, minHeight: Spacing.touchTargetMin)
                }

                Text("Every routine can be edited later.")
                    .pgymText(.body)
                    .foregroundStyle(Color.steel)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.top, Spacing.grid(6))
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton("Use this routine") {
                if let selection { onUse(selection) }
            }
            .disabled(selection == nil)
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.bottom, Spacing.grid(2))
        }
        .sensoryFeedback(.selection, trigger: selection)
        .background(Color.ink.ignoresSafeArea())
        .onAppear { if selection == nil { selection = suggested } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.\(Self.viewID)")
    }
}

/// F2's "Add a starter routine": the B4 picker in a sheet.
struct StarterPickerSheet: View {
    let library: ExerciseLibrary
    let onUse: (StarterRoutine) -> Void
    @Environment(\.dismiss) private var dismiss

    init(library: ExerciseLibrary, onUse: @escaping (StarterRoutine) -> Void) {
        self.library = library
        self.onUse = onUse
    }

    var body: some View {
        NavigationStack {
            StarterRoutinePicker(library: library) { starter in
                onUse(starter)
                dismiss()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.chalk)
                }
            }
            .toolbarBackground(Color.ink, for: .navigationBar)
        }
    }
}

struct StarterRoutinePicker_Previews: PreviewProvider {
    static var previews: some View {
        let _ = FontRegistry.registerAll()
        StarterRoutinePicker(library: ExerciseLibrary(), weeklyGoal: 4, onBuildOwn: {}) { _ in }
            .preferredColorScheme(.dark)
    }
}
