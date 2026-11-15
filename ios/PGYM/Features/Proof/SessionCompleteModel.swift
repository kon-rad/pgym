import DesignSystem
import Foundation

/// Everything D11 Session complete shows, worked out from the session, the server's answer, the stamp
/// queue, the consent flag and the score listener. Pure, so the rules are tested without a screen.
///
/// Rules kept here:
/// - The proof number and the time are the server's. Until it answers, the stamp area is D9's state.
/// - No score UI without consent: the score block needs the switch on, 18 or over, and the session
///   stamped while the switch was on. A score that arrives anyway is not shown.
/// - A refused or failed analysis shows nothing on D11 and no error (the reason lives on E3).
/// - Share opens only once the card is stamped.
struct SessionCompleteModel: Equatable {
    enum StampArea: Equatable {
        /// The server's number and time.
        case stamped(proofNumber: Int, timestamp: String)
        /// Uploading or waiting for the number. `progress` is nil while waiting to start.
        case working(progress: Double?, slow: Bool)
        /// No connection: saved, stamps on reconnect.
        case offline
        /// The queue gave up: Try again.
        case failed
    }

    enum ScoreBlock: Equatable {
        /// Waiting for the listener ("Scoring your photo.").
        case pending
        case scored(score: Int, trend: String, tip: String?)
    }

    struct Stat: Equatable {
        var label: String
        var value: String
        var unit: String?
    }

    struct Inputs {
        var sessionID: String
        var startedAt: Date
        var timezone: String
        var setCount: Int
        var totalKg: Double
        var duration: TimeInterval
        var unit: WeightUnit
        /// Exercise ID to the best working set this session (name, kg, reps).
        var bestSets: [String: (name: String, kg: Double, reps: Int)]
        /// Exercise IDs the phone flagged as new bests while logging; used until the server answers.
        var localNewBests: [String]
        var receipt: StampReceipt?
        var phase: StampPhase?
        /// How long the current upload or stamp has been running.
        var workingFor: TimeInterval
        var consentOn: Bool
        var isAdult: Bool
        var offerShown: Bool
        /// The session was stamped with the score on.
        var physiqueRequested: Bool
        var physique: PhysiqueRecord?
        var previousScore: Int?
        /// Days of this session's week with a proof (stamped or waiting), this one included.
        var doneDays: Set<Weekday>
        var gymDays: Set<Weekday>
        var today: Weekday
    }

    var headline: String
    var stampArea: StampArea
    var weekRings: [(day: Weekday, status: DayRing.Status)]
    var stats: [Stat]
    var newBests: [String]
    var score: ScoreBlock?
    var showsConsentOffer: Bool
    var canShare: Bool

    init(_ input: Inputs) {
        let receipt = input.receipt
        if let receipt {
            stampArea = .stamped(
                proofNumber: receipt.proofNumber,
                timestamp: ProofCardText.timestamp(receipt.stampState, timezone: input.timezone)
            )
        } else {
            switch input.phase {
            case .offline: stampArea = .offline
            case .failed: stampArea = .failed
            case let .uploading(fraction): stampArea = .working(progress: fraction, slow: input.workingFor >= StampCopy.slowAfter)
            case .stamping: stampArea = .working(progress: 1, slow: input.workingFor >= StampCopy.slowAfter)
            case .waiting, .stamped, .none: stampArea = .working(progress: nil, slow: false)
            }
        }

        headline = Self.headline(receipt: receipt, area: stampArea)

        weekRings = Weekday.allCases.map { day in
            let status: DayRing.Status
            if input.doneDays.contains(day) {
                status = .done
            } else if day == input.today {
                status = .today
            } else if input.gymDays.contains(day) {
                status = .planned
            } else {
                status = .rest
            }
            return (day, status)
        }

        let unitLabel = input.unit.rawValue
        stats = [
            Stat(label: StampCopy.statSets, value: "\(receipt?.setCount ?? input.setCount)", unit: nil),
            Stat(
                label: StampCopy.sectionTotal,
                value: ProofCardText.grouped(ProofCardText.totalValue(kg: receipt?.totalVolume ?? input.totalKg, unit: input.unit)),
                unit: unitLabel
            ),
            Stat(label: StampCopy.statTime, value: ProofCardText.duration(input.duration), unit: nil),
        ]

        let bestIDs = receipt?.newBests ?? input.localNewBests
        newBests = bestIDs.compactMap { id in
            guard let best = input.bestSets[id] else { return nil }
            let weight = best.kg > 0 ? ProofCardText.topLiftWeight(kg: best.kg, unit: input.unit) : "0"
            return StampCopy.bestRow(exercise: best.name, weight: weight, unit: unitLabel, reps: best.reps)
        }

        score = Self.scoreBlock(input)
        // Offered once, to adults with the score off, never on the very first proof
        // (pgym-flow-spec.md: "D10 Physique consent is never in the first loop").
        showsConsentOffer = receipt != nil && (receipt?.proofCount ?? 0) > 1 && input.isAdult && !input.consentOn && !input.offerShown
        canShare = receipt != nil
    }

    static func headline(receipt: StampReceipt?, area: StampArea) -> String {
        guard let receipt else {
            switch area {
            case .offline, .failed: return StampCopy.offlineTitle
            default: return StampCopy.stampingTitle
            }
        }
        if receipt.weekGoal > 0, receipt.weekCount > receipt.weekGoal { return StampCopy.headlineBonus }
        if receipt.weekGoal > 0, receipt.weekCount == receipt.weekGoal {
            return StampCopy.headlineLocked(week: max(1, receipt.streakWeeks))
        }
        return StampCopy.headlineProgress(receipt.weekCount, of: receipt.weekGoal)
    }

    static func scoreBlock(_ input: Inputs) -> ScoreBlock? {
        guard input.consentOn, input.isAdult, input.physiqueRequested, input.receipt != nil else { return nil }
        guard let record = input.physique else { return .pending }
        guard record.isScored, let score = record.score else { return nil }
        return .scored(score: score, trend: trend(score: score, previous: input.previousScore), tip: record.tip)
    }

    static func trend(score: Int, previous: Int?) -> String {
        guard let previous else { return StampCopy.trendFirst }
        if score > previous { return StampCopy.trendUp(score - previous) }
        if score == previous { return StampCopy.trendSame }
        return StampCopy.trendDown(previous - score)
    }

    static func == (lhs: SessionCompleteModel, rhs: SessionCompleteModel) -> Bool {
        lhs.headline == rhs.headline && lhs.stampArea == rhs.stampArea
            && lhs.weekRings.map { $0.day } == rhs.weekRings.map { $0.day }
            && lhs.weekRings.map { $0.status } == rhs.weekRings.map { $0.status }
            && lhs.stats == rhs.stats && lhs.newBests == rhs.newBests && lhs.score == rhs.score
            && lhs.showsConsentOffer == rhs.showsConsentOffer && lhs.canShare == rhs.canShare
    }
}

extension SessionCompleteModel.Inputs {
    /// The parts that come from the session on the phone.
    init(
        session: WorkoutSession,
        unit: WeightUnit,
        phase: StampPhase?,
        workingFor: TimeInterval,
        consentOn: Bool,
        isAdult: Bool,
        offerShown: Bool,
        physique: PhysiqueRecord?,
        previousScore: Int?,
        doneDays: Set<Weekday>,
        gymDays: Set<Weekday>,
        today: Weekday
    ) {
        var bestSets: [String: (name: String, kg: Double, reps: Int)] = [:]
        var bestE1rm: [String: Double] = [:]
        var localNewBests: [String] = []
        for exercise in session.orderedExercises {
            for set in exercise.orderedSets where set.isWorkingDone {
                guard let reps = set.reps, reps > 0 else { continue }
                let kg = max(0, set.weightKg ?? 0)
                let e1rm = kg > 0 ? SessionMath.e1rm(weightKg: kg, reps: reps) : Double(reps) * 1e-6
                if e1rm > (bestE1rm[exercise.exerciseId] ?? -1) {
                    bestE1rm[exercise.exerciseId] = e1rm
                    bestSets[exercise.exerciseId] = (exercise.name, kg, reps)
                }
                if set.isNewBest, !localNewBests.contains(exercise.exerciseId) {
                    localNewBests.append(exercise.exerciseId)
                }
            }
        }
        let totals = session.totals
        self.init(
            sessionID: session.id,
            startedAt: session.startedAt,
            timezone: session.timezone,
            setCount: totals.setCount,
            totalKg: totals.volumeKg,
            duration: session.elapsed(at: session.endedAt ?? .now),
            unit: unit,
            bestSets: bestSets,
            localNewBests: localNewBests,
            receipt: session.stampReceipt,
            phase: phase,
            workingFor: workingFor,
            consentOn: consentOn,
            isAdult: isAdult,
            offerShown: offerShown,
            physiqueRequested: session.physiqueRequested == true,
            physique: physique,
            previousScore: previousScore,
            doneDays: doneDays,
            gymDays: gymDays,
            today: today
        )
    }
}
