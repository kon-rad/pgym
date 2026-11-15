import DesignSystem
import SwiftData
import SwiftUI

/// F6 Privacy and data: every control over the user's data in one place. The physique switch (on
/// opens D10, off confirms and deletes every score), Delete all photos, Export my data as a JSON file
/// through the share sheet, and Delete account (F7).
///
/// The switch and Delete all photos need the server and are disabled offline with "Needs a
/// connection." The export is built from the phone's own store, so it works offline too.
struct PrivacyDataScreen: View {
    static let viewID = "F6"

    @Environment(\.modelContext) private var context
    @Environment(AppSession.self) private var session
    @Environment(ProofServices.self) private var proofs
    @Environment(NetworkMonitor.self) private var network
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \Routine.order) private var routines: [Routine]

    @State private var offering = false
    @State private var confirmingOff = false
    @State private var confirmingPhotos = false
    @State private var working: Action?
    @State private var note: String?
    @State private var failure: String?
    @State private var exportURL: URL?
    @State private var sharing: ExportFile?
    @State private var doneTick = 0

    private enum Action { case physique, photos, export }

    private struct ExportFile: Identifiable {
        let url: URL
        var id: URL { url }
    }

    private var isOnline: Bool { network.isOnline }
    private var isAdult: Bool {
        PhysiqueRules.isAdult(birthYear: session.profile?.birthYear, currentYear: AgePolicy.currentYear())
    }

    var body: some View {
        let snapshots = SessionSnapshot.all(sessions)
        let photoCount = DataControls.photoCount(snapshots)
        let scoreCount = snapshots.filter(\.hasScore).count
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.grid(6)) {
                ScreenTitle(text: ProfileCopy.privacy, size: 44)
                if !isOnline {
                    StatusLine(text: ProfileCopy.needsConnection, systemImage: "wifi.slash", identifier: "f6.offline")
                }
                physiqueSection
                photosSection(count: photoCount)
                exportSection
                if let failure {
                    ErrorCard(message: failure, identifier: "f6.error") { self.failure = nil }
                }
                if let note {
                    InlineNote(text: note, tone: .info, identifier: "f6.note")
                }
                accountSection
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.top, Spacing.grid(2))
            .padding(.bottom, Spacing.grid(8))
        }
        .background(Color.ink.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: doneTick)
        .confirmationDialog(ProgressCopy.confirmTitle, isPresented: $confirmingOff, titleVisibility: .visible) {
            Button(ProgressCopy.confirmOff, role: .destructive) { Task { await turnOff() } }
            Button(ProgressCopy.keepOn, role: .cancel) {}
        } message: {
            Text(ProgressCopy.confirmBody(scoreCount))
        }
        .confirmationDialog(ProfileCopy.deletePhotosTitle(photoCount), isPresented: $confirmingPhotos, titleVisibility: .visible) {
            Button(ProfileCopy.deletePhotosConfirm, role: .destructive) { Task { await deletePhotos() } }
            Button(ProfileCopy.cancel, role: .cancel) {}
        } message: {
            Text(ProfileCopy.deletePhotosBody)
        }
        .sheet(isPresented: $offering) {
            PhysiqueConsentScreen(
                isAdult: isAdult,
                onTurnOn: {
                    offering = false
                    Task {
                        await proofs.consent.turnOn()
                        doneTick += 1
                    }
                },
                onNotNow: {
                    proofs.consent.markOfferShown()
                    offering = false
                }
            )
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $sharing) { file in
            FileShareSheet(url: file.url)
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.\(Self.viewID)")
    }

    // MARK: Physique

    private var physiqueSection: some View {
        VStack(alignment: .leading, spacing: Spacing.grid(2)) {
            if isAdult {
                Toggle(isOn: Binding(
                    get: { proofs.consent.isOn },
                    set: { on in
                        if on { offering = true } else { confirmingOff = true }
                    }
                )) {
                    Text(ProfileCopy.physique)
                        .font(.pgym(.bodyMedium, size: 17))
                        .foregroundStyle(Color.chalk)
                }
                .tint(Color.plate)
                .disabled(!isOnline || working != nil)
                .accessibilityIdentifier("f6.physique")
                Text(proofs.consent.isOn ? ProfileCopy.physiqueOn : ProfileCopy.physiqueOff)
                    .pgymText(.body, size: 13)
                    .foregroundStyle(Color.steel)
                    .accessibilityIdentifier("f6.physiqueCaption")
            } else {
                Text(ProfileCopy.physique)
                    .font(.pgym(.bodyMedium, size: 17))
                    .foregroundStyle(Color.chalk)
                Text(ProfileCopy.under18)
                    .pgymText(.body, size: 13)
                    .foregroundStyle(Color.steel)
            }
        }
        .padding(Spacing.grid(4))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.iron))
    }

    // MARK: Photos

    private func photosSection(count: Int) -> some View {
        Button(ProfileCopy.deletePhotos) { confirmingPhotos = true }
            .buttonStyle(DestructiveButtonStyle())
            .disabled(!isOnline || count == 0 || working != nil)
            .accessibilityValue(working == .photos ? "In progress" : "")
            .accessibilityIdentifier("f6.deletePhotos")
    }

    // MARK: Export

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: Spacing.grid(3)) {
            Text(ProfileCopy.exportBody)
                .pgymText(.body, size: 15)
                .foregroundStyle(Color.bone)
            if let exportURL {
                Text(ProfileCopy.exportReady)
                    .pgymText(.body, size: 15)
                    .foregroundStyle(Color.chalk)
                    .accessibilityIdentifier("f6.exportReady")
                SecondaryButton(ProfileCopy.shareFile) { sharing = ExportFile(url: exportURL) }
                    .accessibilityIdentifier("f6.shareFile")
            } else {
                Button {
                    export()
                } label: {
                    ZStack {
                        Text(ProfileCopy.export).opacity(working == .export ? 0 : 1)
                        if working == .export { ProgressView().tint(Color.chalk) }
                    }
                }
                .buttonStyle(.pgymSecondary)
                .disabled(working != nil)
                .accessibilityIdentifier("f6.export")
            }
        }
        .padding(Spacing.grid(4))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.iron))
    }

    // MARK: Account

    private var accountSection: some View {
        VStack(spacing: Spacing.grid(2)) {
            NavigationLink(value: ProfileRoute.deleteAccount) {
                LinkRow(title: ProfileCopy.deleteAccount)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("f6.deleteAccount")
            Link(destination: SiteLinks.privacy) {
                LinkRow(title: ProfileCopy.privacyPolicy)
            }
            .accessibilityIdentifier("f6.privacyPolicy")
        }
    }

    // MARK: Actions

    private func turnOff() async {
        working = .physique
        defer { working = nil }
        let reachedServer = await proofs.controls.turnOffAnalysis(context: context)
        doneTick += 1
        if !reachedServer { note = ProgressCopy.turnOffFailed }
    }

    private func deletePhotos() async {
        working = .photos
        defer { working = nil }
        do {
            try await proofs.controls.deleteAllPhotos(context: context)
            doneTick += 1
            note = ProfileCopy.photosDeleted
        } catch {
            failure = ProfileCopy.actionFailed
        }
    }

    private func export() {
        working = .export
        defer { working = nil }
        do {
            let file = DataExport.make(
                profile: session.profile,
                physiqueConsent: proofs.consent.isOn,
                routines: routines,
                sessions: sessions
            )
            let url = try file.write()
            exportURL = url
            sharing = ExportFile(url: url)
            doneTick += 1
        } catch {
            failure = ProfileCopy.exportFailed
        }
    }
}

/// F8 About: version, legal links, support, source code (pgym-app-copy.md, F8).
struct AboutScreen: View {
    static let viewID = "F8"

    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.grid(6)) {
                ScreenTitle(text: ProfileCopy.about, size: 44)
                Text(ProfileCopy.version(Self.versionString).uppercased())
                    .pgymText(.label)
                    .foregroundStyle(Color.steel)
                    .accessibilityIdentifier("f8.version")
                VStack(spacing: Spacing.grid(2)) {
                    link(ProfileCopy.terms, SiteLinks.terms, id: "f8.terms")
                    link(ProfileCopy.privacyPolicy, SiteLinks.privacy, id: "f8.privacy")
                    link(ProfileCopy.support, SiteLinks.support, id: "f8.support")
                    if let mail = URL(string: "mailto:\(SiteLinks.supportEmail)") {
                        link(SiteLinks.supportEmail, mail, id: "f8.email")
                    }
                    link(ProfileCopy.sourceCode, SiteLinks.source, id: "f8.source")
                }
                Text(ProfileCopy.licence)
                    .pgymText(.body, size: 15)
                    .foregroundStyle(Color.bone)
                VStack(spacing: Spacing.grid(3)) {
                    PGYMMark().frame(width: 56, height: 56)
                    Text(ProfileCopy.footer.uppercased())
                        .pgymText(.label)
                        .foregroundStyle(Color.steel)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, Spacing.grid(6))
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.top, Spacing.grid(2))
            .padding(.bottom, Spacing.grid(8))
        }
        .background(Color.ink.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.\(Self.viewID)")
    }

    private func link(_ title: String, _ url: URL, id: String) -> some View {
        Link(destination: url) {
            LinkRow(title: title)
        }
        .accessibilityIdentifier(id)
    }
}
