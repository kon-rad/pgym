import SwiftData
import SwiftUI

/// The full-screen session, views D1 to D5 (card I5). The camera and card (D6 onward) are card I6;
/// D11 Session complete (card I7) follows in the same cover, so Stamp it hands over without a flash.
///
/// The session cover is driven by the data, not by a flag: whenever a draft that has not ended is on
/// the phone, D2 is shown over the tabs. So Start session only has to create the draft, and a
/// session that was open when the app was killed opens again by itself on the next launch.
enum SessionFeature {
    /// Starts a session from `routine` (nil for Empty session) and queues it for sync.
    @MainActor
    static func start(_ routine: Routine?, context: ModelContext, sync: SessionSyncQueue) {
        let custom = (try? CustomExerciseStore(context: context).all())?.map(\.exercise) ?? []
        _ = try? SessionStore(context: context).start(routine: routine, library: ExerciseLibrary(custom: custom))
        sync.requestSync()
    }
}

/// Presents D2 while a draft is open, then D11 for the session that just ended with a proof.
struct SessionHost: ViewModifier {
    @Query(
        filter: #Predicate<WorkoutSession> { $0.statusRaw == "draft" && $0.endedAt == nil },
        sort: \WorkoutSession.startedAt,
        order: .reverse
    )
    private var active: [WorkoutSession]

    @Environment(\.modelContext) private var context
    @Environment(SessionSyncQueue.self) private var sync
    @Environment(NetworkMonitor.self) private var network
    @Environment(ProofServices.self) private var proofs
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsCover: Bool { !active.isEmpty || proofs.completedSessionID != nil }

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: Binding(get: { showsCover }, set: { _ in })) {
                Group {
                    if let session = active.first {
                        ActiveSessionScreen(session: session, onFinishForProof: { ended in
                            proofs.sessionEndedWithProof(ended.id)
                            sync.requestSync()
                        })
                    } else if let completed = proofs.completedSessionID {
                        SessionCompleteScreen(sessionID: completed) {
                            proofs.finishCompletionFlow(sessionID: completed)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    } else {
                        Color.ink.ignoresSafeArea()
                    }
                }
                .animation(Animation.pgymSpring(reduceMotion: reduceMotion), value: proofs.completedSessionID)
                .environment(sync)
                .environment(network)
                .environment(proofs)
                .modelContext(context)
                .preferredColorScheme(.dark)
            }
            .onChange(of: showsCover) { _, shown in
                guard !shown else { return }
                // The cover is closing: tidy discarded sessions Firestore never had, once nothing shows them.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    try? SessionStore(context: context).purgeDiscarded()
                    sync.requestSync()
                }
            }
    }
}

extension View {
    /// D2 over this view whenever a session is open.
    func sessionHost() -> some View { modifier(SessionHost()) }
}
