import CoreGraphics
import DesignSystem
import SwiftUI

/// Proof camera, card editor and share: views D6, D7, D8 and D12 (card I6). The upload, the server
/// stamp and D11 are card I7.
///
/// The flow runs over D2 and the session stays an open draft until Stamp it is confirmed, so Close on
/// the camera goes back to D2 with the session intact. Files are saved the moment they exist (photo on
/// the shutter, card on Stamp it), so after a kill D2 reopens straight into D8 or the saved card.
enum ProofFeature {
    enum Step: Equatable {
        case permission(CameraPermission)
        case camera
        case editor
        case saved
    }

    /// Where the flow starts for a session, from what is already on the phone.
    static func firstStep(sessionID: String, store: ProofStore, permission: CameraPermission = .current) -> Step {
        if store.hasCard(sessionID) { return .saved }
        if store.hasPhoto(sessionID) { return .editor }
        return permission == .granted ? .camera : .permission(permission)
    }

    /// Renders the card, encodes it (no metadata) and saves it with the options next to the photo.
    static func stamp(
        photo: CGImage,
        summary: ProofCardSummary,
        options: ProofCardOptions,
        sessionID: String,
        tappedAt: Date,
        store: ProofStore
    ) throws -> Data {
        let card = try ProofCardRenderer.render(photo: photo, summary: summary, options: options)
        let jpeg = try ProofImageIO.cardJPEG(card, size: options.size)
        try store.saveCard(jpeg, record: ProofStore.CardRecord(options: options, stampTappedAt: tappedAt), for: sessionID)
        return jpeg
    }
}

/// The full-screen proof flow over D2: D6, D7, D8, then the saved card.
struct ProofFlowView: View {
    let session: WorkoutSession
    let unit: WeightUnit
    var store: ProofStore = .standard
    /// Close on D6 or D7: back to D2, session intact.
    var onClose: () -> Void
    /// Save without proof from the D6 denied state.
    var onSaveWithoutProof: () -> Void
    /// The card is saved: end the session at the moment Stamp it was tapped.
    var onFinished: (Date) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: ProofFeature.Step?
    @State private var photo: CGImage?
    @State private var processing = false

    var body: some View {
        ZStack {
            Color.ink.ignoresSafeArea()
            if let step {
                content(step)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: start)
    }

    @ViewBuilder
    private func content(_ step: ProofFeature.Step) -> some View {
        switch step {
        case let .permission(permission):
            CameraPermissionScreen(
                permission: permission,
                onAllow: { Task { await requestCamera() } },
                onNotNow: onClose,
                onSaveWithoutProof: onSaveWithoutProof
            )
            .transition(.opacity)
        case .camera:
            ProofCameraScreen(onCapture: { data in Task { await keep(data) } }, onClose: onClose)
                .overlay { if processing { Color.ink.opacity(0.4).ignoresSafeArea() } }
                .transition(.opacity)
        case .editor:
            if let photo {
                ProofCardEditorScreen(
                    photo: photo,
                    summary: summary(stamp: .pending(phoneTime: .now)),
                    onRetake: { go(.camera) },
                    onStamped: { options in try await stampIt(photo: photo, options: options) }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        case .saved:
            ProofSavedScreen(sessionID: session.id, store: store) {
                onFinished(store.record(session.id)?.stampTappedAt ?? .now)
            }
            .transition(.opacity)
        }
    }

    private func start() {
        let first = ProofFeature.firstStep(sessionID: session.id, store: store)
        if first == .editor {
            guard let saved = store.loadPhoto(session.id) else {
                step = CameraPermission.current == .granted ? .camera : .permission(CameraPermission.current)
                return
            }
            photo = saved
        }
        step = first
    }

    private func go(_ next: ProofFeature.Step) {
        withAnimation(Animation.pgymSpring(reduceMotion: reduceMotion)) { step = next }
    }

    private func requestCamera() async {
        let result = await CameraPermission.request()
        go(result == .granted ? .camera : .permission(.denied))
    }

    /// Strips the metadata, keeps an upright 2048 px copy, saves it at once and opens D8.
    private func keep(_ data: Data) async {
        processing = true
        defer { processing = false }
        let store = store
        let id = session.id
        let image: CGImage? = await Task.detached(priority: .userInitiated) {
            guard let clean = try? ProofImageIO.cleanPhoto(from: data) else { return nil }
            try? store.savePhoto(clean.jpeg, for: id)
            return clean.image
        }.value
        guard let image else { return }
        photo = image
        go(.editor)
    }

    private func stampIt(photo: CGImage, options: ProofCardOptions) async throws {
        let tappedAt = Date.now
        let summary = summary(stamp: .pending(phoneTime: tappedAt), now: tappedAt)
        let store = store
        let id = session.id
        _ = try await Task.detached(priority: .userInitiated) {
            try ProofFeature.stamp(photo: photo, summary: summary, options: options, sessionID: id, tappedAt: tappedAt, store: store)
        }.value
        go(.saved)
    }

    private func summary(stamp: ProofStampState, now: Date = .now) -> ProofCardSummary {
        ProofCardSummary(session: session, unit: unit, stamp: stamp, now: now)
    }
}

/// After Stamp it: the card as saved, waiting for the server's number and time (card I7 turns this
/// into D11). Share proof opens once the card is stamped.
struct ProofSavedScreen: View {
    let sessionID: String
    let store: ProofStore
    var onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        let data = store.cardData(sessionID)
        VStack(alignment: .leading, spacing: Spacing.grid(4)) {
            Text(ProofCopy.savedTitle)
                .pgymText(.display, size: 56)
                .foregroundStyle(Color.chalk)
                .accessibilityAddTraits(.isHeader)
            if let data, let card = ProofImageIO.decode(data) {
                Image(decorative: card, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))
                    .frame(maxWidth: .infinity, maxHeight: 420)
                    .scaleEffect(appeared || reduceMotion ? 1 : 0.94)
                    .opacity(appeared ? 1 : 0)
                    .accessibilityLabel("Proof card, proof pending, will stamp when online")
                    .accessibilityAddTraits(.isImage)
            }
            Text(ProofCopy.savedBody)
                .pgymText(.body, size: 16)
                .foregroundStyle(Color.bone)
            Text(ProofCopy.savedNote)
                .pgymText(.body, size: 13)
                .foregroundStyle(Color.steel)
            Spacer(minLength: 0)
            ProofShareActions(cardJPEG: data, proofNumber: nil)
            Button(ProofCopy.continueButton, action: onContinue)
                .font(.pgym(.bodyMedium, size: 17))
                .foregroundStyle(Color.chalk)
                .frame(maxWidth: .infinity, minHeight: Spacing.touchTargetMin)
                .accessibilityIdentifier("saved.continue")
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.vertical, Spacing.grid(3))
        .background(Color.ink.ignoresSafeArea())
        .onAppear {
            withAnimation(Animation.pgymSpring(reduceMotion: reduceMotion)) { appeared = true }
        }
    }
}
