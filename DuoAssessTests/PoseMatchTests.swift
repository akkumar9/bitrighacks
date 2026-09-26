import Testing
import Foundation
import CoreGraphics
@testable import DuoAssess

@Suite("PoseMatch")
struct PoseMatchTests {
    let t = MatchThresholds()
    let gen = SyntheticSquat()

    /// A mid-squat frame with arms forward: every limb angle is defined.
    var demo: PoseFrame { gen.frame(at: 0.9) }

    /// Rotate `wrist` about `elbow` by `degrees` so only that elbow angle changes.
    func bendElbow(_ f: PoseFrame, elbow: Joint, wrist: Joint, degrees: Double) -> PoseFrame {
        var out = f
        let e = f.joints[elbow]!, w = f.joints[wrist]!
        let r = degrees * .pi / 180
        let dx = w.x - e.x, dy = w.y - e.y
        out.joints[wrist] = JointPoint(x: e.x + dx * cos(r) - dy * sin(r), y: e.y + dx * sin(r) + dy * cos(r), confidence: w.confidence)
        return out
    }

    func transformed(_ f: PoseFrame, scale: Double, dx: Double, dy: Double) -> PoseFrame {
        var out = f
        for (j, p) in f.joints { out.joints[j] = JointPoint(x: p.x * scale + dx, y: p.y * scale + dy, confidence: p.confidence) }
        return out
    }

    @Test func identicalSkeletonsScore100() {
        var same = t; same.mirrored = false
        let r = PoseMatch.compare(demonstrator: demo, learner: demo, thresholds: same)
        #expect(r.isValid)
        #expect(r.score == 100)
        #expect(r.jointErrors.count == LimbAngle.allCases.count)
        #expect(r.jointErrors.allSatisfy { !$0.isBad && $0.degrees < 1e-9 })
        #expect(r.lag == 0)
    }

    @Test func mirroredPoseMatchesWhenMirroredFlagIsOn() {
        let learner = demo.mirrored()
        var on = t; on.mirrored = true
        let r = PoseMatch.compare(demonstrator: demo, learner: learner, thresholds: on)
        #expect(r.score == 100)
        #expect(r.jointErrors.allSatisfy { $0.degrees < 1e-9 })
    }

    @Test func mirroredPoseFailsWhenMirroredFlagIsOff() {
        // Make the pose asymmetric so mirroring actually changes the angles.
        let asym = bendElbow(demo, elbow: .leftElbow, wrist: .leftWrist, degrees: 60)
        let learner = asym.mirrored()
        var off = t; off.mirrored = false
        var on = t; on.mirrored = true
        let wrong = PoseMatch.compare(demonstrator: asym, learner: learner, thresholds: off)
        let right = PoseMatch.compare(demonstrator: asym, learner: learner, thresholds: on)
        #expect(right.score == 100)
        #expect(wrong.score < 80)
        #expect(wrong.jointErrors.contains { $0.isBad })
    }

    @Test func scaleAndTranslationInvariance() {
        let moved = transformed(demo, scale: 2, dx: -0.4, dy: 0.1)
        var same = t; same.mirrored = false
        let r = PoseMatch.compare(demonstrator: demo, learner: moved, thresholds: same)
        #expect(r.score == 100)
        #expect(r.jointErrors.allSatisfy { $0.degrees < 1e-6 })
        // The ghost lands on the moved learner: its hips coincide with the learner's hips.
        let lh = moved.joints[.leftHip]!, gh = r.ghost.joints[.leftHip]!
        #expect(abs(Double(gh.x) - lh.x) < 1e-9 && abs(Double(gh.y) - lh.y) < 1e-9)
    }

    @Test func thirtyDegreeElbowOffsetFlagsOnlyThatJoint() {
        var same = t; same.mirrored = false
        let learner = bendElbow(demo, elbow: .rightElbow, wrist: .rightWrist, degrees: 30)
        let r = PoseMatch.compare(demonstrator: demo, learner: learner, thresholds: same)
        let elbow = r.jointErrors.first { $0.limb == .rightElbow }!
        #expect(abs(elbow.degrees - 30) < 1e-6)
        #expect(elbow.isBad)
        #expect(r.jointErrors.filter { $0.limb != .rightElbow }.allSatisfy { !$0.isBad && $0.degrees < 1e-6 })
        #expect(r.worst?.limb == .rightElbow)
        #expect(r.score < 100 && r.score > 60)
        // With mirroring on, the same error lands on the learner's right elbow (it is their limb).
        let learnerMirrored = bendElbow(demo, elbow: .leftElbow, wrist: .leftWrist, degrees: 30).mirrored()
        let rm = PoseMatch.compare(demonstrator: demo, learner: learnerMirrored, thresholds: t)
        #expect(rm.worst?.limb == .rightElbow)
    }

    @Test func lagSearchFindsA400msDelay() {
        var tl = PoseTimeline()
        for f in gen.frames(duration: 5) { tl.insert(f) }
        // Learner copies perfectly, mirrored, 0.4 s late.
        let learnerTime = 3.2
        var learner = gen.frame(at: learnerTime - 0.4).mirrored()
        learner.time = learnerTime
        let r = PoseMatch.match(learner: learner, against: tl, thresholds: t)
        #expect(r.isValid)
        #expect(abs(r.lag - 0.4) < 0.04)
        #expect(r.score > 95)
        // Frame-to-frame at the same timestamp reports real error on the same data.
        let naive = PoseMatch.compare(demonstrator: tl.frame(nearest: learnerTime)!, learner: learner, thresholds: t)
        #expect(naive.score < r.score)
    }

    @Test func missingSkeletonIsInvalidNotACrash() {
        let empty = PoseFrame(time: 1, joints: [:])
        #expect(PoseMatch.compare(demonstrator: empty, learner: demo, thresholds: t).isValid == false)
        #expect(PoseMatch.compare(demonstrator: demo, learner: empty, thresholds: t).isValid == false)
        var lowConf = demo
        for (j, p) in demo.joints { lowConf.joints[j] = JointPoint(x: p.x, y: p.y, confidence: 0.1) }
        #expect(PoseMatch.compare(demonstrator: demo, learner: lowConf, thresholds: t).isValid == false)
        #expect(PoseMatch.match(learner: demo, against: PoseTimeline(), thresholds: t).isValid == false)
        #expect(PoseMatch.normalize(empty, minConfidence: 0.3) == nil)
    }

    @Test func normalizationPutsHipsAtOriginAndTorsoAtOne() {
        let n = PoseMatch.normalize(demo, minConfidence: 0.3)!
        let lh = n.joints[.leftHip]!, rh = n.joints[.rightHip]!
        #expect(abs(Double(lh.x + rh.x)) < 1e-9 && abs(Double(lh.y + rh.y)) < 1e-9)
        let ls = n.joints[.leftShoulder]!, rs = n.joints[.rightShoulder]!
        let sh = CGPoint(x: (ls.x + rs.x) / 2, y: (ls.y + rs.y) / 2)
        #expect(abs(Double((sh.x * sh.x + sh.y * sh.y).squareRoot()) - 1) < 1e-9)
    }

    @Test func smootherAveragesAndReflags() {
        var s = MatchSmoother(window: 3, badJointError: 25)
        func result(_ e: Double) -> MatchResult {
            MatchResult(score: 100 - e, lag: e / 100, jointErrors: [JointError(id: "leftElbow", limb: .leftElbow, degrees: e, isBad: e > 25)],
                        worst: nil, ghost: Skeleton(), isValid: true)
        }
        _ = s.push(result(10)); _ = s.push(result(20))
        let out = s.push(result(60))
        #expect(abs(out.score - 70) < 1e-9)
        #expect(abs(out.jointErrors[0].degrees - 30) < 1e-9)
        #expect(out.jointErrors[0].isBad)            // 30 > 25 on the smoothed value
        #expect(out.worst?.limb == .leftElbow)
        #expect(s.push(.invalid).isValid == false)
    }

    @Test func scoreMapping() {
        #expect(PoseMatch.score(meanError: 0, thresholds: t) == 100)
        #expect(abs(PoseMatch.score(meanError: 30, thresholds: t) - 50) < 1e-9)
        #expect(PoseMatch.score(meanError: 60, thresholds: t) == 0)
        #expect(PoseMatch.score(meanError: 200, thresholds: t) == 0)
    }
}
