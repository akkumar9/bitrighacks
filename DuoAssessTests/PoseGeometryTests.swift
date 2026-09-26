import Testing
import Foundation
@testable import DuoAssess

@Suite("PoseGeometry")
struct PoseGeometryTests {
    let hip = JointPoint(x: 0.5, y: 0.6)
    let knee = JointPoint(x: 0.5, y: 0.4)
    let ankle = JointPoint(x: 0.5, y: 0.2)

    @Test func straightLegIs180() {
        let a = PoseGeometry.kneeAngle(hip: hip, knee: knee, ankle: ankle)
        #expect(a != nil)
        #expect(abs(a! - 180) < 1e-9)
    }

    @Test func rightAngleIs90() {
        // Hip directly behind the knee, ankle directly below it.
        let hip = JointPoint(x: 0.3, y: 0.4)
        let a = PoseGeometry.kneeAngle(hip: hip, knee: knee, ankle: ankle)
        #expect(abs(a! - 90) < 1e-9)
        #expect(abs(PoseGeometry.kneeFlexion(hip: hip, knee: knee, ankle: ankle)! - 90) < 1e-9)
    }

    @Test func angleIsSymmetricAndBounded() {
        let a = JointPoint(x: 0.1, y: 0.9), b = JointPoint(x: 0.7, y: 0.3), v = JointPoint(x: 0.4, y: 0.4)
        let ab = PoseGeometry.angle(at: v, a, b)!, ba = PoseGeometry.angle(at: v, b, a)!
        #expect(abs(ab - ba) < 1e-9)
        #expect(ab >= 0 && ab <= 180)
    }

    @Test func degenerateRayReturnsNil() {
        #expect(PoseGeometry.angle(at: knee, knee, ankle) == nil)
    }

    @Test func kneeOnHipAnkleLineHasZeroDeviation() {
        let d = PoseGeometry.medialKneeDeviation(hip: hip, knee: knee, ankle: ankle, midlineX: 0.5)!
        #expect(abs(d) < 1e-9)
    }

    @Test func kneeCollapsingTowardMidlineIsPositive() {
        // Left leg at +x; midline at 0.5; knee pushed toward the midline.
        let hip = JointPoint(x: 0.56, y: 0.6), knee = JointPoint(x: 0.52, y: 0.4), ankle = JointPoint(x: 0.57, y: 0.2)
        let d = PoseGeometry.medialKneeDeviation(hip: hip, knee: knee, ankle: ankle, midlineX: 0.5)!
        #expect(d > 0.15)
        // Same knee pushed away from the midline is negative (varus).
        let out = JointPoint(x: 0.62, y: 0.4)
        #expect(PoseGeometry.medialKneeDeviation(hip: hip, knee: out, ankle: ankle, midlineX: 0.5)! < 0)
    }

    @Test func separationRatio() {
        let lk = JointPoint(x: 0.56, y: 0.4), rk = JointPoint(x: 0.44, y: 0.4)
        let la = JointPoint(x: 0.57, y: 0.2), ra = JointPoint(x: 0.43, y: 0.2)
        let r = PoseGeometry.kneeSeparationRatio(leftKnee: lk, rightKnee: rk, leftAnkle: la, rightAnkle: ra)!
        #expect(abs(r - 0.12 / 0.14) < 1e-9)
        #expect(PoseGeometry.kneeSeparationRatio(leftKnee: lk, rightKnee: rk, leftAnkle: la, rightAnkle: la) == nil)
    }

    @Test func metricsIgnoreLowConfidenceJoints() {
        var joints: [Joint: JointPoint] = [
            .leftHip: hip, .leftKnee: knee, .leftAnkle: ankle,
            .rightHip: JointPoint(x: 0.4, y: 0.6, confidence: 0.1),
            .rightKnee: JointPoint(x: 0.2, y: 0.4, confidence: 0.1),
            .rightAnkle: JointPoint(x: 0.4, y: 0.2, confidence: 0.1),
        ]
        let m = SquatMetrics.compute(from: PoseFrame(time: 0, joints: joints), thresholds: SquatThresholds())!
        #expect(m.rightKneeAngle == nil)
        #expect(abs(m.kneeAngle! - 180) < 1e-9)
        #expect(m.depth == 0)
        #expect(m.isValgus == false)

        joints.removeValue(forKey: .leftHip)
        #expect(SquatMetrics.compute(from: PoseFrame(time: 0, joints: joints), thresholds: SquatThresholds()) == nil)
    }

    @Test func depthIsLinearBetweenThresholds() {
        let t = SquatThresholds(standingAngle: 160, bottomAngle: 100)
        func metrics(angleDeg: Double) -> SquatMetrics {
            // Build a leg with the requested knee angle: hip rotated around the knee.
            let rad = angleDeg * .pi / 180
            let hip = JointPoint(x: knee.x + 0.2 * sin(rad), y: knee.y - 0.2 * cos(rad))
            return SquatMetrics.compute(from: PoseFrame(time: 0, joints: [.leftHip: hip, .leftKnee: knee, .leftAnkle: ankle]), thresholds: t)!
        }
        #expect(abs(metrics(angleDeg: 130).depth - 0.5) < 1e-6)
        #expect(metrics(angleDeg: 175).depth == 0)
        #expect(metrics(angleDeg: 80).depth == 1)
    }
}
