import XCTest

final class RoutinesUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// F1 to F2, add a starter from the empty state, open it in F3, open D3 and search.
    /// The UI-test launch argument signs in a fake user and gives an empty in-memory store.
    @MainActor
    func testStarterToEditorToAddExercise() {
        let app = XCUIApplication()
        app.launchArguments = ["-pgym-ui-test-signed-in"]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "no tab bar after launch")
        tabBar.buttons["Profile"].tap()
        let routinesLink = app.buttons["profile.routines"]
        XCTAssertTrue(routinesLink.waitForExistence(timeout: 5))
        routinesLink.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.F2"].waitForExistence(timeout: 5))

        let fullBody = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Full body.'")).firstMatch
        XCTAssertTrue(fullBody.waitForExistence(timeout: 5), "empty F2 offers the starters")
        fullBody.tap()

        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Full body, 6 exercises'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the adopted routine is listed")
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.F3"].waitForExistence(timeout: 5))

        // The button sits under the six exercise rows, below the fold on a phone.
        let addExercise = app.buttons["Add exercise"].firstMatch
        for _ in 0..<6 where !addExercise.isHittable { app.swipeUp() }
        addExercise.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.D3"].waitForExistence(timeout: 5))
        let search = app.textFields["Search exercises"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("row")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Barbell row'")).firstMatch.waitForExistence(timeout: 5))
    }
}
