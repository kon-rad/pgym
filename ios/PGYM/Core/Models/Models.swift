import SwiftData

/// SwiftData models mirroring the Firestore documents in pgym-architecture.md.
/// Card I4 adds routines and custom exercises; card I5 adds sessions.
enum Models {
    /// Every persistent type, for the app's container and the tests' in-memory containers.
    static let all: [any PersistentModel.Type] = [Routine.self, CustomExercise.self]

    static var schema: Schema { Schema(all) }

    /// The app's on-phone store. If the store cannot open (a broken migration in a dev build), the app
    /// still starts on an in-memory store rather than crash.
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        if let container = try? ModelContainer(for: schema, configurations: [config]) {
            return container
        }
        let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        // An in-memory store with a valid schema cannot fail to open.
        return try! ModelContainer(for: schema, configurations: [fallback])
    }
}
