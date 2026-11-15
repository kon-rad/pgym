import DesignSystem
import LinkPresentation
import Photos
import SwiftUI
import UIKit

/// D12 Share: the iOS share sheet with the card JPEG (at the D8 size). Save to Photos is the sheet's
/// own "Save Image" action; `ProofPhotoSaver` is the same thing as a direct button. Photos access is
/// add-only: the app never reads the library.
struct ProofShareSheet: UIViewControllerRepresentable {
    static let viewID = "D12"

    let item: ProofShareItem
    /// The target the user picked, when iOS reports one (card I7 records the share event).
    var onComplete: (_ activity: String?, _ completed: Bool) -> Void = { _, _ in }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [item], applicationActivities: nil)
        controller.completionWithItemsHandler = { activity, completed, _, _ in
            onComplete(activity?.rawValue, completed)
        }
        controller.view.accessibilityIdentifier = Self.viewID
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// The card as a share item: a JPEG file with a readable name and a preview in the sheet's header.
final class ProofShareItem: NSObject, UIActivityItemSource, Identifiable {
    let fileURL: URL
    let title: String

    var id: URL { fileURL }

    /// Writes the card to a temporary file named after the proof ("pgym-proof-042.jpg").
    init(cardJPEG: Data, proofNumber: Int?, directory: URL = FileManager.default.temporaryDirectory) throws {
        let name = Self.fileName(proofNumber: proofNumber)
        let url = directory.appendingPathComponent(name)
        try cardJPEG.write(to: url, options: .atomic)
        fileURL = url
        title = proofNumber.map { "PGYM proof \(ProofCardText.proofNumber(.stamped(proofNumber: $0, stampedAt: .now, streakWeeks: 0, proofCount: 0)))" } ?? "PGYM proof"
    }

    static func fileName(proofNumber: Int?) -> String {
        guard let proofNumber else { return "pgym-proof.jpg" }
        let digits = String(max(0, proofNumber))
        return "pgym-proof-" + String(repeating: "0", count: max(0, 3 - digits.count)) + digits + ".jpg"
    }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any { fileURL }

    func activityViewController(_ controller: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        fileURL
    }

    func activityViewController(_ controller: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        title
    }

    func activityViewControllerLinkMetadata(_ controller: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = title
        metadata.originalURL = fileURL
        metadata.url = fileURL
        metadata.imageProvider = NSItemProvider(contentsOf: fileURL)
        return metadata
    }
}

/// Save to Photos with add-only access. The card JPEG carries no location, and none is set here.
enum ProofPhotoSaver {
    enum SaveError: Error, Equatable {
        case denied
        case failed
    }

    static func save(_ cardJPEG: Data) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw SaveError.denied }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: cardJPEG, options: nil)
                request.location = nil
            }
        } catch {
            throw SaveError.failed
        }
    }
}

/// Share proof and Save to Photos, used on the saved card screen now and on D11 (card I7).
/// Only a stamped card is shared (pgym-proof-card-spec.md, "Export"): until then both are disabled
/// with a line that says when they open.
struct ProofShareActions: View {
    let cardJPEG: Data?
    let proofNumber: Int?

    @State private var shareItem: ProofShareItem?
    @State private var saveMessage: String?
    @State private var savedTick = 0

    private var canShare: Bool { cardJPEG != nil && proofNumber != nil }

    var body: some View {
        VStack(spacing: Spacing.grid(2)) {
            PrimaryButton(ProofCopy.shareProof) { share() }
                .disabled(!canShare)
                .accessibilityIdentifier("d12.share")
            SecondaryButton(saveMessage == ProofCopy.savedToPhotos ? ProofCopy.savedToPhotos : ProofCopy.saveToPhotos) {
                Task { await saveToPhotos() }
            }
            .disabled(!canShare)
            .accessibilityIdentifier("d12.save")
            if !canShare {
                Text(ProofCopy.shareWaits)
                    .pgymText(.body, size: 13)
                    .foregroundStyle(Color.steel)
            } else if let saveMessage, saveMessage != ProofCopy.savedToPhotos {
                Text(saveMessage)
                    .pgymText(.body, size: 13)
                    .foregroundStyle(Color.bone)
            }
        }
        .sensoryFeedback(.success, trigger: savedTick)
        .sheet(item: $shareItem) { item in
            ProofShareSheet(item: item)
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
    }

    private func share() {
        guard canShare, let cardJPEG else { return }
        shareItem = try? ProofShareItem(cardJPEG: cardJPEG, proofNumber: proofNumber)
    }

    private func saveToPhotos() async {
        guard canShare, let cardJPEG else { return }
        do {
            try await ProofPhotoSaver.save(cardJPEG)
            saveMessage = ProofCopy.savedToPhotos
            savedTick += 1
        } catch {
            saveMessage = ProofCopy.saveToPhotosFailed
        }
    }
}
