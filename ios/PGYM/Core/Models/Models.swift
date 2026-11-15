import Foundation
import SwiftData

/// SwiftData models mirroring the Firestore documents in pgym-architecture.md.
/// Card I4 adds routines and custom exercises; card I5 adds sessions, their exercises and sets, and
/// the phone's copy of the per-exercise bests.
enum Models {
    /// Every persistent type, for the app's container and the tests' in-memory containers.
    static let all: [any PersistentModel.Type] = [
        Routine.self,
        CustomExercise.self,
        WorkoutSession.self,
        SessionExercise.self,
        SessionSet.self,
        ExerciseStat.self,
    ]

    static var schema: Schema { Schema(all) }

    /// The app's on-phone store. If the store cannot open (a broken migration in a dev build), the app
    /// still starts on an in-memory store rather than crash.
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        if let container = try? ModelContainer(for: schema, configurations: [config]) {
            return container
        }
        return inMemoryFallback()
    }

    /// A store in a file of its own. Tests use it to close and reopen the store, the way a relaunch does.
    static func makeContainer(url: URL) throws -> ModelContainer {
        let config = ModelConfiguration(schema: schema, url: url)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private static func inMemoryFallback() -> ModelContainer {
        let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        // An in-memory store with a valid schema cannot fail to open.
        return try! ModelContainer(for: schema, configurations: [fallback])
    }
}
