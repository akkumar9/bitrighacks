import Foundation
import CoreGraphics

enum Side: String, Equatable {
    case left, right, none
}

/// Face landmarks in **normalized image space, origin bottom-left, y up** (already converted out
/// of Vision's face bounding box). `left`/`right` are the subject's sides, as Vision reports them.
struct FaceLandmarks: Equatable {
    var time: Double
    var leftEye: [CGPoint] = []
    var rightEye: [CGPoint] = []
    var leftEyebrow: [CGPoint] = []
    var rightEyebrow: [CGPoint] = []
    var outerLips: [CGPoint] = []
    var innerLips: [CGPoint] = []
    var nose: [CGPoint] = []
    var medianLine: [CGPoint] = []
    var confidence: Float = 1

    var allPoints: [CGPoint] {
        leftEye + rightEye + leftEyebrow + rightEyebrow + outerLips + innerLips + nose + medianLine
    }
}

/// Tunable numbers for the face profile. Everything is in interocular units unless noted.
struct FaceThresholds: Equatable {
    var baselineFrameCount: Int = 20
    /// Mean mouth-corner travel from baseline that starts a gesture.
    var gestureOnsetExcursion: Double = 0.04
    /// Travel it must fall below to end a gesture (hysteresis).
    var gestureReleaseExcursion: Double = 0.02
    /// Travel a gesture must reach to count; onsets that never get here are discarded.
    /// TODO: not in the original spec; tune against face.mp4.
    var gesturePeakExcursion: Double = 0.06
    /// Side-to-side deviation that counts as asymmetric.
    var asymmetryFlag: Double = 0.03
    var minConfidence: Float = 0.3
    var smoothingWindow: Int = 5
}

/// One frame's raw geometry. Vertical positions are relative to the eye midpoint (mouth) or the
/// same-side eye centre (brows), and every number is divided by interocular distance, so the
/// values are invariant to distance from the camera and face size.
struct FaceMeasures: Equatable {
    var interocular: Double
    var leftMouthCorner: Double
    var rightMouthCorner: Double
    var leftBrow: Double
    var rightBrow: Double
    var leftEyeAperture: Double
    var rightEyeAperture: Double

    static func + (a: FaceMeasures, b: FaceMeasures) -> FaceMeasures {
        FaceMeasures(interocular: a.interocular + b.interocular,
                     leftMouthCorner: a.leftMouthCorner + b.leftMouthCorner,
                     rightMouthCorner: a.rightMouthCorner + b.rightMouthCorner,
                     leftBrow: a.leftBrow + b.leftBrow, rightBrow: a.rightBrow + b.rightBrow,
                     leftEyeAperture: a.leftEyeAperture + b.leftEyeAperture,
                     rightEyeAperture: a.rightEyeAperture + b.rightEyeAperture)
    }

    func scaled(_ k: Double) -> FaceMeasures {
        FaceMeasures(interocular: interocular * k, leftMouthCorner: leftMouthCorner * k,
                     rightMouthCorner: rightMouthCorner * k, leftBrow: leftBrow * k, rightBrow: rightBrow * k,
                     leftEyeAperture: leftEyeAperture * k, rightEyeAperture: rightEyeAperture * k)
    }
}

/// Deviation of the current frame from the resting baseline.
struct FaceMetrics: Equatable {
    var mouthCornerDeltaLeft: Double
    var mouthCornerDeltaRight: Double
    var eyebrowDeltaLeft: Double
    var eyebrowDeltaRight: Double
    var eyeApertureDeltaLeft: Double
    var eyeApertureDeltaRight: Double
    /// Smaller aperture / larger aperture, 1 = both eyes equally open. Detects incomplete closure.
    var eyeApertureRatio: Double
    /// Mean of the two mouth-corner travels (absolute). Drives gesture segmentation.
    var meanMouthExcursion: Double
    /// 0…100, 100 = perfectly symmetric.
    var symmetryScore: Double
    /// The side that moved less, or `.none` if within `asymmetryFlag`.
    var affectedSide: Side
}

/// Pure functions over landmarks. No Vision, no views.
enum FaceGeometry {
    /// Contribution of each side-difference to the symmetry score.
    static let weights = (mouth: 0.5, brow: 0.3, eye: 0.2)
    /// Weighted side-difference (interocular units) at which the score reaches 0.
    static let zeroScoreDifference = 0.15

    static func centroid(_ points: [CGPoint]) -> CGPoint? {
        guard !points.isEmpty else { return nil }
        let n = CGFloat(points.count)
        return CGPoint(x: points.map(\.x).reduce(0, +) / n, y: points.map(\.y).reduce(0, +) / n)
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        Double(((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot())
    }

    /// Centre of the left eye to centre of the right eye.
    static func interocularDistance(_ lm: FaceLandmarks) -> Double? {
        guard let l = centroid(lm.leftEye), let r = centroid(lm.rightEye) else { return nil }
        let d = distance(l, r)
        return d > 1e-6 ? d : nil
    }

    /// The outer-lip corner on the subject's left and right. "Left" is the corner nearest the
    /// left eye's x, so this holds whether or not the footage is mirrored.
    static func mouthCorners(_ lm: FaceLandmarks) -> (left: CGPoint, right: CGPoint)? {
        guard lm.outerLips.count >= 2, let le = centroid(lm.leftEye), let re = centroid(lm.rightEye) else { return nil }
        let minX = lm.outerLips.min { $0.x < $1.x }!, maxX = lm.outerLips.max { $0.x < $1.x }!
        return le.x >= re.x ? (left: maxX, right: minX) : (left: minX, right: maxX)
    }

    static func measures(_ lm: FaceLandmarks) -> FaceMeasures? {
        guard let iod = interocularDistance(lm),
              let le = centroid(lm.leftEye), let re = centroid(lm.rightEye),
              let corners = mouthCorners(lm),
              let lbPeak = lm.leftEyebrow.max(by: { $0.y < $1.y }),
              let rbPeak = lm.rightEyebrow.max(by: { $0.y < $1.y }),
              let lTop = lm.leftEye.max(by: { $0.y < $1.y })?.y, let lBot = lm.leftEye.min(by: { $0.y < $1.y })?.y,
              let rTop = lm.rightEye.max(by: { $0.y < $1.y })?.y, let rBot = lm.rightEye.min(by: { $0.y < $1.y })?.y
        else { return nil }
        let eyeMidY = Double(le.y + re.y) / 2
        return FaceMeasures(interocular: iod,
                            leftMouthCorner: (Double(corners.left.y) - eyeMidY) / iod,
                            rightMouthCorner: (Double(corners.right.y) - eyeMidY) / iod,
                            leftBrow: Double(lbPeak.y - le.y) / iod,
                            rightBrow: Double(rbPeak.y - re.y) / iod,
                            leftEyeAperture: Double(lTop - lBot) / iod,
                            rightEyeAperture: Double(rTop - rBot) / iod)
    }

    static func mean(_ ms: [FaceMeasures]) -> FaceMeasures? {
        guard !ms.isEmpty else { return nil }
        return ms.dropFirst().reduce(ms[0], +).scaled(1 / Double(ms.count))
    }

    /// Two points to draw the face's vertical midline. Fits the median-line landmarks when
    /// present, otherwise runs from the inner-eye midpoint through the nose.
    static func midline(_ lm: FaceLandmarks) -> (CGPoint, CGPoint)? {
        if lm.medianLine.count >= 2, let fit = principalAxis(lm.medianLine) { return fit }
        guard let le = centroid(lm.leftEye), let re = centroid(lm.rightEye), let nose = centroid(lm.nose) else { return nil }
        // Inner corners: the eye points closest to the other eye.
        let lInner = lm.leftEye.min { distance($0, re) < distance($1, re) } ?? le
        let rInner = lm.rightEye.min { distance($0, le) < distance($1, le) } ?? re
        let top = CGPoint(x: (lInner.x + rInner.x) / 2, y: (lInner.y + rInner.y) / 2)
        // Extend through the nose so the line spans the face.
        let dx = nose.x - top.x, dy = nose.y - top.y
        return (CGPoint(x: top.x - dx * 0.8, y: top.y - dy * 0.8), CGPoint(x: nose.x + dx * 1.2, y: nose.y + dy * 1.2))
    }

    /// Least-squares line through the points (principal axis), returned as its two extreme
    /// projections so it spans the point set.
    static func principalAxis(_ points: [CGPoint]) -> (CGPoint, CGPoint)? {
        guard points.count >= 2, let c = centroid(points) else { return nil }
        var sxx = 0.0, syy = 0.0, sxy = 0.0
        for p in points {
            let dx = Double(p.x - c.x), dy = Double(p.y - c.y)
            sxx += dx * dx; syy += dy * dy; sxy += dx * dy
        }
        // Direction of the largest eigenvector of the 2×2 covariance.
        let theta = 0.5 * atan2(2 * sxy, sxx - syy)
        let dir = (x: cos(theta), y: sin(theta))
        var tMin = Double.infinity, tMax = -Double.infinity
        for p in points {
            let t = Double(p.x - c.x) * dir.x + Double(p.y - c.y) * dir.y
            tMin = min(tMin, t); tMax = max(tMax, t)
        }
        guard tMax - tMin > 1e-9 else { return nil }
        return (CGPoint(x: c.x + CGFloat(dir.x * tMin), y: c.y + CGFloat(dir.y * tMin)),
                CGPoint(x: c.x + CGFloat(dir.x * tMax), y: c.y + CGFloat(dir.y * tMax)))
    }

    static func metrics(current: FaceMeasures, baseline: FaceMeasures, thresholds t: FaceThresholds) -> FaceMetrics {
        let mL = current.leftMouthCorner - baseline.leftMouthCorner
        let mR = current.rightMouthCorner - baseline.rightMouthCorner
        let bL = current.leftBrow - baseline.leftBrow
        let bR = current.rightBrow - baseline.rightBrow
        let aL = current.leftEyeAperture - baseline.leftEyeAperture
        let aR = current.rightEyeAperture - baseline.rightEyeAperture

        let combined = weights.mouth * abs(mL - mR) + weights.brow * abs(bL - bR) + weights.eye * abs(aL - aR)
        // Snap floating-point dust to a clean 100 so "symmetric" reads as exactly symmetric.
        let score = combined < 1e-9 ? 100 : 100 * max(0, 1 - combined / zeroScoreDifference)

        let moveL = weights.mouth * abs(mL) + weights.brow * abs(bL) + weights.eye * abs(aL)
        let moveR = weights.mouth * abs(mR) + weights.brow * abs(bR) + weights.eye * abs(aR)
        let side: Side
        if moveL - moveR > t.asymmetryFlag { side = .right }         // right moved less
        else if moveR - moveL > t.asymmetryFlag { side = .left }
        else { side = .none }

        let apertures = [current.leftEyeAperture, current.rightEyeAperture]
        let ratio = apertures.max()! > 1e-9 ? apertures.min()! / apertures.max()! : 1

        return FaceMetrics(mouthCornerDeltaLeft: mL, mouthCornerDeltaRight: mR,
                           eyebrowDeltaLeft: bL, eyebrowDeltaRight: bR,
                           eyeApertureDeltaLeft: aL, eyeApertureDeltaRight: aR,
                           eyeApertureRatio: ratio,
                           meanMouthExcursion: (abs(mL) + abs(mR)) / 2,
                           symmetryScore: score, affectedSide: side)
    }
}
