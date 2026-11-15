@preconcurrency import AVFoundation
import Foundation
import Observation
import SwiftUI
import UIKit

/// Camera permission as D6 needs it.
enum CameraPermission: Equatable {
    case notDetermined
    case granted
    case denied

    static var current: CameraPermission {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    /// Shows the one-time iOS prompt.
    static func request() async -> CameraPermission {
        await AVCaptureDevice.requestAccess(for: .video) ? .granted : .denied
    }
}

/// The proof camera (D7): AVFoundation, front and back, photo only. There is no photo-library code
/// anywhere in the app: the camera is the only way a photo gets onto a card (AGENTS.md).
///
/// All session work runs on one serial queue; the UI state is published on the main actor.
@MainActor
@Observable
final class ProofCameraController {
    enum Status: Equatable {
        case starting
        case running
        /// Camera in use by another app, missing (the simulator) or failed to start.
        case unavailable
    }

    private(set) var status: Status = .starting
    private(set) var position: AVCaptureDevice.Position
    private(set) var isCapturing = false

    let engine = CameraEngine()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(position: AVCaptureDevice.Position) {
        self.position = position
    }

    func start() {
        status = .starting
        observe()
        engine.configure(position: position) { [weak self] ok in
            Task { @MainActor in self?.status = ok ? .running : .unavailable }
        }
    }

    func stop() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        engine.stop()
    }

    func flip() {
        let next: AVCaptureDevice.Position = position == .front ? .back : .front
        position = next
        engine.configure(position: next) { [weak self] ok in
            Task { @MainActor in self?.status = ok ? .running : .unavailable }
        }
    }

    /// Takes the photo. The result is the camera's file data, unmirrored even on the front camera.
    func capture() async -> Data? {
        guard status == .running, !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }
        return await withCheckedContinuation { continuation in
            engine.capture { data in continuation.resume(returning: data) }
        }
    }

    private func observe() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: engine.session, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.status = .unavailable }
        })
        observers.append(center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: engine.session, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.status = .running }
        })
    }
}

/// The AVFoundation side. Not main-actor bound: everything happens on `queue`.
final class CameraEngine: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "pgym.proof.camera")
    private var input: AVCaptureDeviceInput?
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private var pending: [Int64: (Data?) -> Void] = [:]

    func configure(position: AVCaptureDevice.Position, done: @escaping (Bool) -> Void) {
        queue.async { [self] in
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
                  let newInput = try? AVCaptureDeviceInput(device: device)
            else {
                done(false)
                return
            }
            session.beginConfiguration()
            session.sessionPreset = .photo
            if let input { session.removeInput(input) }
            guard session.canAddInput(newInput) else {
                if let input { session.addInput(input) }
                session.commitConfiguration()
                done(false)
                return
            }
            session.addInput(newInput)
            input = newInput
            if !session.outputs.contains(output), session.canAddOutput(output) {
                session.addOutput(output)
            }
            output.maxPhotoQualityPrioritization = .quality
            if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
                // The preview is mirrored; the saved photo is not, so writing in the gym reads right.
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
            session.commitConfiguration()
            rotation = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
            if !session.isRunning { session.startRunning() }
            done(session.isRunning)
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func capture(_ completion: @escaping (Data?) -> Void) {
        queue.async { [self] in
            guard session.isRunning else {
                completion(nil)
                return
            }
            if let connection = output.connection(with: .video), let rotation {
                let angle = rotation.videoRotationAngleForHorizonLevelCapture
                if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
            }
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .balanced
            pending[settings.uniqueID] = completion
            output.capturePhoto(with: settings, delegate: self)
        }
    }
}

extension CameraEngine: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        queue.async { [self] in
            pending.removeValue(forKey: photo.resolvedSettings.uniqueID)?(data)
        }
    }
}

/// The live preview, aspect-filled. AVFoundation mirrors the front camera's preview by itself.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .clear
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
