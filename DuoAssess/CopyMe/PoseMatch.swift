import Foundation
import CoreGraphics

/// Limb angles compared between the two people. Proportions differ, angles do not.
enum LimbAngle: String, CaseIterable, Identifiable, Hashable {
    case leftElbow, rightElbow        // shoulder -> elbow -> wrist
    case leftShoulder, rightShoulder  // hip -> shoulder -> elbow
    case leftKnee, rightKnee          // hip -> knee -> ankle
    case leftHip, rightHip            // shoulder -> hip -> knee
    case torsoLean                    // hip midpoint -> shoulder midpoint vs vertical

    var id: String { rawValue }

    /// (a, vertex, b) for the interior angle at `vertex`; nil for torsoLean.
    var joints: (Joint, Joint, Joint)? {
        switch self {
        case .leftElbow: return (.leftShoulder, .leftElbow, .leftWrist)
        case .rightElbow: return (.rightShoulder, .rightElbow, .rightWrist)
        case .leftShoulder: return (.leftHip, .leftShoulder, .leftElbow)
        case .rightShoulder: return (.rightHip, .rightShoulder, .rightElbow)
        case .leftKnee: return (.leftHip, .leftKnee, .leftAnkle)
        case .rightKnee: return (.rightHip, .rightKnee, .rightAnkle)
        case .leftHip: return (.leftShoulder, .leftHip, .leftKnee)
        case .rightHip: return (.rightShoulder, .rightHip, .rightKnee)
        case .torsoLean: return nil
        }
    }

    var mirrored: LimbAngle {
        switch self {
        case .leftElbow: return .rightElbow
        case .rightElbow: return .leftElbow
        case .leftShoulder: return .rightShoulder
        case .rightShoulder: return .leftShoulder
        case .leftKnee: return .rightKnee
        case .rightKnee: return .leftKnee
        case .leftHip: return .rightHip
        case .rightHip: return .leftHip
        case .torsoLean: return .torsoLean
        }
    }

    var label: String {
        switch self {
        case .leftElbow: return "Left elbow"
        case .rightElbow: return "Right elbow"
        case .leftShoulder: return "Left shoulder"
        case .rightShoulder: return "Right shoulder"
        case .leftKnee: return "Left knee"
        case .rightKnee: return "Right knee"
        case .leftHip: return "Left hip"
        case .rightHip: return "Right hip"
        case .torsoLean: return "Torso lean"
        }
    }
}

struct MatchThresholds: Equatable {
    var minConfidence: Double = 0.3
    var maxLag: Double = 1.0            // seconds of search window
    var lagSearchStride: Double = 1.0 / 30
    var goodJointError: Double = 10     // degrees, counts as matching
    var badJointError: Double = 25      // degrees, gets called out
    var smoothingWindow: Int = 5
    /// The two people face each other, so the demonstrator's left is copied with the learner's right.
    var mirrored: Bool = true
    /// Weighted mean error (degrees) at which the score reaches 0; linear from 100 at 0°.
    /// `goodJointError` only decides per-joint flags, so one bad limb always costs score.
    var zeroScoreError: Double = 60

    /// Per-limb weight in the score. Arms and shoulders carry the most expressive movement and are
    /// where copying goes wrong first, so they weigh 1.0. Knees and hips move less in most
    /// upper-body demonstrations and Vision is noisier there (0.8). Torso lean is one number for
    /// whole-body posture, so it gets a little extra (1.2). TODO: retune once demo.mp4 exists.
    var weights: [LimbAngle: Double] = [
        .leftElbow: 1.0, .rightElbow: 1.0,
        .leftShoulder: 1.0, .rightShoulder: 1.0,
        .leftKnee: 0.8, .rightKnee: 0.8,
        .leftHip: 0.8, .rightHip: 0.8,
        .torsoLean: 1.2,
    ]
}

/// Error for one of the **learner's** limbs (what the learner must fix). With `mirrored`, the
/// learner's right elbow is scored against the demonstrator's left elbow.
struct JointError: Identifiable, Equatable {
    let id: String
    var limb: LimbAngle
    var degrees: Double
    var isBad: Bool
}

struct MatchResult: Equatable {
    var score: Double            // 0...100
    var lag: Double              // seconds the learner is behind
    var jointErrors: [JointError]
    var worst: JointError?
    var ghost: Skeleton          // demonstrator pose, normalized into the learner's frame
    var isValid: Bool            // false when either skeleton is missing

    static let invalid = MatchResult(score: 0, lag: 0, jointErrors: [], worst: nil, ghost: Skeleton(), isValid: false)
}

/// A pose with the hip midpoint at the origin and torso length 1, plus the transform that got it
/// there (needed to put a ghost back into the source frame).
struct NormalizedSkeleton: Equatable {
    var joints: [Joint: CGPoint]
    /// Hip midpoint in the source frame.
    var origin: CGPoint
    /// Torso length in the source frame.
    var scale: Double

    /// Back to the source frame.
    func denormalize(_ p: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + p.x * CGFloat(scale), y: origin.y + p.y * CGFloat(scale))
    }
}

/// Pure functions over two `PoseFrame`s. No Vision, no AVFoundation, no views.
enum PoseMatch {
    // MARK: Normalization

    /// Translate to the hip midpoint, scale by torso length, drop low-confidence joints.
    /// nil if either the hips or the shoulders are missing.
    static func normalize(_ frame: PoseFrame, minConfidence: Double) -> NormalizedSkeleton? {
        func pt(_ j: Joint) -> CGPoint? {
            guard let p = frame.joints[j], p.confidence >= minConfidence else { return nil }
            return CGPoint(x: p.x, y: p.y)
        }
        func mid(_ a: Joint, _ b: Joint, fallback: Joint) -> CGPoint? {
            if let pa = pt(a), let pb = pt(b) { return CGPoint(x: (pa.x + pb.x) / 2, y: (pa.y + pb.y) / 2) }
            return pt(fallback)
        }
        guard let hip = mid(.leftHip, .rightHip, fallback: .root),
              let shoulder = mid(.leftShoulder, .rightShoulder, fallback: .neck) else { return nil }
        let torso = Double(((shoulder.x - hip.x) * (shoulder.x - hip.x) + (shoulder.y - hip.y) * (shoulder.y - hip.y)).squareRoot())
        guard torso > 1e-6 else { return nil }
        var joints: [Joint: CGPoint] = [:]
        for j in Joint.allCases {
            guard let p = pt(j) else { continue }
            joints[j] = CGPoint(x: (p.x - hip.x) / CGFloat(torso), y: (p.y - hip.y) / CGFloat(torso))
        }
        return NormalizedSkeleton(joints: joints, origin: hip, scale: torso)
    }

    /// Flip left/right in normalized space and relabel, i.e. the pose as the other person sees it.
    static func mirrored(_ s: NormalizedSkeleton) -> NormalizedSkeleton {
        var out = s
        out.joints = [:]
        for (j, p) in s.joints { out.joints[j.mirrored] = CGPoint(x: -p.x, y: p.y) }
        return out
    }

    // MARK: Angles

    static func angle(_ limb: LimbAngle, in s: NormalizedSkeleton) -> Double? {
        if limb == .torsoLean {
            func mid(_ a: Joint, _ b: Joint, fallback: Joint) -> CGPoint? {
                if let pa = s.joints[a], let pb = s.joints[b] { return CGPoint(x: (pa.x + pb.x) / 2, y: (pa.y + pb.y) / 2) }
                return s.joints[fallback]
            }
            guard let hip = mid(.leftHip, .rightHip, fallback: .root), let sh = mid(.leftShoulder, .rightShoulder, fallback: .neck) else { return nil }
            let vx = Double(sh.x - hip.x), vy = Double(sh.y - hip.y)
            let len = (vx * vx + vy * vy).squareRoot()
            guard len > 1e-9 else { return nil }
            return acos(min(max(vy / len, -1), 1)) * 180 / .pi
        }
        guard let (a, v, b) = limb.joints, let pa = s.joints[a], let pv = s.joints[v], let pb = s.joints[b] else { return nil }
        return PoseGeometry.angle(at: JointPoint(x: Double(pv.x), y: Double(pv.y)),
                                  JointPoint(x: Double(pa.x), y: Double(pa.y)),
                                  JointPoint(x: Double(pb.x), y: Double(pb.y)))
    }

    static func angles(_ s: NormalizedSkeleton) -> [LimbAngle: Double] {
        var out: [LimbAngle: Double] = [:]
        for limb in LimbAngle.allCases { if let a = angle(limb, in: s) { out[limb] = a } }
        return out
    }

    // MARK: Comparison

    /// Per-limb errors keyed by the learner's limb, and the weighted score.
    static func compare(demonstrator d: NormalizedSkeleton, learner l: NormalizedSkeleton,
                        thresholds t: MatchThresholds) -> (errors: [JointError], score: Double) {
        let da = angles(d), la = angles(l)
        var errors: [JointError] = []
        var weighted = 0.0, weightSum = 0.0
        for learnerLimb in LimbAngle.allCases {
            let demoLimb = t.mirrored ? learnerLimb.mirrored : learnerLimb
            guard let a = da[demoLimb], let b = la[learnerLimb] else { continue }
            let e = abs(a - b)
            errors.append(JointError(id: learnerLimb.rawValue, limb: learnerLimb, degrees: e, isBad: e > t.badJointError))
            let w = t.weights[learnerLimb] ?? 1
            weighted += w * e; weightSum += w
        }
        let mean = weightSum > 0 ? weighted / weightSum : 0
        return (errors, score(meanError: mean, thresholds: t))
    }

    static func score(meanError e: Double, thresholds t: MatchThresholds) -> Double {
        guard e > 1e-9 else { return 100 }     // floating-point dust reads as a clean 100
        return 100 * (1 - min(max(e / max(t.zeroScoreError, 1e-9), 0), 1))
    }

    /// One pair of frames, no lag search.
    static func compare(demonstrator: PoseFrame, learner: PoseFrame, thresholds t: MatchThresholds) -> MatchResult {
        guard let d = normalize(demonstrator, minConfidence: t.minConfidence),
              let l = normalize(learner, minConfidence: t.minConfidence) else { return .invalid }
        let (errors, score) = compare(demonstrator: d, learner: l, thresholds: t)
        return MatchResult(score: score, lag: max(learner.time - demonstrator.time, 0), jointErrors: errors,
                           worst: errors.max { $0.degrees < $1.degrees },
                           ghost: ghost(demonstrator: d, onto: l, mirrored: t.mirrored), isValid: true)
    }

    /// The learner is behind: compare against every demonstrator frame in [t − maxLag, t] and keep
    /// the best. Its offset is the learner's lag.
    static func match(learner: PoseFrame, against timeline: PoseTimeline, thresholds t: MatchThresholds) -> MatchResult {
        guard !timeline.isEmpty, let l = normalize(learner, minConfidence: t.minConfidence) else { return .invalid }
        var best: MatchResult = .invalid
        var offset = 0.0
        let stride = max(t.lagSearchStride, 1e-3)
        while offset <= t.maxLag + 1e-9 {
            let want = learner.time - offset
            if let f = timeline.frame(nearest: want), abs(f.time - want) <= stride,
               let d = normalize(f, minConfidence: t.minConfidence) {
                let (errors, score) = compare(demonstrator: d, learner: l, thresholds: t)
                if !best.isValid || score > best.score {
                    best = MatchResult(score: score, lag: max(learner.time - f.time, 0), jointErrors: errors,
                                       worst: errors.max { $0.degrees < $1.degrees },
                                       ghost: ghost(demonstrator: d, onto: l, mirrored: t.mirrored), isValid: true)
                }
            }
            offset += stride
        }
        return best
    }

    // MARK: Ghost

    /// The demonstrator's pose placed onto the learner's hip midpoint and torso length, in the
    /// learner's image coordinates, mirrored when the two are facing each other.
    static func ghost(demonstrator d: NormalizedSkeleton, onto l: NormalizedSkeleton, mirrored: Bool) -> Skeleton {
        let src = mirrored ? self.mirrored(d) : d
        var g = Skeleton()
        for (j, p) in src.joints { g.joints[j] = l.denormalize(p) }
        return g
    }
}

/// Moving average over the last `window` valid results. Score, lag and per-limb errors are
/// averaged and the bad flag is re-evaluated on the averaged error; the ghost and validity come
/// from the newest result. Invalid results pass through without disturbing the window.
struct MatchSmoother {
    let window: Int
    let badJointError: Double
    private var ring: [MatchResult] = []

    init(window: Int, badJointError: Double = 25) {
        self.window = max(window, 1)
        self.badJointError = badJointError
    }

    mutating func push(_ raw: MatchResult) -> MatchResult {
        guard raw.isValid else { return raw }
        ring.append(raw)
        if ring.count > window { ring.removeFirst() }
        let n = Double(ring.count)
        var out = raw
        out.score = ring.map(\.score).reduce(0, +) / n
        out.lag = ring.map(\.lag).reduce(0, +) / n
        var sums: [LimbAngle: (total: Double, count: Int)] = [:]
        for r in ring {
            for e in r.jointErrors {
                let s = sums[e.limb] ?? (0, 0)
                sums[e.limb] = (s.total + e.degrees, s.count + 1)
            }
        }
        out.jointErrors = raw.jointErrors.map { e in
            let s = sums[e.limb] ?? (e.degrees, 1)
            let avg = s.total / Double(s.count)
            return JointError(id: e.id, limb: e.limb, degrees: avg, isBad: avg > badJointError)
        }
        out.worst = out.jointErrors.max { $0.degrees < $1.degrees }
        return out
    }
}
