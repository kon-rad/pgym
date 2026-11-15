import AVFoundation
import AVKit
import DesignSystem
import SwiftUI

/// D7 Proof camera: full-screen preview, Close, the 3 second timer and flip on top; the shutter in the
/// middle of the bottom bar, flip again on the right, and nothing on the left. There is no library
/// button and no import, anywhere: the camera is the proof.
struct ProofCameraScreen: View {
    static let viewID = "D7"

    /// Called with the camera's file data. The caller strips metadata and saves it.
    var onCapture: (Data) -> Void
    var onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var camera: ProofCameraController
    @State private var timerOn: Bool
    @State private var countdown: Int?
    @State private var countdownTask: Task<Void, Never>?
    @State private var showHint = true
    @State private var flash = false
    @State private var shutterTick = 0
    @State private var countTick = 0

    private let preferences: ProofPreferences

    init(preferences: ProofPreferences = ProofPreferences(), onCapture: @escaping (Data) -> Void, onClose: @escaping () -> Void) {
        self.preferences = preferences
        self.onCapture = onCapture
        self.onClose = onClose
        _camera = State(initialValue: ProofCameraController(position: preferences.usesBackCamera ? .back : .front))
        _timerOn = State(initialValue: preferences.timerOn)
    }

    var body: some View {
        ZStack {
            Color.photo.ignoresSafeArea()
            if camera.status != .unavailable {
                CameraPreview(session: camera.engine.session)
                    .ignoresSafeArea()
                    .opacity(camera.status == .running ? 1 : 0)
                    .animation(.easeOut(duration: reduceMotion ? 0 : 0.25), value: camera.status)
            }
            if camera.status == .starting {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(Color.steel)
                    .accessibilityHidden(true)
            }
            if camera.status == .unavailable {
                Text(ProofCopy.cameraBusy)
                    .pgymText(.body, size: 17)
                    .foregroundStyle(Color.chalk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.grid(10))
                    .accessibilityIdentifier("d7.busy")
            }
            if let countdown {
                Text("\(countdown)")
                    .font(.custom(FontFace.jetBrainsMonoBold.postScriptName, size: 160))
                    .foregroundStyle(Color.chalk)
                    .shadow(color: .black.opacity(0.5), radius: 12)
                    .contentTransition(.numericText(countsDown: true))
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("\(countdown)")
            }
            Color.white.opacity(flash ? 0.85 : 0).ignoresSafeArea().allowsHitTesting(false)
            VStack {
                topBar
                if showHint {
                    Text(ProofCopy.cameraHint)
                        .pgymText(.labelBold, size: 12)
                        .foregroundStyle(Color.chalk)
                        .padding(.horizontal, Spacing.grid(3))
                        .padding(.vertical, Spacing.grid(2))
                        .background(Capsule().fill(Color.ink.opacity(0.7)))
                        .transition(.opacity)
                        .padding(.top, Spacing.grid(2))
                }
                Spacer()
                bottomBar
            }
        }
        .statusBarHidden()
        .sensoryFeedback(.impact(weight: .heavy), trigger: shutterTick)
        .sensoryFeedback(.selection, trigger: countTick)
        .modifier(VolumeShutter { shoot() })
        .onAppear { camera.start() }
        .onDisappear {
            countdownTask?.cancel()
            camera.stop()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, camera.status == .unavailable { camera.start() }
        }
        .task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.4)) { showHint = false }
        }
        .accessibilityIdentifier(Self.viewID)
    }

    private var topBar: some View {
        HStack {
            iconButton("xmark", label: ProofCopy.closeCameraLabel, id: "d7.close") {
                countdownTask?.cancel()
                onClose()
            }
            Spacer()
            Button {
                timerOn.toggle()
                preferences.timerOn = timerOn
            } label: {
                HStack(spacing: Spacing.grid(1)) {
                    Image(systemName: "timer")
                    Text(timerOn ? ProofCopy.timerOn : ProofCopy.timerOff)
                        .font(.pgym(.data, size: 15))
                }
                .foregroundStyle(timerOn ? Color.ink : Color.chalk)
                .padding(.horizontal, Spacing.grid(3))
                .frame(minHeight: Spacing.touchTargetMin)
                .background(Capsule().fill(timerOn ? Color.plate : Color.ink.opacity(0.6)))
            }
            .accessibilityLabel(ProofCopy.timerLabel)
            .accessibilityValue(timerOn ? ProofCopy.timerOn : ProofCopy.timerOff)
            .accessibilityIdentifier("d7.timer")
            Spacer()
            iconButton("arrow.triangle.2.circlepath.camera", label: ProofCopy.switchCameraLabel, id: "d7.flipTop") { flip() }
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.top, Spacing.grid(2))
    }

    private var bottomBar: some View {
        HStack {
            // Nothing on the left: no library button.
            Color.clear.frame(width: 56, height: 56)
            Spacer()
            Button(action: shoot) {
                ZStack {
                    Circle().strokeBorder(Color.chalk, lineWidth: 5).frame(width: 84, height: 84)
                    Circle().fill(countdown == nil ? Color.chalk : Color.plate).frame(width: 66, height: 66)
                        .scaleEffect(camera.isCapturing ? 0.88 : 1)
                }
            }
            .disabled(camera.status != .running || camera.isCapturing)
            .accessibilityLabel(timerOn ? ProofCopy.shutterTimerLabel : ProofCopy.shutterLabel)
            .accessibilityIdentifier("d7.shutter")
            Spacer()
            iconButton("arrow.triangle.2.circlepath", label: ProofCopy.switchCameraLabel, id: "d7.flip") { flip() }
                .frame(width: 56, height: 56)
        }
        .padding(.horizontal, Spacing.grid(8))
        .padding(.bottom, Spacing.grid(6))
        .animation(Animation.pgymSpring(reduceMotion: reduceMotion), value: camera.isCapturing)
    }

    private func iconButton(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.chalk)
                .frame(width: Spacing.touchTargetMin, height: Spacing.touchTargetMin)
                .background(Circle().fill(Color.ink.opacity(0.6)))
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private func flip() {
        camera.flip()
        preferences.usesBackCamera = camera.position == .back
    }

    /// The shutter (or a volume button). With the timer on: 3, 2, 1, then the photo.
    private func shoot() {
        guard camera.status == .running, !camera.isCapturing else { return }
        if countdown != nil {
            // A second tap during the countdown cancels it.
            countdownTask?.cancel()
            withAnimation { countdown = nil }
            return
        }
        guard timerOn else {
            take()
            return
        }
        countdownTask = Task { @MainActor in
            for n in stride(from: 3, through: 1, by: -1) {
                withAnimation(Animation.pgymSpring(reduceMotion: reduceMotion)) { countdown = n }
                countTick += 1
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
            }
            withAnimation { countdown = nil }
            take()
        }
    }

    private func take() {
        Task { @MainActor in
            shutterTick += 1
            if !reduceMotion {
                flash = true
                withAnimation(.easeOut(duration: 0.25)) { flash = false }
            }
            guard let data = await camera.capture() else { return }
            onCapture(data)
        }
    }
}

/// The volume buttons as a shutter (capture events, iOS 18 and later; earlier versions keep the
/// on-screen shutter only).
private struct VolumeShutter: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onCameraCaptureEvent { event in
                if event.phase == .ended { action() }
            }
        } else {
            content
        }
    }
}
