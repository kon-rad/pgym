import CoreGraphics
import DesignSystem
import SwiftUI

/// Proof camera, card editor and share: views D6, D7, D8 and D12 (card I6). Card I7 adds the upload,
/// the server stamp (`ProofStampQueue`), D9 as the stamp's pending state on D11, D10 and D11.
///
/// The flow runs over D2 and the session stays an open draft until Stamp it is tapped, so Close on
/// the camera goes back to D2 with the session intact. Files are saved the moment they exist (photo on
/// the shutter, card on Stamp it), so after a kill D2 reopens straight into D8, or ends the session if
/// the card was already saved. Stamp it goes to D11 at once; nothing waits on the network.
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

    /// The card summary with the server's stamp: the number, the server's time and the streak replace
    /// PENDING and the phone's time (pgym-architecture.md, "Offline": "the server time then replaces it").
    static func stampedSummary(session: WorkoutSession, receipt: StampReceipt, unit: WeightUnit) -> ProofCardSummary {
        ProofCardSummary(session: session, unit: unit, stamp: receipt.stampState, now: session.endedAt ?? receipt.stampedAt)
    }

    /// Re-renders `card.jpg` from the saved photo with the options picked on D8 and the server's stamp,
    /// and saves it over the pending card. This is the card that is shared.
    @discardableResult
    static func restampCard(session: WorkoutSession, receipt: StampReceipt, unit: WeightUnit, store: ProofStore) throws -> Data {
        guard let photo = store.loadPhoto(session.id), let record = store.record(session.id) else {
            throw StampError.missingFiles
        }
        let summary = stampedSummary(session: session, receipt: receipt, unit: unit)
        let card = try ProofCardRenderer.render(photo: photo, summary: summary, options: record.options)
        let jpeg = try ProofImageIO.cardJPEG(card, size: record.options.size)
        try store.saveCard(jpeg, record: record, for: session.id)
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
            // The card was saved before a kill: the session ends now and D11 takes over.
            Color.ink.ignoresSafeArea()
        }
    }

    private func start() {
        // The Debug-only UI-test camera needs no permission (UITestCamera.swift).
        let permission: CameraPermission = UITestCamera.isOn ? .granted : .current
        let first = ProofFeature.firstStep(sessionID: session.id, store: store, permission: permission)
        if first == .saved {
            step = .saved
            onFinished(store.record(session.id)?.stampTappedAt ?? .now)
            return
        }
        if first == .editor {
            guard let saved = store.loadPhoto(session.id) else {
                step = permission == .granted ? .camera : .permission(permission)
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
        // Straight to D11: the upload and the stamp run in the queue.
        step = .saved
        onFinished(tappedAt)
    }

    private func summary(stamp: ProofStampState, now: Date = .now) -> ProofCardSummary {
        ProofCardSummary(session: session, unit: unit, stamp: stamp, now: now)
    }
}
