import DesignSystem
import SwiftUI

/// The onboarding container: the step label and progress bars on top, one screen at a time,
/// sliding forward and back with a spring (a cross-fade under Reduce Motion).
struct OnboardingFlowView: View {
    @Environment(AppSession.self) private var session
    @Environment(AppServices.self) private var services
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var model: OnboardingModel?

    var body: some View {
        ZStack {
            Color.ink.ignoresSafeArea()
            if let model {
                content(model)
            }
        }
        .onAppear {
            guard model == nil, let uid = session.user?.uid else { return }
            model = OnboardingModel(uid: uid, startingUnits: session.startingUnits, store: services.onboardingDrafts)
        }
    }

    private func content(_ model: OnboardingModel) -> some View {
        let onBack: (() -> Void)? = model.step == .goal ? nil : { model.back() }
        return VStack(spacing: 0) {
            OnboardingHeader(step: model.step, onBack: onBack)

            Group {
                switch model.step {
                case .goal: WeeklyGoalScreen(model: model)
                case .days: GymDaysScreen(model: model)
                case .reminders: RemindersScreen(model: model)
                case .routine: FirstRoutineScreen(model: model)
                }
            }
            .id(model.step)
            .transition(transition(forward: model.movingForward))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .animation(Animation.pgymSpring(reduceMotion: reduceMotion) ?? .easeInOut(duration: 0.2), value: model.step)
        .sensoryFeedback(.impact(weight: .light), trigger: model.step)
    }

    private func transition(forward: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
        )
    }
}

/// "STEP 2 OF 4", four bars that fill in Plate as the steps are done, and Back.
struct OnboardingHeader: View {
    let step: OnboardingDraft.Step
    var onBack: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.grid(3)) {
            HStack {
                if let onBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.chalk)
                            .frame(width: Spacing.touchTargetMin, height: Spacing.touchTargetMin, alignment: .leading)
                    }
                    .accessibilityLabel(OnboardingCopy.back)
                    .accessibilityIdentifier("onboarding.back")
                } else {
                    Color.clear.frame(width: Spacing.touchTargetMin, height: Spacing.touchTargetMin)
                }
                Spacer()
                Text(OnboardingCopy.step(step.number, of: OnboardingDraft.Step.count))
                    .pgymText(.label)
                    .foregroundStyle(Color.steel)
                    .accessibilityIdentifier("onboarding.step")
            }

            HStack(spacing: Spacing.grid(1)) {
                ForEach(OnboardingDraft.Step.allCases, id: \.self) { each in
                    Capsule()
                        .fill(each.rawValue <= step.rawValue ? Color.plate : Color.rail)
                        .frame(height: 4)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.top, Spacing.grid(2))
    }
}

/// The layout every onboarding screen shares: a scrolling body and the main button pinned at the
/// bottom in thumb reach.
struct OnboardingScreen<Content: View, Footer: View>: View {
    let viewID: String
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.grid(6)) {
                content
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.top, Spacing.grid(8))
            .padding(.bottom, Spacing.grid(6))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Spacing.grid(3)) {
                footer
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.top, Spacing.grid(3))
            .padding(.bottom, Spacing.grid(2))
            .background(Color.ink)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.\(viewID)")
    }
}

/// A screen title in Anton.
struct OnboardingTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .pgymText(.display, size: 52)
            .foregroundStyle(Color.chalk)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A quiet text button (Back to B1, Skip for now, Build my own).
struct OnboardingLink: View {
    let title: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .pgymText(.bodyMedium, size: 16)
                .foregroundStyle(Color.bone)
                .underline()
                .frame(minHeight: Spacing.touchTargetMin)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

struct OnboardingFlowView_Previews: PreviewProvider {
    static var previews: some View {
        let _ = FontRegistry.registerAll()
        OnboardingFlowView()
            .environment(AppSession(dependencies: .fake()))
            .environment(AppServices.inMemory())
            .preferredColorScheme(.dark)
    }
}
