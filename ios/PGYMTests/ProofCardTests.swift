import CoreGraphics
import CoreText
import DesignSystem
import ImageIO
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import PGYM

/// Card I6: the card renderer, its text rules, the filters, the clean JPEGs and the proof files.
/// Snapshot-style checks run on a bundled synthetic photo (PGYMTests/Fixtures/proof-test-photo.png,
/// made by ios/Tools/make-proof-test-photo.py). Nothing here touches the network or the camera.
final class ProofCardTests: XCTestCase {
    // MARK: Fixtures

    private static let stampedAt = ISO8601DateFormatter().date(from: "2026-11-15T18:47:00Z")!

    private func testPhoto(file: StaticString = #filePath, line: UInt = #line) throws -> CGImage {
        let bundle = Bundle(for: Self.self)
        let url = bundle.url(forResource: "proof-test-photo", withExtension: "png")
            ?? bundle.url(forResource: "proof-test-photo", withExtension: "png", subdirectory: "Fixtures")
        let found = try XCTUnwrap(url, "proof-test-photo.png is missing from the test bundle", file: file, line: line)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(found as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func summary(
        name: String = "Push A: chest, shoulders, triceps",
        stamp: ProofStampState = .stamped(proofNumber: 42, stampedAt: ProofCardTests.stampedAt, streakWeeks: 7, proofCount: 42),
        unit: WeightUnit = .kg,
        totalKg: Double = 6240
    ) -> ProofCardSummary {
        ProofCardSummary(
            sessionName: name,
            setCount: 18,
            totalKg: totalKg,
            duration: 72 * 60 + 40,
            topLift: ProofTopLift(exerciseName: "Barbell bench press", weightKg: 140, reps: 5),
            unit: unit,
            timezone: "Europe/London",
            stamp: stamp
        )
    }

    /// RGBA8 sRGB pixels of an image, top row first.
    private func pixels(_ image: CGImage) -> [UInt8] {
        let width = image.width
        let height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        data.withUnsafeMutableBytes { buffer in
            let ctx = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return data
    }

    private func meanDifference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        precondition(a.count == b.count)
        var total = 0
        for i in stride(from: 0, to: a.count, by: 4) {
            total += abs(Int(a[i]) - Int(b[i])) + abs(Int(a[i + 1]) - Int(b[i + 1])) + abs(Int(a[i + 2]) - Int(b[i + 2]))
        }
        return Double(total) / Double(a.count / 4 * 3)
    }

    // MARK: Fonts

    func testCardFontsAreTheBundledFaces() {
        XCTAssertEqual(FontRegistry.registerAll(), [])
        XCTAssertEqual(CTFontCopyPostScriptName(ProofCardFont.anton(112)) as String, "Anton-Regular")
        XCTAssertEqual(CTFontCopyPostScriptName(ProofCardFont.mono(28)) as String, "JetBrainsMono-Bold")
    }

    // MARK: Renderer sizes

    func testRendererReturnsExactly1080x1350And1080x1920() throws {
        let photo = try testPhoto()
        for filter in ProofFilter.allCases {
            let feed = try ProofCardRenderer.render(photo: photo, summary: summary(), options: ProofCardOptions(filter: filter, size: .feed))
            XCTAssertEqual(feed.width, 1080, "\(filter)")
            XCTAssertEqual(feed.height, 1350, "\(filter)")
            let story = try ProofCardRenderer.render(photo: photo, summary: summary(), options: ProofCardOptions(filter: filter, size: .story))
            XCTAssertEqual(story.width, 1080, "\(filter)")
            XCTAssertEqual(story.height, 1920, "\(filter)")
        }
    }

    func testScoreOverlayContainsScoresWithoutWorkoutName() throws {
        let photo = try testPhoto()
        let options = ProofCardOptions(filter: .raw, size: .feed)
        let dimensions = ["shoulderWaist": 71, "waistHeight": 72, "torsoDelt": 73,
                          "symmetryAlignment": 74, "torsoCoreDefinition": 75, "quadProportion": 76]
        let score = PhysiqueRecord(score: 77, dimensions: dimensions)
        let first = pixels(try ProofCardRenderer.render(photo: photo, summary: summary(name: "Push A"), options: options, score: score, shareMode: .scores))
        let renamed = pixels(try ProofCardRenderer.render(photo: photo, summary: summary(name: "Deadlift day"), options: options, score: score, shareMode: .scores))
        let workout = pixels(try ProofCardRenderer.render(photo: photo, summary: summary(name: "Push A"), options: options, shareMode: .workout))
        let differentScore = PhysiqueRecord(score: 90, dimensions: dimensions)
        let rescored = pixels(try ProofCardRenderer.render(photo: photo, summary: summary(name: "Push A"), options: options, score: differentScore, shareMode: .scores))
        XCTAssertEqual(first, renamed, "The AI overlay must exclude the workout title")
        XCTAssertNotEqual(first, workout, "The two share overlays must render different content")
        XCTAssertNotEqual(first, rescored, "The overall score must be visible on the AI overlay")
    }

    func testRendererHandlesLandscapeAndTinyPhotos() throws {
        for (w, h) in [(2048, 1536), (64, 64)] {
            let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            ctx.setFillColor(CGColor(srgbRed: 0.8, green: 0.3, blue: 0.2, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            let photo = try XCTUnwrap(ctx.makeImage())
            let card = try ProofCardRenderer.render(photo: photo, summary: summary(), options: ProofCardOptions(size: .story))
            XCTAssertEqual(card.width, 1080)
            XCTAssertEqual(card.height, 1920)
        }
    }

    /// The story card is the feed card moved down 300 px: the overlays of the two match pixel for pixel
    /// once the photo is the same flat colour behind both.
    func testStoryLayoutIsTheFeedLayoutMovedDown300() throws {
        // Camera-sized, so the photo is scaled down as in the app. A tiny photo scaled up 200 times gets
        // soft left and right edges whose width depends on the card size, which is not what this test is about.
        let ctx = CGContext(data: nil, width: 1440, height: 2560, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 1440, height: 2560))
        let flat = try XCTUnwrap(ctx.makeImage())
        let feed = pixels(try ProofCardRenderer.render(photo: flat, summary: summary(), options: ProofCardOptions(filter: .raw, size: .feed)))
        let story = pixels(try ProofCardRenderer.render(photo: flat, summary: summary(), options: ProofCardOptions(filter: .raw, size: .story)))
        // The lower block (inside the scrim on both): feed y 860...1300 against story y 1160...1600.
        var differing = 0
        for y in 860..<1300 {
            for x in 0..<1080 {
                let f = (y * 1080 + x) * 4
                let s = ((y + 300) * 1080 + x) * 4
                if abs(Int(feed[f]) - Int(story[s])) > 2 { differing += 1 }
            }
        }
        XCTAssertEqual(differing, 0)
    }

    // MARK: Session name

    func testFortyCharacterSessionNamesStayInsideTheirBox() throws {
        let names = [
            "Upper body power day with heavy deadlift",
            String(repeating: "W", count: 40),
            "MMMMMMMMM MMMMMMMMM MMMMMMMMM MMMMMMMMMM",
            "Push A: chest, shoulders, triceps + abs!",
            "WWW WWW WWW WWW WWW WWW WWW WWW WWW WWWW",
        ]
        for name in names {
            XCTAssertEqual(name.count, 40, name)
            let fit = ProofCardText.fitSessionName(name)
            XCTAssertLessThanOrEqual(fit.lines.count, 2, name)
            XCTAssertFalse(fit.lines.isEmpty, name)
            let font = ProofCardFont.anton(fit.step.size)
            for line in fit.lines {
                XCTAssertLessThanOrEqual(ProofTextRun(text: line, font: font).width, 952, "\(name): \(line)")
            }
            // The name block stays under the timestamp and above the stat row.
            XCTAssertEqual(fit.baselines.last, 1124)
            XCTAssertGreaterThan(fit.timestampBaseline - 28, 608, "timestamp inside the scrim")
        }
    }

    /// Rendered, a 40-character name puts no ink to the right of the 952 px column.
    func testFortyCharacterNameDrawsNothingOutsideTheColumn() throws {
        let photo = try testPhoto()
        let options = ProofCardOptions(filter: .raw, size: .feed)
        let long = pixels(try ProofCardRenderer.render(photo: photo, summary: summary(name: String(repeating: "W", count: 40)), options: options))
        let short = pixels(try ProofCardRenderer.render(photo: photo, summary: summary(name: "Legs"), options: options))
        var differing = 0
        // Right margin x 1020...1079 (a few px of anti-aliasing allowed past 1016), from the top of the
        // scrim to the stat row.
        for y in 608..<1150 {
            for x in 1020..<1080 {
                let i = (y * 1080 + x) * 4
                if abs(Int(long[i]) - Int(short[i])) > 2 { differing += 1 }
            }
        }
        XCTAssertEqual(differing, 0)
    }

    func testSessionNameRules() {
        XCTAssertEqual(ProofCardText.sessionDisplayName("  push a  "), "PUSH A")
        XCTAssertEqual(ProofCardText.sessionDisplayName("   "), "SESSION")
        XCTAssertEqual(ProofCardText.sessionDisplayName(String(repeating: "a", count: 60)).count, 40)
        let short = ProofCardText.fitSessionName("Legs")
        XCTAssertEqual(short.lines, ["LEGS"])
        XCTAssertEqual(short.step.size, 112)
        XCTAssertEqual(short.baselines, [1124])
        XCTAssertEqual(short.timestampBaseline, 988)
        let template = ProofCardText.fitSessionName("Push A: chest, shoulders, triceps")
        XCTAssertEqual(template.lines.count, 2)
        XCTAssertEqual(template.baselines.first, template.lines.count == 2 ? 1124 - template.step.pitch : 1124)
    }

    // MARK: Filters

    func testEveryFilterProducesAnImageDifferentFromRaw() throws {
        let photo = try testPhoto()
        let size = ProofCardSize.feed.pixelSize
        let raw = pixels(try ProofCardRenderer.filteredPhoto(photo, filter: .raw, size: size))
        for filter in ProofFilter.allCases where filter != .raw {
            let filtered = pixels(try ProofCardRenderer.filteredPhoto(photo, filter: filter, size: size))
            let difference = meanDifference(raw, filtered)
            XCTAssertGreaterThan(difference, 2, "\(filter) mean difference \(difference)")
        }
    }

    func testFiltersAreDistinctFromEachOtherAndReproducible() throws {
        let photo = try testPhoto()
        let size = ProofCardSize.feed.pixelSize
        let images = try ProofFilter.allCases.map { pixels(try ProofCardRenderer.filteredPhoto(photo, filter: $0, size: size)) }
        for i in images.indices {
            for j in images.indices where j > i {
                XCTAssertGreaterThan(meanDifference(images[i], images[j]), 1, "\(ProofFilter.allCases[i]) vs \(ProofFilter.allCases[j])")
            }
        }
        // Grain comes from CIRandomGenerator, which is deterministic: the same card twice is identical.
        let again = pixels(try ProofCardRenderer.filteredPhoto(photo, filter: .iron, size: size))
        XCTAssertEqual(meanDifference(images[0], again), 0)
    }

    func testIronIsBlackAndWhite() throws {
        let iron = pixels(try ProofCardRenderer.filteredPhoto(try testPhoto(), filter: .iron, size: CGSize(width: 160, height: 200), grain: false))
        for i in stride(from: 0, to: iron.count, by: 4 * 97) {
            XCTAssertLessThanOrEqual(abs(Int(iron[i]) - Int(iron[i + 2])), 2)
        }
    }

    // MARK: Clean JPEGs

    /// A camera-style JPEG with GPS, EXIF and TIFF maker data, like the one AVFoundation hands over.
    private func jpegWithLocation(_ image: CGImage) throws -> Data {
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil))
        let properties: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 51.5007,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 0.1246,
                kCGImagePropertyGPSLongitudeRef: "W",
            ],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:11:15 18:47:00"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone"],
            kCGImagePropertyOrientation: 6,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    func testCleanPhotoHasNoGPSAndIsUprightAtMost2048() throws {
        let source = try jpegWithLocation(try testPhoto())
        XCTAssertTrue(ProofImageIO.hasLocation(source), "fixture must carry GPS")

        let clean = try ProofImageIO.cleanPhoto(from: source)
        XCTAssertFalse(ProofImageIO.hasLocation(clean.jpeg))
        let metadata = ProofImageIO.metadata(of: clean.jpeg)
        XCTAssertNil(metadata[kCGImagePropertyTIFFDictionary as String].flatMap { ($0 as? [String: Any])?[kCGImagePropertyTIFFMake as String] })
        XCTAssertNil((metadata[kCGImagePropertyExifDictionary as String] as? [String: Any])?[kCGImagePropertyExifDateTimeOriginal as String])
        // Orientation 6 (rotated 90°) is applied to the pixels: the 768 x 1024 photo comes out 1024 x 768.
        XCTAssertEqual(clean.image.width, 1024)
        XCTAssertEqual(clean.image.height, 768)
        XCTAssertLessThanOrEqual(max(clean.image.width, clean.image.height), 2048)
        XCTAssertNotEqual(metadata[kCGImagePropertyOrientation as String] as? Int, 6)
    }

    func testExportedCardJPEGHasNoGPSAndKeepsItsSize() throws {
        let photo = try ProofImageIO.cleanPhoto(from: try jpegWithLocation(try testPhoto())).image
        for size in ProofCardSize.allCases {
            let card = try ProofCardRenderer.render(photo: photo, summary: summary(), options: ProofCardOptions(size: size))
            let jpeg = try ProofImageIO.cardJPEG(card, size: size)
            XCTAssertFalse(ProofImageIO.hasLocation(jpeg), "\(size)")
            XCTAssertNil(ProofImageIO.metadata(of: jpeg)[kCGImagePropertyGPSDictionary as String])
            let decoded = try XCTUnwrap(ProofImageIO.decode(jpeg))
            XCTAssertEqual(decoded.width, 1080)
            XCTAssertEqual(decoded.height, Int(size.pixelSize.height))
        }
    }

    // MARK: Stamp, timestamp, stat row

    func testStampLines() {
        let t = Self.stampedAt
        XCTAssertEqual(ProofCardText.proofNumber(.stamped(proofNumber: 42, stampedAt: t, streakWeeks: 7, proofCount: 42)), "#042")
        XCTAssertEqual(ProofCardText.proofNumber(.stamped(proofNumber: 1000, stampedAt: t, streakWeeks: 7, proofCount: 42)), "#1000")
        XCTAssertEqual(ProofCardText.proofNumber(.pending(phoneTime: t)), "#---")
        XCTAssertEqual(ProofCardText.streakLine(.stamped(proofNumber: 42, stampedAt: t, streakWeeks: 7, proofCount: 42)), "7 WEEKS RUNNING")
        XCTAssertEqual(ProofCardText.streakLine(.stamped(proofNumber: 15, stampedAt: t, streakWeeks: 1, proofCount: 15)), "1 WEEK RUNNING")
        XCTAssertEqual(ProofCardText.streakLine(.stamped(proofNumber: 16, stampedAt: t, streakWeeks: 0, proofCount: 16)), "NEW STREAK")
        XCTAssertEqual(ProofCardText.streakLine(.stamped(proofNumber: 1, stampedAt: t, streakWeeks: 1, proofCount: 1)), "FIRST PROOF")
        XCTAssertEqual(ProofCardText.streakLine(.pending(phoneTime: t)), "PENDING")
        // The longest planned streak line fits the 164 px stamp column at 14 px.
        XCTAssertLessThanOrEqual(ProofTextRun(text: "99 WEEKS RUNNING", font: ProofCardFont.mono(14), tracking: 1).width, 164)
        XCTAssertGreaterThanOrEqual(ProofCardText.stampNumberSize("#10000"), 40)
    }

    func testTimestampIsServerTimeInTheSessionZone() {
        XCTAssertEqual(
            ProofCardText.timestamp(.stamped(proofNumber: 42, stampedAt: Self.stampedAt, streakWeeks: 7, proofCount: 42), timezone: "Europe/London"),
            "SUN 15 NOV 2026 · 18:47"
        )
        XCTAssertEqual(
            ProofCardText.timestamp(.pending(phoneTime: Self.stampedAt), timezone: "America/New_York"),
            "SUN 15 NOV 2026 · 13:47 · NOT STAMPED"
        )
    }

    func testStatRowValues() {
        let s = summary()
        XCTAssertEqual(ProofCardText.statCell(.sets, summary: s), .init(value: "18", unit: nil, label: "SETS", number: nil))
        XCTAssertEqual(ProofCardText.statCell(.total, summary: s).value, "6,240")
        XCTAssertEqual(ProofCardText.statCell(.total, summary: s).unit, "KG")
        XCTAssertEqual(ProofCardText.statCell(.time, summary: s).value, "1:12")
        XCTAssertEqual(ProofCardText.statCell(.topLift, summary: s).value, "140×5")
        XCTAssertEqual(ProofCardText.statCell(.topLift, summary: s).label, "BARBELL BENCH PRESS")
        XCTAssertEqual(ProofCardText.statCell(.total, summary: summary(unit: .lb, totalKg: 100)).value, "220")
        XCTAssertEqual(ProofCardText.topLiftWeight(kg: 102.5, unit: .kg), "102.5")
        XCTAssertEqual(ProofCardText.topLiftWeight(kg: 100, unit: .kg), "100")
        XCTAssertEqual(ProofCardText.duration(48 * 60 + 59), "0:48")
        XCTAssertEqual(ProofCardText.grouped(100_000), "100,000")
        XCTAssertEqual(ProofCardText.abbreviated(1_234_567), "1.2M")
    }

    func testBigTotalsFitTheColumn() {
        for (kg, unit) in [(6240.0, WeightUnit.kg), (12480, .kg), (45359.237, .lb), (2_000_000, .kg)] {
            let cell = ProofCardText.statCell(.total, summary: summary(unit: unit, totalKg: kg))
            let fitted = ProofCardText.fitStatValue(cell)
            XCTAssertLessThanOrEqual(fitted.width, 296, "\(kg) \(unit): \(fitted)")
        }
    }

    func testStatSelectionAlwaysHoldsThree() {
        var selection = ProofStatSelection()
        XCTAssertEqual(selection.row, [.sets, .total, .time])
        selection.pick(.topLift)
        XCTAssertEqual(selection.row, [.sets, .total, .topLift])
        selection.pick(.time)
        XCTAssertEqual(selection.row, [.sets, .total, .time])
        selection.pick(.sets)
        XCTAssertEqual(selection.row.count, 3)
        XCTAssertEqual(ProofStatSelection([.time, .time]).row.count, 3)
    }

    // MARK: From a session

    @MainActor
    func testSummaryFromSessionUsesWorkingSetsOnlyAndBestE1RM() throws {
        let container = Models.makeContainer(inMemory: true)
        let context = container.mainContext
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let session = WorkoutSession(routineId: nil, routineName: "Push A", startedAt: start, timezone: "Europe/London")
        context.insert(session)
        let exercise = SessionExercise(exerciseId: "barbell-bench-press", name: "Bench press", order: 0, targetSets: 3, targetReps: 5)
        context.insert(exercise)
        session.exercises.append(exercise)
        for (n, weight, reps, type) in [(1, 60.0, 10, SetType.warmup), (2, 100.0, 5, .working), (3, 90.0, 10, .working)] {
            let set = SessionSet(n: n, weightKg: weight, reps: reps, type: type)
            set.done = true
            context.insert(set)
            exercise.sets.append(set)
        }
        let card = ProofCardSummary(session: session, unit: .kg, stamp: .pending(phoneTime: start), now: start.addingTimeInterval(3000))
        XCTAssertEqual(card.setCount, 2)
        XCTAssertEqual(card.totalKg, 1400)
        XCTAssertEqual(card.duration, 3000)
        // 90 x 10 (e1RM 120) beats 100 x 5 (116.7); the warm-up never counts.
        XCTAssertEqual(card.topLift, ProofTopLift(exerciseName: "Bench press", weightKg: 90, reps: 10))
    }

    // MARK: Files and share

    func testProofStoreKeepsPhotoAndCardAndARetakeDropsTheCard() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProofStore(root: root)
        let clean = try ProofImageIO.cleanPhoto(from: try jpegWithLocation(try testPhoto()))
        XCTAssertEqual(ProofFeature.firstStep(sessionID: "s1", store: store, permission: .notDetermined), .permission(.notDetermined))
        XCTAssertEqual(ProofFeature.firstStep(sessionID: "s1", store: store, permission: .granted), .camera)

        try store.savePhoto(clean.jpeg, for: "s1")
        XCTAssertEqual(ProofFeature.firstStep(sessionID: "s1", store: store, permission: .granted), .editor)
        let photo = try XCTUnwrap(store.loadPhoto("s1"))

        let tapped = Self.stampedAt
        let jpeg = try ProofFeature.stamp(photo: photo, summary: summary(stamp: .pending(phoneTime: tapped)), options: ProofCardOptions(filter: .plate, size: .story), sessionID: "s1", tappedAt: tapped, store: store)
        XCTAssertEqual(store.cardData("s1"), jpeg)
        XCTAssertEqual(store.record("s1"), ProofStore.CardRecord(options: ProofCardOptions(filter: .plate, size: .story), stampTappedAt: tapped))
        XCTAssertEqual(ProofFeature.firstStep(sessionID: "s1", store: store), .saved)
        XCTAssertFalse(ProofImageIO.hasLocation(try Data(contentsOf: store.photoURL("s1"))))

        try store.savePhoto(clean.jpeg, for: "s1")
        XCTAssertFalse(store.hasCard("s1"), "a retake replaces the photo and drops the old card")
        store.remove("s1")
        XCTAssertFalse(store.hasPhoto("s1"))
    }

    func testPreferencesRememberTheLastChoice() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "proof-tests-\(UUID().uuidString)"))
        let preferences = ProofPreferences(defaults: defaults)
        XCTAssertFalse(preferences.usesBackCamera, "front camera the first time")
        XCTAssertFalse(preferences.timerOn)
        XCTAssertEqual(preferences.cardOptions, ProofCardOptions(filter: .iron, size: .feed))
        var options = ProofCardOptions(filter: .chalk, size: .story)
        options.stats.pick(.topLift)
        preferences.cardOptions = options
        preferences.usesBackCamera = true
        XCTAssertEqual(ProofPreferences(defaults: defaults).cardOptions, options)
        XCTAssertTrue(ProofPreferences(defaults: defaults).usesBackCamera)
    }

    func testPrivacyFirstMediaPreferenceDefaultsAndPersistence() throws {
        let suite = "proof-privacy-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ProofPreferences(defaults: defaults)
        XCTAssertTrue(preferences.keepCardsOnPhone)
        XCTAssertFalse(preferences.automaticallySaveCardsToPhotos)
        XCTAssertFalse(preferences.deleteOriginalAfterCard, "the original remains local for optional analysis and score sharing")

        preferences.keepCardsOnPhone = false
        preferences.automaticallySaveCardsToPhotos = true
        preferences.deleteOriginalAfterCard = true
        let reloaded = ProofPreferences(defaults: defaults)
        XCTAssertFalse(reloaded.keepCardsOnPhone)
        XCTAssertTrue(reloaded.automaticallySaveCardsToPhotos)
        XCTAssertTrue(reloaded.deleteOriginalAfterCard)
    }

    func testShareItemIsANamedJPEGFile() throws {
        XCTAssertEqual(ProofShareItem.fileName(proofNumber: 42), "pgym-proof-042.jpg")
        XCTAssertEqual(ProofShareItem.fileName(proofNumber: nil), "pgym-proof.jpg")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let item = try ProofShareItem(cardJPEG: Data([0xFF, 0xD8, 0xFF, 0xD9]), proofNumber: 7, directory: dir)
        XCTAssertEqual(item.fileURL.lastPathComponent, "pgym-proof-007.jpg")
        XCTAssertEqual(try Data(contentsOf: item.fileURL), Data([0xFF, 0xD8, 0xFF, 0xD9]))
    }

    func testCardModelCarriesNoScore() {
        let labels = Mirror(reflecting: summary()).children.compactMap(\.label).map { $0.lowercased() }
        for forbidden in ["score", "tip", "physique", "location", "latitude", "longitude"] {
            XCTAssertFalse(labels.contains { $0.contains(forbidden) }, forbidden)
        }
    }

    func testLogoPathsMatchTheTemplate() {
        let wordmark = ProofCardArt.wordmark.boundingBoxOfPath
        XCTAssertEqual(wordmark.minX, 0, accuracy: 0.5)
        XCTAssertEqual(wordmark.minY, 0, accuracy: 0.5)
        XCTAssertEqual(wordmark.maxX, 612, accuracy: 0.5) // 456 + 156
        XCTAssertEqual(wordmark.maxY, 200, accuracy: 0.5)
        let ring = ProofCardArt.markRing.boundingBoxOfPath
        XCTAssertLessThanOrEqual(ring.maxX, 300.5)
        XCTAssertGreaterThanOrEqual(ring.minX, -300.5)
        XCTAssertLessThan(ring.minY, -250, "the ring's large arc goes over the top")
    }

    // MARK: Sample cards for the pull request

    /// Writes four sample cards when PGYM_SAMPLE_DIR is set, for example:
    /// `TEST_RUNNER_PGYM_SAMPLE_DIR=$PWD/../docs/proof-card-samples xcodebuild -scheme PGYM ... test`.
    func testWriteSampleCards() throws {
        guard let dir = ProcessInfo.processInfo.environment["PGYM_SAMPLE_DIR"], !dir.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_PGYM_SAMPLE_DIR to write the sample cards")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let photo = try testPhoto()
        let samples: [(String, ProofCardOptions, ProofCardSummary)] = [
            ("iron-4x5", ProofCardOptions(filter: .iron, size: .feed), summary()),
            ("chalk-4x5-top-lift", ProofCardOptions(filter: .chalk, size: .feed, stats: ProofStatSelection([.sets, .total, .topLift])), summary(name: "Legs")),
            ("plate-9x16", ProofCardOptions(filter: .plate, size: .story), summary(name: "Upper body power day with heavy deadlift")),
            ("raw-9x16-pending", ProofCardOptions(filter: .raw, size: .story), summary(stamp: .pending(phoneTime: Self.stampedAt))),
        ]
        for (name, options, summary) in samples {
            let card = try ProofCardRenderer.render(photo: photo, summary: summary, options: options)
            try ProofImageIO.cardJPEG(card, size: options.size).write(to: folder.appendingPathComponent("pgym-card-\(name).jpg"))
        }
    }
}
