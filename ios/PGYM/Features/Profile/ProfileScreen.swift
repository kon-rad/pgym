import DesignSystem
import SwiftData
import SwiftUI

/// F1 Profile. Name and member-since come from sign-in (card I2). The account block (email,
/// verification, sign out, delete account) sits here until card I8 builds F5 Settings and
/// F6 Privacy and data, where the flow spec puts those rows.
struct ProfileScreen: View {
    static let viewID = "F1"

    @Environment(AppSession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(RoutineStore.activeDescriptor) private var routines: [Routine]

    @State private var confirmingSignOut = false
    @State private var verificationSent = false
    @State private var path: [ProfileRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.cardGap) {
                    header

                    HStack(spacing: Spacing.cardGapMin) {
                        StatTile(label: "Proofs", value: "0")
                        StatTile(label: "Longest streak", value: "0", unit: "wk")
                    }

                    NavigationLink(value: ProfileRoute.routines) {
                        ProfileLinkRow(title: "Routines", detail: routines.isEmpty ? nil : "\(routines.count)")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("profile.routines")
                    .padding(.top, Spacing.grid(2))

                    account
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.top, Spacing.grid(4))
                .padding(.bottom, Spacing.grid(8))
            }
            .background(Color.ink.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("screen.\(Self.viewID)")
            .navigationDestination(for: ProfileRoute.self) { route in
                switch route {
                case .deleteAccount: DeleteAccountScreen()
                case .routines: RoutinesScreen()
                }
            }
            .confirmationDialog(AuthCopy.Profile.signOutTitle, isPresented: $confirmingSignOut, titleVisibility: .visible) {
                Button(AuthCopy.Profile.signOut, role: .destructive) { try? session.signOut() }
                Button(AuthCopy.Profile.cancel, role: .cancel) {}
            }
            .task { await session.refreshUser() }
        }
        .tint(Color.chalk)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.grid(2)) {
            Text(session.displayName ?? "Profile")
                .pgymText(.display)
                .foregroundStyle(Color.chalk)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .accessibilityAddTraits(.isHeader)

            if let month = memberSince {
                Text(AuthCopy.Profile.memberSince(month))
                    .pgymText(.label)
                    .foregroundStyle(Color.steel)
            }
        }
    }

    private var memberSince: String? {
        guard let created = session.profile?.createdAt else { return nil }
        return created.formatted(.dateTime.month(.wide).year())
    }

    private var account: some View {
        VStack(alignment: .leading, spacing: Spacing.grid(3)) {
            Text(AuthCopy.Profile.accountEmail)
                .pgymText(.label)
                .foregroundStyle(Color.steel)
                .padding(.top, Spacing.grid(4))

            if let email = session.user?.email {
                Text(email)
                    .pgymText(.bodyMedium, size: 17)
                    .foregroundStyle(Color.chalk)
                    .accessibilityIdentifier("f1.email")
            }

            if session.user?.needsEmailVerification == true, let email = session.user?.email {
                VStack(alignment: .leading, spacing: Spacing.grid(1)) {
                    InlineNote(
                        text: verificationSent ? AuthCopy.Profile.linkSent(email) : AuthCopy.Profile.notVerified,
                        tone: .info,
                        identifier: "f1.verification"
                    )
                    if !verificationSent {
                        Button(AuthCopy.Profile.resend) {
                            Task {
                                if (try? await session.resendVerificationEmail()) != nil {
                                    withAnimation(Animation.pgymSpring(reduceMotion: reduceMotion)) { verificationSent = true }
                                }
                            }
                        }
                        .font(.pgym(.bodyMedium, size: 15))
                        .foregroundStyle(Color.chalk)
                        .frame(minHeight: Spacing.touchTargetMin)
                    }
                }
            }

            SecondaryButton(AuthCopy.Profile.signOut) { confirmingSignOut = true }
                .accessibilityIdentifier("f1.signOut")

            Button(AuthCopy.Profile.deleteAccount) { path.append(.deleteAccount) }
                .font(.pgym(.bodyMedium, size: 15))
                .foregroundStyle(Color.bone)
                .frame(maxWidth: .infinity, minHeight: Spacing.touchTargetMin)
                .accessibilityIdentifier("f1.deleteAccount")
        }
    }
}

enum ProfileRoute: Hashable {
    case deleteAccount
    case routines
}

/// A link row on F1: title, an optional mono count, a chevron.
private struct ProfileLinkRow: View {
    let title: String
    let detail: String?

    var body: some View {
        HStack {
            Text(title)
                .font(.pgym(.bodyMedium, size: 17))
                .foregroundStyle(Color.chalk)
            Spacer()
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
        .padding(.vertical, Spacing.grid(1))
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.iron))
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct ProfileScreen_Previews: PreviewProvider {
    static var previews: some View {
        let _ = FontRegistry.registerAll()
        ProfileScreen()
            .environment(AppSession(dependencies: .fake()))
            .environment(NetworkMonitor(fixed: true))
            .modelContainer(Models.makeContainer(inMemory: true))
            .preferredColorScheme(.dark)
    }
}
