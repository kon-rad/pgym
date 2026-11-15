import DesignSystem
import SwiftData
import SwiftUI

/// E3 Session detail: the card, the full set list, totals, the score and tip for that day, Share again,
/// and Delete in the top menu. Text comes from the phone; only the card image may need the network.
struct SessionDetailScreen: View {
    static let viewID = "E3"

    let sessionID: String

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ProofServices.self) private var proofs
    @Environment(AppSession.self) private var account: AppSession?
    @Environment(NetworkMonitor.self) private var network: NetworkMonitor?
    @Query private var matches: [WorkoutSession]

    @State private var cardData: Data?
    @State private var cardFailed = false
    @State private var shareItem: ProofShareItem?
    @State private var confirmingDelete = false
    @State private var deleting = false
    @State private var deleteFailed = false

    init(sessionID: String) {
        self.sessionID = sessionID
        let id = sessionID
        _matches = Query(filter: #Predicate<WorkoutSession> { $0.id == id })
    }

    private var unit: WeightUnit { WeightUnit.preferred(profile: account?.profile?.units) }
    private var isOnline: Bool { network?.isOnline ?? true }

    var body: some View {
        Group {
            if let session = matches.first {
                content(session)
            } else {
                Color.ink.ignoresSafeArea()
            }
        }
        .background(Color.ink.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.\(Self.viewID)")
    }

    private func content(_ session: WorkoutSession) -> some View {
        let snapshot = SessionSnapshot(session)
        let totals = snapshot.totals
        let needsServer = session.lastSyncedAt != nil || session.status == .stamped
        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.grid(6)) {
                if snapshot.isProof { cardSection(snapshot) }

                VStack(alignment: .leading, spacing: Spacing.grid(2)) {
                    Text(session.routineName.uppercased())
                        .pgymText(.display, size: 44)
                        .foregroundStyle(Color.chalk)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .accessibilityAddTraits(.isHeader)
                    Text(meta(snapshot))
                        .pgymText(.label)
                        .foregroundStyle(Color.steel)
                        .accessibilityIdentifier("e3.meta")
                    if snapshot.status == .finished {
                        Text(ProgressCopy.unstamped)
                            .pgymText(.body, size: 15)
                            .foregroundStyle(Color.bone)
                            .accessibilityIdentifier("e3.unstamped")
                    }
                }

                HStack(spacing: Spacing.grid(2)) {
                    StatTile(label: ProgressCopy.sets, value: "\(totals.setCount)")
                    StatTile(label: ProgressCopy.totalLifted, value: unit.formatTotal(kg: totals.volumeKg), unit: unit.rawValue)
                    StatTile(label: ProgressCopy.time, value: ProofCardText.duration(snapshot.duration))
                }

                setsSection(snapshot)

                if let record = session.physique, proofs.consent.isOn {
                    ScoreBlockView(record: record)
                }

                if deleteFailed {
                    ErrorCard(message: ProgressCopy.deleteFailed, identifier: "e3.deleteError") {
                        deleteFailed = false
                        confirmingDelete = true
                    }
                }
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.top, Spacing.grid(2))
            .padding(.bottom, Spacing.grid(8))
        }
        .safeAreaInset(edge: .bottom) {
            if session.status == .stamped, session.proofNumber != nil {
                PrimaryButton(ProgressCopy.shareAgain) { share(session) }
                    .disabled(cardData == nil)
                    .padding(.horizontal, Spacing.screenMargin)
                    .padding(.bottom, Spacing.grid(2))
                    .accessibilityIdentifier("e3.share")
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(ProgressCopy.deleteSession, role: .destructive) { confirmingDelete = true }
                        .disabled(deleting || (needsServer && !isOnline))
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Color.chalk)
                        .frame(minWidth: Spacing.touchTargetMin, minHeight: Spacing.touchTargetMin)
                        .accessibilityLabel("More")
                }
                .accessibilityIdentifier("e3.menu")
            }
        }
        .confirmationDialog(
            ProgressCopy.deleteTitle(proof: session.status == .stamped ? session.proofNumber : nil),
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button(ProgressCopy.delete, role: .destructive) { Task { await delete(session) } }
            Button(ProgressCopy.cancel, role: .cancel) {}
        } message: {
            Text(ProgressCopy.deleteBody)
        }
        .sheet(item: $shareItem) { item in
            ProofShareSheet(item: item)
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
        .task(id: session.cardKey) { await loadCard(session) }
    }

    private func meta(_ snapshot: SessionSnapshot) -> String {
        let when = snapshot.stampedAt ?? snapshot.startedAt
        return ProgressCopy.meta(
            proof: snapshot.status == .stamped ? snapshot.proofNumber : nil,
            date: HistoryFormat.day(snapshot.startedAt, timezone: snapshot.timezone),
            time: snapshot.isProof ? HistoryFormat.time(when, timezone: snapshot.timezone) : nil
        )
        .uppercased()
    }

    // MARK: Card

    @ViewBuilder
    private func cardSection(_ snapshot: SessionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Spacing.grid(2)) {
            ZStack {
                Color.photo
                if let cardData, let image = ProofImageIO.decode(cardData) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .transition(.opacity)
                } else if snapshot.isPending {
                    Stamp(proofNumber: nil, line: ProgressCopy.pending)
                }
            }
            .aspectRatio(4.0 / 5.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(snapshot.proofNumber.map { "Proof card \($0)" } ?? ProgressCopy.pending)
            .accessibilityIdentifier("e3.card")
            if cardFailed {
                ErrorCard(message: ProgressCopy.cardFailed, retryTitle: ProgressCopy.retry, identifier: "e3.cardError") {
                    guard let session = matches.first else { return }
                    Task { await loadCard(session) }
                }
            }
        }
    }

    private func loadCard(_ session: WorkoutSession) async {
        cardFailed = false
        if let local = proofs.store.cardData(session.id) {
            cardData = local
            return
        }
        guard let key = session.cardKey else { return }
        do {
            let data = try await proofs.images.data(for: key)
            withAnimation(.easeOut(duration: 0.2)) { cardData = data }
        } catch {
            cardFailed = true
        }
    }

    // MARK: Sets

    private func setsSection(_ snapshot: SessionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Spacing.grid(3)) {
            SectionLabel(ProgressCopy.sets)
            ForEach(snapshot.exercises, id: \.exerciseId) { exercise in
                let logged = exercise.sets.filter(\.done)
                if !logged.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.grid(2)) {
                        Text(exercise.name)
                            .pgymText(.title)
                            .foregroundStyle(Color.chalk)
                        ForEach(logged, id: \.n) { set in
                            SetLine(set: set, unit: unit)
                        }
                    }
                    .padding(Spacing.grid(4))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.iron))
                }
            }
        }
    }

    // MARK: Actions

    private func share(_ session: WorkoutSession) {
        guard let cardData else { return }
        shareItem = try? ProofShareItem(cardJPEG: cardData, proofNumber: session.proofNumber)
    }

    private func delete(_ session: WorkoutSession) async {
        deleting = true
        defer { deleting = false }
        do {
            try await proofs.controls.deleteSession(session, context: context)
            dismiss()
        } catch {
            deleteFailed = true
        }
    }
}

/// One logged set: number, weight x reps, warm-up tag.
struct SetLine: View {
    let set: SessionSnapshot.LoggedSet
    let unit: WeightUnit

    var body: some View {
        HStack(spacing: Spacing.grid(3)) {
            Text("\(set.n)")
                .font(.pgym(.data, size: 15))
                .foregroundStyle(Color.steel)
                .frame(width: 24, alignment: .leading)
            Text(HistoryFormat.set(kg: set.weightKg, reps: set.reps, unit: unit))
                .font(.pgym(.data, size: 15))
                .foregroundStyle(set.type == .warmup ? Color.bone : Color.chalk)
            Spacer()
            if set.type == .warmup {
                Text(ProgressCopy.warmup.uppercased())
                    .pgymText(.label, size: 10)
                    .foregroundStyle(Color.steel)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The stored score for one session (E3), or the refusal in plain words. Never red, never a warning.
struct ScoreBlockView: View {
    let record: PhysiqueRecord

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.grid(2)) {
            SectionLabel(StampCopy.sectionScore)
            if record.isScored, let score = record.score {
                Text("\(score)")
                    .font(.pgym(.data, size: 24))
                    .foregroundStyle(Color.chalk)
                    .accessibilityLabel("Score \(score) out of 100")
                if let tip = record.tip {
                    SectionLabel(StampCopy.sectionTip)
                        .padding(.top, Spacing.grid(2))
                    Text(tip)
                        .pgymText(.body, size: 17)
                        .foregroundStyle(Color.chalk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(StampCopy.disclaimer)
                    .pgymText(.body, size: 13)
                    .foregroundStyle(Color.steel)
            } else {
                Text(ProgressCopy.noScoreLead)
                    .pgymText(.body, size: 17)
                    .foregroundStyle(Color.chalk)
                Text(ProgressCopy.refusal(record.refusedReason ?? ""))
                    .pgymText(.body, size: 15)
                    .foregroundStyle(Color.bone)
                Text(ProgressCopy.noScoreFooter)
                    .pgymText(.body, size: 13)
                    .foregroundStyle(Color.steel)
            }
        }
        .padding(Spacing.grid(4))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.iron))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("e3.score")
    }
}
