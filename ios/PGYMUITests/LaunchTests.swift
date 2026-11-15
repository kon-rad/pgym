import XCTest

final class LaunchTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The app launches to the tab shell: three tabs, Today selected, C1 on screen.
    @MainActor
    func testLaunchesToTabShell() {
        let app = XCUIApplication()
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "no tab bar after launch")
        for title in ["Today", "Progress", "Profile"] {
            XCTAssertTrue(tabBar.buttons[title].exists, "missing tab \(title)")
        }
        XCTAssertTrue(app.descendants(matching: .any)["screen.C1"].waitForExistence(timeout: 5))

        tabBar.buttons["Progress"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.E1"].waitForExistence(timeout: 5))

        tabBar.buttons["Profile"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.F1"].waitForExistence(timeout: 5))
    }
}
