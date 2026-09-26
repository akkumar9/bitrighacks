import Foundation

/// Tunable numbers for squat analysis. Everything downstream reads these, nothing hardcodes them.
/// TODO: values are guesses for a ~35° oblique camera; retune on the real squat.mp4.
struct SquatThresholds: Equatable {
    /// Knee angle at or above this counts as standing (180 = straight leg).
    var standingAngle: Double = 155
    /// Knee angle below this counts as the bottom of a squat.
    var bottomAngle: Double = 120
    /// Knee separation / ankle separation below this = knees caving in (valgus).
    var valgusSeparationRatio: Double = 0.75
    /// Per-leg medial deviation of the knee from the hip–ankle line, as a fraction of thigh
    /// length, above which that leg is flagged. Only meaningful for a near-frontal camera.
    var valgusDeviation: Double = 0.15
    /// Joints below this confidence are treated as missing.
    var minConfidence: Double = 0.3
    /// Rising this many degrees above the rep's minimum switches the phase to ascending.
    var ascentHysteresis: Double = 10
}

/// Pure functions over joint coordinates. No SwiftUI, no Vision.
enum PoseGeometry {
    static func distance(_ a: JointPoint, _ b: JointPoint) -> Double {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }

    /// Interior angle at `vertex` between the rays to `a` and `b`, in degrees, 0…180.
    /// Returns nil when either ray is degenerate (a joint sitting on the vertex).
    static func angle(at vertex: JointPoint, _ a: JointPoint, _ b: JointPoint) -> Double? {
        let ux = a.x - vertex.x, uy = a.y - vertex.y
        let vx = b.x - vertex.x, vy = b.y - vertex.y
        let lu = (ux * ux + uy * uy).squareRoot()
        let lv = (vx * vx + vy * vy).squareRoot()
        guard lu > 1e-9, lv > 1e-9 else { return nil }
        let cosine = min(max((ux * vx + uy * vy) / (lu * lv), -1), 1)
        return acos(cosine) * 180 / .pi
    }

    /// Knee angle: 180 = straight leg, ~90 = thighs parallel to the floor.
    static func kneeAngle(hip: JointPoint, knee: JointPoint, ankle: JointPoint) -> Double? {
        angle(at: knee, hip, ankle)
    }

    /// Flexion is the complement: 0 = straight, 90 = parallel squat.
    static func kneeFlexion(hip: JointPoint, knee: JointPoint, ankle: JointPoint) -> Double? {
        kneeAngle(hip: hip, knee: knee, ankle: ankle).map { 180 - $0 }
    }

    /// How far the knee sits **inside** (toward `midlineX`) the straight hip→ankle line, as a
    /// fraction of thigh length. Positive = knee collapsing inward, negative = bowing outward.
    /// Frontal-camera measure; an oblique camera adds a constant offset to both legs, which is why
    /// `kneeSeparationRatio` is the primary flag.
    static func medialKneeDeviation(hip: JointPoint, knee: JointPoint, ankle: JointPoint, midlineX: Double) -> Double? {
        let dy = ankle.y - hip.y
        guard abs(dy) > 1e-9 else { return nil }
        let thigh = distance(hip, knee)
        guard thigh > 1e-9 else { return nil }
        let t = (knee.y - hip.y) / dy
        let lineX = hip.x + t * (ankle.x - hip.x)
        let deviation = knee.x - lineX                  // + = toward +x
        let medialSign: Double = midlineX >= lineX ? 1 : -1
        return deviation * medialSign / thigh
    }

    /// Distance between the knees divided by the distance between the ankles.
    /// ≈1 with a neutral stance, well below 1 when the knees cave in. Invariant to the sideways
    /// shift an oblique camera adds to both knees.
    static func kneeSeparationRatio(leftKnee: JointPoint, rightKnee: JointPoint,
                                    leftAnkle: JointPoint, rightAnkle: JointPoint) -> Double? {
        let ankles = abs(leftAnkle.x - rightAnkle.x)
        guard ankles > 1e-6 else { return nil }
        return abs(leftKnee.x - rightKnee.x) / ankles
    }
}

/// Everything the UI shows for one frame.
struct SquatMetrics: Equatable {
    var leftKneeAngle: Double?
    var rightKneeAngle: Double?
    /// Mean of the available knee angles. nil if neither leg is visible.
    var kneeAngle: Double?
    var leftMedialDeviation: Double?
    var rightMedialDeviation: Double?
    var kneeSeparationRatio: Double?
    var isValgus: Bool
    /// 0 = standing, 1 = at/below the bottom threshold. Linear in knee angle between the two.
    var depth: Double

    static func compute(from frame: PoseFrame, thresholds t: SquatThresholds) -> SquatMetrics? {
        let c = t.minConfidence
        let lh = frame.joint(.leftHip, minConfidence: c), rh = frame.joint(.rightHip, minConfidence: c)
        let lk = frame.joint(.leftKnee, minConfidence: c), rk = frame.joint(.rightKnee, minConfidence: c)
        let la = frame.joint(.leftAnkle, minConfidence: c), ra = frame.joint(.rightAnkle, minConfidence: c)

        var left: Double? = nil, right: Double? = nil
        if let lh, let lk, let la { left = PoseGeometry.kneeAngle(hip: lh, knee: lk, ankle: la) }
        if let rh, let rk, let ra { right = PoseGeometry.kneeAngle(hip: rh, knee: rk, ankle: ra) }
        let angles = [left, right].compactMap { $0 }
        guard !angles.isEmpty else { return nil }
        let mean = angles.reduce(0, +) / Double(angles.count)

        var midlineX: Double? = nil
        if let lh, let rh { midlineX = (lh.x + rh.x) / 2 }
        var leftDev: Double? = nil, rightDev: Double? = nil
        if let lh, let lk, let la, let m = midlineX { leftDev = PoseGeometry.medialKneeDeviation(hip: lh, knee: lk, ankle: la, midlineX: m) }
        if let rh, let rk, let ra, let m = midlineX { rightDev = PoseGeometry.medialKneeDeviation(hip: rh, knee: rk, ankle: ra, midlineX: m) }

        var ratio: Double? = nil
        if let lk, let rk, let la, let ra {
            ratio = PoseGeometry.kneeSeparationRatio(leftKnee: lk, rightKnee: rk, leftAnkle: la, rightAnkle: ra)
        }

        let valgus = (ratio.map { $0 < t.valgusSeparationRatio } ?? false)
        let span = max(t.standingAngle - t.bottomAngle, 1)
        let depth = min(max((t.standingAngle - mean) / span, 0), 1)

        return SquatMetrics(leftKneeAngle: left, rightKneeAngle: right, kneeAngle: mean,
                            leftMedialDeviation: leftDev, rightMedialDeviation: rightDev,
                            kneeSeparationRatio: ratio, isValgus: valgus, depth: depth)
    }
}
