import Foundation
import Observation

/// Phone-side services that live for the whole app: the reminder scheduler and onboarding's
/// draft store. Built once at launch and passed down through the environment.
@MainActor
@Observable
final class AppServices {
    let reminders: ReminderScheduler
    let onboardingDrafts: OnboardingDraftStore

    init(reminders: ReminderScheduler, onboardingDrafts: OnboardingDraftStore) {
        self.reminders = reminders
        self.onboardingDrafts = onboardingDrafts
    }

    /// The real phone: iOS notifications and UserDefaults.
    static func live() -> AppServices {
        AppServices(
            reminders: ReminderScheduler(center: SystemNotificationCenter(), store: UserDefaultsReminderStore()),
            onboardingDrafts: UserDefaultsOnboardingDraftStore()
        )
    }

    /// UI tests and previews: nothing reaches iOS, nothing outlives the process.
    static func inMemory() -> AppServices {
        AppServices(
            reminders: ReminderScheduler(center: FakeNotificationCenter(), store: InMemoryReminderStore()),
            onboardingDrafts: InMemoryOnboardingDraftStore()
        )
    }
}
