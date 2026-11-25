import Charts
import DesignSystem
import SwiftData
import SwiftUI

/// E5 Score history: the scores over time with their tips, the disclaimer, and the off switch. Turning
/// it off asks first, then deletes every score (on the phone at once, then on the server) and goes back
/// to E1. Refused sessions are gaps in the line, never zeros; nothing here is red.
struct ScoreHistoryScreen: View {
    static let viewID = "E5"

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ProofServices.self) private var proofs
    @Environment(AppSession.self) private var account: AppSession?
    @Environment(NetworkMonitor.self) private var network: NetworkMonitor?
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    @State private var phase: ProgressScreen.LoadPhase = .loading
    @State private var confirmingOff = false
    @State private var offering = false
    @State private var working = false
    @State private var offTick = 0
    @State private var selectedDimension: PhysiqueDimension?
    @State private var showingMetricInfo = false

    private var isOnline: Bool { network?.isOnline ?? true }
    private var isAdult: Bool {
        PhysiqueRules.isAdult(birthYear: account?.profile?.birthYear, currentYear: AgePolicy.currentYear())
    }

    var body: some View {
        let points = ProgressModel.scoreHistory(SessionSnapshot.all(sessions))
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.grid(6)) {
                ScreenTitle(text: ProgressCopy.scoreTitle, size: 44)
                if !isAdult {
                    Text(ProgressCopy.under18)
                        .pgymText(.body, size: 17)
                        .foregroundStyle(Color.bone)
                        .accessibilityIdentifier("e5.under18")
                } else if !proofs.consent.isOn {
                    offState
                } else {
                    Text(ProgressCopy.scoreBody)
                        .pgymText(.body, size: 17)
                        .foregroundStyle(Color.bone)
                        .fixedSize(horizontal: false, vertical: true)
                    onState(points)
                    toggleSection(points)
                }
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.top, Spacing.grid(2))
            .padding(.bottom, Spacing.grid(8))
        }
        .background(Color.ink.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: offTick)
        .task { await refresh() }
        .confirmationDialog(ProgressCopy.confirmTitle, isPresented: $confirmingOff, titleVisibility: .visible) {
            Button(ProgressCopy.confirmOff, role: .destructive) { Task { await turnOff() } }
            Button(ProgressCopy.keepOn, role: .cancel) {}
        } message: {
            Text(ProgressCopy.confirmBody(points.filter { $0.score != nil }.count))
        }
        .sheet(isPresented: $offering) {
            PhysiqueConsentScreen(
                isAdult: isAdult,
                onTurnOn: {
                    offering = false
                    Task {
                        await proofs.consent.turnOn()
                        await refresh()
                    }
                },
                onNotNow: {
                    proofs.consent.markOfferShown()
                    offering = false
                }
            )
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingMetricInfo) {
            PhysiqueMetricInfoScreen()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.\(Self.viewID)")
    }

    // MARK: States

    private var offState: some View {
        VStack(alignment: .leading, spacing: Spacing.grid(4)) {
            Text(ProgressCopy.offState)
                .pgymText(.body, size: 17)
                .foregroundStyle(Color.bone)
                .accessibilityIdentifier("e5.off")
            SecondaryButton(ProgressCopy.turnOn) { offering = true }
                .disabled(!isOnline)
                .accessibilityIdentifier("e5.turnOn")
            if !isOnline {
                StatusLine(text: ProgressCopy.needsConnection, systemImage: "wifi.slash", identifier: "e5.offline")
            }
        }
    }

    @ViewBuilder
    private func onState(_ points: [ProgressModel.ScorePoint]) -> some View {
        if phase == .loading && points.isEmpty {
            SkeletonGroup {
                SkeletonBlock(height: 180)
                SkeletonBlock(height: 64)
                SkeletonBlock(height: 64)
            }
        } else {
            Button("What do the six scores mean?") { showingMetricInfo = true }
                .foregroundStyle(Color.plate)
            if phase == .failed {
                ErrorCard(message: ProgressCopy.scoresFailed, retryTitle: ProgressCopy.retry, identifier: "e5.error") {
                    Task { await refresh() }
                }
            }
            if points.contains(where: { $0.score != nil }) {
                if points.contains(where: { !$0.dimensions.isEmpty }) {
                    Picker("Metric", selection: $selectedDimension) {
                        Text("Overall fitness and muscle").tag(PhysiqueDimension?.none)
                        ForEach(PhysiqueDimension.allCases) { dimension in
                            Text(dimension.title).tag(Optional(dimension))
                        }
                    }
                    .tint(Color.chalk)
                    .pickerStyle(.menu)
                    metricBests(points)
                }
                chart(points)
                rows(points)
                Text(StampCopy.disclaimer)
                    .pgymText(.body, size: 13)
                    .foregroundStyle(Color.steel)
            } else if phase != .failed {
                Text(ProgressCopy.firstScoreSoon)
                    .pgymText(.body, size: 17)
                    .foregroundStyle(Color.bone)
                    .accessibilityIdentifier("e5.empty")
            }
        }
    }

    /// Scores as one plain Plate line; a refusal starts a new segment so it shows as a gap.
    private func chart(_ points: [ProgressModel.ScorePoint]) -> some View {
        let segments = Self.segments(points).filter { selectedDimension == nil || $0.point.dimensions[selectedDimension!.rawValue] != nil }
        let rolling = Self.rollingAverage(segments, dimension: selectedDimension)
        return VStack(alignment: .leading, spacing: Spacing.grid(3)) {
            SectionLabel("Scores over time · 7-day average")
            Chart {
                ForEach(segments, id: \.point.sessionID) { item in
                    PointMark(x: .value("Date", item.point.date), y: .value("Score", selectedDimension.flatMap { item.point.dimensions[$0.rawValue] } ?? item.point.score ?? 0))
                        .foregroundStyle(Color.chalk)
                        .symbolSize(30)
                }
                ForEach(rolling, id: \.id) { item in
                    LineMark(x: .value("Date", item.date), y: .value("7-day average", item.value))
                        .foregroundStyle(Color.plate)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
            }
            .chartYScale(domain: 0...100)
            .frame(height: 180)
            .accessibilityIdentifier("e5.chart")
        }
        .padding(Spacing.grid(4))
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.iron))
    }

    struct RollingScore {
        var id: String
        var date: Date
        var value: Double
    }

    static func rollingAverage(_ items: [Segmented], dimension: PhysiqueDimension?) -> [RollingScore] {
        items.map { current in
            let start = current.point.date.addingTimeInterval(-7 * 24 * 60 * 60)
            let values = items.filter { $0.point.date >= start && $0.point.date <= current.point.date }
                .compactMap { item -> Int? in
                    dimension.flatMap { item.point.dimensions[$0.rawValue] } ?? item.point.score
                }
            return RollingScore(id: current.point.sessionID, date: current.point.date,
                                value: Double(values.reduce(0, +)) / Double(max(1, values.count)))
        }
    }

    private func metricBests(_ points: [ProgressModel.ScorePoint]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.grid(2)) {
            SectionLabel("Personal records")
            if let best = points.compactMap(\.score).max() {
                Text("Overall best · \(best)/100").foregroundStyle(Color.chalk)
            }
            ForEach(PhysiqueDimension.allCases) { dimension in
                if let best = points.compactMap({ $0.dimensions[dimension.rawValue] }).max() {
                    Text("\(dimension.title) · \(best)/100")
                        .foregroundStyle(Color.bone)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .pgymText(.body, size: 15)
        .padding(Spacing.grid(4))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card).fill(Color.iron))
    }

    struct Segmented {
        var point: ProgressModel.ScorePoint
        var segment: Int
    }

    /// Scored points with a segment number that moves on after every refusal.
    static func segments(_ points: [ProgressModel.ScorePoint]) -> [Segmented] {
        var segment = 0
        var out: [Segmented] = []
        for point in points {
            if point.score == nil {
                segment += 1
            } else {
                out.append(Segmented(point: point, segment: segment))
            }
        }
        return out
    }

    private func rows(_ points: [ProgressModel.ScorePoint]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.grid(2)) {
            ForEach(points.reversed()) { point in
                VStack(alignment: .leading, spacing: Spacing.grid(1)) {
                    if let score = point.score {
                        Text(ProgressCopy.scoreRow(date: HistoryFormat.day(point.date, timezone: TimeZone.current.identifier), score: score).uppercased())
                            .font(.pgym(.data, size: 15))
                            .foregroundStyle(Color.chalk)
                        if let tip = point.tip {
                            Text(tip)
                                .pgymText(.body, size: 15)
                                .foregroundStyle(Color.bone)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Text(HistoryFormat.day(point.date, timezone: TimeZone.current.identifier).uppercased())
                            .pgymText(.label)
                            .foregroundStyle(Color.steel)
                        Text("\(ProgressCopy.noScoreLead) \(ProgressCopy.refusal(point.refusedReason ?? ""))")
                            .pgymText(.body, size: 15)
                            .foregroundStyle(Color.steel)
                    }
                }
                .padding(Spacing.grid(4))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.iron))
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func toggleSection(_ points: [ProgressModel.ScorePoint]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.grid(2)) {
            Toggle(isOn: Binding(
                get: { proofs.consent.isOn },
                set: { on in if !on { confirmingOff = true } }
            )) {
                Text(ProgressCopy.toggle)
                    .font(.pgym(.bodyMedium, size: 17))
                    .foregroundStyle(Color.chalk)
            }
            .tint(Color.plate)
            .disabled(!isOnline || working)
            .accessibilityIdentifier("e5.toggle")
            Text(isOnline ? ProgressCopy.toggleCaption : ProgressCopy.needsConnection)
                .pgymText(.body, size: 13)
                .foregroundStyle(Color.steel)
        }
        .padding(Spacing.grid(4))
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.iron))
    }

    // MARK: Actions

    private func refresh() async {
        guard proofs.consent.isOn, let uid = account?.user?.uid else {
            phase = .loaded
            return
        }
        do {
            try await proofs.controls.refreshScores(uid: uid, context: context)
            phase = .loaded
        } catch {
            phase = isOnline ? .failed : .loaded
        }
    }

    private func turnOff() async {
        working = true
        defer { working = false }
        await proofs.controls.turnOffAnalysis(context: context)
        offTick += 1
        dismiss()
    }
}

struct PhysiqueMetricInfoScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.grid(4)) {
                    Text("Photo scores are estimates, not health measurements. Use similar light, distance, clothing, and pose when comparing photos.")
                        .pgymText(.body, size: 17)
                        .foregroundStyle(Color.bone)
                    ForEach(PhysiqueDimension.allCases) { dimension in
                        VStack(alignment: .leading, spacing: Spacing.grid(1)) {
                            Text(dimension.title).pgymText(.title).foregroundStyle(Color.chalk)
                            Text(dimension.explanation).pgymText(.body, size: 15).foregroundStyle(Color.bone)
                        }
                    }
                }
                .padding(Spacing.screenMargin)
            }
            .background(Color.ink)
            .navigationTitle("About the six scores")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}
