import DesignSystem
import SwiftData
import SwiftUI

/// D11 Session complete: the reward. The stamp and the server's time, the headline, the week rings,
/// sets, total lifted and time, new bests, the private score and tip when on, the consent row once,
/// Share proof and Done.
///
/// D9 Stamping lives here as the stamp's pending state (pgym-flow-spec.md, "D9 Stamping": merged into
/// D11), so Stamp it never waits on the network: everything already known shows at once, and the number
/// lands with the stamp animation, a haptic and the count-up when the server answers.
struct SessionCompleteScreen: View {
    static let viewID = "D11"

    let sessionID: String
    var onDone: () -> Void

    @Environment(ProofServices.self) private var services
    @Environment(AppServices.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(AppSession.self) private var account: AppSession?
    @Environment(NetworkMonitor.self) private var network: NetworkMonitor?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query private var matches: [WorkoutSession]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var allSessions: [WorkoutSession]

    @State private var physique: PhysiqueRecord?
    @State private var previousScore: Int?
    @State private var slow = false
    @State private var cardJPEG: Data?
    @State private var consentSheet = false
    @State private var appeared = false
    @State private var overlay: ProofCardRenderer.ShareMode = .workout
    @State private var scoreCardJPEG: Data?
    @State private var analyzing = false
    @State private var analysisError: String?
    @State private var showingPaywall = false

    init(sessionID: String, onDone: @escaping () -> Void) {
        self.sessionID = sessionID
        self.onDone = onDone
        _matches = Query(filter: #Predicate<WorkoutSession> { $0.id == sessionID })
    }

    private var session: WorkoutSession? { matches.first }
    private var phase: StampPhase? { services.queue.phase(for: sessionID) }
    private var unit: WeightUnit { WeightUnit.preferred(profile: account?.profile?.units) }
    private var uid: String? { account?.user?.uid }
    private var isOnline: Bool { network?.isOnline ?? true }
    private var selectedCardJPEG: Data? { overlay == .scores ? scoreCardJPEG : cardJPEG }
    private var isAdult: Bool {
        PhysiqueRules.isAdult(birthYear: account?.profile?.birthYear, currentYear: AgePolicy.currentYear())
    }

    var body: some View {
        ZStack {
            Color.ink.ignoresSafeArea()
            if let session {
                content(session, model: model(session))
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.\(Self.viewID)")
        .task(id: listenKey) { await listen() }
        .task(id: workingKey) { await watchSlow() }
        .onAppear {
            loadCard()
            withAnimation(Animation.pgymSpring(reduceMotion: reduceMotion)) { appeared = true }
        }
        .onChange(of: session?.proofNumber) { _, _ in loadCard() }
        .sheet(isPresented: $consentSheet) {
            PhysiqueConsentScreen(
                isAdult: isAdult,
                onTurnOn: {
                    consentSheet = false
                    Task {
                        await services.consent.turnOn()
                        if let session { await analyze(session) }
                    }
                },
                onNotNow: {
                    services.consent.markOfferShown()
                    consentSheet = false
                }
            )
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingPaywall) { ProPaywallView() }
    }

    // MARK: Model

    private func model(_ session: WorkoutSession) -> SessionCompleteModel {
        let calendar = PlanCalendar(timeZone: TimeZone(identifier: session.timezone) ?? .current)
        let week = session.weekKey
        var done = Set<Weekday>()
        for other in allSessions where other.weekKey == week && (other.status == .stamped || other.awaitsStamp) {
            done.insert(calendar.weekday(for: other.startedAt))
        }
        done.insert(calendar.weekday(for: session.startedAt))
        return SessionCompleteModel(SessionCompleteModel.Inputs(
            session: session,
            unit: unit,
            phase: phase,
            workingFor: slow ? StampCopy.slowAfter : 0,
            consentOn: services.consent.isOn,
            isAdult: isAdult,
            offerShown: services.consent.offerShown,
            physique: physique,
            previousScore: previousScore,
            doneDays: done,
            gymDays: Set(account?.profile?.gymDays ?? []),
            today: calendar.weekday(for: .now)
        ))
    }

    // MARK: Layout

    private func content(_ session: WorkoutSession, model: SessionCompleteModel) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.grid(6)) {
                    StampHeader(area: model.stampArea, onRetry: { services.queue.retry(sessionID: sessionID) })
                        .padding(.top, Spacing.grid(6))
                    Text(model.headline.uppercased())
                        .pgymText(.display, size: 48)
                        .foregroundStyle(Color.chalk)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .contentTransition(.opacity)
                        .animation(Animation.pgymSpring(reduceMotion: reduceMotion), value: model.headline)
                    cardPreview(session)
                    weekSection(model)
                    statsRow(model)
                    if !model.newBests.isEmpty { bestsSection(model) }
                    if let record = session.physique, services.consent.isOn { ScoreBlockView(record: record) }
                    if model.canShare { analysisSection(session) }
                    if model.showsConsentOffer { consentRow }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.bottom, Spacing.grid(6))
                .opacity(appeared ? 1 : 0)
            }
            VStack(spacing: Spacing.grid(1)) {
                if model.canShare {
                    ProofCardOverlayPicker(selection: Binding(get: { overlay }, set: { chooseOverlay($0, session: session) }), scoreAvailable: session.physique?.hasSevenScores == true)
                        .padding(.bottom, Spacing.grid(2))
                }
                ProofShareActions(cardJPEG: model.canShare ? selectedCardJPEG : nil, proofNumber: session.proofNumber)
                Button(StampCopy.done, action: onDone)
                    .font(.pgym(.bodyMedium, size: 17))
                    .foregroundStyle(Color.chalk)
                    .frame(maxWidth: .infinity, minHeight: Spacing.touchTargetMin)
                    .accessibilityIdentifier("d11.done")
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.vertical, Spacing.grid(3))
            .background(Color.ink)
        }
    }

    @ViewBuilder
    private func cardPreview(_ session: WorkoutSession) -> some View {
        Group {
            if let selectedCardJPEG, let image = ProofImageIO.decode(selectedCardJPEG) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if let key = session.cardKey {
                SignedPhotoView(key: key, cache: services.images)
                    .aspectRatio(4.0 / 5.0, contentMode: .fit)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: 360)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(session.proofNumber.map { "Proof card, proof \($0)" } ?? "Proof card, proof pending, will stamp when online")
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("d11.card")
    }

    private func weekSection(_ model: SessionCompleteModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.grid(3)) {
            sectionLabel(StampCopy.sectionThisWeek)
            WeekRings(
                days: model.weekRings,
                count: model.weekRings.filter { $0.status == .done }.count,
                goal: account?.profile?.goalPerWeek,
                identifier: "d11.rings"
            )
            .animation(Animation.pgymSpring(reduceMotion: reduceMotion), value: model.weekRings.map { $0.status })
        }
    }

    /// Three tiles across; stacked at the accessibility sizes so no number is shrunk or cut.
    private func statsRow(_ model: SessionCompleteModel) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Spacing.grid(2)))
            : AnyLayout(HStackLayout(spacing: Spacing.grid(2)))
        return layout {
            ForEach(model.stats, id: \.label) { stat in
                StatTile(label: stat.label.uppercased(), value: stat.value, unit: stat.unit?.uppercased())
            }
        }
        .accessibilityIdentifier("d11.stats")
    }

    @Environment(\.dynamicTypeSize) private var typeSize

    private func bestsSection(_ model: SessionCompleteModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.grid(2)) {
            sectionLabel(StampCopy.sectionNewBests)
            ForEach(model.newBests, id: \.self) { line in
                HStack(spacing: Spacing.grid(2)) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Color.plate)
                        .accessibilityHidden(true)
                    Text(line)
                        .pgymText(.bodyMedium, size: 17)
                        .foregroundStyle(Color.chalk)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var consentRow: some View {
        Button {
            consentSheet = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.grid(1)) {
                    Text(StampCopy.consentRowTitle.uppercased())
                        .pgymText(.label)
                        .foregroundStyle(Color.steel)
                    Text(StampCopy.consentRowAction)
                        .pgymText(.bodyMedium, size: 17)
                        .foregroundStyle(Color.chalk)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Color.steel)
                    .accessibilityHidden(true)
            }
            .padding(Spacing.grid(4))
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.iron))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("d11.consentRow")
        // Shown once: seeing it counts (pgym-flow-spec.md D10, "Entry").
        .onAppear { services.consent.markOfferShown() }
    }

    private func analysisSection(_ session: WorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: Spacing.grid(2)) {
            Button {
                if !app.purchases.isPro { showingPaywall = true }
                else if !services.consent.isOn { consentSheet = true }
                else { Task { await analyze(session) } }
            } label: {
                HStack {
                    Image(systemName: "sparkles")
                    Text(session.physique?.isScored == true ? "Regenerate AI analysis" : "Get AI analysis and coaching")
                    Spacer()
                    if !app.purchases.isPro { Text("PRO") }
                }
                .pgymText(.bodyMedium, size: 17)
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity, minHeight: Spacing.touchTargetMin)
                .padding(.horizontal, Spacing.grid(4))
                .background(RoundedRectangle(cornerRadius: Radius.card).fill(Color.plate))
            }
            .disabled(analyzing || !isOnline)
            .accessibilityIdentifier("d11.analyze")
            if analyzing {
                HStack { Spacer(); ProgressView("Analyzing photo"); Spacer() }
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("d11.analyzing")
            }
            if let analysisError {
                Text(analysisError).pgymText(.body, size: 15).foregroundStyle(Color.bone)
            }
        }
    }

    private func chooseOverlay(_ mode: ProofCardRenderer.ShareMode, session: WorkoutSession) {
        if mode == .scores {
            scoreCardJPEG = PhysiqueScoreCard.jpeg(session: session, store: services.store, unit: unit)
            guard scoreCardJPEG != nil else {
                analysisError = "The original photo is needed to make a score card. Your workout card is still available."
                return
            }
        }
        overlay = mode
    }

    private func analyze(_ session: WorkoutSession) async {
        guard app.purchases.isPro else { showingPaywall = true; return }
        guard services.consent.isOn else { consentSheet = true; return }
        guard let photo = services.store.loadPhoto(session.id),
              let jpeg = try? ProofImageIO.analysisJPEG(photo) else {
            analysisError = "The original photo is needed for analysis. Your workout card is still available."
            return
        }
        analyzing = true
        analysisError = nil
        defer { analyzing = false }
        do {
            let result = try await services.api.analyzePhysiquePhoto(jpeg: jpeg, sessionID: session.id)
            session.applyPhysique(result)
            try context.save()
            chooseOverlay(.scores, session: session)
        } catch {
            analysisError = PhysiqueAnalysisMessage.failure(error)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .pgymText(.label)
            .foregroundStyle(Color.steel)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Effects

    private var stamped: Bool { session?.proofNumber != nil }

    /// Listen for the score only when it can be shown: consent on, adult, stamped with the score on.
    private var listenKey: String {
        let requested = session?.physiqueRequested == true
        return "\(sessionID)|\(stamped)|\(requested && services.consent.isOn && isAdult)"
    }

    private var workingKey: String {
        switch phase {
        case .uploading, .stamping: "working"
        default: "idle"
        }
    }

    private func listen() async {
        guard let uid, let session, let stampedAt = session.stampedAt, session.physiqueRequested == true,
              services.consent.isOn, isAdult
        else { return }
        let observation = services.physique.observe(uid: uid, sessionID: sessionID) { record in
            withAnimation(Animation.pgymSpring(reduceMotion: reduceMotion)) { physique = record }
        }
        previousScore = await services.physique.previousScore(uid: uid, before: stampedAt, excluding: sessionID)
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
        }
        observation.cancel()
    }

    private func watchSlow() async {
        slow = false
        guard workingKey == "working" else { return }
        try? await Task.sleep(nanoseconds: UInt64(StampCopy.slowAfter * 1_000_000_000))
        if !Task.isCancelled { slow = true }
    }

    private func loadCard() {
        cardJPEG = services.store.cardData(sessionID)
    }
}

/// The stamp at the top of D11, and D9's states while there is no number yet.
private struct StampHeader: View {
    let area: SessionCompleteModel.StampArea
    var onRetry: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = false
    @State private var shownNumber = 0
    @State private var stampTick = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.grid(3)) {
            switch area {
            case let .stamped(number, timestamp):
                // One element: "Proof 42, stamped Sun 15 Nov 2026 18:47" (pgym-flow-spec.md).
                VStack(alignment: .leading, spacing: Spacing.grid(3)) {
                    Stamp(proofNumber: max(1, shownNumber), line: nil, rotation: Rotation.proofCardStamp)
                        .scaleEffect(landed || reduceMotion ? 1 : 1.8)
                        .opacity(landed ? 1 : 0)
                    Text(timestamp)
                        .font(.pgym(.data, size: 13))
                        .foregroundStyle(Color.bone)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(StampCopy.a11yStamped(number: number, timestamp: timestamp))
                .accessibilityIdentifier("d11.stamp")
                .onAppear { land(number) }
            case let .working(progress, slow):
                Stamp(proofNumber: nil, line: nil, rotation: Rotation.proofCardStamp)
                    .opacity(0.6)
                    .accessibilityLabel(StampCopy.a11yPending)
                    .accessibilityIdentifier("d9.stamp")
                Text(slow ? StampCopy.stampingSlow : StampCopy.stampingBody)
                    .pgymText(.body, size: 15)
                    .foregroundStyle(Color.bone)
                    .fixedSize(horizontal: false, vertical: true)
                ProgressBar(fraction: progress)
            case .offline:
                Stamp(proofNumber: nil, line: "PENDING", rotation: Rotation.proofCardStamp)
                    .accessibilityLabel(StampCopy.a11yPending)
                    .accessibilityIdentifier("d9.stamp")
                Text(StampCopy.offlineBody)
                    .pgymText(.body, size: 15)
                    .foregroundStyle(Color.bone)
                    .fixedSize(horizontal: false, vertical: true)
                Text(StampCopy.offlineNote)
                    .pgymText(.body, size: 13)
                    .foregroundStyle(Color.steel)
            case .failed:
                Stamp(proofNumber: nil, line: "PENDING", rotation: Rotation.proofCardStamp)
                    .accessibilityLabel(StampCopy.a11yPending)
                    .accessibilityIdentifier("d9.stamp")
                Text(StampCopy.errorBody)
                    .pgymText(.body, size: 15)
                    .foregroundStyle(Color.bone)
                SecondaryButton(StampCopy.tryAgain, action: onRetry)
                    .accessibilityIdentifier("d9.retry")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("D9")
        .sensoryFeedback(.impact(weight: .heavy), trigger: stampTick)
    }

    /// The big moment: the stamp drops in, the haptic hits, the number counts up to the server's
    /// (the one animation allowed past 600 ms, AGENTS.md). Reduce Motion: a fade and the final number.
    private func land(_ number: Int) {
        guard !landed else { return }
        if reduceMotion {
            shownNumber = number
            withAnimation(.easeOut(duration: 0.25)) { landed = true }
            stampTick += 1
            return
        }
        shownNumber = max(1, number - 12)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { landed = true }
        stampTick += 1
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            while shownNumber < number {
                shownNumber += 1
                try? await Task.sleep(nanoseconds: 45_000_000)
            }
        }
    }
}

/// A thin Plate bar on Rail. Indeterminate (no fraction yet) is a short bar, never a spinner.
private struct ProgressBar: View {
    let fraction: Double?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.rail)
                Capsule()
                    .fill(Color.plate)
                    .frame(width: proxy.size.width * CGFloat(min(1, max(0.06, fraction ?? 0.06))))
                    .animation(.easeOut(duration: 0.3), value: fraction)
            }
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityLabel(StampCopy.stampingTitle)
        .accessibilityValue(fraction.map { "\(Int(($0 * 100).rounded())) percent" } ?? "")
    }
}

/// The private score block: score, trend, tip, disclaimer; "Scoring your photo." until it arrives.
private struct ScoreSection: View {
    let block: SessionCompleteModel.ScoreBlock

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.grid(2)) {
            Text(StampCopy.sectionScore.uppercased())
                .pgymText(.label)
                .foregroundStyle(Color.steel)
                .accessibilityAddTraits(.isHeader)
            switch block {
            case .pending:
                RoundedRectangle(cornerRadius: Radius.setCell, style: .continuous)
                    .fill(Color.iron)
                    .frame(width: 96, height: 56)
                    .accessibilityHidden(true)
                Text(StampCopy.scorePending)
                    .pgymText(.body, size: 15)
                    .foregroundStyle(Color.bone)
            case let .scored(score, trend, tip):
                Text("\(score)")
                    .font(.pgym(.data, size: 56))
                    .foregroundStyle(Color.chalk)
                    .contentTransition(.numericText())
                    .accessibilityLabel("Score \(score) out of 100")
                Text(trend)
                    .pgymText(.body, size: 13)
                    .foregroundStyle(Color.bone)
                if let tip {
                    Text(StampCopy.sectionTip.uppercased())
                        .pgymText(.label)
                        .foregroundStyle(Color.steel)
                        .padding(.top, Spacing.grid(2))
                    Text(tip)
                        .pgymText(.body, size: 17)
                        .foregroundStyle(Color.chalk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(StampCopy.disclaimer)
                .pgymText(.body, size: 13)
                .foregroundStyle(Color.steel)
        }
        .padding(Spacing.grid(4))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.iron))
        .accessibilityIdentifier("d11.score")
    }
}

/// An image behind a signed S3 link, through `SignedImageCache`. Shows the Photo colour until it loads;
/// no spinner.
struct SignedPhotoView: View {
    let key: String
    let cache: SignedImageCache

    @State private var image: CGImage?

    var body: some View {
        ZStack {
            Color.photo
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            }
        }
        .task(id: key) {
            guard let data = try? await cache.data(for: key) else { return }
            withAnimation(.easeOut(duration: 0.2)) { image = ProofImageIO.decode(data) }
        }
    }
}
