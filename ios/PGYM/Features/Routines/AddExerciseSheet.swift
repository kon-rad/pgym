import DesignSystem
import SwiftData
import SwiftUI

/// D3 Add exercise: search, Recent, By muscle group, and "Add {query} as a new exercise".
/// One tap on an exercise picks it and closes the sheet. Used by F3 now and by D2 (card I5).
/// Strings: pgym-app-copy.md D3. Behaviour: pgym-flow-spec.md D3.
struct AddExerciseSheet: View {
    static let viewID = "D3"

    let onPick: (Exercise) -> Void
    var recents: RecentExercises

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \CustomExercise.name) private var customExercises: [CustomExercise]

    @State private var query = ""
    @State private var group: MuscleGroup?
    @State private var creating: NewExerciseDraft?
    @State private var pickTick = 0
    @FocusState private var searchFocused: Bool

    init(recents: RecentExercises = RecentExercises(), onPick: @escaping (Exercise) -> Void) {
        self.recents = recents
        self.onPick = onPick
    }

    private var library: ExerciseLibrary {
        ExerciseLibrary(custom: customExercises.map(\.exercise))
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if let creating {
                NewExerciseForm(
                    draft: Binding(get: { creating }, set: { self.creating = $0 }),
                    onCancel: { withAnimation(.pgymSpring(reduceMotion: reduceMotion)) { self.creating = nil } },
                    onAdd: addCustom
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                searchField
                groupChips
                results
            }
        }
        .background(Color.ink.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.ink)
        .sensoryFeedback(.selection, trigger: pickTick)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.\(Self.viewID)")
    }

    // MARK: Parts

    private var topBar: some View {
        HStack {
            Text(creating == nil ? "Add exercise" : "New exercise")
                .pgymText(.labelBold, size: 12)
                .foregroundStyle(Color.chalk)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button("Cancel") { dismiss() }
                .font(.pgym(.bodyMedium, size: 17))
                .foregroundStyle(Color.chalk)
                .frame(minHeight: Spacing.touchTargetMin)
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.top, Spacing.grid(4))
    }

    private var searchField: some View {
        HStack(spacing: Spacing.grid(2)) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.steel)
                .accessibilityHidden(true)
            // Not focused on open: a raised keyboard would hide Recent (flow spec D3).
            TextField("", text: $query, prompt: Text("Search exercises").foregroundStyle(Color.steel))
                .font(.pgym(.body, size: 17))
                .foregroundStyle(Color.chalk)
                .tint(Color.plate)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .focused($searchFocused)
                .accessibilityLabel("Search exercises")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.steel)
                        .frame(minWidth: Spacing.touchTargetMin, minHeight: Spacing.touchTargetMin)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Spacing.grid(4))
        .frame(minHeight: 48)
        .background(RoundedRectangle(cornerRadius: Radius.input, style: .continuous).fill(Color.iron))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.input, style: .continuous)
                .strokeBorder(searchFocused ? Color.chalk : Color.rail, lineWidth: Stroke.border)
        )
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.top, Spacing.grid(3))
    }

    /// The "By muscle group" filter. With no search, the list below is sectioned by group too.
    private var groupChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.grid(2)) {
                Chip(title: "All", isSelected: group == nil) { select(nil) }
                ForEach(MuscleGroup.allCases) { g in
                    Chip(title: g.label, isSelected: group == g) { select(g) }
                }
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.vertical, Spacing.grid(2))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("By muscle group")
    }

    private var results: some View {
        List {
            if trimmedQuery.isEmpty {
                let recent = recents.exercises(in: library).filter { group == nil || $0.muscleGroup == group }
                if !recent.isEmpty {
                    Section {
                        ForEach(recent) { row($0) }
                    } header: {
                        sectionHeader("Recent")
                    }
                }
                ForEach(group.map { [$0] } ?? MuscleGroup.allCases) { g in
                    Section {
                        ForEach(library.exercises(in: g)) { row($0) }
                    } header: {
                        sectionHeader(g.label)
                    }
                }
            } else {
                let found = library.search(trimmedQuery, in: group)
                if found.isEmpty {
                    noResults
                } else {
                    ForEach(found) { row($0) }
                    addAsNewRow
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .animation(.pgymSpring(reduceMotion: reduceMotion), value: group)
    }

    private func sectionHeader(_ text: String) -> some View {
        SectionLabel(text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.vertical, Spacing.grid(2))
            .background(Color.ink)
            .listRowInsets(EdgeInsets())
    }

    private func row(_ exercise: Exercise) -> some View {
        Button {
            pick(exercise)
        } label: {
            HStack(spacing: Spacing.grid(3)) {
                ExerciseLabel(exercise)
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.steel)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, Spacing.grid(3))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.ink)
        .listRowSeparatorTint(Color.hairline)
        .listRowInsets(EdgeInsets(top: 0, leading: Spacing.screenMargin, bottom: 0, trailing: Spacing.screenMargin))
        .accessibilityLabel("\(exercise.name), \(exercise.muscleGroup.label), \(exercise.equipment.label)")
        .accessibilityHint("Adds it and closes.")
    }

    private var noResults: some View {
        VStack(alignment: .leading, spacing: Spacing.cardGap) {
            Text("Nothing called \(trimmedQuery).")
                .pgymText(.body)
                .foregroundStyle(Color.bone)
            SecondaryButton("Add \(trimmedQuery) as a new exercise") { startCreating() }
        }
        .padding(.top, Spacing.grid(4))
        .designedListRow()
    }

    private var addAsNewRow: some View {
        Button {
            startCreating()
        } label: {
            Label("Add \(trimmedQuery) as a new exercise", systemImage: "plus.circle")
                .font(.pgym(.bodyMedium, size: 15))
                .foregroundStyle(Color.bone)
                .frame(maxWidth: .infinity, minHeight: Spacing.touchTargetMin, alignment: .leading)
        }
        .buttonStyle(.plain)
        .designedListRow(top: Spacing.grid(3))
    }

    // MARK: Actions

    private func select(_ g: MuscleGroup?) {
        withAnimation(.pgymSpring(reduceMotion: reduceMotion)) { group = g }
    }

    private func pick(_ exercise: Exercise) {
        recents.record(exercise.id)
        pickTick += 1
        onPick(exercise)
        dismiss()
    }

    private func startCreating() {
        searchFocused = false
        withAnimation(.pgymSpring(reduceMotion: reduceMotion)) {
            creating = NewExerciseDraft(name: trimmedQuery, muscleGroup: group ?? .chest, equipment: .barbell)
        }
    }

    private func addCustom() {
        guard let creating, creating.isValid,
              let custom = try? CustomExerciseStore(context: context).create(
                name: creating.name, muscleGroup: creating.muscleGroup, equipment: creating.equipment)
        else { return }
        pick(custom.exercise)
    }
}

struct NewExerciseDraft: Equatable {
    var name: String
    var muscleGroup: MuscleGroup
    var equipment: Equipment

    var isValid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// "Add {query} as a new exercise": name, muscle group, equipment, then Add.
private struct NewExerciseForm: View {
    @Binding var draft: NewExerciseDraft
    let onCancel: () -> Void
    let onAdd: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.cardGap) {
                SectionLabel("Name")
                TextField("", text: $draft.name, prompt: Text("Cable fly").foregroundStyle(Color.steel))
                    .font(.pgym(.title))
                    .foregroundStyle(Color.chalk)
                    .tint(Color.plate)
                    .textInputAutocapitalization(.sentences)
                    .padding(.horizontal, Spacing.grid(4))
                    .frame(minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: Radius.input, style: .continuous).fill(Color.iron))
                    .accessibilityLabel("Name")

                SectionLabel("Muscle group")
                    .padding(.top, Spacing.grid(2))
                FlowChips(items: MuscleGroup.allCases, label: \.label, selection: $draft.muscleGroup)

                SectionLabel("Equipment")
                    .padding(.top, Spacing.grid(2))
                FlowChips(items: Equipment.allCases, label: \.label, selection: $draft.equipment)

                Button("Cancel", action: onCancel)
                    .font(.pgym(.bodyMedium, size: 17))
                    .foregroundStyle(Color.bone)
                    .frame(maxWidth: .infinity, minHeight: Spacing.touchTargetMin)
                    .padding(.top, Spacing.grid(2))
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.top, Spacing.grid(4))
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton("Add", action: onAdd)
                .disabled(!draft.isValid)
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.bottom, Spacing.grid(2))
        }
    }
}

/// Chips that wrap onto as many lines as they need (Dynamic Type safe).
private struct FlowChips<Item: Hashable & Identifiable>: View {
    let items: [Item]
    let label: KeyPath<Item, String>
    @Binding var selection: Item

    var body: some View {
        WrapLayout(spacing: Spacing.grid(2)) {
            ForEach(items) { item in
                Chip(title: item[keyPath: label], isSelected: selection == item) { selection = item }
            }
        }
    }
}

/// Left-to-right wrapping layout.
private struct WrapLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let isFirst = rows[rows.count - 1].indices.isEmpty
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += isFirst ? size.width : size.width + spacing
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}

struct AddExerciseSheet_Previews: PreviewProvider {
    static var previews: some View {
        let _ = FontRegistry.registerAll()
        Color.ink
            .sheet(isPresented: .constant(true)) {
                AddExerciseSheet { _ in }
            }
            .modelContainer(Models.makeContainer(inMemory: true))
            .preferredColorScheme(.dark)
    }
}
