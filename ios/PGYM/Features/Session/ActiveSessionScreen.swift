import DesignSystem
import SwiftData
import SwiftUI

/// D2 Active session, full screen over the tabs. Logs every set with as few taps as possible,
/// one-handed. D3 Add exercise and D4 Set detail are sheets over it; D5 Leave session is its alert.
///
/// Nothing here waits on the network: every tap is saved to SwiftData at once and the sync queue
/// sends it later (pgym-architecture.md, "The app is offline-first").
struct ActiveSessionScreen: View {
    static let viewID = "D2"

    let session: WorkoutSession
    /// Called after Finish and take proof has ended the session. The proof camera (D6, D7) is card I6.
    var onFinishForProof: (WorkoutSession) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(SessionSyncQueue.self) private var sync
    @Environment(NetworkMonitor.self) private var network
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var unit = WeightUnit.preferred()
    @State private var keypad: KeypadState?
    @State private var detailSet: SessionSet?
    @State private var addingExercise = false
    @State private var confirmingLeave = false
    @State private var confirmingDiscard = false
    @State private var errorSetID: String?
    @State private var toast: String?
    @State private var logTick = 0
    @State private var bestTick = 0
    @State private var restDoneTick = 0

    private let notifier: RestNotificationScheduling = RestTimerNotifier()

    private var store: SessionStore { SessionStore(context: context) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if !network.isOnline {
                Text(SessionCopy.offline)
                    .pgymText(.label, size: 10)
                    .foregroundStyle(Color.steel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.screenMargin)
                    .padding(.bottom, Spacing.grid(2))
                    .accessibilityIdentifier("d2.offline")
            }
            ScrollViewReader { proxy in
                ScrollView {
                    content
                        .padding(.horizontal, Spacing.screenMargin)
                        .padding(.top, Spacing.grid(2))
                        .padding(.bottom, Spacing.grid(6))
                }
                .scrollDismissesKeyboard(.immediately)
                .onChange(of: keypad?.setID) { _, id in
                    // The row being edited sits just above the keypad.
                    guard let id else { return }
                    withAnimation(.pgymSpring(reduceMotion: reduceMotion)) { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            if keypad == nil {
                footer
                    .transition(.opacity)
            }
        }
        .background(Color.ink.ignoresSafeArea())
        .overlay(alignment: .bottom) { keypadOverlay }
        .overlay(alignment: .top) {
            if let toast {
                SessionToast(text: toast)
                    .padding(.top, Spacing.grid(14))
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.pgymSpring(reduceMotion: reduceMotion), value: keypad?.field)
        .animation(.pgymSpring(reduceMotion: reduceMotion), value: keypad == nil)
        .animation(.pgymSpring(reduceMotion: reduceMotion), value: toast)
        .animation(.pgymSpring(reduceMotion: reduceMotion), value: session.restEndsAt)
        .sensoryFeedback(.impact(weight: .medium), trigger: logTick)
        .sensoryFeedback(.success, trigger: bestTick)
        .sensoryFeedback(.success, trigger: restDoneTick)
        .interactiveDismissDisabled()
        .sheet(isPresented: $addingExercise) {
            AddExerciseSheet { picked in
                act { try store.addExercise(picked, to: session) }
            }
        }
        .sheet(item: $detailSet) { set in
            SetDetailSheet(set: set) { result in
                applyDetail(result, to: set)
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(Color.ink)
        }
        .alert(SessionCopy.leaveTitle, isPresented: $confirmingLeave) {
            Button(SessionCopy.keepGoing, role: .cancel) {}
            if session.doneSetCount > 0 {
                Button(SessionCopy.saveWithoutProof) { saveWithoutProof() }
            }
            Button(SessionCopy.discardSession, role: .destructive) {
                if session.doneSetCount > 0 {
                    confirmingDiscard = true
                } else {
                    discard()
                }
            }
        } message: {
            if session.doneSetCount > 0 {
                Text(SessionCopy.leaveBody(sets: session.doneSetCount) + "\n" + SessionCopy.saveWithoutProofCaption)
            } else {
                Text(SessionCopy.leaveBody(sets: 0))
            }
        }
        .alert(SessionCopy.discardTitle(sets: session.doneSetCount), isPresented: $confirmingDiscard) {
            Button(SessionCopy.cancel, role: .cancel) {}
            Button(SessionCopy.discard, role: .destructive) { discard() }
        } message: {
            Text(SessionCopy.discardBody)
        }
        .task { await onAppear() }
        .task(id: session.restEndsAt) { await waitForRestEnd() }
        .onChange(of: session.restEndsAt) { _, end in scheduleRestNotification(end) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { unit = WeightUnit.preferred() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.\(Self.viewID)")
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Spacing.grid(3)) {
            Button { askToLeave() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.chalk)
                    .frame(width: Spacing.touchTargetMin, height: Spacing.touchTargetMin)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(SessionCopy.close)
            .accessibilityIdentifier("d2.close")

            VStack(alignment: .leading, spacing: 2) {
                Text(session.routineName)
                    .pgymText(.title)
                    .foregroundStyle(Color.chalk)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    Text(SessionClock.elapsed(session.elapsed(at: timeline.date)))
                        .font(.pgym(.data, size: 15))
                        .foregroundStyle(Color.steel)
                        .monospacedDigit()
                }
                .accessibilityIdentifier("d2.elapsed")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                Button(SessionCopy.addExercise, systemImage: "plus") { addingExercise = true }
                Menu(SessionCopy.restLength) {
                    ForEach([60, 90, 120, 180, 240], id: \.self) { seconds in
                        Button {
                            act { try store.setRestDefault(seconds, for: session) }
                        } label: {
                            if seconds == session.restDefaultSeconds {
                                Label(SessionCopy.restSeconds(seconds), systemImage: "checkmark")
                            } else {
                                Text(SessionCopy.restSeconds(seconds))
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.chalk)
                    .frame(width: Spacing.touchTargetMin, height: Spacing.touchTargetMin)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(SessionCopy.menu)
            .accessibilityIdentifier("d2.menu")
        }
        .padding(.horizontal, Spacing.grid(3))
        .padding(.vertical, Spacing.grid(2))
        .contentShape(Rectangle())
        // Swiping down from the top asks D5 first: the session never closes by accident.
        .gesture(
            DragGesture(minimumDistance: 24).onEnded { value in
                if value.translation.height > 80 && abs(value.translation.width) < 80 { askToLeave() }
            }
        )
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        let ordered = session.orderedExercises
        let current = store.current(in: session)
        if ordered.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.cardGap) {
                Text(SessionCopy.noExercises)
                    .pgymText(.title)
                    .foregroundStyle(Color.bone)
                SecondaryButton(SessionCopy.addExercise) { addingExercise = true }
                    .accessibilityIdentifier("d2.addExercise.empty")
            }
            .padding(.top, Spacing.grid(10))
        } else {
            VStack(alignment: .leading, spacing: Spacing.cardGap) {
                let done = ordered.filter { $0.isComplete && $0.id != current?.id }
                if !done.isEmpty {
                    SectionLabel(SessionCopy.done)
                    VStack(spacing: Spacing.grid(2)) {
                        ForEach(done) { exercise in
                            collapsedRow(exercise, summary: doneSummary(exercise))
                        }
                    }
                }

                if let current {
                    currentCard(current)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .bottom)), removal: .opacity))
                }

                let upNext = ordered.filter { !$0.isComplete && $0.id != current?.id }
                if !upNext.isEmpty {
                    SectionLabel(SessionCopy.upNext).padding(.top, Spacing.grid(2))
                    VStack(spacing: Spacing.grid(2)) {
                        ForEach(upNext) { exercise in
                            collapsedRow(exercise, summary: upNextSummary(exercise))
                        }
                    }
                }

                Button {
                    addingExercise = true
                } label: {
                    Label(SessionCopy.addExercise, systemImage: "plus")
                        .font(.pgym(.bodyMedium, size: 15))
                        .foregroundStyle(Color.bone)
                        .frame(maxWidth: .infinity, minHeight: Spacing.touchTargetMin)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("d2.addExercise")
            }
            .animation(.pgymSpring(reduceMotion: reduceMotion), value: current?.id)
        }
    }

    private func currentCard(_ exercise: SessionExercise) -> some View {
        VStack(alignment: .leading, spacing: Spacing.grid(3)) {
            Text(exercise.name)
                .pgymText(.title)
                .foregroundStyle(Color.chalk)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("d2.current.name")
            if let lastTime = lastTime(exercise) {
                Text(lastTime)
                    .font(.pgym(.body, size: 15))
                    .foregroundStyle(Color.steel)
            }
            if !dynamicTypeIsAccessibility {
                HStack(spacing: Spacing.grid(2)) {
                    Text(SessionCopy.set).frame(width: 32, alignment: .leading)
                    Text(SessionCopy.last).frame(maxWidth: .infinity, alignment: .leading)
                    Text(unit.label).frame(width: 84)
                    Text(SessionCopy.reps).frame(width: 60)
                    Color.clear.frame(width: Spacing.touchTargetMin, height: 1)
                }
                .pgymText(.label)
                .foregroundStyle(Color.steel)
                .accessibilityHidden(true)
            }
            VStack(spacing: Spacing.grid(1)) {
                ForEach(exercise.orderedSets) { set in
                    VStack(alignment: .leading, spacing: Spacing.grid(1)) {
                        row(for: set)
                        if errorSetID == set.id {
                            Text(SessionCopy.saveFailed)
                                .font(.pgym(.body, size: 15))
                                .foregroundStyle(Color.chalk)
                                .padding(Spacing.grid(2))
                                .background(RoundedRectangle(cornerRadius: Radius.setCell).fill(Color.rail))
                        }
                    }
                    .id(set.id)
                }
            }
            .animation(.pgymSpring(reduceMotion: reduceMotion), value: exercise.sets.count)
            Button {
                act { try store.addSet(to: exercise) }
            } label: {
                Label(SessionCopy.addSet, systemImage: "plus")
                    .font(.pgym(.bodyMedium, size: 15))
                    .foregroundStyle(Color.chalk)
                    .frame(maxWidth: .infinity, minHeight: Spacing.touchTargetMin)
                    .background(RoundedRectangle(cornerRadius: Radius.setCell, style: .continuous).strokeBorder(Color.rail, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("d2.addSet")
        }
        .padding(Spacing.grid(4))
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.iron))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("d2.current")
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var dynamicTypeIsAccessibility: Bool { dynamicTypeSize.isAccessibilitySize }

    private func row(for set: SessionSet) -> some View {
        SetRowView(
            set: set,
            unit: unit,
            editing: keypad?.setID == set.id ? keypad?.field : nil,
            onWeight: { openKeypad(set, field: .weight) },
            onReps: { openKeypad(set, field: .reps) },
            onCheck: { toggle(set) },
            onDetail: { commitKeypad(); detailSet = set },
            onStepWeight: { direction in
                act { try store.setWeight(unit.stepped(kg: set.weightKg, by: direction), for: set) }
            },
            onStepReps: { direction in
                act { try store.setReps(max(0, (set.reps ?? 0) + direction), for: set) }
            },
            onCopyToNext: { copyToNext(set) },
            onDelete: { act { try store.deleteSet(set) } }
        )
    }

    private func collapsedRow(_ exercise: SessionExercise, summary: String) -> some View {
        Button {
            commitKeypad()
            act { try store.makeCurrent(exercise, in: session) }
        } label: {
            HStack(spacing: Spacing.grid(3)) {
                if exercise.isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Color.ink)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.plate))
                        .accessibilityHidden(true)
                }
                Text(summary)
                    .font(.pgym(.bodyMedium, size: 15))
                    .foregroundStyle(exercise.isComplete ? Color.chalk : Color.bone)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if exercise.sets.contains(where: \.isNewBest) {
                    Text(SessionCopy.newBest)
                        .pgymText(.labelBold, size: 10)
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, Spacing.grid(2))
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.plate))
                }
            }
            .padding(.horizontal, Spacing.grid(4))
            .frame(minHeight: 52)
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.iron))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("d2.exercise.\(exercise.order)")
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: Spacing.grid(3)) {
            if let end = session.restEndsAt, end > .now {
                RestBar(
                    endsAt: end,
                    total: session.restTotalSeconds,
                    onAdjust: { seconds in act { try store.adjustRest(session, by: seconds) } },
                    onSkip: { act { try store.skipRest(session) } }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            let canFinish = session.doneSetCount > 0
            PrimaryButton(SessionCopy.finish) { finishForProof() }
                .disabled(!canFinish)
                .accessibilityIdentifier("d2.finish")
                .accessibilityHint(canFinish ? "" : SessionCopy.finishHint)
            if !canFinish {
                Text(SessionCopy.finishHint)
                    .font(.pgym(.body, size: 15))
                    .foregroundStyle(Color.steel)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.top, Spacing.grid(2))
        .padding(.bottom, Spacing.grid(2))
        .background(Color.ink)
    }

    @ViewBuilder private var keypadOverlay: some View {
        if keypad != nil {
            ZStack(alignment: .bottom) {
                // Tapping outside the keypad commits the value without logging the set.
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { commitKeypad() }
                    .accessibilityHidden(true)
                SetKeypad(
                    state: Binding(get: { keypad ?? KeypadState(setID: "", field: .weight, text: "") }, set: { keypad = $0 }),
                    unit: unit,
                    onSwitchField: switchKeypadField,
                    onLogSet: logFromKeypad
                )
            }
            .transition(.move(edge: .bottom))
        }
    }

    // MARK: Summaries

    private func lastTime(_ exercise: SessionExercise) -> String? {
        let last = exercise.orderedSets.compactMap { set -> String? in
            guard let w = set.lastWeightKg, let r = set.lastReps else { return nil }
            return "\(w == 0 ? SessionCopy.bodyweight : unit.format(kg: w)) x \(r)"
        }
        return last.isEmpty ? nil : SessionCopy.lastTime(last)
    }

    private func doneSummary(_ exercise: SessionExercise) -> String {
        let done = exercise.orderedSets.filter(\.done)
        let top = done.compactMap(\.weightKg).max()
        let reps = done.compactMap(\.reps).max()
        return SessionCopy.doneSummary(
            name: exercise.name,
            sets: done.count,
            reps: reps,
            top: top.map { $0 == 0 ? SessionCopy.bodyweight : "\(unit.format(kg: $0)) \(unit.rawValue)" }
        )
    }

    private func upNextSummary(_ exercise: SessionExercise) -> String {
        let sets = exercise.sets.count
        let reps = exercise.orderedSets.first?.reps
        return "\(exercise.name) \(sets) x \(reps ?? exercise.targetReps ?? RoutineItem.defaultReps)"
    }

    // MARK: Actions

    /// Runs a store change. A failed local write (storage full) shows the copy deck's line instead of
    /// losing the tap silently; a good one is queued for sync.
    private func act(setID: String? = nil, _ change: () throws -> Void) {
        do {
            try change()
            if errorSetID == setID || setID == nil { errorSetID = nil }
            sync.requestSync()
        } catch {
            errorSetID = setID ?? keypad?.setID ?? store.current(in: session)?.orderedSets.first?.id
        }
    }

    private func toggle(_ set: SessionSet) {
        commitKeypad()
        if set.done {
            act(setID: set.id) { try store.uncomplete(set) }
            return
        }
        var outcome: SessionStore.CompletionResult?
        act(setID: set.id) { outcome = try store.complete(set) }
        guard let outcome else { return }
        switch outcome {
        case .needsWeight:
            openKeypad(set, field: .weight)
        case let .logged(isNewBest, _):
            logTick += 1
            if isNewBest { bestTick += 1 }
            var announcement = SessionCopy.a11yLogged(set: set.n, rest: SessionCopy.a11yRestSpoken(session.restTotalSeconds))
            if isNewBest { announcement += " " + SessionCopy.a11yNewBest + "." }
            AccessibilityNotification.Announcement(announcement).post()
        }
    }

    private func copyToNext(_ set: SessionSet) {
        guard let exercise = set.exercise else { return }
        if let next = exercise.orderedSets.first(where: { $0.n == set.n + 1 }), !next.done {
            act(setID: next.id) {
                try store.setWeight(set.weightKg, for: next)
                try store.setReps(set.reps, for: next)
            }
        } else {
            act { try store.addSet(to: exercise) }
        }
    }

    private func openKeypad(_ set: SessionSet, field: KeypadField) {
        commitKeypad()
        let text: String
        switch field {
        case .weight: text = set.weightKg.map { unit.format(kg: $0) } ?? ""
        case .reps: text = set.reps.map { String($0) } ?? ""
        }
        keypad = KeypadState(setID: set.id, field: field, text: text)
    }

    private func set(id: String) -> SessionSet? {
        session.exercises.lazy.flatMap(\.sets).first { $0.id == id }
    }

    /// Writes the keypad's value if it changed, and closes the keypad.
    private func commitKeypad() {
        guard let state = keypad else { return }
        keypad = nil
        write(state)
    }

    private func write(_ state: KeypadState) {
        guard state.isEdited, let set = set(id: state.setID) else { return }
        switch state.field {
        case .weight: act(setID: set.id) { try store.setWeight(state.weightKg(unit: unit), for: set) }
        case .reps: act(setID: set.id) { try store.setReps(state.reps, for: set) }
        }
    }

    private func switchKeypadField() {
        guard let state = keypad, let set = set(id: state.setID) else { return }
        write(state)
        keypad = nil
        openKeypad(set, field: state.field == .weight ? .reps : .weight)
    }

    /// Log set on the keypad: commits both cells, checks the row, closes the keypad, starts the rest.
    private func logFromKeypad() {
        guard let state = keypad, let set = set(id: state.setID) else { return }
        keypad = nil
        write(state)
        if set.weightKg == nil {
            // Still no weight: keep the keypad on it rather than log an empty set.
            openKeypad(set, field: .weight)
            return
        }
        if !set.done { toggle(set) }
    }

    private func applyDetail(_ result: SetDetailSheet.Result, to set: SessionSet) {
        switch result {
        case let .save(type, rpe, note):
            act(setID: set.id) {
                if set.type != type { try store.setType(type, for: set) }
                try store.setDetail(rpe: rpe, note: note, for: set)
            }
        case .delete:
            // Close D4 first and delete once it is gone, so no view reads the deleted set.
            detailSet = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                act { try store.deleteSet(set) }
            }
        }
    }

    private func askToLeave() {
        commitKeypad()
        confirmingLeave = true
    }

    private func saveWithoutProof() {
        notifier.cancelRestEnd()
        act { try store.finish(session, withProof: false) }
    }

    private func discard() {
        notifier.cancelRestEnd()
        act { try store.discard(session) }
    }

    private func finishForProof() {
        commitKeypad()
        guard session.doneSetCount > 0 else { return }
        notifier.cancelRestEnd()
        act { try store.finish(session, withProof: true) }
        onFinishForProof(session)
    }

    // MARK: Rest timer and resume

    private func onAppear() async {
        try? store.clearExpiredRest(session)
        scheduleRestNotification(session.restEndsAt)
        if session.startedAt < AppLaunch.date.addingTimeInterval(-1) {
            // Opened straight back into the draft after a kill or a relaunch.
            show(SessionCopy.resumed(at: session.startedAt.formatted(date: .omitted, time: .shortened)))
        }
    }

    private func waitForRestEnd() async {
        guard let end = session.restEndsAt else { return }
        let wait = end.timeIntervalSinceNow
        if wait > 0 {
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled else { return }
        }
        guard session.restEndsAt == end else { return }
        restDoneTick += 1
        AccessibilityNotification.Announcement(SessionCopy.restDone).post()
        try? store.skipRest(session)
        show(SessionCopy.restDone)
    }

    private func scheduleRestNotification(_ end: Date?) {
        guard let end, end > .now, session.isActive else {
            notifier.cancelRestEnd()
            return
        }
        let current = store.current(in: session)
        let nextSet = current?.orderedSets.first(where: { !$0.done })
        notifier.scheduleRestEnd(
            at: end,
            title: SessionCopy.restNotificationTitle,
            body: SessionCopy.restNotificationBody(exercise: current?.name, set: nextSet?.n)
        )
    }

    private func show(_ text: String) {
        toast = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if toast == text { toast = nil }
        }
    }
}
