import Testing
import Foundation
import CoreGraphics
@testable import DuoAssess

@Suite("FaceGeometry")
struct FaceGeometryTests {
    let t = FaceThresholds()

    /// Rest face: every synthetic frame at t = 0 has excursion 0.
    func rest(_ gen: SyntheticFace = SyntheticFace()) -> FaceLandmarks { gen.frame(at: 0) }
    /// Full smile of the given generator.
    func peak(_ gen: SyntheticFace) -> FaceLandmarks { gen.frame(at: gen.period * 0.75) }

    @Test func interocularAndCorners() {
        let lm = rest()
        let iod = FaceGeometry.interocularDistance(lm)!
        #expect(abs(iod - 0.12) < 1e-9)
        let corners = FaceGeometry.mouthCorners(lm)!
        #expect(corners.left.x > corners.right.x)      // subject's left is at +x
    }

    @Test func perfectlySymmetricFaceScores100() {
        let gen = SyntheticFace(weakSideFactor: 1)
        let base = FaceGeometry.measures(rest(gen))!
        let now = FaceGeometry.measures(peak(gen))!
        let m = FaceGeometry.metrics(current: now, baseline: base, thresholds: t)
        #expect(m.symmetryScore == 100)
        #expect(m.affectedSide == .none)
        #expect(abs(m.mouthCornerDeltaLeft - m.mouthCornerDeltaRight) < 1e-9)
        #expect(m.mouthCornerDeltaLeft > 0.1)          // the smile actually lifted the corners
    }

    @Test func oneSidedOffsetGivesExpectedScoreAndSide() {
        // Hand-built measures: left mouth corner travels 0.06 iod more than the right, nothing else.
        let base = FaceGeometry.measures(rest())!
        var now = base
        now.leftMouthCorner += 0.06
        let m = FaceGeometry.metrics(current: now, baseline: base, thresholds: t)
        let expected = 100 * (1 - FaceGeometry.weights.mouth * 0.06 / FaceGeometry.zeroScoreDifference)
        #expect(abs(m.symmetryScore - expected) < 1e-9)      // 80 with the default weights
        #expect(m.affectedSide == .right)                      // right moved less
        now = base; now.rightMouthCorner += 0.06
        #expect(FaceGeometry.metrics(current: now, baseline: base, thresholds: t).affectedSide == .left)
    }

    @Test func syntheticDeficitIsRightSided() {
        let gen = SyntheticFace()   // weakSideFactor 0.35 → right corner lifts less
        let base = FaceGeometry.measures(rest(gen))!, now = FaceGeometry.measures(peak(gen))!
        let m = FaceGeometry.metrics(current: now, baseline: base, thresholds: t)
        #expect(m.affectedSide == .right)
        #expect(m.symmetryScore < 60)
        #expect(m.mouthCornerDeltaLeft > m.mouthCornerDeltaRight)
        #expect(m.eyebrowDeltaLeft > m.eyebrowDeltaRight)
        #expect(m.eyeApertureDeltaLeft < m.eyeApertureDeltaRight)   // left eye squints more
    }

    @Test func baselineSubtractionIgnoresRestingAsymmetry() {
        // Asymmetric at rest (right corner droops), symmetric in motion → reports symmetric.
        let gen = SyntheticFace(weakSideFactor: 1, restingAsymmetry: 0.08)
        let base = FaceGeometry.measures(rest(gen))!, now = FaceGeometry.measures(peak(gen))!
        #expect(abs(base.leftMouthCorner - base.rightMouthCorner - 0.08) < 1e-9)
        let m = FaceGeometry.metrics(current: now, baseline: base, thresholds: t)
        #expect(m.symmetryScore == 100)
        #expect(m.affectedSide == .none)
    }

    @Test func scaleInvariance() {
        let small = SyntheticFace(interocular: 0.08)
        let large = SyntheticFace(center: CGPoint(x: 0.4, y: 0.6), interocular: 0.16)
        let a = FaceGeometry.metrics(current: FaceGeometry.measures(peak(small))!, baseline: FaceGeometry.measures(rest(small))!, thresholds: t)
        let b = FaceGeometry.metrics(current: FaceGeometry.measures(peak(large))!, baseline: FaceGeometry.measures(rest(large))!, thresholds: t)
        #expect(abs(a.symmetryScore - b.symmetryScore) < 1e-9)
        #expect(abs(a.mouthCornerDeltaLeft - b.mouthCornerDeltaLeft) < 1e-9)
        #expect(abs(a.eyeApertureDeltaRight - b.eyeApertureDeltaRight) < 1e-9)
        #expect(abs(FaceGeometry.interocularDistance(rest(large))! / FaceGeometry.interocularDistance(rest(small))! - 2) < 1e-9)
    }

    @Test func midlineFromMedianLineIsVertical() {
        let (a, b) = FaceGeometry.midline(rest())!
        #expect(abs(a.x - b.x) < 1e-6)
        #expect(abs(a.y - b.y) > 0.1)
        var lm = rest(); lm.medianLine = []
        let (c, d) = FaceGeometry.midline(lm)!      // fallback through the nose
        #expect(abs(c.x - d.x) < 1e-6)
    }

    @Test func smoothingMeanIsExact() {
        let a = FaceGeometry.measures(rest())!, b = FaceGeometry.measures(peak(SyntheticFace()))!
        let m = FaceGeometry.mean([a, b])!
        #expect(abs(m.leftMouthCorner - (a.leftMouthCorner + b.leftMouthCorner) / 2) < 1e-12)
        #expect(FaceGeometry.mean([]) == nil)
    }
}
