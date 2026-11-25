import Charts
import DesignSystem
import SwiftData
import SwiftUI

enum ProgressRoute: Hashable {
    case wall
    case session(String)
    case lift(String)
}

/// E1 Progress: visible progress in one scroll. Proofs, streak and score; the last 12 weeks against
/// the goal; the proof wall preview; lifts with their bests; the score row. Everything is read from
/// the phone's store, so it works offline; the stored scores are refreshed from the server when the
/// score is on.
struct ProgressScreen: View {
    static let viewID = "E1"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppSession.self) private var account: AppSession?
    @Environment(AppServices.self) private var services: AppServices?
    @Environment(NetworkMonitor.self) private var network: NetworkMonitor?
    @Environment(SessionSyncQueue.self) private var sync: SessionSyncQueue?
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    @State private var path: [ProgressRoute] = []
    @State private var phase: LoadPhase = .loading
    @State private var appeared = false
    @State private var showingPaywall = false

    enum LoadPhase: Equatable {
        case loading, loaded, failed
    }

    private var unit: WeightUnit { WeightUnit.preferred(profile: account?.profile?.units) }
    var body: some View {
        let snapshots = SessionSnapshot.all(sessions)
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.grid(6)) {
                    ScreenTitle(text: ProgressCopy.title)
                    if phase == .loading && snapshots.isEmpty {
                        SkeletonGroup {
                            HStack(spacing: Spacing.cardGapMin) {
                                SkeletonBlock(height: 84)
                                SkeletonBlock(height: 84)
                            }
                            SkeletonBlock(height: 180)
                            SkeletonBlock(height: 120)
                        }
                    } else {
                        content(snapshots)
                    }
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.top, Spacing.grid(4))
                .padding(.bottom, Spacing.grid(8))
            }
            .background(Color.ink.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await refresh() }
            .task { await refresh() }
            .navigationDestination(for: ProgressRoute.self) { route in
                switch route {
                case .wall: ProofWallScreen()
                case let .session(id): SessionDetailScreen(sessionID: id)
                case let .lift(id): LiftDetailScreen(exerciseId: id)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("screen.\(Self.viewID)")
        }
        .tint(Color.chalk)
        .sheet(isPresented: $showingPaywall) { ProPaywallView() }
    }

    @ViewBuilder
    private func content(_ snapshots: [SessionSnapshot]) -> some View {
        let facts = StreakFacts.make(sessions: snapshots, profile: account?.profile, now: .now, timeZone: .current)
        let proofsOnly = snapshots.filter(\.isProof)
        let lifts = ProgressModel.lifts(snapshots)

        stats(facts: facts, snapshots: snapshots)
        stateLines

        if proofsOnly.isEmpty {
            Text(ProgressCopy.empty)
                .pgymText(.body, size: 17)
                .foregroundStyle(Color.bone)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("e1.empty")
        }

        if services?.purchases.canUse(.advancedProgress) ?? true {
            chartSection(snapshots)
        } else {
            Button { showingPaywall = true } label: {
                LinkRow(title: "Unlock advanced progress", caption: "Twelve-week trends and your full proof history", detail: "PRO")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("e1.pro")
        }

        if !proofsOnly.isEmpty {
            wallPreview(Array(proofsOnly.sorted { $0.startedAt > $1.startedAt }.prefix(6)))
        }

        liftsSection(lifts)

    }

    // MARK: Stats

    private func stats(facts: StreakFacts, snapshots: [SessionSnapshot]) -> some View {
        HStack(spacing: Spacing.grid(2)) {
            StatTile(label: ProgressCopy.proofs, value: "\(facts.proofCount)")
                .contentTransition(.numericText())
            StatTile(label: ProgressCopy.streak, value: "\(facts.streakWeeks)", unit: facts.streakWeeks == 1 ? "week" : "weeks")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("e1.stats")
    }

    @ViewBuilder
    private var stateLines: some View {
        if network?.isOnline == false {
            StatusLine(text: TodayCopy.offline, systemImage: "wifi.slash", identifier: "e1.offline")
        } else if let sync, sync.pendingCount > 0 {
            StatusLine(text: TodayCopy.willSync(sync.pendingCount), identifier: "e1.willSync")
        }
        if phase == .failed {
            ErrorCard(message: ProgressCopy.couldNotLoad, retryTitle: ProgressCopy.retry, identifier: "e1.error") {
                Task { await refresh() }
            }
        }
    }

    // MARK: 12-week chart

    private func goal(for week: WeekKey) -> Int {
        if let schedule = services?.reminders.state.schedule { return schedule.plan(for: week).goal }
        return account?.profile?.goalPerWeek ?? 0
    }

    private func chartSection(_ snapshots: [SessionSnapshot]) -> some View {
        let bars = ProgressModel.twelveWeeks(snapshots, now: .now, timeZone: .current, goal: goal(for:))
        let currentGoal = bars.last?.goal ?? 0
        let top = Double(max(currentGoal, bars.map(\.count).max() ?? 0, 1) + 1)
        let isEmpty = bars.allSatisfy { $0.count == 0 }
        return VStack(alignment: .leading, spacing: Spacing.grid(3)) {
            SectionLabel(ProgressCopy.last12)
            Chart {
                ForEach(bars) { bar in
                    BarMark(
                        x: .value("Week", bar.start, unit: .weekOfYear),
                        y: .value("Proofs", isEmpty && bar.isCurrent ? 0.15 : Double(bar.count))
                    )
                    .foregroundStyle(bar.isHit ? Color.plate : (bar.isCurrent ? Color.chalk : Color.rail))
                    .cornerRadius(3)
                    .accessibilityLabel(HistoryFormat.day(bar.start, timezone: TimeZone.current.identifier))
                    .accessibilityValue("\(bar.count) of \(bar.goal)")
                }
                if currentGoal > 0 {
                    RuleMark(y: .value("Goal", Double(currentGoal)))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Color.steel)
                        .annotation(position: .top, alignment: .leading) {
                            Text(ProgressCopy.goalLabel(currentGoal).uppercased())
                                .pgymText(.label, size: 10)
                                .foregroundStyle(Color.steel)
                        }
                }
            }
            .chartYScale(domain: 0...top)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(Color.hairline)
                    AxisValueLabel()
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 4)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
            .frame(height: 180)
            .scaleEffect(x: 1, y: appeared || reduceMotion ? 1 : 0.001, anchor: .bottom)
            .onAppear {
                withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.85)) { appeared = true }
            }
            .accessibilityIdentifier("e1.chart")
        }
        .padding(Spacing.grid(4))
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.iron))
    }

    // MARK: Proof wall preview

    private func wallPreview(_ latest: [SessionSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.grid(3)) {
            HStack {
                SectionLabel(ProgressCopy.proofWall)
                Spacer()
                Button {
                    if services?.purchases.canUse(.fullHistory) ?? true { path.append(.wall) }
                    else { showingPaywall = true }
                } label: {
                    Text(ProgressCopy.seeAll)
                        .font(.pgym(.bodyMedium, size: 15))
                        .foregroundStyle(Color.chalk)
                        .frame(minHeight: Spacing.touchTargetMin)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("e1.seeAll")
            }
            ProofGrid(sessions: latest)
        }
    }

    // MARK: Lifts

    @ViewBuilder
    private func liftsSection(_ lifts: [ProgressModel.Lift]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.grid(2)) {
            SectionLabel(ProgressCopy.lifts)
            if lifts.isEmpty {
                Text(ProgressCopy.emptyLifts)
                    .pgymText(.body, size: 15)
                    .foregroundStyle(Color.steel)
                    .accessibilityIdentifier("e1.liftsEmpty")
            } else {
                ForEach(lifts) { lift in
                    NavigationLink(value: ProgressRoute.lift(lift.exerciseId)) {
                        LinkRow(
                            title: lift.name,
                            caption: ProgressCopy.liftBest(
                                weight: unit.format(kg: lift.bestWeightKg),
                                unit: unit.rawValue,
                                reps: lift.bestReps
                            )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("e1.lift.\(lift.exerciseId)")
                }
            }
        }
    }

    // MARK: Refresh

    private func refresh() async {
        phase = .loaded
    }
}

/// Three columns of cards, 4:5, each opening E3. Pending cards carry the PENDING stamp.
struct ProofGrid: View {
    let sessions: [SessionSnapshot]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Spacing.grid(2)), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: Spacing.grid(2)) {
            ForEach(sessions) { session in
                NavigationLink(value: ProgressRoute.session(session.id)) {
                    ProofCardImage(
                        sessionID: session.id,
                        cardKey: session.cardKey,
                        proofNumber: session.status == .stamped ? session.proofNumber : nil
                    )
                    .aspectRatio(4.0 / 5.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("e2.tile.\(session.id)")
            }
        }
    }
}

/// E2 Proof wall: every card in a grid, newest first, under month headings.
struct ProofWallScreen: View {
    static let viewID = "E2"

    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    var body: some View {
        let snapshots = SessionSnapshot.all(sessions)
        let groups = ProgressModel.proofWall(snapshots, timeZone: .current)
        let count = groups.reduce(0) { $0 + $1.sessions.count }
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.grid(6)) {
                VStack(alignment: .leading, spacing: Spacing.grid(2)) {
                    ScreenTitle(text: ProgressCopy.proofWall)
                    Text(ProgressCopy.proofCount(count).uppercased())
                        .pgymText(.label)
                        .foregroundStyle(Color.steel)
                }
                if groups.isEmpty {
                    Text(ProgressCopy.wallEmpty)
                        .pgymText(.body, size: 17)
                        .foregroundStyle(Color.bone)
                        .accessibilityIdentifier("e2.empty")
                } else {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: Spacing.grid(3)) {
                            SectionLabel(HistoryFormat.month(group.monthStart))
                            ProofGrid(sessions: group.sessions)
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.top, Spacing.grid(2))
            .padding(.bottom, Spacing.grid(8))
        }
        .background(Color.ink.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.\(Self.viewID)")
    }
}

struct ProgressScreen_Previews: PreviewProvider {
    static var previews: some View {
        let _ = FontRegistry.registerAll()
        let container = Models.makeContainer(inMemory: true)
        let sync = SessionSyncQueue(container: container, engine: nil, uid: { nil })
        ProgressScreen()
            .environment(ProofServices.make(
                container: container, useFirebase: false, isUITest: true,
                uid: { nil }, isOnline: { true }, sessionSync: sync
            ))
            .modelContainer(container)
            .preferredColorScheme(.dark)
    }
}
