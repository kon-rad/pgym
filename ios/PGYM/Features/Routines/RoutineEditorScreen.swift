import DesignSystem
import SwiftData
import SwiftUI

/// F3 Routine editor: name, exercises in order with target sets and reps, Add exercise (D3), Save.
/// Edits a `RoutineDraft`; the stored routine changes only on Save, so Back can discard.
/// Strings: pgym-app-copy.md F3. Behaviour: pgym-flow-spec.md F3.
struct RoutineEditorScreen: View {
    static let viewID = "F3"

    /// Called after a successful save, before the screen closes (B4's "Build my own" uses it).
    var onSaved: ((Routine) -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \CustomExercise.name) private var customExercises: [CustomExercise]

    @State private var draft: RoutineDraft
    @State private var original: RoutineDraft
    @State private var editMode: EditMode = .inactive
    @State private var showAddExercise = false
    @State private var confirmDiscard = false
    @State private var confirmDelete = false
    @State private var saveTick = 0
    @State private var addTick = 0
    @FocusState private var nameFocused: Bool

    private let routine: Routine?

    init(routine: Routine?, onSaved: ((Routine) -> Void)? = nil) {
        self.routine = routine
        self.onSaved = onSaved
        let start = routine.map(RoutineDraft.init(routine:)) ?? RoutineDraft()
        _draft = State(initialValue: start)
        _original = State(initialValue: start)
    }

    private var library: ExerciseLibrary {
        ExerciseLibrary(custom: customExercises.map(\.exercise))
    }

    private var hasChanges: Bool { draft != original }

    var body: some View {
        List {
            header
            nameField
            exercisesSection
            footer
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Color.ink.ignoresSafeArea())
        .environment(\.editMode, $editMode)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(Color.ink, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if hasChanges { confirmDiscard = true } else { dismiss() }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.chalk)
                        .frame(minWidth: Spacing.touchTargetMin, minHeight: Spacing.touchTargetMin, alignment: .leading)
                }
                .accessibilityLabel("Back")
            }
            ToolbarItem(placement: .topBarTrailing) {
                if draft.exercises.count > 1 {
                    Button(editMode.isEditing ? "Done" : "Reorder") {
                        withAnimation(Animation.pgymSpring(reduceMotion: reduceMotion)) {
                            editMode = editMode.isEditing ? .inactive : .active
                        }
                    }
                    .font(.pgym(.bodyMedium, size: 17))
                    .foregroundStyle(Color.chalk)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Spacing.grid(2)) {
                // Save stays disabled until the draft is valid (flow spec F3); this line says why.
                if hasChanges || routine != nil, let problem = draft.problem {
                    Text(problem.message)
                        .font(.pgym(.bodyMedium, size: 15))
                        .foregroundStyle(Color.chalk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Spacing.grid(3))
                        .background(RoundedRectangle(cornerRadius: Radius.input, style: .continuous).fill(Color.iron))
                        .transition(.opacity)
                }
                PrimaryButton("Save routine", action: save)
                    .disabled(!draft.isValid)
                    .accessibilityHint(draft.problem?.message ?? "")
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.bottom, Spacing.grid(2))
        }
        .sheet(isPresented: $showAddExercise) {
            AddExerciseSheet { exercise in
                withAnimation(Animation.pgymSpring(reduceMotion: reduceMotion)) { draft.add(exercise) }
                addTick += 1
            }
        }
        .confirmationDialog("Discard changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard") { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete \(draft.trimmedName.isEmpty ? "this routine" : draft.trimmedName)?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete routine", action: deleteRoutine)
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("Past sessions keep their sets.")
        }
        .sensoryFeedback(.success, trigger: saveTick)
        .sensoryFeedback(.impact(weight: .light), trigger: addTick)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.\(Self.viewID)")
    }

    // MARK: Sections

    private var header: some View {
        Text(routine == nil ? "New routine" : "Edit routine")
            .pgymText(.display, size: 44)
            .foregroundStyle(Color.chalk)
            .accessibilityAddTraits(.isHeader)
            .designedListRow(top: Spacing.grid(2), bottom: Spacing.grid(3))
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: Spacing.grid(2)) {
            SectionLabel("Name")
            TextField("", text: $draft.name, prompt: Text("Push A").foregroundStyle(Color.steel))
                .font(.pgym(.title))
                .foregroundStyle(Color.chalk)
                .tint(Color.plate)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused($nameFocused)
                .padding(.horizontal, Spacing.grid(4))
                .frame(minHeight: 52)
                .background(RoundedRectangle(cornerRadius: Radius.input, style: .continuous).fill(Color.iron))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.input, style: .continuous)
                        .strokeBorder(nameFocused ? Color.chalk : Color.rail, lineWidth: Stroke.border)
                )
                .accessibilityLabel("Name")
        }
        .designedListRow(bottom: Spacing.grid(4))
    }

    @ViewBuilder private var exercisesSection: some View {
        SectionLabel("Exercises")
            .designedListRow(bottom: Spacing.grid(1))

        if draft.exercises.isEmpty {
            Text("Add the first exercise.")
                .pgymText(.body)
                .foregroundStyle(Color.bone)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ironCard()
                .designedListRow()
        } else {
            ForEach($draft.exercises) { $item in
                RoutineItemRow(item: $item, exercise: library.exercise(id: item.exerciseId))
                    .designedListRow()
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Remove") { remove(item.id) }
                            .tint(Color.rail)
                    }
            }
            .onMove { source, destination in
                withAnimation(Animation.pgymSpring(reduceMotion: reduceMotion)) {
                    draft.exercises.moveElements(fromOffsets: source, toOffset: destination)
                }
            }
        }

        SecondaryButton("Add exercise") { showAddExercise = true }
            .designedListRow(top: Spacing.grid(2))
    }

    @ViewBuilder private var footer: some View {
        if routine != nil {
            Button("Delete routine") { confirmDelete = true }
                .font(.pgym(.bodyMedium, size: 15))
                .foregroundStyle(Color.steel)
                .frame(maxWidth: .infinity, minHeight: Spacing.touchTargetMin)
                .buttonStyle(.plain)
                .designedListRow(top: Spacing.grid(6), bottom: Spacing.grid(6))
        }
    }

    // MARK: Actions

    private func remove(_ id: UUID) {
        withAnimation(Animation.pgymSpring(reduceMotion: reduceMotion)) {
            draft.exercises.removeAll { $0.id == id }
        }
    }

    private func save() {
        guard draft.isValid, let saved = try? RoutineStore(context: context).save(draft) else { return }
        saveTick += 1
        original = draft
        RoutineSyncCoordinator.shared.requestSync()
        onSaved?(saved)
        dismiss()
    }

    private func deleteRoutine() {
        if let routine {
            try? RoutineStore(context: context).delete(routine)
            RoutineSyncCoordinator.shared.requestSync()
        }
        dismiss()
    }
}

/// One exercise in F3: name and meta, then sets and reps steppers.
private struct RoutineItemRow: View {
    @Binding var item: RoutineItem
    let exercise: Exercise?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.grid(3)) {
            ExerciseLabel(exercise)
            HStack(spacing: Spacing.grid(3)) {
                SectionLabel("Sets x reps")
                Spacer(minLength: 0)
                CountStepper(label: "Sets", value: $item.targetSets, range: RoutineItem.setsRange)
                Text("x")
                    .font(.pgym(.data, size: 15))
                    .foregroundStyle(Color.steel)
                    .accessibilityHidden(true)
                CountStepper(label: "Reps", value: $item.targetReps, range: RoutineItem.repsRange)
            }
        }
        .ironCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(exercise?.name ?? "Unknown exercise"), \(item.targetSets) sets of \(item.targetReps)")
    }
}

struct RoutineEditorScreen_Previews: PreviewProvider {
    static var previews: some View {
        let _ = FontRegistry.registerAll()
        let container = Models.makeContainer(inMemory: true)
        let routine = try? RoutineStore(context: container.mainContext).adopt(.upperLower).first
        NavigationStack { RoutineEditorScreen(routine: routine) }
            .modelContainer(container)
            .preferredColorScheme(.dark)
    }
}
