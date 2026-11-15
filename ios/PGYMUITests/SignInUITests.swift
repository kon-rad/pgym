import XCTest

/// The sign-in gate end to end on the fake auth layer (launch argument `-pgym-ui-test`).
/// No Apple or Google sheet is driven here: those need a real account and a signed build.
final class SignInUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    /// Signed out: A1. Email, create mode (A3), A5, then the tabs. Then delete the account (F7)
    /// and land back on A1 with the deleted line.
    @MainActor
    func testCreateAccountYearOfBirthAndDelete() {
        let app = XCUIApplication()
        app.launchArguments = ["-pgym-ui-test"]
        app.launch()

        XCTAssertTrue(element(app, "screen.A1").waitForExistence(timeout: 10), "signed out must start on A1")
        XCTAssertFalse(app.tabBars.firstMatch.exists, "the tabs are behind the gate")

        app.buttons["auth.useEmail"].tap()
        XCTAssertTrue(element(app, "screen.A2").waitForExistence(timeout: 5))

        app.buttons["auth.toggleMode"].tap()
        XCTAssertTrue(element(app, "screen.A3").waitForExistence(timeout: 5))

        let email = app.textFields["auth.email"]
        email.tap()
        email.typeText("ui@example.com")
        let password = app.secureTextFields["auth.password"]
        password.tap()
        // Return submits (the field's onSubmit), so the button under the keyboard is never needed.
        password.typeText("longenough\n")

        XCTAssertTrue(element(app, "screen.A5").waitForExistence(timeout: 5))
        let year = app.textFields["a5.year"]
        year.tap()
        year.typeText("1990")
        app.buttons["a5.continue"].tap()

        // Onboarding (card I3): B1 goal, B2 days (pre-filled to match), B3 skip, B4 starter.
        XCTAssertTrue(element(app, "screen.B1").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["b1.lockIn"].isEnabled, "no goal is pre-selected")
        app.buttons["b1.goal.3"].tap()
        app.buttons["b1.lockIn"].tap()
        XCTAssertTrue(element(app, "screen.B2").waitForExistence(timeout: 5))
        app.buttons["b2.continue"].tap()
        XCTAssertTrue(element(app, "screen.B3").waitForExistence(timeout: 5))
        app.buttons["b3.skip"].tap()
        XCTAssertTrue(element(app, "screen.B4").waitForExistence(timeout: 5))
        app.buttons["b4.use"].tap()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        tabBar.buttons["Profile"].tap()
        XCTAssertTrue(element(app, "screen.F1").waitForExistence(timeout: 5))

        app.buttons["f1.deleteAccount"].tap()
        XCTAssertTrue(element(app, "screen.F7").waitForExistence(timeout: 5))
        let deleteButton = app.buttons["f7.delete"]
        XCTAssertFalse(deleteButton.isEnabled, "DELETE must be typed first")
        let confirm = app.textFields["f7.confirm"]
        confirm.tap()
        confirm.typeText("DELETE\n") // return closes the keyboard so the button is reachable
        deleteButton.tap()

        XCTAssertTrue(element(app, "screen.A1").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "auth.accountDeleted").exists)
    }
}
