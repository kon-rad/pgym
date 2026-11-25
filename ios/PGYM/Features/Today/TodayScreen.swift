import DesignSystem
import SwiftData
import SwiftUI

/// C1 Today, with its states C2 rest day, C3 week done and C4 first run (pgym-flow-spec.md: one view
/// with variants keeps the week row and the streak in one place). Which state shows is `TodayModel`'s
/// decision, from the phone's sessions, so Today works fully offline.
///
/// Start session goes straight to D2 with the Next up routine (card I5); Change opens D1. The last
/// proof row opens E3.
struct TodayScreen: View {
    static let viewID = "C1"

    @Environment(\.modelContext) private var context
    @Environment(SessionSyncQueue.self) private var sync
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// For the reminders (card I3) and the plan in force. Optional so previews run without it.
    @Environment(AppServices.self) private var services: AppServices?
    @Environment(AppSession.self) private var account: AppSession?
    @Environment(NetworkMonitor.self) private var network: NetworkMonitor?
    @Query(RoutineStore.activeDescriptor) private var routines: [Routine]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @State private var picking = false
    /// The D1 choice, started once the sheet has closed so D2 never presents over a closing sheet.
    @State private var pending: PendingStart?
    @State private var startTick = 0
    @State private var path: [TodayRoute] = []
    @State private var showingPaywall = false

    private enum PendingStart {
        case routine(Routine)
        case empty
    }

    private var nextUp: Routine? {
        NextUp.routine(in: routines, lastRoutineID: NextUp.lastRoutineID(sessions))
    }

    private var snapshots: [SessionSnapshot] { SessionSnapshot.all(sessions) }

    private var model: TodayModel {
        TodayModel(TodayModel.Inputs(
            sessions: snapshots,
            plan: services?.reminders.currentPlan,
            profile: account?.profile,
            now: .now,
            timeZone: .current
        ))
    }

    /// Fresh sign-in on a new phone: the profile is still on its way. Start session works anyway.
    private var isLoading: Bool { account != nil && account?.profile == nil }

    var body: some View {
        let model = model
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.cardGap) {
                    header(model)
                    if isLoading {
                        SkeletonGroup {
                            SkeletonBlock(height: 60)
                            SkeletonBlock(height: 150)
                        }
                    } else {
                        weekSection(model)
                        stateCard(model)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        aiCoachingCard
                        syncLine
                        if let last = model.lastProof { lastProofRow(last) }
                    }
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.top, Spacing.grid(4))
                .padding(.bottom, Spacing.grid(6))
                .animation(Animation.pgymSpring(reduceMotion: reduceMotion), value: model.state)
            }
            .safeAreaInset(edge: .bottom) { bottomAction(model) }
            .background(Color.ink.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: TodayRoute.self) { route in
                switch route {
                case let .session(id): SessionDetailScreen(sessionID: id)
                case .scores: ScoreHistoryScreen()
                }
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: startTick)
            .sheet(isPresented: $picking, onDismiss: startPending) {
                PickRoutineSheet { routine in pending = routine.map(PendingStart.routine) ?? .empty }
                    .presentationDetents([.medium, .large])
                    .presentationBackground(Color.ink)
            }
            .sheet(isPresented: $showingPaywall) { ProPaywallView() }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("screen.\(Self.viewID)")
        }
        .tint(Color.chalk)
    }

    // MARK: Header

    private var aiCoachingCard: some View {
        Button {
            if services?.purchases.isPro == true { path.append(.scores) }
            else { showingPaywall = true }
        } label: {
            VStack(alignment: .leading, spacing: Spacing.grid(2)) {
                HStack {
                    Image(systemName: "sparkles")
                    Text("AI ANALYSIS + COACHING")
                    Spacer()
                    if services?.purchases.isPro != true { Text("PRO") }
                }
                .pgymText(.labelBold)
                Text("Seven photo scores. Personal bests. Coaching for your next session.")
                    .pgymText(.body, size: 17)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Color.ink)
            .padding(Spacing.grid(4))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.card).fill(Color.plate))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("c1.aiCoaching")
    }

    @Environment(\.dynamicTypeSize) private var typeSize

    /// A row that stacks at the accessibility text sizes, so nothing is squeezed off the side.
    private func rowLayout<Content: View>(alignment: VerticalAlignment, @ViewBuilder content: () -> Content) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.grid(2)))
            : AnyLayout(HStackLayout(alignment: alignment))
        return layout(content)
    }

    private func header(_ model: TodayModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.grid(3)) {
            rowLayout(alignment: .center) {
                Text(Date.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).uppercased())
                    .pgymText(.label)
                    .foregroundStyle(Color.steel)
                    .accessibilityLabel(Date.now.formatted(date: .complete, time: .omitted))
                if !typeSize.isAccessibilitySize { Spacer() }
                if let text = model.streakStampText {
                    streakStamp(text)
                }
            }
            if case .firstRun = model.state {
                Text(TodayCopy.firstRunTitle.uppercased())
                    .pgymText(.display, size: 56)
                    .foregroundStyle(Color.chalk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("c4.title")
            } else {
                Text("Today".uppercased())
                    .pgymText(.display)
                    .foregroundStyle(Color.chalk)
                    .accessibilityAddTraits(.isHeader)
            }
        }
    }

    /// The streak stamp: Plate outline, tilted, the only rotated thing on the screen.
    private func streakStamp(_ text: String) -> some View {
        Text(text.uppercased())
            .pgymText(.labelBold, size: 11)
            .foregroundStyle(Color.plate)
            .padding(.horizontal, Spacing.grid(3))
            .padding(.vertical, Spacing.grid(2))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.stamp, style: .continuous)
                    .strokeBorder(Color.plate, lineWidth: Stroke.stamp)
            )
            .rotationEffect(.degrees(-Rotation.proofCardStamp))
            .fixedSize()
            .accessibilityLabel("Streak: \(text)")
            .accessibilityIdentifier("c1.streak")
    }

    // MARK: Week

    private func weekSection(_ model: TodayModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.grid(3)) {
            rowLayout(alignment: .firstTextBaseline) {
                SectionLabel(TodayCopy.thisWeek)
                if !typeSize.isAccessibilitySize { Spacer() }
                if model.weekRow.goal > 0 {
                    Text(model.freshStart
                         ? TodayCopy.newWeek(goal: model.weekRow.goal)
                         : TodayCopy.weekCount(model.weekRow.count, of: model.weekRow.goal).uppercased())
                        .font(.pgym(.data, size: 15))
                        .foregroundStyle(model.weekRow.isGoalReached ? Color.plate : Color.chalk)
                        .contentTransition(.numericText())
                        .accessibilityIdentifier("c1.count")
                }
            }
            WeekRings(
                days: model.weekRow.days.map { (day: $0.weekday, status: $0.status) },
                count: model.weekRow.count,
                goal: model.weekRow.goal,
                identifier: "c1.rings"
            )
            if model.streak.passWeeks > 0 {
                Text(TodayCopy.passWeeks(model.streak.passWeeks))
                    .pgymText(.label)
                    .foregroundStyle(Color.steel)
            }
        }
        .padding(.vertical, Spacing.grid(2))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("c1.week")
    }

    // MARK: State card

    @ViewBuilder
    private func stateCard(_ model: TodayModel) -> some View {
        switch model.state {
        case .firstRun:
            card(identifier: "c4.card") {
                Text(TodayCopy.firstRunBody)
                    .pgymText(.body, size: 17)
                    .foregroundStyle(Color.bone)
                    .fixedSize(horizontal: false, vertical: true)
                nextUpBlock
            }
        case .gymDay:
            card(identifier: "c1.card") {
                nextUpBlock
                if let line = model.lockLine {
                    Text(line)
                        .pgymText(.body, size: 15)
                        .foregroundStyle(Color.chalk)
                        .accessibilityIdentifier("c1.lockLine")
                }
            }
        case let .restDay(nextDay):
            card(identifier: "c2.card") {
                Text(TodayCopy.restDay.uppercased())
                    .pgymText(.display, size: 44)
                    .foregroundStyle(Color.chalk)
                if let nextDay {
                    Text(TodayCopy.nextSession(routine: nextUp?.name, day: nextDay.full))
                        .pgymText(.body, size: 17)
                        .foregroundStyle(Color.bone)
                }
            }
        case let .weekDone(week):
            card(identifier: "c3.card") {
                Text(TodayCopy.weekLocked(week).uppercased())
                    .pgymText(.display, size: 44)
                    .foregroundStyle(Color.plate)
                    .fixedSize(horizontal: false, vertical: true)
                Text(TodayCopy.weekDoneBody(goal: model.weekRow.goal))
                    .pgymText(.body, size: 17)
                    .foregroundStyle(Color.chalk)
                Text(TodayCopy.extras)
                    .pgymText(.body, size: 15)
                    .foregroundStyle(Color.bone)
                    .fixedSize(horizontal: false, vertical: true)
                SecondaryButton(TodayCopy.bonus) { start(nextUp) }
                    .accessibilityIdentifier("c3.bonus")
            }
        }
    }

    private func card<Content: View>(identifier: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.grid(3)) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.grid(4))
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.iron))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(identifier)
    }

    private var nextUpBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.grid(2)) {
            HStack {
                SectionLabel(TodayCopy.nextUp)
                Spacer()
                Button(TodayCopy.change) { picking = true }
                    .font(.pgym(.bodyMedium, size: 15))
                    .foregroundStyle(Color.chalk)
                    .frame(minHeight: Spacing.touchTargetMin)
                    .accessibilityIdentifier("c1.change")
            }
            Text(nextUp?.name ?? SessionCopy.emptySessionName)
                .pgymText(.title)
                .foregroundStyle(Color.chalk)
            if let routine = nextUp {
                Text(TodayCopy.cardMeta(
                    exercises: routine.exercises.count,
                    lastDuration: TodayModel.lastDuration(of: routine.id, in: snapshots).map(TodayModel.durationLabel)
                ))
                .pgymText(.body, size: 15)
                .foregroundStyle(Color.steel)
            } else {
                Text(SessionCopy.emptySessionCaption)
                    .pgymText(.body, size: 15)
                    .foregroundStyle(Color.steel)
            }
        }
    }

    // MARK: Sync and last proof

    @ViewBuilder
    private var syncLine: some View {
        if network?.isOnline == false {
            StatusLine(text: TodayCopy.offline, systemImage: "wifi.slash", identifier: "c1.offline")
        } else if sync.lastAttemptFailed && sync.pendingCount > 0 {
            ErrorCard(message: TodayCopy.syncFailed, identifier: "c1.syncError") { sync.requestSync() }
        } else if sync.pendingCount > 0 {
            StatusLine(text: TodayCopy.willSync(sync.pendingCount), identifier: "c1.willSync")
        }
    }

    private func lastProofRow(_ last: TodayModel.LastProof) -> some View {
        NavigationLink(value: TodayRoute.session(last.sessionID)) {
            HStack(spacing: Spacing.grid(3)) {
                ProofCardImage(sessionID: last.sessionID, cardKey: last.cardKey, proofNumber: last.proofNumber)
                    .frame(width: 56, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))
                VStack(alignment: .leading, spacing: Spacing.grid(1)) {
                    SectionLabel(TodayCopy.lastProof)
                    Text(lastProofText(last))
                        .font(.pgym(.data, size: 15))
                        .foregroundStyle(Color.chalk)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.steel)
                    .accessibilityHidden(true)
            }
            .padding(Spacing.grid(3))
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.iron))
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("c1.lastProof")
    }

    private func lastProofText(_ last: TodayModel.LastProof) -> String {
        let day = NextUp.dayLabel(last.startedAt)
        guard let number = last.proofNumber else { return TodayCopy.lastProofPending(day: day) }
        return TodayCopy.lastProofMeta(proof: number, day: day)
    }

    // MARK: Bottom action

    /// One Plate button per screen, in thumb reach. C2 has a quiet link instead; C3 offers the bonus
    /// session inside the card, so nothing sits here.
    @ViewBuilder
    private func bottomAction(_ model: TodayModel) -> some View {
        switch model.state {
        case .gymDay, .firstRun:
            PrimaryButton(TodayCopy.startSession) { start(nextUp) }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.bottom, Spacing.grid(2))
                .accessibilityIdentifier("c1.start")
        case .restDay:
            Button(TodayCopy.trainAnyway) { start(nextUp) }
                .font(.pgym(.bodyMedium, size: 17))
                .foregroundStyle(Color.bone)
                .underline()
                .frame(maxWidth: .infinity, minHeight: Spacing.touchTargetMin)
                .padding(.bottom, Spacing.grid(2))
                .accessibilityIdentifier("c2.trainAnyway")
        case .weekDone:
            EmptyView()
        }
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

enum TodayRoute: Hashable {
    case session(String)
    case scores
}

struct TodayScreen_Previews: PreviewProvider {
    static var previews: some View {
        let _ = FontRegistry.registerAll()
        let container = Models.makeContainer(inMemory: true)
        TodayScreen()
            .environment(SessionSyncQueue(container: container, engine: nil, uid: { nil }))
            .environment(ProofServices.make(
                container: container, useFirebase: false, isUITest: true,
                uid: { nil }, isOnline: { true },
                sessionSync: SessionSyncQueue(container: container, engine: nil, uid: { nil })
            ))
            .modelContainer(container)
            .preferredColorScheme(.dark)
    }
}
