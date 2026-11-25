import Foundation

#if canImport(RevenueCat)
import RevenueCat

@MainActor
final class RevenueCatPurchaseService: PurchaseService {
    static let entitlementID = "pro"
    private var packages: [String: Package] = [:]
    let isConfigured: Bool

    init(apiKey: String) {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        isConfigured = !key.isEmpty && !key.contains("placeholder") && !key.contains("YOUR_")
        if isConfigured { Purchases.configure(withAPIKey: key) }
    }

    func identify(uid: String) async throws { _ = try await Purchases.shared.logIn(uid) }
    func logOut() async throws { _ = try await Purchases.shared.logOut() }
    func hasProEntitlement() async throws -> Bool {
        let info = try await Purchases.shared.customerInfo()
        return info.entitlements[Self.entitlementID]?.isActive == true
    }
    func currentOffering() async throws -> [PurchaseOption] {
        guard let offering = try await Purchases.shared.offerings().current else { return [] }
        packages = Dictionary(uniqueKeysWithValues: offering.availablePackages.map { ($0.identifier, $0) })
        return offering.availablePackages.map { package in
            let product = package.storeProduct
            let locale = product.priceFormatter?.locale ?? .current
            let intro = product.introductoryDiscount.flatMap { discount in
                discount.paymentMode == .freeTrial
                    ? "\(Self.localized(discount.subscriptionPeriod, locale: locale)) free"
                    : nil
            }
            return PurchaseOption(
                id: package.identifier,
                title: product.localizedTitle,
                localizedPrice: product.localizedPriceString,
                localizedPeriod: product.subscriptionPeriod.map { "per \(Self.localized($0, locale: locale))" } ?? "",
                introductoryTerms: intro,
                isAnnual: package.packageType == .annual
            )
        }.sorted { $0.isAnnual && !$1.isAnnual }
    }
    func purchase(optionID: String) async throws -> Bool {
        guard let package = packages[optionID] else { throw PurchaseError.unavailable("That plan is no longer available.") }
        let result = try await Purchases.shared.purchase(package: package)
        if result.userCancelled { throw PurchaseError.cancelled }
        return result.customerInfo.entitlements[Self.entitlementID]?.isActive == true
    }
    func restore() async throws -> Bool {
        let info = try await Purchases.shared.restorePurchases()
        return info.entitlements[Self.entitlementID]?.isActive == true
    }
    func managementURL() async -> URL? {
        let info = try? await Purchases.shared.customerInfo()
        return info?.managementURL
    }

    private static func localized(_ period: SubscriptionPeriod, locale: Locale) -> String {
        let formatter = DateComponentsFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        formatter.calendar = calendar
        formatter.unitsStyle = .full
        let components: DateComponents
        switch period.unit {
        case .day: components = DateComponents(day: period.value)
        case .week: components = DateComponents(day: period.value * 7)
        case .month: components = DateComponents(month: period.value)
        case .year: components = DateComponents(year: period.value)
        @unknown default: return "\(period.value)"
        }
        return formatter.string(from: components) ?? "\(period.value)"
    }
}
#else
@MainActor
final class RevenueCatPurchaseService: PurchaseService {
    let isConfigured = false
    init(apiKey: String) {}
    func identify(uid: String) async throws { throw PurchaseError.notConfigured }
    func logOut() async throws {}
    func hasProEntitlement() async throws -> Bool { false }
    func currentOffering() async throws -> [PurchaseOption] { [] }
    func purchase(optionID: String) async throws -> Bool { throw PurchaseError.notConfigured }
    func restore() async throws -> Bool { throw PurchaseError.notConfigured }
    func managementURL() async -> URL? { nil }
}
#endif
