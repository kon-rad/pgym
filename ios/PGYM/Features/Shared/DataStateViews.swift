import DesignSystem
import SwiftUI
import UIKit

/// Shared pieces for the data views of card I8: section labels, the loading skeleton, the small
/// "will sync" line and the error card (pgym-app-views.md, "States every data view needs").

/// A mono, upper-case Steel label over a section.
struct SectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .pgymText(.label)
            .foregroundStyle(Color.steel)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Anton display title, left-aligned, as on every tab root.
struct ScreenTitle: View {
    let text: String
    var size: CGFloat = 56

    var body: some View {
        Text(text.uppercased())
            .pgymText(.display, size: size)
            .foregroundStyle(Color.chalk)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Loading: an Iron block that breathes slowly. Never a spinner; no breathing with Reduce Motion.
struct SkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat
    var radius: CGFloat = Radius.card

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.iron)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .opacity(dim ? 0.55 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { dim = true }
            }
            .accessibilityHidden(true)
    }
}

/// A group of skeleton blocks read as one "Loading" element.
struct SkeletonGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.cardGap) { content }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(TodayCopy.loading)
            .accessibilityIdentifier("state.loading")
    }
}

/// The small Steel line for offline and "will sync". Never a blocking screen.
struct StatusLine: View {
    let text: String
    var systemImage = "icloud.and.arrow.up"
    var identifier = "state.sync"

    var body: some View {
        HStack(spacing: Spacing.grid(2)) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .accessibilityHidden(true)
            Text(text)
                .pgymText(.body, size: 13)
        }
        .foregroundStyle(Color.steel)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

/// Error: one plain sentence and a retry, Chalk on Iron, never Plate and never red.
struct ErrorCard: View {
    let message: String
    var retryTitle: String = TodayCopy.tryAgain
    var identifier = "state.error"
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.grid(3)) {
            Text(message)
                .pgymText(.body, size: 15)
                .foregroundStyle(Color.chalk)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(retryTitle, action: retry)
                .font(.pgym(.bodyMedium, size: 15))
                .foregroundStyle(Color.chalk)
                .padding(.horizontal, Spacing.grid(3))
                .frame(minHeight: Spacing.touchTargetMin)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                        .strokeBorder(Color.rail, lineWidth: Stroke.border)
                )
                .accessibilityIdentifier("\(identifier).retry")
        }
        .padding(Spacing.grid(4))
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.iron))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

/// A navigation row on Iron: title, an optional mono detail, a chevron.
struct LinkRow: View {
    let title: String
    var detail: String? = nil
    var caption: String? = nil

    var body: some View {
        HStack(spacing: Spacing.grid(3)) {
            VStack(alignment: .leading, spacing: Spacing.grid(1)) {
                Text(title)
                    .font(.pgym(.bodyMedium, size: 17))
                    .foregroundStyle(Color.chalk)
                if let caption {
                    Text(caption)
                        .pgymText(.body, size: 13)
                        .foregroundStyle(Color.steel)
                }
            }
            Spacer(minLength: Spacing.grid(2))
            if let detail {
                Text(detail)
                    .font(.pgym(.data, size: 15))
                    .foregroundStyle(Color.steel)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.steel)
                .accessibilityHidden(true)
        }
        .frame(minHeight: Spacing.touchTargetMin)
        .padding(.horizontal, Spacing.grid(4))
        .padding(.vertical, Spacing.grid(2))
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.iron))
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A proof card image: the phone's own copy first (no network), then the signed S3 link, else the
/// Photo colour with the stamp text. No spinner.
struct ProofCardImage: View {
    let sessionID: String
    let cardKey: String?
    let proofNumber: Int?

    @Environment(ProofServices.self) private var proofs
    @State private var local: CGImage?
    @State private var checked = false

    var body: some View {
        ZStack {
            if let local {
                Image(decorative: local, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if checked, let cardKey {
                SignedPhotoView(key: cardKey, cache: proofs.images)
            } else {
                Color.photo
            }
            if local == nil && (cardKey == nil || proofNumber == nil) && checked {
                Text(proofNumber == nil ? ProgressCopy.pending.uppercased() : Stamp.title(for: proofNumber))
                    .pgymText(.labelBold, size: 10)
                    .foregroundStyle(Color.plate)
                    .padding(Spacing.grid(1))
            }
        }
        .clipped()
        .task(id: sessionID) {
            if let data = proofs.store.cardData(sessionID) { local = ProofImageIO.decode(data) }
            checked = true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(proofNumber.map { "Proof \($0)" } ?? ProgressCopy.pending)
    }
}

/// The iOS share sheet for a file (F6 export).
struct FileShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Formats for the data views. Every date is shown in the zone the session happened in.
enum HistoryFormat {
    static func day(_ date: Date, timezone: String) -> String {
        var style = Date.FormatStyle.dateTime.day().month(.abbreviated).year()
        style.timeZone = TimeZone(identifier: timezone) ?? .current
        return date.formatted(style)
    }

    static func time(_ date: Date, timezone: String) -> String {
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.timeZone = TimeZone(identifier: timezone) ?? .current
        return date.formatted(style)
    }

    static func month(_ date: Date, timeZone: TimeZone = .current) -> String {
        var style = Date.FormatStyle.dateTime.month(.wide).year()
        style.timeZone = timeZone
        return date.formatted(style).uppercased()
    }

    /// "80 kg x 8", in the user's unit.
    static func set(kg: Double?, reps: Int?, unit: WeightUnit) -> String {
        let weight = kg.map { unit.format(kg: $0) } ?? "-"
        return "\(weight) \(unit.rawValue) x \(reps.map(String.init) ?? "-")"
    }
}
