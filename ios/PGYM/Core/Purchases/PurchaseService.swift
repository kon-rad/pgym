import Foundation
import Observation

enum ProFeature: String, CaseIterable, Sendable {
    case photoInsight, fullHistory, advancedProgress, agentAccess
}

struct PurchaseOption: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let localizedPrice: String
    let localizedPeriod: String
    let introductoryTerms: String?
    let isAnnual: Bool
}

enum PurchaseError: Error, Equatable {
    case notConfigured, offline, unavailable(String), cancelled
}

@MainActor
protocol PurchaseService: AnyObject {
    var isConfigured: Bool { get }
    func identify(uid: String) async throws
    func logOut() async throws
    func hasProEntitlement() async throws -> Bool
    func currentOffering() async throws -> [PurchaseOption]
    func purchase(optionID: String) async throws -> Bool
    func restore() async throws -> Bool
    func managementURL() async -> URL?
}

@MainActor
@Observable
final class PurchaseState {
    enum Phase: Equatable { case idle, loading, ready, unavailable(String) }
    private(set) var isPro = false
    private(set) var phase: Phase = .idle
    private(set) var options: [PurchaseOption] = []
    let service: PurchaseService

    init(service: PurchaseService) { self.service = service }

    func identify(uid: String) async {
        guard service.isConfigured else { phase = .ready; return }
        phase = .loading
        do {
            try await service.identify(uid: uid)
            isPro = try await service.hasProEntitlement()
            options = try await service.currentOffering()
            phase = .ready
        } catch {
            // The free workout loop remains available during a RevenueCat outage.
            phase = .unavailable("Subscriptions are temporarily unavailable. Your workouts still work.")
        }
    }

    func refresh() async {
        guard service.isConfigured else { phase = .ready; return }
        do {
            isPro = try await service.hasProEntitlement()
            options = try await service.currentOffering()
            phase = .ready
        } catch { phase = .unavailable("Subscriptions are temporarily unavailable. Your workouts still work.") }
    }

    func purchase(_ option: PurchaseOption) async throws {
        phase = .loading
        isPro = try await service.purchase(optionID: option.id)
        phase = .ready
    }

    func restore() async throws {
        phase = .loading
        isPro = try await service.restore()
        phase = .ready
    }

    func signedOut() async {
        if service.isConfigured { try? await service.logOut() }
        isPro = false
        options = []
        phase = .idle
    }

    func canUse(_ feature: ProFeature) -> Bool { isPro }
}

@MainActor
final class FakePurchaseService: PurchaseService {
    var isConfigured = true
    var entitlementActive = false
    var offerings: [PurchaseOption]
    var failure: PurchaseError?
    private(set) var identifiedUIDs: [String] = []
    private(set) var logOutCalls = 0
    private(set) var restoreCalls = 0
    private(set) var purchasedOptionIDs: [String] = []

    init(entitlementActive: Bool = false, offerings: [PurchaseOption] = []) {
        self.entitlementActive = entitlementActive
        self.offerings = offerings
    }
    func identify(uid: String) async throws { try fail(); identifiedUIDs.append(uid) }
    func logOut() async throws { try fail(); logOutCalls += 1 }
    func hasProEntitlement() async throws -> Bool { try fail(); return entitlementActive }
    func currentOffering() async throws -> [PurchaseOption] { try fail(); return offerings }
    func purchase(optionID: String) async throws -> Bool { try fail(); purchasedOptionIDs.append(optionID); entitlementActive = true; return true }
    func restore() async throws -> Bool { try fail(); restoreCalls += 1; return entitlementActive }
    func managementURL() async -> URL? { URL(string: "https://apps.apple.com/account/subscriptions") }
    private func fail() throws { if let failure { throw failure } }
}
