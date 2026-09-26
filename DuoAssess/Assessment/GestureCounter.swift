import Foundation

/// One completed facial gesture (smile, brow raise, eye closure…).
struct Gesture: Equatable, Identifiable {
    let id: Int
    var startTime: Double
    var peakTime: Double
    var endTime: Double
    var peakExcursionLeft: Double
    var peakExcursionRight: Double
    var minSymmetryScore: Double
    var affectedSide: Side

    var duration: Double { endTime - startTime }
}

/// The face profile's analogue of `RepCounter`, driven by mean mouth-corner excursion from baseline.
///
/// rest ──exc > onset──▶ onset ──exc > peak──▶ peak ──exc < onset──▶ release ──exc < release──▶ rest
///   ▲                     │                                                                    │
///   └── exc < release ────┘ (never reached peak: discarded)          (gesture emitted) ◀────────┘
struct GestureCounter: Equatable {
    enum Phase: String, Equatable {
        case rest, onset, peak, release
    }

    var thresholds: FaceThresholds
    private(set) var phase: Phase = .rest
    private(set) var gestures: [Gesture] = []

    private var startTime: Double = 0
    private var maxExcursion: Double = 0
    private var peakTime: Double = 0
    private var peakLeft: Double = 0
    private var peakRight: Double = 0
    private var minScore: Double = 100

    init(thresholds: FaceThresholds = FaceThresholds()) {
        self.thresholds = thresholds
    }

    var currentGestureNumber: Int? { phase == .rest ? nil : gestures.count + 1 }

    mutating func reset() {
        phase = .rest; gestures = []; maxExcursion = 0; minScore = 100
    }

    /// `excursion` is the mean mouth-corner travel; `left`/`right` the signed per-side travel.
    @discardableResult
    mutating func update(excursion: Double, left: Double, right: Double, symmetryScore: Double, time: Double) -> Gesture? {
        let t = thresholds
        if phase != .rest {
            if excursion > maxExcursion {
                maxExcursion = excursion; peakTime = time; peakLeft = left; peakRight = right
            }
            minScore = min(minScore, symmetryScore)
        }

        switch phase {
        case .rest:
            if excursion > t.gestureOnsetExcursion {
                phase = .onset
                startTime = time
                maxExcursion = excursion; peakTime = time; peakLeft = left; peakRight = right
                minScore = symmetryScore
            }
            return nil

        case .onset:
            if excursion > t.gesturePeakExcursion { phase = .peak }
            else if excursion < t.gestureReleaseExcursion { phase = .rest }    // never peaked: discard
            return nil

        case .peak:
            if excursion < t.gestureOnsetExcursion { phase = .release }
            return nil

        case .release:
            if excursion > t.gesturePeakExcursion { phase = .peak; return nil }  // went back up
            guard excursion < t.gestureReleaseExcursion else { return nil }
            phase = .rest
            let side: Side
            if abs(peakLeft) - abs(peakRight) > t.asymmetryFlag { side = .right }
            else if abs(peakRight) - abs(peakLeft) > t.asymmetryFlag { side = .left }
            else { side = .none }
            let g = Gesture(id: gestures.count + 1, startTime: startTime, peakTime: peakTime, endTime: time,
                            peakExcursionLeft: peakLeft, peakExcursionRight: peakRight,
                            minSymmetryScore: minScore, affectedSide: side)
            gestures.append(g)
            return g
        }
    }
}
