import DesignSystem
import SwiftData
import SwiftUI

/// Where F2 sends the user: the F3 editor for a new routine or an existing one.
enum RoutineEditorTarget: Hashable, Identifiable {
    case new
    case existing(String)

    var id: String {
        switch self {
        case .new: "new"
        case .existing(let id): id
        }
    }
}

/// F2 Routines: the rotation in order, reorder by drag, delete by swipe, Add routine.
/// Strings: pgym-app-copy.md F2. Behaviour: pgym-flow-spec.md F2.
struct RoutinesScreen: View {
    static let viewID = "F2"

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(RoutineStore.activeDescriptor) private var routines: [Routine]
    @Query(sort: \CustomExercise.name) private var customExercises: [CustomExercise]

    @State private var editMode: EditMode = .inactive
    @State private var editorTarget: RoutineEditorTarget?
    @State private var pendingDelete: Routine?
    @State private var showStarters = false
    @State private var reorderTick = 0
    @State private var addedTick = 0

    private var library: ExerciseLibrary {
        ExerciseLibrary(custom: customExercises.map(\.exercise))
    }

    var body: some View {
        List {
            Text("Routines")
                .pgymText(.display)
                .foregroundStyle(Color.chalk)
                .designedListRow(top: Spacing.grid(2), bottom: Spacing.grid(3))
                .accessibilityAddTraits(.isHeader)

            if routines.isEmpty {
                emptyState
            } else {
                ForEach(Array(routines.enumerated()), id: \.element.id) { index, routine in
                    RoutineRow(routine: routine, position: index + 1, library: library, isNextUp: index == 0) {
                        editorTarget = .existing(routine.id)
                    }
                    .designedListRow()
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete") { pendingDelete = routine }
                            .tint(Color.rail)
                    }
                }
                .onMove(perform: move)

                Button {
                    showStarters = true
                } label: {
                    Label("Add a starter routine", systemImage: "square.stack.3d.up")
                        .font(.pgym(.bodyMedium, size: 15))
                        .foregroundStyle(Color.bone)
                        .frame(maxWidth: .infinity, minHeight: Spacing.touchTargetMin)
                }
                .buttonStyle(.plain)
                .designedListRow(top: Spacing.grid(3))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.ink.ignoresSafeArea())
        .environment(\.editMode, $editMode)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.ink, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if routines.count > 1 {
                    Button(editMode.isEditing ? "Done" : "Reorder") {
                        withAnimation(.pgymSpring(reduceMotion: reduceMotion)) {
                            editMode = editMode.isEditing ? .inactive : .active
                        }
                    }
                    .font(.pgym(.bodyMedium, size: 17))
                    .foregroundStyle(Color.chalk)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton("Add routine") { editorTarget = .new }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.bottom, Spacing.grid(2))
                .background(Color.ink.opacity(0.001))
        }
        .navigationDestination(item: $editorTarget) { target in
            switch target {
            case .new:
                RoutineEditorScreen(routine: nil)
            case .existing(let id):
                RoutineEditorScreen(routine: routines.first { $0.id == id })
            }
        }
        .sheet(isPresented: $showStarters) {
            StarterPickerSheet(library: library) { starter in
                adopt(starter)
            }
            .presentationDetents([.large])
            .presentationBackground(Color.ink)
        }
        .confirmationDialog(
            pendingDelete.map { "Delete \($0.name)?" } ?? "",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { routine in
            Button("Delete") { delete(routine) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Past sessions keep their sets.")
        }
        .sensoryFeedback(.impact(weight: .light), trigger: reorderTick)
        .sensoryFeedback(.success, trigger: addedTick)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.\(Self.viewID)")
    }

    @ViewBuilder private var emptyState: some View {
        VStack(alignment: .leading, spacing: Spacing.cardGap) {
            Text("No routines. Add one, or start an empty session from Today.")
                .pgymText(.body)
                .foregroundStyle(Color.bone)
            SectionLabel("Start from a starter")
                .padding(.top, Spacing.grid(2))
        }
        .designedListRow()

        ForEach(StarterRoutine.all) { starter in
            Button {
                adopt(starter)
            } label: {
                StarterRoutineCard(starter: starter, library: library, isSelected: false)
            }
            .buttonStyle(.plain)
            .designedListRow()
            .accessibilityHint("Adds \(starter.workouts.count) routines you can edit.")
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        withAnimation(.pgymSpring(reduceMotion: reduceMotion)) {
            try? RoutineStore(context: context).move(fromOffsets: source, toOffset: destination)
        }
        reorderTick += 1
        RoutineSyncCoordinator.shared.requestSync()
    }

    private func delete(_ routine: Routine) {
        withAnimation(.pgymSpring(reduceMotion: reduceMotion)) {
            try? RoutineStore(context: context).delete(routine)
        }
        pendingDelete = nil
        RoutineSyncCoordinator.shared.requestSync()
    }

    private func adopt(_ starter: StarterRoutine) {
        withAnimation(.pgymSpring(reduceMotion: reduceMotion)) {
            _ = try? RoutineStore(context: context).adopt(starter)
        }
        addedTick += 1
        RoutineSyncCoordinator.shared.requestSync()
    }
}

/// One routine in F2: position number, name, "{n} exercises", the exercises in one line.
private struct RoutineRow: View {
    let routine: Routine
    let position: Int
    let library: ExerciseLibrary
    let isNextUp: Bool
    let onOpen: () -> Void

    var body: some View {
        let items = routine.exercises
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: Spacing.grid(3)) {
                Text(String(format: "%02d", position))
                    .font(.pgym(.data, size: 15))
                    .foregroundStyle(isNextUp ? Color.plate : Color.steel)
                    .frame(width: 28, alignment: .leading)
                VStack(alignment: .leading, spacing: Spacing.grid(1)) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(routine.name)
                            .pgymText(.title)
                            .foregroundStyle(Color.chalk)
                            .lineLimit(2)
                        Spacer(minLength: Spacing.grid(2))
                        if isNextUp {
                            Text("Next up")
                                .pgymText(.labelBold, size: 10)
                                .foregroundStyle(Color.plate)
                        }
                    }
                    Text("\(items.count) exercises")
                        .pgymText(.label)
                        .foregroundStyle(Color.steel)
                    Text(items.map { library.name(for: $0.exerciseId) }.joined(separator: ", "))
                        .font(.pgym(.body, size: 15))
                        .foregroundStyle(Color.bone)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.steel)
                    .padding(.top, Spacing.grid(1))
                    .accessibilityHidden(true)
            }
            .ironCard()
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(routine.name), \(items.count) exercises\(isNextUp ? ", next up" : "")")
        .accessibilityHint("Opens the routine editor.")
    }
}

struct RoutinesScreen_Previews: PreviewProvider {
    static var previews: some View {
        let _ = FontRegistry.registerAll()
        let container = Models.makeContainer(inMemory: true)
        let _ = try? RoutineStore(context: container.mainContext).adopt(.pushPullLegs)
        NavigationStack { RoutinesScreen() }
            .modelContainer(container)
            .preferredColorScheme(.dark)
    }
}
