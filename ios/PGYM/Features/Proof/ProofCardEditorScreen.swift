import CoreGraphics
import DesignSystem
import SwiftUI

/// D8 Proof card editor: the card preview at the chosen size, four filters as labelled thumbnails,
/// the stat row (pick 3), 4:5 or 9:16, Retake and Stamp it. The preview is the real renderer's output,
/// so what the user sees is exactly the file that is saved and shared.
struct ProofCardEditorScreen: View {
    static let viewID = "D8"

    let photo: CGImage
    /// The session as the card shows it, with the stamp PENDING and the phone's time.
    let summary: ProofCardSummary
    var onRetake: () -> Void
    /// Called after the card is rendered, saved and ready for the upload queue (card I7).
    var onStamped: (ProofCardOptions) async throws -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var options: ProofCardOptions
    @State private var preview: CGImage?
    @State private var thumbnails: [ProofFilter: CGImage] = [:]
    @State private var stamping = false
    @State private var error: String?
    @State private var pickTick = 0
    @State private var stampTick = 0

    private let preferences: ProofPreferences

    init(
        photo: CGImage,
        summary: ProofCardSummary,
        preferences: ProofPreferences = ProofPreferences(),
        onRetake: @escaping () -> Void,
        onStamped: @escaping (ProofCardOptions) async throws -> Void
    ) {
        self.photo = photo
        self.summary = summary
        self.preferences = preferences
        self.onRetake = onRetake
        self.onStamped = onStamped
        _options = State(initialValue: preferences.cardOptions)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(ProofCopy.editorTitle)
                .pgymText(.display, size: 44)
                .foregroundStyle(Color.chalk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.top, Spacing.grid(3))
                .accessibilityAddTraits(.isHeader)
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.grid(6)) {
                    cardPreview
                    filterPicker
                    statPicker
                    sizePicker
                    if let error {
                        Text(error)
                            .pgymText(.body, size: 15)
                            .foregroundStyle(Color.chalk)
                            .accessibilityIdentifier("d8.error")
                    }
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.vertical, Spacing.grid(4))
            }
            footer
        }
        .background(Color.ink.ignoresSafeArea())
        .sensoryFeedback(.selection, trigger: pickTick)
        .sensoryFeedback(.success, trigger: stampTick)
        .task(id: options) { await renderPreview() }
        .task { await renderThumbnails() }
        .onChange(of: options) { _, new in preferences.cardOptions = new }
        .accessibilityIdentifier(Self.viewID)
    }

    // MARK: Sections

    private var cardPreview: some View {
        let size = options.size.pixelSize
        return ZStack {
            Rectangle().fill(Color.photo)
            if let preview {
                Image(decorative: preview, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .transition(.opacity)
            }
        }
        .aspectRatio(size.width / size.height, contentMode: .fit)
        .frame(maxWidth: options.size == .story ? 300 : .infinity)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
        .animation(Animation.pgymSpring(reduceMotion: reduceMotion), value: options.size)
        .accessibilityElement()
        .accessibilityLabel(ProofCopy.cardLabel(summary, options: options))
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("d8.preview")
    }

    private var filterPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.grid(2)) {
            sectionLabel(ProofCopy.sectionFilter)
            HStack(spacing: Spacing.grid(3)) {
                ForEach(ProofFilter.allCases, id: \.self) { filter in
                    let selected = options.filter == filter
                    Button {
                        guard !selected else { return }
                        options.filter = filter
                        pickTick += 1
                    } label: {
                        VStack(spacing: Spacing.grid(1)) {
                            ZStack {
                                Rectangle().fill(Color.photo)
                                if let thumb = thumbnails[filter] {
                                    Image(decorative: thumb, scale: 1).resizable().transition(.opacity)
                                }
                            }
                            .aspectRatio(4 / 5, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.photo, style: .continuous)
                                    .strokeBorder(selected ? Color.plate : Color.rail, lineWidth: selected ? 3 : 1)
                            )
                            Text(filter.label)
                                .pgymText(.labelBold, size: 11)
                                .foregroundStyle(selected ? Color.chalk : Color.steel)
                        }
                        .scaleEffect(selected ? 1.04 : 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(filter.label) filter")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("d8.filter.\(filter.rawValue)")
                }
            }
            .animation(Animation.pgymSpring(reduceMotion: reduceMotion), value: options.filter)
        }
    }

    private var statPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.grid(2)) {
            HStack {
                sectionLabel(ProofCopy.sectionOnCard)
                Spacer()
                Text(ProofCopy.pickThree)
                    .pgymText(.label, size: 11)
                    .foregroundStyle(Color.steel)
            }
            FlowChips(items: ProofCardStat.allCases, isOn: { options.stats.contains($0) }, label: \.toggleLabel) { stat in
                guard !options.stats.contains(stat) else { return }
                options.stats.pick(stat)
                pickTick += 1
            }
            .accessibilityIdentifier("d8.stats")
        }
    }

    private var sizePicker: some View {
        VStack(alignment: .leading, spacing: Spacing.grid(2)) {
            sectionLabel(ProofCopy.sectionSize)
            HStack(spacing: Spacing.grid(2)) {
                ForEach(ProofCardSize.allCases, id: \.self) { size in
                    let selected = options.size == size
                    Button {
                        guard !selected else { return }
                        options.size = size
                        pickTick += 1
                    } label: {
                        Text(size.label)
                            .font(.pgym(.data, size: 15))
                            .foregroundStyle(selected ? Color.ink : Color.chalk)
                            .frame(maxWidth: .infinity, minHeight: Spacing.touchTargetMin)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                                    .fill(selected ? Color.plate : Color.iron)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                                    .strokeBorder(selected ? Color.clear : Color.rail, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("d8.size.\(size.rawValue)")
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: Spacing.grid(2)) {
            HStack(spacing: Spacing.grid(3)) {
                SecondaryButton(ProofCopy.retake, action: onRetake)
                    .frame(maxWidth: 140)
                    .accessibilityHint(ProofCopy.retakeHint)
                    .accessibilityIdentifier("d8.retake")
                Button {
                    Task { await stamp() }
                } label: {
                    if stamping {
                        Image(systemName: "checkmark.seal.fill").accessibilityLabel(ProofCopy.stampIt)
                    } else {
                        Text(ProofCopy.stampIt)
                    }
                }
                .buttonStyle(.pgymPrimary)
                .disabled(stamping || preview == nil)
                .accessibilityIdentifier("d8.stamp")
            }
            Text(ProofCopy.retakeHint)
                .pgymText(.body, size: 13)
                .foregroundStyle(Color.steel)
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.top, Spacing.grid(3))
        .padding(.bottom, Spacing.grid(2))
        .background(Color.ink)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .pgymText(.labelBold, size: 11)
            .foregroundStyle(Color.steel)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Rendering

    private func renderPreview() async {
        let photo = photo
        let summary = summary
        let options = options
        let image = await Task.detached(priority: .userInitiated) {
            try? ProofCardRenderer.render(photo: photo, summary: summary, options: options)
        }.value
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.2)) {
            preview = image
            error = image == nil ? ProofCopy.renderFailed : nil
        }
    }

    /// Thumbnails fill in one by one over the Photo colour; grain is skipped at this size.
    private func renderThumbnails() async {
        let photo = photo
        for filter in ProofFilter.allCases {
            let thumb = await Task.detached(priority: .utility) {
                try? ProofCardRenderer.filteredPhoto(photo, filter: filter, size: CGSize(width: 160, height: 200), grain: false)
            }.value
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.2)) { thumbnails[filter] = thumb }
        }
    }

    private func stamp() async {
        stamping = true
        defer { stamping = false }
        do {
            try await onStamped(options)
            stampTick += 1
        } catch {
            self.error = ProofCopy.renderFailed
        }
    }
}

/// Chips that wrap onto a second line at large text sizes.
struct FlowChips<Item: Hashable>: View {
    let items: [Item]
    let isOn: (Item) -> Bool
    let label: (Item) -> String
    let onTap: (Item) -> Void

    init(items: [Item], isOn: @escaping (Item) -> Bool, label: KeyPath<Item, String>, onTap: @escaping (Item) -> Void) {
        self.items = items
        self.isOn = isOn
        self.label = { $0[keyPath: label] }
        self.onTap = onTap
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.grid(2)) { chips }
            VStack(alignment: .leading, spacing: Spacing.grid(2)) { chips }
        }
    }

    @ViewBuilder private var chips: some View {
        ForEach(items, id: \.self) { item in
            let on = isOn(item)
            Button { onTap(item) } label: {
                HStack(spacing: Spacing.grid(1)) {
                    Image(systemName: on ? "checkmark" : "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text(label(item))
                        .font(.pgym(.bodyMedium, size: 15))
                        .lineLimit(1)
                }
                .foregroundStyle(on ? Color.ink : Color.chalk)
                .padding(.horizontal, Spacing.grid(3))
                .frame(minHeight: Spacing.touchTargetMin)
                .background(Capsule().fill(on ? Color.plate : Color.iron))
                .overlay(Capsule().strokeBorder(on ? Color.clear : Color.rail, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label(item))
            .accessibilityAddTraits(on ? .isSelected : [])
        }
    }
}
