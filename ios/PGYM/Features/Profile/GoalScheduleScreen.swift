import DesignSystem
import SwiftUI

/// F4 Goal and schedule: weekly goal, gym days and reminder time. A new goal or new days start next
/// Monday (the commitment rule; `PlanSchedule`); the time moves at once. Saved on the phone first, so
/// it works offline, then to `users/{uid}`.
struct GoalScheduleScreen: View {
    static let viewID = "F4"

    @Environment(AppSession.self) private var session
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var draft: WeeklyPlan?
    @State private var saving = false
    @State private var note: String?
    @State private var savedTick = 0

    private var calendar: PlanCalendar { services.reminders.calendar }
    private var schedule: PlanSchedule? { services.reminders.state.schedule }
    private var thisWeek: WeekKey { calendar.weekKey(for: .now) }

    /// What the user last chose: the pending change if there is one.
    private var stored: WeeklyPlan {
        schedule?.latest ?? session.profile?.plan
            ?? WeeklyPlan(goal: 3, days: GoalPolicy.defaultDays(for: 3), time: .default)
    }

    private var currentGoal: Int { schedule?.plan(for: thisWeek).goal ?? stored.goal }

    var body: some View {
        let plan = draft ?? stored
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.grid(6)) {
                ScreenTitle(text: ProfileCopy.goalAndSchedule, size: 44)
                goalSection(plan)
                daysSection(plan)
                TimeCard(time: plan.time, label: ProfileCopy.reminderTime, identifier: "f4.time") { time in
                    var next = plan
                    next.time = time
                    draft = next
                }
                if let note {
                    InlineNote(text: note, tone: .info, identifier: "f4.note")
                }
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.top, Spacing.grid(2))
            .padding(.bottom, Spacing.grid(8))
        }
        .safeAreaInset(edge: .bottom) {
            LoadingPrimaryButton(title: ProfileCopy.save, isLoading: saving, identifier: "f4.save") {
                Task { await save(plan) }
            }
            .disabled(!plan.isValid || plan == stored || saving)
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.bottom, Spacing.grid(2))
        }
        .background(Color.ink.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: savedTick)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.\(Self.viewID)")
    }

    // MARK: Goal

    private func goalSection(_ plan: WeeklyPlan) -> some View {
        VStack(alignment: .leading, spacing: Spacing.grid(3)) {
            SectionLabel(ProfileCopy.weeklyGoal)
            HStack(spacing: Spacing.grid(2)) {
                ForEach(Array(GoalPolicy.range), id: \.self) { goal in
                    Button {
                        var next = plan
                        next.goal = goal
                        withAnimation(Animation.pgymSpring(reduceMotion: reduceMotion)) { draft = next }
                    } label: {
                        Text("\(goal)")
                            .font(.pgym(.data, size: 24))
                            .foregroundStyle(plan.goal == goal ? Color.ink : Color.chalk)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.setCell, style: .continuous)
                                    .fill(plan.goal == goal ? Color.plate : Color.iron)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.setCell, style: .continuous)
                                    .strokeBorder(plan.goal == goal ? Color.plate : Color.rail, lineWidth: Stroke.border)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(goal) days a week")
                    .accessibilityAddTraits(plan.goal == goal ? [.isButton, .isSelected] : .isButton)
                    .accessibilityIdentifier("f4.goal.\(goal)")
                }
            }
            Text(ProfileCopy.goalHint(current: currentGoal))
                .pgymText(.body, size: 15)
                .foregroundStyle(Color.bone)
                .fixedSize(horizontal: false, vertical: true)
            if let schedule, let pending = schedule.pending, let from = schedule.pendingFrom {
                Text(ProfileCopy.pending(from: Self.mondayLabel(calendar.startOfWeek(from), calendar: calendar), goal: pending.goal))
                    .pgymText(.body, size: 15)
                    .foregroundStyle(Color.chalk)
                    .accessibilityIdentifier("f4.pending")
            }
        }
    }

    static func mondayLabel(_ date: Date, calendar: PlanCalendar) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.wide).day().month(.abbreviated)
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }

    // MARK: Days

    private func daysSection(_ plan: WeeklyPlan) -> some View {
        VStack(alignment: .leading, spacing: Spacing.grid(3)) {
            SectionLabel(ProfileCopy.gymDays)
            HStack(spacing: Spacing.grid(1)) {
                ForEach(Weekday.allCases, id: \.self) { day in
                    DayToggle(day: day, isOn: plan.days.contains(day), identifierPrefix: "f4") {
                        var next = plan
                        if next.days.contains(day) { next.days.remove(day) } else { next.days.insert(day) }
                        draft = next
                    }
                }
            }
            if plan.days.count > plan.goal {
                InlineNote(text: ProfileCopy.tooMany(goal: plan.goal), identifier: "f4.tooMany")
            } else if plan.days.count < plan.goal {
                Text(ProfileCopy.pickMore(plan.goal - plan.days.count))
                    .pgymText(.body, size: 15)
                    .foregroundStyle(Color.steel)
            }
        }
    }

    // MARK: Save

    private func save(_ plan: WeeklyPlan) async {
        guard plan.isValid else { return }
        saving = true
        defer { saving = false }
        await services.reminders.changePlan(plan)
        do {
            try await session.updatePlan(services.reminders.state.schedule?.latest ?? plan)
            savedTick += 1
            draft = nil
            dismiss()
        } catch {
            // The phone already has it and the reminders follow it; Firestore gets it later.
            note = ProfileCopy.savedOffline
            draft = nil
        }
    }
}
