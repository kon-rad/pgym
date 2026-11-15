import DesignSystem
import Observation
import SwiftUI

/// A5 Year of birth: asked once, after the first sign-in by any method. A typed field, not a
/// wheel, so nobody accepts a default year by accident (pgym-flow-spec.md, A5).
@MainActor
@Observable
final class YearOfBirthViewModel {
    var text = ""
    private(set) var isSaving = false
    private(set) var errorText: String?

    var canSubmit: Bool { text.count == 4 && !isSaving }

    /// Digits only, four at most; the number pad can still paste anything.
    static func sanitize(_ input: String) -> String {
        String(input.filter { $0.isASCII && $0.isNumber }.prefix(4))
    }

    func textChanged() {
        let clean = Self.sanitize(text)
        if clean != text { text = clean }
        errorText = nil
    }

    func submit(session: AppSession, currentYear: Int = AgePolicy.currentYear()) async {
        guard canSubmit else { return }
        switch AgePolicy.check(text, currentYear: currentYear) {
        case .invalid:
            errorText = AuthCopy.YearOfBirth.checkYear
        case .tooYoung(let year), .ok(let year):
            errorText = nil
            isSaving = true
            defer { isSaving = false }
            do {
                try await session.submitBirthYear(year)
            } catch {
                errorText = AuthCopy.YearOfBirth.couldNotSave
            }
        }
    }
}

struct YearOfBirthScreen: View {
    static let viewID = "A5"

    @Environment(AppSession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var model = YearOfBirthViewModel()
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.grid(6)) {
                if let email = session.verificationSentTo {
                    InlineNote(text: AuthCopy.YearOfBirth.checkInbox(email), tone: .info, identifier: "a5.verification")
                }

                Text(AuthCopy.YearOfBirth.title)
                    .pgymText(.display, size: 64)
                    .foregroundStyle(Color.chalk)
                    .accessibilityAddTraits(.isHeader)

                Text(AuthCopy.YearOfBirth.body)
                    .pgymText(.body, size: 17)
                    .foregroundStyle(Color.bone)
                    .fixedSize(horizontal: false, vertical: true)

                AuthField(
                    label: AuthCopy.YearOfBirth.label,
                    text: $model.text,
                    placeholder: AuthCopy.YearOfBirth.placeholder,
                    kind: .year,
                    isFocused: fieldFocused,
                    identifier: "a5.year"
                )
                .focused($fieldFocused)
                .disabled(model.isSaving)
                .onChange(of: model.text) { model.textChanged() }

                if let error = model.errorText {
                    InlineNote(text: error, identifier: "a5.error")
                }

                LoadingPrimaryButton(title: AuthCopy.YearOfBirth.button, isLoading: model.isSaving, identifier: "a5.continue") {
                    Task { await model.submit(session: session) }
                }
                .disabled(!model.canSubmit)
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.top, Spacing.grid(12))
            .animation(Animation.pgymSpring(reduceMotion: reduceMotion), value: model.errorText)
        }
        .scrollDismissesKeyboard(.never)
        .background(Color.ink.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.\(Self.viewID)")
        // "A four-digit field with the number pad already open."
        .onAppear { fieldFocused = true }
    }
}

/// A5's stop screen for anyone under `AgePolicy.minimumAge`. Plain, no blame; nothing is stored.
struct UnderMinimumAgeScreen: View {
    static let viewID = "A5.stop"

    @Environment(AppSession.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.grid(6)) {
            Spacer()
            PGYMMark(color: .chalk)
                .frame(width: 72, height: 72)
            Text(AuthCopy.YearOfBirth.tooYoung())
                .pgymText(.display, size: 48)
                .foregroundStyle(Color.chalk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            SecondaryButton(AuthCopy.YearOfBirth.signOut) {
                try? session.signOut()
            }
            .accessibilityIdentifier("a5.signOut")
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.bottom, Spacing.grid(4))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ink.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.\(Self.viewID)")
    }
}

/// Signed in, but `users/{uid}` could not be read (a fresh install with no connection).
/// Retrying is the only useful thing; signing out is the way back.
struct ProfileUnavailableScreen: View {
    @Environment(AppSession.self) private var session
    @State private var retrying = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.grid(6)) {
            Spacer()
            Text(AuthCopy.Profile.couldNotLoad)
                .pgymText(.display, size: 44)
                .foregroundStyle(Color.chalk)
                .fixedSize(horizontal: false, vertical: true)
            Text(AuthCopy.noConnection)
                .pgymText(.body, size: 17)
                .foregroundStyle(Color.bone)
            Spacer()
            LoadingPrimaryButton(title: AuthCopy.Profile.retry, isLoading: retrying, identifier: "profile.retry") {
                Task {
                    retrying = true
                    await session.retryProfile()
                    retrying = false
                }
            }
            SecondaryButton(AuthCopy.Profile.signOut) { try? session.signOut() }
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.bottom, Spacing.grid(4))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ink.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.profileUnavailable")
    }
}

struct YearOfBirthScreen_Previews: PreviewProvider {
    static var previews: some View {
        let _ = FontRegistry.registerAll()
        YearOfBirthScreen()
            .environment(AppSession(dependencies: .fake()))
            .preferredColorScheme(.dark)
    }
}
