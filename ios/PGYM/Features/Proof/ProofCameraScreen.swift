import AVFoundation
import AVKit
import DesignSystem
import PhotosUI
import SwiftUI

/// D7 Proof camera: full-screen preview, Close, the 3 second timer and flip on top; the shutter in the
/// middle of the bottom bar, library import on the left and flip on the right.
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
    @State private var flash = false
    @State private var shutterTick = 0
    @State private var countTick = 0
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var importing = false
    @State private var importError = false

    private let preferences: ProofPreferences
    /// UI tests on the simulator (Debug only): no hardware, the shutter returns a drawn picture.
    private let fakeCamera = UITestCamera.isOn
    private var isReady: Bool { fakeCamera || camera.status == .running }

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
            if !fakeCamera && camera.status != .unavailable {
                CameraPreview(session: camera.engine.session)
                    .ignoresSafeArea()
                    .opacity(camera.status == .running ? 1 : 0)
                    .animation(.easeOut(duration: reduceMotion ? 0 : 0.25), value: camera.status)
            }
            if !fakeCamera && camera.status == .starting {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(Color.steel)
                    .accessibilityHidden(true)
            }
            if !fakeCamera && camera.status == .unavailable {
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
            if importing {
                ProgressView("Opening photo…")
                    .padding(Spacing.grid(4))
                    .background(RoundedRectangle(cornerRadius: Radius.card).fill(Color.ink.opacity(0.85)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("d7.importing")
            }
            Color.white.opacity(flash ? 0.85 : 0).ignoresSafeArea().allowsHitTesting(false)
            VStack {
                topBar
                Text(ProofCopy.cameraHint)
                    .pgymText(.labelBold, size: 12)
                    .foregroundStyle(Color.chalk)
                    .padding(.horizontal, Spacing.grid(3))
                    .padding(.vertical, Spacing.grid(2))
                    .background(Capsule().fill(Color.ink.opacity(0.7)))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Spacing.grid(3))
                    .padding(.top, Spacing.grid(2))
                Spacer()
                bottomBar
            }
        }
        .statusBarHidden()
        .sensoryFeedback(.impact(weight: .heavy), trigger: shutterTick)
        .sensoryFeedback(.selection, trigger: countTick)
        .modifier(VolumeShutter { shoot() })
        .onAppear { if !fakeCamera { camera.start() } }
        .onDisappear {
            countdownTask?.cancel()
            camera.stop()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, !fakeCamera, camera.status == .unavailable { camera.start() }
        }
        .onChange(of: selectedPhoto) { _, selection in
            guard let selection else { return }
            Task {
                importing = true
                defer { importing = false; selectedPhoto = nil }
                if let data = try? await selection.loadTransferable(type: Data.self) {
                    onCapture(data)
                } else {
                    importError = true
                }
            }
        }
        .alert("Could not open photo", isPresented: $importError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Choose another image from your library.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.\(Self.viewID)")
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
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.chalk)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Color.ink.opacity(0.6)))
            }
            .disabled(importing)
            .accessibilityLabel("Choose photo from library")
            .accessibilityIdentifier("d7.library")
            Spacer()
            Button(action: shoot) {
                ZStack {
                    Circle().strokeBorder(Color.chalk, lineWidth: 5).frame(width: 84, height: 84)
                    Circle().fill(countdown == nil ? Color.chalk : Color.plate).frame(width: 66, height: 66)
                        .scaleEffect(camera.isCapturing ? 0.88 : 1)
                }
            }
            .disabled(!isReady || camera.isCapturing)
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
        guard isReady, !camera.isCapturing else { return }
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
            let captured: Data?
            if fakeCamera {
                captured = UITestCamera.photoData()
            } else {
                captured = await camera.capture()
            }
            guard let data = captured else { return }
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
