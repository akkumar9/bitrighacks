import Testing
import Foundation
@testable import DuoAssess

@Suite("SyntheticSquat + SquatAnalyzer")
struct SyntheticSquatTests {
    @Test func standingAndBottomKneeAngles() {
        let gen = SyntheticSquat()
        let standing = SquatMetrics.compute(from: gen.frame(at: 0), thresholds: SquatThresholds())!
        let bottom = SquatMetrics.compute(from: gen.frame(at: gen.period / 2), thresholds: SquatThresholds())!
        #expect(standing.kneeAngle! > 170)
        #expect(bottom.kneeAngle! < 110)
        #expect(bottom.depth == 1)
        #expect(standing.isValgus == false && bottom.isValgus == false)
    }

    @Test func allJointsInsideTheFrame() {
        let gen = SyntheticSquat()
        for f in gen.frames(duration: 2.5, fps: 10) {
            #expect(f.joints.count == Joint.allCases.count)
            for (_, p) in f.joints { #expect(p.x > 0 && p.x < 1 && p.y > 0 && p.y < 1) }
        }
    }

    @Test func isPureInTime() {
        let gen = SyntheticSquat(noise: 0.02, seed: 3)
        #expect(gen.frame(at: 1.234) == gen.frame(at: 1.234))
        #expect(gen.frame(at: 1.234) != SyntheticSquat(noise: 0.02, seed: 4).frame(at: 1.234))
    }

    @Test func injectedValgusIsDetected() {
        let clean = SyntheticSquat(valgus: 0), bad = SyntheticSquat(valgus: 1)
        let t = SquatThresholds()
        let cleanBottom = SquatMetrics.compute(from: clean.frame(at: 1.25), thresholds: t)!
        let badBottom = SquatMetrics.compute(from: bad.frame(at: 1.25), thresholds: t)!
        #expect(cleanBottom.isValgus == false)
        #expect(badBottom.isValgus == true)
        #expect(badBottom.kneeSeparationRatio! < cleanBottom.kneeSeparationRatio! * 0.5)
        // Frontal camera: per-leg deviation is positive (inward) on both legs.
        let frontal = SyntheticSquat(valgus: 1, cameraAzimuthDegrees: 0)
        let m = SquatMetrics.compute(from: frontal.frame(at: 1.25), thresholds: t)!
        #expect(m.leftMedialDeviation! > t.valgusDeviation && m.rightMedialDeviation! > t.valgusDeviation)
    }

    @Test func analyzerCountsFourRepsInTenSeconds() {
        let gen = SyntheticSquat(period: 2.5)
        let analysis = SquatAnalyzer.analyze(gen.frames(duration: 10.0, fps: 30))
        #expect(analysis.repCount == 4)
        #expect(analysis.reps.allSatisfy { !$0.hadValgus })
        #expect(analysis.reps.allSatisfy { $0.minKneeAngle < 110 })
        // Bottom of rep 1 is near t = 1.25.
        #expect(abs(analysis.reps[0].bottomTime - 1.25) < 0.1)
        // Rep numbers are attached to frames mid-rep.
        #expect(analysis.frame(at: 1.25)?.repNumber == 1)
        #expect(analysis.frame(at: 3.75)?.repNumber == 2)
    }

    @Test func analyzerFlagsValgusReps() {
        let analysis = SquatAnalyzer.analyze(SyntheticSquat(period: 2.0, valgus: 1).frames(duration: 4.0))
        #expect(analysis.repCount == 2)
        #expect(analysis.reps.allSatisfy { $0.hadValgus })
    }

    @Test func analyzerSurvivesNoise() {
        let analysis = SquatAnalyzer.analyze(SyntheticSquat(period: 2.5, noise: 0.006, seed: 11).frames(duration: 10.0))
        #expect(analysis.repCount == 4)
    }

    @Test func timelineInsertsInOrderAndMerges() {
        var tl = PoseTimeline()
        let gen = SyntheticSquat()
        for t in [2.0, 0.5, 1.0, 0.5001, 3.0] { tl.insert(gen.frame(at: t)) }
        #expect(tl.frames.map(\.time) == [0.5001, 1.0, 2.0, 3.0])
        #expect(tl.frame(nearest: 1.9)?.time == 2.0)
        #expect(tl.frame(nearest: 0.0)?.time == 0.5001)
        #expect(tl.frame(nearest: 9)?.time == 3.0)
    }
}
