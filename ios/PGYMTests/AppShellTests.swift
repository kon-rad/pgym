import XCTest
@testable import PGYM

final class AppShellTests: XCTestCase {
    /// pgym-app-views.md, "Navigation": three tabs, in this order, rooted at C1, E1, F1.
    func testThreeTabsInOrder() {
        XCTAssertEqual(AppTab.allCases, [.today, .progress, .profile])
        XCTAssertEqual(AppTab.allCases.map(\.title), ["Today", "Progress", "Profile"])
        XCTAssertEqual(AppTab.allCases.map(\.viewID), ["C1", "E1", "F1"])
        XCTAssertEqual(TodayScreen.viewID, AppTab.today.viewID)
        XCTAssertEqual(ProgressScreen.viewID, AppTab.progress.viewID)
        XCTAssertEqual(ProfileScreen.viewID, AppTab.profile.viewID)
    }

    /// With no GoogleService-Info.plist the app must still start, with Firebase off.
    func testFirebaseStaysOffWithoutConfig() {
        let emptyBundle = Bundle(for: AppShellTests.self)
        XCTAssertNil(FirebaseBootstrap.configPath(in: emptyBundle))
        XCTAssertEqual(
            FirebaseBootstrap.configure(bundle: emptyBundle, environment: ["PGYM_EMULATOR_HOST": "127.0.0.1"]),
            .missingConfig
        )
    }
}
