import Foundation

/// The Recent section of D3: exercise IDs, newest first, no repeats. Kept in UserDefaults because it
/// is a convenience list for this phone, not user data that needs to sync.
struct RecentExercises {
    static let key = "pgym.recentExerciseIDs"
    static let limit = 8

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var ids: [String] { defaults.stringArray(forKey: Self.key) ?? [] }

    func record(_ exerciseID: String) {
        var list = ids.filter { $0 != exerciseID }
        list.insert(exerciseID, at: 0)
        defaults.set(Array(list.prefix(Self.limit)), forKey: Self.key)
    }

    /// Recent exercises that still exist (a deleted custom exercise drops out).
    func exercises(in library: ExerciseLibrary) -> [Exercise] {
        ids.compactMap(library.exercise(id:))
    }
}
