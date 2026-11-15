import Charts
import DesignSystem
import SwiftData
import SwiftUI

/// E4 Lift detail: one exercise over time. Best set, the estimated one-rep max (Epley) as a line, and
/// every session's sets newest first; sessions saved without proof are included and marked.
struct LiftDetailScreen: View {
    static let viewID = "E4"

    let exerciseId: String

    @Environment(AppSession.self) private var account: AppSession?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @State private var drawn = false

    private var unit: WeightUnit { WeightUnit.preferred(profile: account?.profile?.units) }

    var body: some View {
        let history = ProgressModel.liftHistory(exerciseId: exerciseId, in: SessionSnapshot.all(sessions))
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.grid(6)) {
                ScreenTitle(text: history.name.isEmpty ? ProgressCopy.lifts : history.name, size: 44)
                if history.entries.isEmpty {
                    Text(ProgressCopy.liftEmpty)
                        .pgymText(.body, size: 17)
                        .foregroundStyle(Color.bone)
                        .accessibilityIdentifier("e4.empty")
                } else {
                    bests(history)
                    trend(history)
                    everySession(history)
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

    private func bests(_ history: ProgressModel.LiftHistory) -> some View {
        HStack(spacing: Spacing.grid(2)) {
            StatTile(
                label: ProgressCopy.bestSet,
                value: history.best.map { "\(unit.format(kg: $0.kg)) x \($0.reps)" } ?? "-",
                unit: history.best == nil ? nil : unit.rawValue
            )
            StatTile(
                label: ProgressCopy.e1rm,
                value: history.bestE1rmKg > 0 ? unit.format(kg: history.bestE1rmKg) : "-",
                unit: history.bestE1rmKg > 0 ? unit.rawValue : nil
            )
        }
    }

    @ViewBuilder
    private func trend(_ history: ProgressModel.LiftHistory) -> some View {
        VStack(alignment: .leading, spacing: Spacing.grid(3)) {
            SectionLabel(ProgressCopy.e1rm)
            if history.points.count >= 2 {
                Chart(history.points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value(unit.label, unit.displayValue(kg: point.e1rmKg))
                    )
                    .foregroundStyle(Color.plate)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value(unit.label, unit.displayValue(kg: point.e1rmKg))
                    )
                    .foregroundStyle(Color.chalk)
                    .symbolSize(24)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 180)
                .opacity(drawn || reduceMotion ? 1 : 0)
                .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.4)) { drawn = true } }
                .accessibilityIdentifier("e4.chart")
            } else {
                Text(ProgressCopy.oneSession)
                    .pgymText(.body, size: 15)
                    .foregroundStyle(Color.bone)
                    .accessibilityIdentifier("e4.oneSession")
            }
            Text(ProgressCopy.e1rmCaption)
                .pgymText(.body, size: 13)
                .foregroundStyle(Color.steel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.grid(4))
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.iron))
    }

    private func everySession(_ history: ProgressModel.LiftHistory) -> some View {
        VStack(alignment: .leading, spacing: Spacing.grid(3)) {
            SectionLabel(ProgressCopy.everySession)
            ForEach(history.entries) { entry in
                if entry.isProof {
                    NavigationLink(value: ProgressRoute.session(entry.sessionID)) { entryCard(entry) }
                        .buttonStyle(.plain)
                } else {
                    entryCard(entry)
                }
            }
        }
    }

    private func entryCard(_ entry: ProgressModel.LiftHistory.Entry) -> some View {
        VStack(alignment: .leading, spacing: Spacing.grid(2)) {
            HStack {
                Text(HistoryFormat.day(entry.date, timezone: entry.timezone).uppercased())
                    .pgymText(.label)
                    .foregroundStyle(Color.steel)
                Spacer()
                if !entry.isProof {
                    Text(ProgressCopy.noProof.uppercased())
                        .pgymText(.label, size: 10)
                        .foregroundStyle(Color.steel)
                } else if let number = entry.proofNumber {
                    Text("#\(ProofNumber.padded(number))")
                        .font(.pgym(.data, size: 15))
                        .foregroundStyle(Color.plate)
                }
            }
            ForEach(entry.sets, id: \.n) { set in
                SetLine(set: set, unit: unit)
            }
        }
        .padding(Spacing.grid(4))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.iron))
        .accessibilityElement(children: .combine)
    }
}
