import CoreText
import SwiftUI
import XCTest
import DesignSystem

final class ColorTokenTests: XCTestCase {
    /// The table in pgym-design-style.md, "Colour", copied by hand. A change to either side fails here.
    func testEveryStyleGuideColourHasAToken() {
        let expected: [ColorToken: UInt32] = [
            .ink: 0x0B0B0C, .iron: 0x17171A, .rail: 0x34343A, .hairline: 0x26262B, .steel: 0xA3A3AC,
            .bone: 0xC9C7C1, .chalk: 0xF2EFE8, .plate: 0xFF4D1F, .photo: 0x2A2A2F,
        ]
        XCTAssertEqual(Set(ColorToken.allCases), Set(expected.keys))
        for token in ColorToken.allCases {
            XCTAssertEqual(token.hex, expected[token], "\(token)")
        }
    }

    /// The contrast figures the style guide quotes.
    func testContrastMatchesStyleGuide() {
        XCTAssertEqual(ColorToken.contrast(.ink, .plate), 5.9, accuracy: 0.05)
        XCTAssertEqual(ColorToken.contrast(.chalk, .plate), 2.9, accuracy: 0.05)
        XCTAssertEqual(ColorToken.contrast(.steel, .ink), 7.9, accuracy: 0.05)
        XCTAssertEqual(ColorToken.contrast(.steel, .iron), 7.1, accuracy: 0.05)
    }

    /// Plate carries Ink text, never Chalk: Ink passes AA for body text, Chalk does not.
    func testPlateCarriesInkNotChalk() {
        XCTAssertGreaterThanOrEqual(ColorToken.contrast(.ink, .plate), 4.5)
        XCTAssertLessThan(ColorToken.contrast(.chalk, .plate), 4.5)
    }
}

final class TypeTokenTests: XCTestCase {
    func testDefaultSizesSitInsideTheirRange() {
        for role in TypeRole.allCases {
            XCTAssertTrue(role.sizeRange.contains(role.defaultSize), "\(role)")
        }
    }

    /// Anton titles scale one step and then wrap; every other role follows Dynamic Type to the top
    /// (pgym-flow-spec.md, "Dynamic Type at the largest size").
    func testOnlyDisplayTitlesStopScalingEarly() {
        XCTAssertEqual(TypeRole.display.maxDynamicTypeSize, .xLarge)
        for role in TypeRole.allCases where role != .display {
            XCTAssertEqual(role.maxDynamicTypeSize, .accessibility5, "\(role) must scale to Accessibility XXXL")
        }
    }

    func testRolesUseTheStyleGuideFaces() {
        XCTAssertEqual(TypeRole.display.face, .antonRegular)
        XCTAssertEqual(TypeRole.button.face, .antonRegular)
        XCTAssertEqual(TypeRole.title.face, .archivoBold)
        XCTAssertEqual(TypeRole.body.face, .archivoRegular)
        XCTAssertEqual(TypeRole.label.face, .jetBrainsMonoRegular)
        XCTAssertEqual(TypeRole.data.face, .jetBrainsMonoBold)
        XCTAssertEqual(TypeRole.button.tracking, 1)
        XCTAssertEqual(TypeRole.body.lineHeight, 1.45)
    }

    func testBundledFontsRegisterUnderTheirPostScriptNames() {
        XCTAssertEqual(FontRegistry.registerAll(), [])
        for face in FontFace.allCases {
            XCTAssertNotNil(FontRegistry.url(for: face), "\(face) missing from bundle")
            let font = CTFontCreateWithName(face.postScriptName as CFString, 12, nil)
            XCTAssertEqual(CTFontCopyPostScriptName(font) as String, face.postScriptName)
        }
    }

    func testOFLLicencesShipWithTheFonts() throws {
        XCTAssertEqual(FontRegistry.licenceURLs.count, 3)
        for url in FontRegistry.licenceURLs {
            let text = try String(contentsOf: url, encoding: .utf8)
            XCTAssertTrue(text.contains("SIL OPEN FONT LICENSE Version 1.1"), url.lastPathComponent)
        }
    }
}

final class LayoutTokenTests: XCTestCase {
    func testStyleGuideNumbers() {
        XCTAssertEqual(Spacing.grid, 4)
        XCTAssertEqual(Spacing.screenMargin, 20)
        XCTAssertEqual(Spacing.cardGapMin, 14)
        XCTAssertEqual(Spacing.cardGapMax, 20)
        XCTAssertEqual(Spacing.touchTargetMin, 44)
        XCTAssertEqual(Spacing.mainButtonHeight, 56)
        XCTAssertEqual(Radius.card, 16)
        XCTAssertEqual(Radius.button, 12)
        XCTAssertEqual(Radius.input, 12)
        XCTAssertEqual(Radius.setCell, 10)
        XCTAssertEqual(Radius.photo, 6)
        XCTAssertEqual(Radius.stamp, 6)
        XCTAssertEqual(Rotation.stampRange, 3...8)
        XCTAssertEqual(ProofCardSpec.feedSize, CGSize(width: 1080, height: 1350))
        XCTAssertEqual(ProofCardSpec.storySize, CGSize(width: 1080, height: 1920))
        XCTAssertEqual(ProofFilter.default, .iron)
    }

    func testFixedSizesSitOnTheGrid() {
        for value in [Spacing.screenMargin, Spacing.cardGap, Spacing.cardGapMax, Spacing.touchTargetMin,
                      Spacing.mainButtonHeight, Spacing.secondaryButtonHeight] {
            XCTAssertEqual(value.truncatingRemainder(dividingBy: Spacing.grid), 0, "\(value)")
        }
        XCTAssertGreaterThanOrEqual(Spacing.secondaryButtonHeight, Spacing.touchTargetMin)
    }
}

final class StampTests: XCTestCase {
    func testTitlePadsToThreeDigits() {
        XCTAssertEqual(Stamp.title(for: 1), "PROOF #001")
        XCTAssertEqual(Stamp.title(for: 42), "PROOF #042")
        XCTAssertEqual(Stamp.title(for: 1234), "PROOF #1234")
    }

    /// The number comes from the server; until then the stamp says pending.
    func testNoNumberMeansPending() {
        XCTAssertEqual(Stamp.title(for: nil), "PROOF PENDING")
    }
}
