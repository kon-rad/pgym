import XCTest
@testable import PGYM

final class ExerciseCatalogueTests: XCTestCase {
    private var catalogue: ExerciseCatalogue!
    private var library: ExerciseLibrary!

    override func setUpWithError() throws {
        catalogue = try ExerciseCatalogue.load()
        library = ExerciseLibrary(catalogue: catalogue)
    }

    // MARK: Decoding

    func testBundledCatalogueDecodes() throws {
        XCTAssertEqual(catalogue.version, 1)
        XCTAssertGreaterThanOrEqual(catalogue.exercises.count, 120, "the card asks for at least 120 exercises")
        XCTAssertEqual(ExerciseCatalogue.bundled.exercises.count, catalogue.exercises.count)
    }

    func testCatalogueHasNoDuplicateIDs() {
        XCTAssertEqual(catalogue.duplicateIDs, [])
        XCTAssertEqual(Set(catalogue.exercises.map(\.id)).count, catalogue.exercises.count)
    }

    func testCatalogueHasNoDuplicateNames() {
        let names = catalogue.exercises.map { ExerciseLibrary.words($0.name).joined(separator: " ") }
        XCTAssertEqual(Set(names).count, names.count)
    }

    func testIDsAreStableSlugs() {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        for exercise in catalogue.exercises {
            XCTAssertTrue(exercise.id.unicodeScalars.allSatisfy(allowed.contains), exercise.id)
            XCTAssertFalse(exercise.id.hasPrefix(CustomExercise.idPrefix), "catalogue IDs never look custom")
            XCTAssertFalse(exercise.name.isEmpty)
            XCTAssertFalse(exercise.isCustom)
        }
    }

    func testEveryMuscleGroupHasExercises() {
        for group in MuscleGroup.allCases {
            XCTAssertGreaterThanOrEqual(library.exercises(in: group).count, 10, group.label)
        }
    }

    func testDuplicateIDsAreDetected() throws {
        let json = """
        {"version": 1, "exercises": [
          {"id": "a", "name": "A", "muscleGroup": "chest", "equipment": "barbell"},
          {"id": "a", "name": "A again", "muscleGroup": "back", "equipment": "cable"}
        ]}
        """
        let bad = try ExerciseCatalogue.decode(Data(json.utf8))
        XCTAssertEqual(bad.duplicateIDs, ["a"])
    }

    func testUnknownMuscleGroupFailsToDecode() {
        let json = #"{"version": 1, "exercises": [{"id": "a", "name": "A", "muscleGroup": "neck", "equipment": "barbell"}]}"#
        XCTAssertThrowsError(try ExerciseCatalogue.decode(Data(json.utf8)))
    }

    // MARK: Search

    func testSearchFindsBench() {
        let ids = library.search("bench").map(\.id)
        XCTAssertFalse(ids.isEmpty)
        for expected in ["barbell-bench-press", "dumbbell-bench-press", "incline-barbell-bench-press", "bench-dip"] {
            XCTAssertTrue(ids.contains(expected), "bench should find \(expected)")
        }
        for exercise in library.search("bench") {
            XCTAssertTrue(exercise.name.localizedCaseInsensitiveContains("bench"), exercise.name)
        }
    }

    func testSearchFindsRow() {
        let found = library.search("row")
        let ids = found.map(\.id)
        for expected in ["barbell-row", "dumbbell-row", "seated-cable-row", "t-bar-row", "upright-row"] {
            XCTAssertTrue(ids.contains(expected), "row should find \(expected)")
        }
        // Word starts only: "row" must not match inside another word.
        XCTAssertFalse(ids.contains("rope-pushdown"))
        XCTAssertFalse(ids.contains("landmine-rotation"))
    }

    func testSearchIsCaseAndAccentInsensitive() {
        XCTAssertEqual(library.search("BENCH").map(\.id), library.search("bench").map(\.id))
        XCTAssertEqual(library.search("  Row ").map(\.id), library.search("row").map(\.id))
        XCTAssertTrue(library.search("roumanian").isEmpty)
        XCTAssertTrue(library.search("rómanian").map(\.id).contains("romanian-deadlift"))
    }

    func testSearchMatchesEveryWordAsAPrefix() {
        let ids = library.search("incl bench").map(\.id)
        XCTAssertTrue(ids.contains("incline-barbell-bench-press"))
        XCTAssertTrue(ids.contains("incline-dumbbell-bench-press"))
        XCTAssertFalse(ids.contains("barbell-bench-press"))
    }

    func testSearchRanksNamesStartingWithTheQueryFirst() {
        XCTAssertEqual(library.search("bench").first?.id, "bench-dip")
        XCTAssertEqual(library.search("deadlift").first?.id, "deadlift")
    }

    func testSearchFallsBackToEquipmentAndGroup() {
        let kettlebell = library.search("kettlebell")
        XCTAssertTrue(kettlebell.contains { $0.id == "kettlebell-swing" })
        // "Chest" is a group label, not in any name: still finds chest exercises.
        let chest = library.search("chest")
        XCTAssertTrue(chest.contains { $0.id == "pec-deck" })
    }

    func testSearchWithinAGroup() {
        let backRows = library.search("row", in: .back)
        XCTAssertTrue(backRows.allSatisfy { $0.muscleGroup == .back })
        XCTAssertFalse(backRows.contains { $0.id == "upright-row" }, "upright row is shoulders")
    }

    func testSearchFindsCustomExercises() {
        let custom = Exercise(id: "custom-1", name: "Sled push", muscleGroup: .legs, equipment: .other, isCustom: true)
        let withCustom = ExerciseLibrary(catalogue: catalogue, custom: [custom])
        XCTAssertEqual(withCustom.search("sled").map(\.id), ["custom-1"])
        XCTAssertEqual(withCustom.name(for: "custom-1"), "Sled push")
        XCTAssertEqual(withCustom.name(for: "nope"), "Unknown exercise")
    }

    func testEmptySearchReturnsEverything() {
        XCTAssertEqual(library.search("").count, catalogue.exercises.count)
    }

    // MARK: Recents

    func testRecentsAreNewestFirstWithoutRepeatsAndCapped() throws {
        let suite = "pgym.tests.recents.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let recents = RecentExercises(defaults: defaults)

        XCTAssertEqual(recents.ids, [])
        recents.record("deadlift")
        recents.record("back-squat")
        recents.record("deadlift")
        XCTAssertEqual(recents.ids, ["deadlift", "back-squat"])

        for exercise in catalogue.exercises.prefix(20) { recents.record(exercise.id) }
        XCTAssertEqual(recents.ids.count, RecentExercises.limit)

        recents.record("not-an-exercise")
        XCTAssertFalse(recents.exercises(in: library).contains { $0.id == "not-an-exercise" })
    }
}
