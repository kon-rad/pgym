import XCTest
@testable import PGYM

@MainActor
final class PurchaseServiceTests: XCTestCase {
    private let plans = [
        PurchaseOption(id: "$rc_annual", title: "Annual", localizedPrice: "$29.99", localizedPeriod: "per year", introductoryTerms: "7 days free", isAnnual: true),
        PurchaseOption(id: "$rc_monthly", title: "Monthly", localizedPrice: "$4.99", localizedPeriod: "per month", introductoryTerms: nil, isAnnual: false),
    ]

    func testIdentityEntitlementPurchaseRestoreAndLogoutUseInjectedService() async throws {
        let fake = FakePurchaseService(offerings: plans)
        let state = PurchaseState(service: fake)
        await state.identify(uid: "firebase-user")
        XCTAssertEqual(fake.identifiedUIDs, ["firebase-user"])
        XCTAssertFalse(state.isPro)
        XCTAssertEqual(state.options, plans)

        try await state.purchase(plans[0])
        XCTAssertTrue(state.isPro)
        XCTAssertEqual(fake.purchasedOptionIDs, ["$rc_annual"])

        fake.entitlementActive = false
        try await state.restore()
        XCTAssertFalse(state.isPro)
        XCTAssertEqual(fake.restoreCalls, 1)

        await state.signedOut()
        XCTAssertEqual(fake.logOutCalls, 1)
        XCTAssertFalse(state.isPro)
    }

    func testRevenueCatFailureLeavesFreeCoreAvailableAndProLocked() async {
        let fake = FakePurchaseService()
        fake.failure = .offline
        let state = PurchaseState(service: fake)
        await state.identify(uid: "firebase-user")
        XCTAssertFalse(state.canUse(.photoInsight))
        XCTAssertFalse(state.canUse(.fullHistory))
        guard case .unavailable = state.phase else { return XCTFail("Expected non-blocking unavailable state") }

        // Free actions are deliberately not represented by ProFeature and need no purchase check.
        XCTAssertEqual(Set(ProFeature.allCases), [.photoInsight, .fullHistory, .advancedProgress, .agentAccess])
    }

    func testUnconfiguredRevenueCatDoesNotAttemptIdentityOrBlockApp() async {
        let fake = FakePurchaseService()
        fake.isConfigured = false
        let state = PurchaseState(service: fake)
        await state.identify(uid: "firebase-user")
        XCTAssertEqual(fake.identifiedUIDs, [])
        XCTAssertEqual(state.phase, .ready)
        XCTAssertFalse(state.isPro)
    }
}
