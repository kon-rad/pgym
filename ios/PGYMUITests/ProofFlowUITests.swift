import XCTest

/// Card I9: the whole core loop on the simulator, from a faked sign-in to a stamped proof, checking on
/// the way that the controls VoiceOver needs carry their identifiers and spoken labels.
///
/// `-pgym-ui-test` gives the fake auth, store and stamping server (no network, no Firebase).
/// `-pgym-ui-test-camera` gives the Debug-only camera stand-in (`UITestCamera`), because the
/// simulator has no camera. Neither exists in a Release build.
final class ProofFlowUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    /// Keeps a screenshot of each screen in the result bundle, so a run can be reviewed by eye.
    @MainActor
    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "screen-\(name)"
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func waitUntilEnabled(_ element: XCUIElement, timeout: TimeInterval = 10) {
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: element)
        wait(for: [enabled], timeout: timeout)
    }

    @MainActor
    func testSignInToStampedProofWithVoiceOverLabels() {
        let app = XCUIApplication()
        app.launchArguments = ["-pgym-ui-test", "-pgym-ui-test-camera"]
        app.launch()

        // A1 to A3 to A5: faked email sign-up.
        XCTAssertTrue(element(app, "screen.A1").waitForExistence(timeout: 10))
        snap(app, "A1")
        app.buttons["auth.useEmail"].tap()
        XCTAssertTrue(element(app, "screen.A2").waitForExistence(timeout: 5))
        snap(app, "A2")
        app.buttons["auth.toggleMode"].tap()
        XCTAssertTrue(element(app, "screen.A3").waitForExistence(timeout: 5))
        snap(app, "A3")
        let email = app.textFields["auth.email"]
        email.tap()
        email.typeText("proof@example.com")
        let password = app.secureTextFields["auth.password"]
        password.tap()
        password.typeText("longenough\n")
        XCTAssertTrue(element(app, "screen.A5").waitForExistence(timeout: 5))
        snap(app, "A5")
        let year = app.textFields["a5.year"]
        year.tap()
        year.typeText("1990")
        app.buttons["a5.continue"].tap()

        // B1 to B4: goal, days, skip reminders, take the starter routine.
        XCTAssertTrue(element(app, "screen.B1").waitForExistence(timeout: 5))
        snap(app, "B1")
        app.buttons["b1.goal.3"].tap()
        app.buttons["b1.lockIn"].tap()
        XCTAssertTrue(element(app, "screen.B2").waitForExistence(timeout: 5))
        snap(app, "B2")
        app.buttons["b2.continue"].tap()
        XCTAssertTrue(element(app, "screen.B3").waitForExistence(timeout: 5))
        snap(app, "B3")
        app.buttons["b3.skip"].tap()
        XCTAssertTrue(element(app, "screen.B4").waitForExistence(timeout: 5))
        snap(app, "B4")
        app.buttons["b4.use"].tap()

        // C1 Today: the week row is one spoken element.
        XCTAssertTrue(element(app, "screen.C1").waitForExistence(timeout: 10))
        snap(app, "C1")
        let rings = element(app, "c1.rings")
        XCTAssertTrue(rings.waitForExistence(timeout: 5))
        XCTAssertTrue(rings.label.hasPrefix("This week"), "C1 rings read: \(rings.label)")

        // Start: Start session on a gym day or the first run, Train anyway on a rest day.
        let start = app.buttons["c1.start"]
        if start.waitForExistence(timeout: 3) {
            start.tap()
        } else {
            let anyway = app.buttons["c2.trainAnyway"]
            XCTAssertTrue(anyway.waitForExistence(timeout: 3), "Today offers a way to start")
            anyway.tap()
        }

        // D2: log set 1. A first session has no weight yet, so the check opens the keypad on weight.
        XCTAssertTrue(element(app, "screen.D2").waitForExistence(timeout: 10))
        snap(app, "D2")
        XCTAssertEqual(element(app, "d2.close").label, "Leave session")
        let check = app.buttons["d2.set.1.check"]
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        XCTAssertEqual(check.label, "Mark set 1 done")
        XCTAssertEqual(app.buttons["d2.set.1.weight"].label, "Set 1, weight")
        check.tap()
        let keypad = element(app, "d2.keypad")
        if keypad.waitForExistence(timeout: 2) {
            keypad.buttons["6"].tap()
            keypad.buttons["0"].tap()
            app.buttons["d2.keypad.log"].tap()
        }
        XCTAssertTrue(app.buttons["Set 1 done"].waitForExistence(timeout: 5), "set 1 is logged")
        let finish = app.buttons["d2.finish"]
        waitUntilEnabled(finish)
        finish.tap()

        // D7: the shutter reads as the spec says.
        XCTAssertTrue(element(app, "screen.D7").waitForExistence(timeout: 10))
        snap(app, "D7")
        let shutter = app.buttons["d7.shutter"]
        XCTAssertTrue(shutter.label.hasPrefix("Take proof photo"), "shutter reads: \(shutter.label)")
        XCTAssertEqual(app.buttons["d7.close"].label, "Close camera")
        waitUntilEnabled(shutter)
        shutter.tap()

        // D8: the preview has a label made from the card, then Stamp it.
        XCTAssertTrue(element(app, "screen.D8").waitForExistence(timeout: 15))
        snap(app, "D8")
        let preview = element(app, "d8.preview")
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertTrue(preview.label.hasPrefix("Proof card"), "D8 preview reads: \(preview.label)")
        XCTAssertEqual(app.buttons["d8.filter.iron"].label, "Iron filter")
        let stamp = app.buttons["d8.stamp"]
        waitUntilEnabled(stamp, timeout: 15)
        stamp.tap()

        // D11: the fake server stamps it; the stamp reads the number and the time, Share opens.
        XCTAssertTrue(element(app, "screen.D11").waitForExistence(timeout: 10))
        snap(app, "D11")
        let stamped = element(app, "d11.stamp")
        XCTAssertTrue(stamped.waitForExistence(timeout: 20), "the proof is stamped by the server")
        snap(app, "D11-stamped")
        XCTAssertTrue(stamped.label.hasPrefix("Proof "), "D11 stamp reads: \(stamped.label)")
        XCTAssertTrue(stamped.label.contains("stamped"), "D11 stamp reads: \(stamped.label)")
        XCTAssertTrue(element(app, "d11.rings").label.hasPrefix("This week"))
        waitUntilEnabled(app.buttons["d12.share"])
        app.buttons["d11.done"].tap()

        // Back on Today with the proof logged.
        XCTAssertTrue(element(app, "screen.C1").waitForExistence(timeout: 10))
        snap(app, "C1")
        XCTAssertTrue(element(app, "c1.lastProof").waitForExistence(timeout: 10), "Today shows the last proof")
        snap(app, "C1-after-proof")
    }
}
