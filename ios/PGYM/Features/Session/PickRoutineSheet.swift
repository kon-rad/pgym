import DesignSystem
import SwiftData
import SwiftUI

/// The routine that runs when the user taps Start session: the one after the routine of the last
/// session in F2 order, wrapping round; the first routine when nothing has been done yet.
enum NextUp {
    static func routine(in routines: [Routine], lastRoutineID: String?) -> Routine? {
        guard !routines.isEmpty else { return nil }
        guard let lastRoutineID, let index = routines.firstIndex(where: { $0.id == lastRoutineID }) else {
            return routines.first
        }
        return routines[(index + 1) % routines.count]
    }

    /// When each routine was last started, from the phone's history.
    static func lastDone(_ sessions: [WorkoutSession]) -> [String: Date] {
        var map: [String: Date] = [:]
        for session in sessions where session.status != .discarded {
            guard let id = session.routineId else { continue }
            if (map[id] ?? .distantPast) < session.startedAt { map[id] = session.startedAt }
        }
        return map
    }

    /// The routine of the most recent session that had one.
    static func lastRoutineID(_ sessions: [WorkoutSession]) -> String? {
        sessions
            .filter { $0.status != .discarded && $0.routineId != nil }
            .max { $0.startedAt < $1.startedAt }?
            .routineId
    }

    /// "Thursday" within the last week, "12 Nov" before that, "today" for today.
    static func dayLabel(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "today" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days < 7 { return date.formatted(.dateTime.weekday(.wide)) }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}

/// D1 Pick routine: change what this session runs, off the main path. Next up first, the other
/// routines in F2 order, then Empty session. One tap on any row starts the session and closes the sheet.
struct PickRoutineSheet: View {
    static let viewID = "D1"

    let onPick: (Routine?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(RoutineStore.activeDescriptor) private var routines: [Routine]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @State private var pickTick = 0

    var body: some View {
        let lastDone = NextUp.lastDone(sessions)
        let next = NextUp.routine(in: routines, lastRoutineID: NextUp.lastRoutineID(sessions))
        let others = routines.filter { $0.id != next?.id }

        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.cardGap) {
                HStack(alignment: .firstTextBaseline) {
                    Text(SessionCopy.pickTitle)
                        .pgymText(.display, size: 44)
                        .foregroundStyle(Color.chalk)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button(SessionCopy.cancel) { dismiss() }
                        .font(.pgym(.bodyMedium, size: 17))
                        .foregroundStyle(Color.bone)
                        .frame(minHeight: Spacing.touchTargetMin)
                        .accessibilityIdentifier("d1.cancel")
                }

                if let next {
                    SectionLabel(SessionCopy.nextUp)
                    row(next, lastDone: lastDone[next.id], highlighted: true)
                }

                if !others.isEmpty {
                    SectionLabel(SessionCopy.otherRoutines).padding(.top, Spacing.grid(2))
                    ForEach(others) { routine in
                        row(routine, lastDone: lastDone[routine.id], highlighted: false)
                    }
                }

                if routines.isEmpty {
                    Text(SessionCopy.noRoutines)
                        .font(.pgym(.body, size: 17))
                        .foregroundStyle(Color.bone)
                }

                Rectangle().fill(Color.hairline).frame(height: Stroke.hairline).padding(.vertical, Spacing.grid(2))

                Button { pick(nil) } label: {
                    VStack(alignment: .leading, spacing: Spacing.grid(1)) {
                        Text(SessionCopy.emptySessionName)
                            .pgymText(.title)
                            .foregroundStyle(Color.chalk)
                        Text(SessionCopy.emptySessionCaption)
                            .font(.pgym(.body, size: 15))
                            .foregroundStyle(Color.steel)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.grid(4))
                    .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.rail, lineWidth: Stroke.border))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("d1.empty")
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.top, Spacing.grid(6))
            .padding(.bottom, Spacing.grid(8))
        }
        .background(Color.ink.ignoresSafeArea())
        .sensoryFeedback(.impact(weight: .light), trigger: pickTick)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.\(Self.viewID)")
    }

    private func row(_ routine: Routine, lastDone: Date?, highlighted: Bool) -> some View {
        Button { pick(routine) } label: {
            HStack(spacing: Spacing.grid(3)) {
                VStack(alignment: .leading, spacing: Spacing.grid(1)) {
                    Text(routine.name)
                        .pgymText(.title)
                        .foregroundStyle(Color.chalk)
                    Text(SessionCopy.routineMeta(exercises: routine.exercises.count, lastDone: lastDone.map { NextUp.dayLabel($0) }))
                        .pgymText(.label)
                        .foregroundStyle(Color.steel)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(highlighted ? Color.ink : Color.chalk)
                    .frame(width: Spacing.touchTargetMin, height: Spacing.touchTargetMin)
                    .background(Circle().fill(highlighted ? Color.plate : Color.rail))
                    .accessibilityHidden(true)
            }
            .padding(Spacing.grid(4))
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.iron))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(highlighted ? Color.plate : Color.clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("d1.routine.\(routine.order)")
    }

    private func pick(_ routine: Routine?) {
        pickTick += 1
        onPick(routine)
        dismiss()
    }
}
