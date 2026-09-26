import Testing
import Foundation
@testable import DuoAssess

@Suite("FaceAnalyzer + SyntheticFace")
struct FaceAnalyzerTests {
    @Test func syntheticIsPureInTime() {
        let gen = SyntheticFace(noise: 0.002, seed: 9)
        #expect(gen.frame(at: 1.5) == gen.frame(at: 1.5))
        #expect(gen.frame(at: 1.5) != SyntheticFace(noise: 0.002, seed: 10).frame(at: 1.5))
        #expect(gen.excursion(at: 0) == 0)
        #expect(abs(gen.excursion(at: gen.period * 0.75) - 1) < 1e-9)
        #expect(gen.excursion(at: gen.period * 0.25) == 0)
    }

    @Test func calibratesThenCountsFourSmiles() {
        let gen = SyntheticFace(period: 3)
        let a = FaceAnalyzer.analyze(gen.frames(duration: 13))
        #expect(a.isCalibrated)
        #expect(a.baselineProgress == FaceThresholds().baselineFrameCount)
        #expect(a.gestureCount == 4)
        #expect(a.gestures.allSatisfy { $0.affectedSide == .right })
        #expect(a.gestures.allSatisfy { $0.minSymmetryScore < 70 })
        // Smile 1 peaks at 2.25 s; smoothing lags a frame or two.
        #expect(abs(a.gestures[0].peakTime - 2.25) < 0.15)
        #expect(a.frame(at: 2.25)?.gestureNumber == 1)
        #expect(a.frame(at: 0.5)?.gestureNumber == nil)
        #expect(a.baselineLandmarks != nil)
    }

    @Test func symmetricSubjectIsNotFlagged() {
        let a = FaceAnalyzer.analyze(SyntheticFace(period: 3, weakSideFactor: 1).frames(duration: 7))
        #expect(a.gestureCount == 2)
        #expect(a.gestures.allSatisfy { $0.affectedSide == .none && $0.minSymmetryScore > 99 })
    }

    @Test func restingAsymmetryIsCalibratedOut() {
        let a = FaceAnalyzer.analyze(SyntheticFace(period: 3, weakSideFactor: 1, restingAsymmetry: 0.1).frames(duration: 7))
        #expect(a.gestureCount == 2)
        #expect(a.gestures.allSatisfy { $0.affectedSide == .none })
        #expect((a.frame(at: 2.25)?.metrics?.symmetryScore ?? 0) > 99)
    }

    @Test func survivesNoise() {
        let a = FaceAnalyzer.analyze(SyntheticFace(period: 3, noise: 0.0015, seed: 4).frames(duration: 13))
        #expect(a.isCalibrated)
        #expect(a.gestureCount == 4)
    }

    @Test func lowConfidenceFramesAreSkipped() {
        var frames = SyntheticFace(period: 3).frames(duration: 7)
        for i in frames.indices where i % 2 == 0 { frames[i].confidence = 0.1 }
        let a = FaceAnalyzer.analyze(frames)
        #expect(a.frames.count == frames.count)
        #expect(a.frames[0].measures == nil && a.frames[1].measures != nil)
        #expect(a.gestureCount == 2)
    }

    @Test func timelineOrdersAndMerges() {
        var tl = Timeline<FaceLandmarks>()
        let gen = SyntheticFace()
        for t in [2.0, 0.5, 1.0, 0.5001, 3.0] { tl.insert(gen.frame(at: t)) }
        #expect(tl.samples.map(\.time) == [0.5001, 1.0, 2.0, 3.0])
    }
}
