import Foundation
import Observation

/// Onboarding, views B1 to B5. Card I3.
///
/// Four screens after pgym-flow-spec.md's cut: B1 Weekly goal (with B5 Units as a one-tap chip),
/// B2 Gym days and time, B3 Reminders, B4 First routine. Every answer is saved on the phone as it
/// changes, so quitting mid-way resumes at the same step; the last step writes everything to
/// `users/{uid}` and schedules the reminders.
enum OnboardingFeature {
    /// The view IDs from pgym-app-views.md this feature draws.
    static let viewIDs = ["B1", "B2", "B3", "B4", "B5"]
}

/// What the user has answered so far. Saved after every change.
struct OnboardingDraft: Codable, Equatable, Sendable {
    enum Step: Int, Codable, CaseIterable, Sendable {
        case goal, days, reminders, routine

        /// "STEP 1 OF 4".
        var number: Int { rawValue + 1 }
        static var count: Int { allCases.count }

        var viewID: String {
            switch self {
            case .goal: "B1"
            case .days: "B2"
            case .reminders: "B3"
            case .routine: "B4"
            }
        }
    }

    enum ReminderAnswer: String, Codable, Sendable {
        case notAsked, allowed, declined, skipped
    }

    var step: Step = .goal
    /// Nil until the user taps a number: the commitment depends on choosing (flow spec, B1).
    var goal: Int?
    var days: Set<Weekday> = []
    var time: ReminderTime = .default
    var units: NewUserProfile.Units
    var reminders: ReminderAnswer = .notAsked
    /// The picked starter's `StarterRoutine.id`. Nil until the user picks; B4 pre-selects the one
    /// that fits the goal.
    var starterID: String?
    /// "Build my own" on B4: no starter is written; F3 (card I4) takes over.
    var buildOwn = false
}

extension StarterRoutine {
    /// The shipped starter with this ID, for a draft read back from disk.
    static func withID(_ id: String?) -> StarterRoutine? {
        all.first { $0.id == id }
    }
}

/// Where the draft lives between launches, one per user.
@MainActor
protocol OnboardingDraftStore: AnyObject {
    func load(uid: String) -> OnboardingDraft?
    func save(_ draft: OnboardingDraft, uid: String)
    func clear(uid: String)
}

@MainActor
final class InMemoryOnboardingDraftStore: OnboardingDraftStore {
    private(set) var drafts: [String: OnboardingDraft] = [:]

    func load(uid: String) -> OnboardingDraft? { drafts[uid] }
    func save(_ draft: OnboardingDraft, uid: String) { drafts[uid] = draft }
    func clear(uid: String) { drafts[uid] = nil }
}

@MainActor
final class UserDefaultsOnboardingDraftStore: OnboardingDraftStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(_ uid: String) -> String { "pgym.onboarding.v1.\(uid)" }

    func load(uid: String) -> OnboardingDraft? {
        guard let data = defaults.data(forKey: key(uid)) else { return nil }
        return try? JSONDecoder().decode(OnboardingDraft.self, from: data)
    }

    func save(_ draft: OnboardingDraft, uid: String) {
        if let data = try? JSONEncoder().encode(draft) {
            defaults.set(data, forKey: key(uid))
        }
    }

    func clear(uid: String) {
        defaults.removeObject(forKey: key(uid))
    }
}

/// The one view model for B1 to B5.
@MainActor
@Observable
final class OnboardingModel {
    /// Every change goes through `update`, which saves it.
    private(set) var draft: OnboardingDraft
    private(set) var isSaving = false
    private(set) var errorText: String?
    /// Moves forward or back, for the screen transition's direction.
    private(set) var movingForward = true

    private let uid: String
    private let store: OnboardingDraftStore

    private func update(_ change: (inout OnboardingDraft) -> Void) {
        var copy = draft
        change(&copy)
        guard copy != draft else { return }
        draft = copy
        store.save(copy, uid: uid)
    }

    init(uid: String, startingUnits: NewUserProfile.Units, store: OnboardingDraftStore) {
        self.uid = uid
        self.store = store
        draft = store.load(uid: uid) ?? OnboardingDraft(units: startingUnits)
    }

    var step: OnboardingDraft.Step { draft.step }

    // MARK: B1 Weekly goal

    /// The commitment sentence, or nil before a number is picked.
    var commitment: String? { draft.goal.map(OnboardingCopy.Goal.commitment) }

    var canLockIn: Bool { draft.goal != nil }

    func pickGoal(_ goal: Int) {
        guard GoalPolicy.range.contains(goal) else { return }
        guard draft.goal != goal else { return }
        // A new goal brings the matching pre-filled spread to B2 and the fitting starter to B4.
        update {
            $0.goal = goal
            $0.days = GoalPolicy.defaultDays(for: goal)
            $0.starterID = nil
        }
    }

    /// B5: one tap flips kg and lb.
    func toggleUnits() {
        update { $0.units = $0.units == .kg ? .lb : .kg }
    }

    func lockIn() {
        guard let goal = draft.goal else { return }
        if draft.days.isEmpty { update { $0.days = GoalPolicy.defaultDays(for: goal) } }
        go(to: .days)
    }

    // MARK: B2 Gym days and time

    var goal: Int { draft.goal ?? GoalPolicy.range.lowerBound }
    var pickedCount: Int { draft.days.count }
    var daysMatchGoal: Bool { draft.days.count == goal }
    var isOverGoal: Bool { draft.days.count > goal }

    /// "2 of 3 picked".
    var counterText: String { OnboardingCopy.Days.counter(picked: pickedCount, goal: goal) }

    func toggle(_ day: Weekday) {
        update {
            if $0.days.contains(day) {
                $0.days.remove(day)
            } else {
                $0.days.insert(day)
            }
        }
    }

    func setTime(_ time: ReminderTime) {
        update { $0.time = time }
    }

    func continueFromDays() {
        guard daysMatchGoal else { return }
        go(to: .reminders)
    }

    /// "Change the goal": back to B1.
    func changeGoal() {
        go(to: .goal)
    }

    // MARK: B3 Reminders

    /// B3's preview line, built from the real reminder copy.
    var previewTitle: String {
        ReminderCopy.title(routine: selectedStarter.workouts.first?.name, time: draft.time.formatted())
    }

    var previewBody: String {
        ReminderCopy.progress(done: 0, goal: goal)
    }

    /// Turn on reminders: the iOS prompt, then B4 whatever the answer (flow spec, B3).
    func turnOnReminders(_ scheduler: ReminderScheduler) async {
        let granted = await scheduler.requestAuthorization()
        update { $0.reminders = granted ? .allowed : .declined }
        go(to: .routine)
    }

    func skipReminders() {
        update { $0.reminders = .skipped }
        go(to: .routine)
    }

    /// "Reminders are off. Turn them on in Settings any time." after a no.
    var showsRemindersDeclined: Bool { draft.reminders == .declined }

    // MARK: B4 First routine

    var suggestedStarter: StarterRoutine { StarterRoutine.suggested(forGoal: goal) }
    var selectedStarter: StarterRoutine { StarterRoutine.withID(draft.starterID) ?? suggestedStarter }

    func pickStarter(_ starter: StarterRoutine) {
        update {
            $0.starterID = starter.id
            $0.buildOwn = false
        }
    }

    // MARK: Navigation

    func back() {
        guard let previous = OnboardingDraft.Step(rawValue: draft.step.rawValue - 1) else { return }
        go(to: previous)
    }

    private func go(to step: OnboardingDraft.Step) {
        movingForward = step.rawValue > draft.step.rawValue
        errorText = nil
        update { $0.step = step }
    }

    // MARK: Finish

    /// The plan the user built. Nil until B1 and B2 agree.
    var plan: WeeklyPlan? {
        guard let goal = draft.goal else { return nil }
        let plan = WeeklyPlan(goal: goal, days: draft.days, time: draft.time)
        return plan.isValid ? plan : nil
    }

    /// B4's main button ("Use this routine") or "Build my own": saves everything to `users/{uid}`,
    /// copies the starter into the phone's routines (card I4's store; its sync sends them to
    /// Firestore), schedules the reminders, then Today.
    func finish(
        buildOwn: Bool = false,
        session: AppSession,
        scheduler: ReminderScheduler,
        routines routineStore: RoutineStore
    ) async {
        guard let plan, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        errorText = nil
        update { $0.buildOwn = buildOwn }

        let starter = selectedStarter
        let settings = OnboardingSettings(plan: plan, units: draft.units, timezone: session.userTimezone)
        do {
            try await session.completeOnboarding(settings)
        } catch {
            errorText = OnboardingCopy.couldNotSave
            return
        }
        // After the save, so a failed save that is retried never adopts the starter twice. If the
        // local write fails the user still lands on the tabs, where F2 offers the starters again.
        if !buildOwn, session.route == .main {
            _ = try? routineStore.adopt(starter)
        }

        var facts = ReminderFacts()
        facts.routineNames = buildOwn ? [] : starter.workouts.map(\.name)
        facts.unitsLabel = draft.units.rawValue
        facts.weekToLock = (session.profile?.streakWeeks ?? 0) + 1
        facts.nextProof = (session.profile?.proofCount ?? 0) + 1
        // Skipped means off; a declined prompt stays on in PGYM so reminders start if the user
        // later allows them in iOS Settings.
        let wantsReminders = draft.reminders == .allowed || draft.reminders == .declined
        await scheduler.setFirstPlan(plan, remindersEnabled: wantsReminders, facts: facts)
        store.clear(uid: uid)
    }
}
