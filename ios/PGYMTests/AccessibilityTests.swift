import DesignSystem
import XCTest
@testable import PGYM

/// Card I9: what VoiceOver reads on C1, D2, D8 and D11, and the release-only guard on the UI-test camera.
final class AccessibilityTests: XCTestCase {
    func testWeekRingsReadAsOneSentence() {
        let days: [WeekRings.Entry] = [
            (.mon, .done), (.tue, .done), (.wed, .rest), (.thu, .today),
            (.fri, .planned), (.sat, .rest), (.sun, .rest),
        ]
        XCTAssertEqual(
            WeekRingSpeech.label(days: days, count: 2, goal: 4),
            "This week, 2 of 4. Monday done, Tuesday done, Wednesday rest, Thursday today, not done, "
                + "Friday gym day, Saturday rest, Sunday rest."
        )
    }

    func testWeekRingsWithoutAGoalSkipTheCount() {
        let days: [WeekRings.Entry] = [(.mon, .today)]
        XCTAssertEqual(WeekRingSpeech.label(days: days, count: 0, goal: nil), "This week. Monday today, not done.")
        XCTAssertEqual(WeekRingSpeech.label(days: days, count: 0, goal: 0), "This week. Monday today, not done.")
    }

    func testNoRingIsReadAsMissed() {
        for status in DayRing.Status.allCases {
            let spoken = WeekRingSpeech.status(status).lowercased()
            XCTAssertFalse(spoken.contains("miss"), "positive only: \(status) reads \(spoken)")
        }
    }

    func testElapsedTimeIsSpokenInWords() {
        XCTAssertEqual(SessionClock.spoken(40), "40 seconds")
        XCTAssertEqual(SessionClock.spoken(61), "1 minute")
        XCTAssertEqual(SessionClock.spoken(52 * 60 + 10), "52 minutes")
        XCTAssertEqual(SessionClock.spoken(3600), "1 hour")
        XCTAssertEqual(SessionClock.spoken(3600 + 2 * 60 + 5), "1 hour 2 minutes")
        XCTAssertEqual(SessionCopy.a11yElapsed("52 minutes"), "Session time, 52 minutes")
    }

    func testStampReadsNumberAndTime() {
        XCTAssertEqual(StampCopy.a11yStamped(number: 42, timestamp: "Sun 15 Nov 18:47"), "Proof 42, stamped Sun 15 Nov 18:47")
        XCTAssertEqual(StampCopy.a11yPending, "Proof pending, will stamp when online")
    }

    func testShutterAndSizesReadAsTheSpecSays() {
        XCTAssertEqual(ProofCopy.shutterLabel, "Take proof photo")
        XCTAssertEqual(ProofCopy.sizeLabel(.feed), "Feed size, 4 by 5")
        XCTAssertEqual(ProofCopy.sizeLabel(.story), "Story size, 9 by 16")
    }

    /// The unit-test host is launched without the argument, so the real camera path is the default.
    func testUITestCameraIsOffWithoutItsArgument() {
        XCTAssertFalse(ProcessInfo.processInfo.arguments.contains(UITestCamera.argument))
        XCTAssertFalse(UITestCamera.isOn)
    }

    func testUITestCameraPictureIsAReadablePhoto() throws {
        #if DEBUG
        let data = try XCTUnwrap(UITestCamera.photoData())
        let clean = try ProofImageIO.cleanPhoto(from: data)
        XCTAssertEqual(max(clean.image.width, clean.image.height), ProofImageIO.photoLongEdge)
        #else
        XCTAssertNil(UITestCamera.photoData())
        #endif
    }
}
