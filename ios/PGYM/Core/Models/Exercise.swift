import Foundation

/// Muscle groups for the catalogue and the D3 sections. The six groups are the copy deck's list
/// (pgym-app-copy.md, D3 "Chest, Back, Shoulders, Arms, Legs, Core"), in that order.
enum MuscleGroup: String, Codable, CaseIterable, Identifiable, Sendable {
    case chest, back, shoulders, arms, legs, core

    var id: String { rawValue }

    var label: String {
        switch self {
        case .chest: "Chest"
        case .back: "Back"
        case .shoulders: "Shoulders"
        case .arms: "Arms"
        case .legs: "Legs"
        case .core: "Core"
        }
    }
}

enum Equipment: String, Codable, CaseIterable, Identifiable, Sendable {
    case barbell, dumbbell, kettlebell, machine, cable, bodyweight, band, ezBar, smithMachine, trapBar, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .barbell: "Barbell"
        case .dumbbell: "Dumbbell"
        case .kettlebell: "Kettlebell"
        case .machine: "Machine"
        case .cable: "Cable"
        case .bodyweight: "Bodyweight"
        case .band: "Band"
        case .ezBar: "EZ bar"
        case .smithMachine: "Smith machine"
        case .trapBar: "Trap bar"
        case .other: "Other"
        }
    }
}

/// One exercise, from the bundled catalogue or made by the user. Names only: no descriptions.
struct Exercise: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let muscleGroup: MuscleGroup
    let equipment: Equipment
    /// True for exercises the user made in D3. Not in the JSON.
    var isCustom: Bool = false

    private enum CodingKeys: String, CodingKey {
        case id, name, muscleGroup, equipment
    }

    init(id: String, name: String, muscleGroup: MuscleGroup, equipment: Equipment, isCustom: Bool = false) {
        self.id = id
        self.name = name
        self.muscleGroup = muscleGroup
        self.equipment = equipment
        self.isCustom = isCustom
    }

    /// "CHEST · BARBELL" under the name in D3 and F3.
    var meta: String { "\(muscleGroup.label) · \(equipment.label)" }
}

/// The exercise catalogue that ships in the app (`Resources/exercise-catalogue.json`).
/// pgym-architecture.md: "The exercise catalogue (names, muscle groups) ships inside the app as a
/// JSON file; custom exercises live under the user."
struct ExerciseCatalogue: Decodable, Sendable {
    static let resourceName = "exercise-catalogue"

    let version: Int
    let exercises: [Exercise]

    init(version: Int, exercises: [Exercise]) {
        self.version = version
        self.exercises = exercises
    }

    enum LoadError: Error, Equatable {
        case missingResource
    }

    static func load(from bundle: Bundle = .pgymApp) throws -> ExerciseCatalogue {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw LoadError.missingResource
        }
        return try decode(Data(contentsOf: url))
    }

    static func decode(_ data: Data) throws -> ExerciseCatalogue {
        try JSONDecoder().decode(ExerciseCatalogue.self, from: data)
    }

    /// Loaded once. An unreadable file is a build mistake that the tests catch; the app falls back
    /// to an empty catalogue rather than crash, and custom exercises still work.
    static let bundled: ExerciseCatalogue = (try? load()) ?? ExerciseCatalogue(version: 0, exercises: [])

    /// IDs that appear more than once. Empty for a valid catalogue.
    var duplicateIDs: [String] {
        var seen = Set<String>()
        var dupes: [String] = []
        for exercise in exercises where !seen.insert(exercise.id).inserted {
            dupes.append(exercise.id)
        }
        return dupes
    }
}

private final class PGYMBundleToken {}

extension Bundle {
    /// The app bundle, also when code runs inside the hosted unit-test bundle.
    static var pgymApp: Bundle { Bundle(for: PGYMBundleToken.self) }
}

/// The catalogue plus the user's custom exercises, with lookup and search. Value type, cheap to rebuild
/// when the custom list changes.
struct ExerciseLibrary: Sendable {
    let exercises: [Exercise]
    private let byID: [String: Exercise]

    init(catalogue: ExerciseCatalogue = .bundled, custom: [Exercise] = []) {
        let all = catalogue.exercises + custom
        exercises = all
        var map: [String: Exercise] = [:]
        for exercise in all where map[exercise.id] == nil {
            map[exercise.id] = exercise
        }
        byID = map
    }

    func exercise(id: String) -> Exercise? { byID[id] }

    /// Display name for an ID; an unknown ID (an exercise from another phone not synced yet) shows as such.
    func name(for id: String) -> String { byID[id]?.name ?? "Unknown exercise" }

    /// Exercises of one group, sorted by name.
    func exercises(in group: MuscleGroup) -> [Exercise] {
        exercises.filter { $0.muscleGroup == group }.sorted(by: Self.byName)
    }

    /// Search by name, muscle group or equipment. Case and accent insensitive; every word typed must
    /// start a word of the exercise ("inc db" does not match, "incl bench" does). Name matches rank
    /// first, then names that start with the query, then alphabetical.
    func search(_ query: String, in group: MuscleGroup? = nil) -> [Exercise] {
        let tokens = Self.words(query)
        let pool = group.map { g in exercises.filter { $0.muscleGroup == g } } ?? exercises
        guard !tokens.isEmpty else { return pool.sorted(by: Self.byName) }
        let joinedQuery = tokens.joined(separator: " ")

        var scored: [(Exercise, Int)] = []
        for exercise in pool {
            let nameWords = Self.words(exercise.name)
            let extraWords = Self.words(exercise.muscleGroup.label) + Self.words(exercise.equipment.label)
            let matchesName = tokens.allSatisfy { t in nameWords.contains { $0.hasPrefix(t) } }
            let matchesAny = matchesName
                || tokens.allSatisfy { t in (nameWords + extraWords).contains { $0.hasPrefix(t) } }
            guard matchesAny else { continue }
            let score: Int
            if nameWords.joined(separator: " ").hasPrefix(joinedQuery) {
                score = 0
            } else if matchesName {
                score = 1
            } else {
                score = 2
            }
            scored.append((exercise, score))
        }
        return scored
            .sorted { a, b in a.1 != b.1 ? a.1 < b.1 : Self.byName(a.0, b.0) }
            .map(\.0)
    }

    static func byName(_ a: Exercise, _ b: Exercise) -> Bool {
        a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }

    /// Lower-cased, accent-free words; hyphens and apostrophes split or vanish ("Push-up" is "push up",
    /// "Farmer's" is "farmers").
    static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
