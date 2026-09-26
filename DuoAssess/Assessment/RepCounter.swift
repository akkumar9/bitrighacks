import Foundation

/// One completed squat.
struct Rep: Equatable, Identifiable {
    let id: Int              // 1-based rep number
    var startTime: TimeInterval
    var bottomTime: TimeInterval
    var endTime: TimeInterval
    /// Smallest knee angle reached (lower = deeper).
    var minKneeAngle: Double
    /// True if any frame of the rep was flagged valgus.
    var hadValgus: Bool

    var duration: TimeInterval { endTime - startTime }
}

/// State machine over a stream of knee angles. Feed it frames in time order.
///
/// standing ──angle < standing──▶ descending ──angle < bottom──▶ bottom
///     ▲                                                          │
///     └────── angle ≥ standing (rep counted) ◀── ascending ◀─────┘ (angle rises past min + hysteresis)
///
/// A descent that never reaches `bottomAngle` before returning to standing is discarded, not counted.
struct RepCounter: Equatable {
    enum Phase: String, Equatable {
        case standing, descending, bottom, ascending
    }

    var thresholds: SquatThresholds
    private(set) var phase: Phase = .standing
    private(set) var reps: [Rep] = []

    private var startTime: TimeInterval?
    private var minAngle: Double = .infinity
    private var minTime: TimeInterval = 0
    private var reachedBottom = false
    private var sawValgus = false

    init(thresholds: SquatThresholds = SquatThresholds()) {
        self.thresholds = thresholds
    }

    /// Rep number of the squat in progress (reps.count + 1) while not standing, else nil.
    var currentRepNumber: Int? { phase == .standing ? nil : reps.count + 1 }

    mutating func reset() {
        phase = .standing; reps = []; startTime = nil
        minAngle = .infinity; reachedBottom = false; sawValgus = false
    }

    /// Returns the rep just completed, if this sample finished one.
    @discardableResult
    mutating func update(kneeAngle: Double, isValgus: Bool, time: TimeInterval) -> Rep? {
        let t = thresholds
        if phase != .standing {
            if kneeAngle < minAngle { minAngle = kneeAngle; minTime = time }
            if isValgus { sawValgus = true }
        }

        switch phase {
        case .standing:
            if kneeAngle < t.standingAngle {
                phase = .descending
                startTime = time
                minAngle = kneeAngle; minTime = time
                reachedBottom = false; sawValgus = isValgus
            }
            return nil

        case .descending:
            if kneeAngle < t.bottomAngle { phase = .bottom; reachedBottom = true }
            else if kneeAngle >= t.standingAngle { phase = .standing }   // shallow dip, discard
            return nil

        case .bottom:
            if kneeAngle > minAngle + t.ascentHysteresis { phase = .ascending }
            return finishIfStanding(kneeAngle: kneeAngle, time: time)

        case .ascending:
            if kneeAngle < t.bottomAngle, kneeAngle <= minAngle { phase = .bottom }  // went deeper again
            return finishIfStanding(kneeAngle: kneeAngle, time: time)
        }
    }

    private mutating func finishIfStanding(kneeAngle: Double, time: TimeInterval) -> Rep? {
        guard kneeAngle >= thresholds.standingAngle else { return nil }
        phase = .standing
        guard reachedBottom, let start = startTime else { return nil }
        let rep = Rep(id: reps.count + 1, startTime: start, bottomTime: minTime, endTime: time,
                      minKneeAngle: minAngle, hadValgus: sawValgus)
        reps.append(rep)
        startTime = nil
        return rep
    }
}
