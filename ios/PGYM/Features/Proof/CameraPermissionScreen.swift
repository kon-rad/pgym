import DesignSystem
import PhotosUI
import SwiftUI
import UIKit

/// D6 Camera permission: why the camera, shown before the one-time iOS prompt. When access is off it
/// turns into the denied state with Open Settings and Save without proof.
struct CameraPermissionScreen: View {
    static let viewID = "D6"

    let permission: CameraPermission
    var onAllow: () -> Void
    var onNotNow: () -> Void
    var onSaveWithoutProof: () -> Void
    var onImport: (Data) -> Void = { _ in }

    @Environment(\.openURL) private var openURL
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var importError = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.grid(5)) {
            HStack {
                Spacer()
                Button {
                    onNotNow()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.chalk)
                        .frame(width: Spacing.touchTargetMin, height: Spacing.touchTargetMin)
                }
                .accessibilityLabel(ProofCopy.closeCameraLabel)
                .accessibilityIdentifier("d6.close")
            }
            Spacer(minLength: Spacing.grid(4))
            Image(systemName: "camera.fill")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(Color.plate)
                .accessibilityHidden(true)
            Text(ProofCopy.permissionTitle)
                .pgymText(.display, size: 52)
                .foregroundStyle(Color.chalk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(permission == .denied ? ProofCopy.permissionDenied : ProofCopy.permissionBody)
                .pgymText(.body, size: 17)
                .foregroundStyle(Color.bone)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("d6.body")
            Spacer()
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label("Choose from Photos", systemImage: "photo.on.rectangle")
                    .font(.pgym(.bodyMedium, size: 17))
                    .foregroundStyle(Color.ink)
                    .frame(maxWidth: .infinity, minHeight: Spacing.touchTargetMin)
                    .background(RoundedRectangle(cornerRadius: Radius.card).fill(Color.plate))
            }
            .accessibilityIdentifier("d6.library")
            if permission == .denied {
                PrimaryButton(ProofCopy.openSettings) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .accessibilityIdentifier("d6.settings")
                Button(ProofCopy.saveWithoutProof, action: onSaveWithoutProof)
                    .font(.pgym(.bodyMedium, size: 17))
                    .foregroundStyle(Color.chalk)
                    .frame(maxWidth: .infinity, minHeight: Spacing.touchTargetMin)
                    .accessibilityIdentifier("d6.saveWithoutProof")
            } else {
                PrimaryButton(ProofCopy.permissionAllow, action: onAllow)
                    .accessibilityIdentifier("d6.allow")
                Button(ProofCopy.permissionNotNow, action: onNotNow)
                    .font(.pgym(.bodyMedium, size: 17))
                    .foregroundStyle(Color.chalk)
                    .frame(maxWidth: .infinity, minHeight: Spacing.touchTargetMin)
                    .accessibilityIdentifier("d6.notNow")
            }
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.bottom, Spacing.grid(4))
        .background(Color.ink.ignoresSafeArea())
        .accessibilityIdentifier(Self.viewID)
        .onChange(of: selectedPhoto) { _, selection in
            guard let selection else { return }
            Task {
                defer { selectedPhoto = nil }
                if let data = try? await selection.loadTransferable(type: Data.self) { onImport(data) }
                else { importError = true }
            }
        }
        .alert("Could not open photo", isPresented: $importError) {
            Button("OK", role: .cancel) {}
        } message: { Text("Choose another image from your library.") }
    }
}

#Preview("D6") {
    CameraPermissionScreen(permission: .notDetermined, onAllow: {}, onNotNow: {}, onSaveWithoutProof: {})
        .preferredColorScheme(.dark)
}

#Preview("D6 denied") {
    CameraPermissionScreen(permission: .denied, onAllow: {}, onNotNow: {}, onSaveWithoutProof: {})
        .preferredColorScheme(.dark)
}
