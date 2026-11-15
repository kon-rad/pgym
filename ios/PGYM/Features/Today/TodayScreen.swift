import DesignSystem
import SwiftData
import SwiftUI

/// C1 Today. Card I5 wires the session in: the Next up card names the routine Start session will run,
/// Start session goes straight to D2 with it (no sheet in between), and Change opens D1.
/// Live week rings, the streak stamp and the last proof are card I8.
struct TodayScreen: View {
    static let viewID = "C1"

    @Environment(\.modelContext) private var context
    @Environment(SessionSyncQueue.self) private var sync
    /// For the reminders (card I3). Optional so previews run without it.
    @Environment(AppServices.self) private var services: AppServices?
    @Query(RoutineStore.activeDescriptor) private var routines: [Routine]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @State private var picking = false
    /// The D1 choice, started once the sheet has closed so D2 never presents over a closing sheet.
    @State private var pending: PendingStart?

    private enum PendingStart {
        case routine(Routine)
        case empty
    }
    @State private var startTick = 0

    private let weekdays = ["M", "T", "W", "T", "F", "S", "S"]

    private var nextUp: Routine? {
        NextUp.routine(in: routines, lastRoutineID: NextUp.lastRoutineID(sessions))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.cardGap) {
                Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .pgymText(.label)
                    .foregroundStyle(Color.steel)

                Text("Today")
                    .pgymText(.display)
                    .foregroundStyle(Color.chalk)

                HStack(spacing: 0) {
                    ForEach(Array(weekdays.enumerated()), id: \.offset) { _, day in
                        DayRing(day: day, state: .planned)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, Spacing.grid(2))

                nextUpCard
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.top, Spacing.grid(4))
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton("Start session") { start(nextUp) }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.bottom, Spacing.grid(2))
                .accessibilityIdentifier("c1.start")
        }
        .background(Color.ink.ignoresSafeArea())
        .sensoryFeedback(.impact(weight: .medium), trigger: startTick)
        .sheet(isPresented: $picking, onDismiss: startPending) {
            PickRoutineSheet { routine in pending = routine.map(PendingStart.routine) ?? .empty }
                .presentationDetents([.medium, .large])
                .presentationBackground(Color.ink)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.\(Self.viewID)")
    }

    private var nextUpCard: some View {
        VStack(alignment: .leading, spacing: Spacing.grid(3)) {
            HStack {
                Text(SessionCopy.nextUp)
                    .pgymText(.label)
                    .foregroundStyle(Color.steel)
                Spacer()
                Button("Change") { picking = true }
                    .font(.pgym(.bodyMedium, size: 15))
                    .foregroundStyle(Color.chalk)
                    .frame(minHeight: Spacing.touchTargetMin)
                    .accessibilityIdentifier("c1.change")
            }
            if let routine = nextUp {
                Text(routine.name)
                    .pgymText(.title)
                    .foregroundStyle(Color.chalk)
                Text(SessionCopy.routineMeta(
                    exercises: routine.exercises.count,
                    lastDone: NextUp.lastDone(sessions)[routine.id].map { NextUp.dayLabel($0) }
                ))
                .pgymText(.label)
                .foregroundStyle(Color.steel)
            } else {
                Text("Proof #001 is waiting.")
                    .pgymText(.title)
                    .foregroundStyle(Color.chalk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.grid(4))
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.iron))
    }

    private func startPending() {
        guard let choice = pending else { return }
        pending = nil
        switch choice {
        case let .routine(routine): start(routine)
        case .empty: start(nil)
        }
    }

    private func start(_ routine: Routine?) {
        startTick += 1
        SessionFeature.start(routine, context: context, sync: sync)
        // A draft today counts as already trained for the reminder; it does not move the week count.
        Task { await services?.reminders.sessionLogged(at: .now, countsTowardWeek: false) }
    }
}

struct TodayScreen_Previews: PreviewProvider {
    static var previews: some View {
        let _ = FontRegistry.registerAll()
        let container = Models.makeContainer(inMemory: true)
        TodayScreen()
            .environment(SessionSyncQueue(container: container, engine: nil, uid: { nil }))
            .modelContainer(container)
            .preferredColorScheme(.dark)
    }
}
