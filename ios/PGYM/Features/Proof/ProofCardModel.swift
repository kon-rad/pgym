import CoreGraphics
import DesignSystem
import Foundation

/// The two card sizes (pgym-proof-card-spec.md). One layout builds both: the story card is the feed
/// card with every overlay moved down `yOffset` px; only the photo and the scrim change size.
enum ProofCardSize: String, CaseIterable, Codable, Sendable {
    /// 4:5 feed, 1080 x 1350.
    case feed
    /// 9:16 story, 1080 x 1920.
    case story

    var pixelSize: CGSize {
        switch self {
        case .feed: ProofCardSpec.feedSize
        case .story: ProofCardSpec.storySize
        }
    }

    var yOffset: CGFloat {
        switch self {
        case .feed: 0
        case .story: 300
        }
    }

    /// Top edge of the flat Ink scrim: 45% of 1350 rounded up (608), or the lower 55% of 1920 (864).
    var scrimTop: CGFloat {
        switch self {
        case .feed: 608
        case .story: 864
        }
    }

    /// D8 option label.
    var label: String {
        switch self {
        case .feed: ProofCopy.sizeFeed
        case .story: ProofCopy.sizeStory
        }
    }
}

/// What the stat row can show. The row holds three (D8 "Pick 3."). Shown in this order.
enum ProofCardStat: String, CaseIterable, Codable, Sendable {
    case sets
    case total
    case time
    case topLift

    var toggleLabel: String {
        switch self {
        case .sets: ProofCopy.statSets
        case .total: ProofCopy.statTotal
        case .time: ProofCopy.statTime
        case .topLift: ProofCopy.statTopLift
        }
    }

    /// Sets, total lifted, time: the default row.
    static let defaultRow: [ProofCardStat] = [.sets, .total, .time]
}

/// The stat-row choice on D8. Always exactly three. Picking a stat that is not on the row replaces the
/// one picked most recently, so on a normal day the third column flips between Time and Top lift and
/// Sets and Total stay put (pgym-flow-spec.md D8: "Third stat: Time or Top lift").
struct ProofStatSelection: Equatable, Codable, Sendable {
    /// In the order they were picked; the last one is the one that gives way.
    private(set) var picked: [ProofCardStat]

    init(_ picked: [ProofCardStat] = ProofCardStat.defaultRow) {
        var unique: [ProofCardStat] = []
        for stat in picked where !unique.contains(stat) { unique.append(stat) }
        for stat in ProofCardStat.defaultRow + [.topLift] where unique.count < ProofCardSpec.statCount && !unique.contains(stat) {
            unique.append(stat)
        }
        self.picked = Array(unique.prefix(ProofCardSpec.statCount))
    }

    /// The three stats in row order.
    var row: [ProofCardStat] {
        ProofCardStat.allCases.filter(picked.contains)
    }

    func contains(_ stat: ProofCardStat) -> Bool { picked.contains(stat) }

    /// Tapping a stat that is already on the row does nothing (the row always holds three).
    mutating func pick(_ stat: ProofCardStat) {
        guard !picked.contains(stat) else { return }
        picked.removeLast()
        picked.append(stat)
    }
}

/// Everything the user chooses on D8.
struct ProofCardOptions: Equatable, Codable, Sendable {
    var filter: ProofFilter
    var size: ProofCardSize
    var stats: ProofStatSelection

    init(filter: ProofFilter = .default, size: ProofCardSize = .feed, stats: ProofStatSelection = ProofStatSelection()) {
        self.filter = filter
        self.size = size
        self.stats = stats
    }
}

extension ProofFilter: Codable {
    var label: String {
        switch self {
        case .iron: ProofCopy.filterIron
        case .chalk: ProofCopy.filterChalk
        case .plate: ProofCopy.filterPlate
        case .raw: ProofCopy.filterRaw
        }
    }
}

/// The stamp on the card. The phone never makes up a proof number or a time: until `stampSession`
/// answers (card I7) the card shows PENDING and the phone's time.
enum ProofStampState: Equatable, Sendable {
    case pending(phoneTime: Date)
    /// Server values: proof number, `stampedAt`, the streak in weeks and the user's proof count.
    case stamped(proofNumber: Int, stampedAt: Date, streakWeeks: Int, proofCount: Int)

    var isPending: Bool {
        if case .pending = self { return true }
        return false
    }
}

/// The best working set of the session by estimated one-rep max (Epley).
struct ProofTopLift: Equatable, Sendable {
    var exerciseName: String
    var weightKg: Double
    var reps: Int
}

/// The session as the card sees it. There is deliberately no physique score, tip, body measurement or
/// location field here: what is not in the model cannot reach the card (pgym-proof-card-spec.md,
/// "Never on the card").
struct ProofCardSummary: Equatable, Sendable {
    var sessionName: String
    var setCount: Int
    var totalKg: Double
    var duration: TimeInterval
    var topLift: ProofTopLift?
    var unit: WeightUnit
    /// IANA zone the session started in; the timestamp is shown there.
    var timezone: String
    var stamp: ProofStampState
    /// Optional transient AI result stored only with the local session/card.
    var trainingInsight: String? = nil
}

extension ProofCardSummary {
    /// The card summary of a finished session. Working sets only, like the totals.
    init(session: WorkoutSession, unit: WeightUnit, stamp: ProofStampState, now: Date = .now) {
        let totals = session.totals
        var top: ProofTopLift?
        var topE1rm = -1.0
        for exercise in session.orderedExercises {
            for set in exercise.orderedSets where set.isWorkingDone {
                guard let reps = set.reps, reps > 0 else { continue }
                let weight = max(0, set.weightKg ?? 0)
                let e1rm = SessionMath.e1rm(weightKg: weight, reps: reps)
                // Bodyweight sets have no 1RM; among them, the most reps wins.
                let score = weight > 0 ? e1rm : Double(reps) * 1e-6
                if score > topE1rm {
                    topE1rm = score
                    top = ProofTopLift(exerciseName: exercise.name, weightKg: weight, reps: reps)
                }
            }
        }
        self.init(
            sessionName: session.routineName,
            setCount: totals.setCount,
            totalKg: totals.volumeKg,
            duration: session.elapsed(at: now),
            topLift: top,
            unit: unit,
            timezone: session.timezone,
            stamp: stamp,
            trainingInsight: session.physiqueTip
        )
    }
}
