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
    @Environment(AppServices.self) private var services
    @Environment(AppSession.self) private var account: AppSession?
    @Environment(NetworkMonitor.self) private var network: NetworkMonitor?
    @Query private var matches: [WorkoutSession]

    @State private var cardData: Data?
    @State private var cardFailed = false
    @State private var shareItem: ProofShareItem?
    @State private var confirmingDelete = false
    @State private var deleting = false
    @State private var deleteFailed = false
    @State private var showingPaywall = false
    @State private var showingConsent = false
    @State private var analyzing = false
    @State private var analysisError: String?
    @State private var overlay: ProofCardRenderer.ShareMode = .workout
    @State private var scoreCardData: Data?

    init(sessionID: String) {
        self.sessionID = sessionID
        let id = sessionID
        _matches = Query(filter: #Predicate<WorkoutSession> { $0.id == id })
    }

    private var unit: WeightUnit { WeightUnit.preferred(profile: account?.profile?.units) }
    private var isOnline: Bool { network?.isOnline ?? true }
    private var selectedCardData: Data? { overlay == .scores ? scoreCardData : cardData }

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
                if session.status == .stamped {
                    Button {
                        if !services.purchases.isPro { showingPaywall = true }
                        else if !proofs.consent.isOn { showingConsent = true }
                        else { Task { await analyze(session) } }
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                            Text(session.physique?.isScored == true ? "Regenerate AI analysis and coaching" : "Get AI analysis and coaching")
                            Spacer()
                            if !services.purchases.isPro { Text("PRO") }
                        }
                        .pgymText(.body, size: 17)
                        .foregroundStyle(Color.ink)
                        .padding(Spacing.grid(4))
                        .background(RoundedRectangle(cornerRadius: Radius.card).fill(Color.plate))
                    }
                    .disabled(analyzing || !isOnline)
                    .accessibilityIdentifier("e3.analyze")
                    if analyzing {
                        HStack(spacing: Spacing.grid(2)) {
                            ProgressView()
                            Text("Reading your photo and preparing seven scores…")
                                .pgymText(.body, size: 15)
                        }
                            .frame(maxWidth: .infinity)
                            .padding(Spacing.grid(4))
                            .background(RoundedRectangle(cornerRadius: Radius.card).fill(Color.iron))
                            .accessibilityIdentifier("e3.analyzing")
                    }
                    if let analysisError {
                        Label(analysisError, systemImage: "info.circle")
                            .pgymText(.body, size: 15)
                            .foregroundStyle(Color.bone)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Spacing.grid(4))
                            .background(RoundedRectangle(cornerRadius: Radius.card).fill(Color.iron))
                    }
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
                VStack(spacing: Spacing.grid(2)) {
                    ProofCardOverlayPicker(selection: Binding(get: { overlay }, set: { chooseOverlay($0, session: session) }), scoreAvailable: session.physique?.hasSevenScores == true)
                    Button { share(session) } label: {
                        Text(ProgressCopy.shareAgain.uppercased())
                            .pgymText(.labelBold)
                            .foregroundStyle(Color.ink)
                            .frame(maxWidth: .infinity, minHeight: Spacing.touchTargetMin)
                            .background(RoundedRectangle(cornerRadius: Radius.button).fill(Color.plate))
                    }
                    .disabled(selectedCardData == nil)
                    .accessibilityIdentifier("e3.share")
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.bottom, Spacing.grid(2))
                .background(Color.ink)
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
        .sheet(isPresented: $showingPaywall) { ProPaywallView() }
        .sheet(isPresented: $showingConsent) {
            PhysiqueConsentScreen(isAdult: PhysiqueRules.isAdult(birthYear: account?.profile?.birthYear, currentYear: AgePolicy.currentYear()), onTurnOn: {
                showingConsent = false
                Task {
                    await proofs.consent.turnOn()
                    if let session = matches.first { await analyze(session) }
                }
            }, onNotNow: { showingConsent = false })
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
                if let selectedCardData, let image = ProofImageIO.decode(selectedCardData) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .transition(.opacity)
                } else if snapshot.isPending {
                    Stamp(proofNumber: nil, line: ProgressCopy.pending)
                } else {
                    Text(ProgressCopy.cardUnavailable)
                        .pgymText(.body, size: 15)
                        .foregroundStyle(Color.bone)
                        .multilineTextAlignment(.center)
                        .padding(Spacing.grid(5))
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
        // Cards are local-only. A missing card is an expected unavailable state, never a network fetch.
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

    private func chooseOverlay(_ mode: ProofCardRenderer.ShareMode, session: WorkoutSession) {
        if mode == .scores {
            scoreCardData = PhysiqueScoreCard.jpeg(session: session, store: proofs.store, unit: unit)
            guard scoreCardData != nil else {
            analysisError = "The original photo is needed to make a score card. Your workout card is still available."
            return
            }
        }
        overlay = mode
    }

    private func share(_ session: WorkoutSession) {
        guard let selectedCardData else { return }
        shareItem = try? ProofShareItem(cardJPEG: selectedCardData, proofNumber: session.proofNumber)
    }

    private func analyze(_ session: WorkoutSession) async {
        guard services.purchases.isPro else { showingPaywall = true; return }
        guard proofs.consent.isOn else { showingConsent = true; return }
        if proofs.consent.needsUpload {
            await proofs.consent.flush()
            guard !proofs.consent.needsUpload else {
                analysisError = "Your photo-analysis consent is still syncing. Connect to the internet and try again."
                return
            }
        }
        guard let image = proofs.store.loadPhoto(session.id),
              let jpeg = try? ProofImageIO.analysisJPEG(image) else {
            analysisError = "The original photo is needed for analysis. This card cannot be used as a substitute."
            return
        }
        analyzing = true
        analysisError = nil
        defer { analyzing = false }
        do {
            let result = try await proofs.api.analyzePhysiquePhoto(jpeg: jpeg, sessionID: session.id)
            session.applyPhysique(result)
            try context.save()
            chooseOverlay(.scores, session: session)
        } catch {
            analysisError = PhysiqueAnalysisMessage.failure(error)
        }
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
    @State private var showingInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.grid(2)) {
            SectionLabel(StampCopy.sectionScore)
            Button("What do these scores mean?") { showingInfo = true }
                .pgymText(.body, size: 14)
                .foregroundStyle(Color.plate)
            if record.isScored, let score = record.score {
                Text("\(score)")
                    .font(.pgym(.data, size: 24))
                    .foregroundStyle(Color.chalk)
                    .accessibilityLabel("Score \(score) out of 100")
                ForEach(PhysiqueDimension.allCases) { dimension in
                    if let value = record.dimensions[dimension.rawValue] {
                        HStack(alignment: .firstTextBaseline) {
                            Text(dimension.title)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: Spacing.grid(1))
                            Text("\(value)/100")
                                .font(.pgym(.data, size: 15))
                        }
                        .pgymText(.body, size: 14)
                        .foregroundStyle(Color.bone)
                    }
                }
                if let tip = record.tip {
                    SectionLabel(StampCopy.sectionTip)
                        .padding(.top, Spacing.grid(2))
                    Text(tip)
                        .pgymText(.body, size: 17)
                        .foregroundStyle(Color.chalk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let encouragement = record.encouragement {
                    Text(encouragement)
                        .pgymText(.body, size: 15)
                        .foregroundStyle(Color.plate)
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
        .sheet(isPresented: $showingInfo) { PhysiqueMetricInfoScreen() }
    }
}
