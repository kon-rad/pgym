import Foundation
import Observation

/// Phone-side services that live for the whole app: the reminder scheduler and onboarding's
/// draft store. Built once at launch and passed down through the environment.
@MainActor
@Observable
final class AppServices {
    let reminders: ReminderScheduler
    let onboardingDrafts: OnboardingDraftStore
    let purchases: PurchaseState

    init(reminders: ReminderScheduler, onboardingDrafts: OnboardingDraftStore, purchases: PurchaseState) {
        self.reminders = reminders
        self.onboardingDrafts = onboardingDrafts
        self.purchases = purchases
    }

    /// The real phone: iOS notifications and UserDefaults.
    static func live() -> AppServices {
        AppServices(
            reminders: ReminderScheduler(center: SystemNotificationCenter(), store: UserDefaultsReminderStore()),
            onboardingDrafts: UserDefaultsOnboardingDraftStore(),
            purchases: PurchaseState(service: RevenueCatPurchaseService(
                apiKey: Bundle.main.object(forInfoDictionaryKey: "REVENUECAT_API_KEY") as? String ?? ""
            ))
        )
    }

    /// UI tests and previews: nothing reaches iOS, nothing outlives the process.
    static func inMemory() -> AppServices {
        AppServices(
            reminders: ReminderScheduler(center: FakeNotificationCenter(), store: InMemoryReminderStore()),
            onboardingDrafts: InMemoryOnboardingDraftStore(),
            purchases: PurchaseState(service: FakePurchaseService())
        )
    }
}
