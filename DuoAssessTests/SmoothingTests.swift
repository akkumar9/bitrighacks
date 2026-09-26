import Testing
import Foundation
@testable import DuoAssess

@Suite("Smoothing")
struct SmoothingTests {
    @Test func firstFramePassesThrough() {
        var s = PoseSmoother(alpha: 0.5)
        let f = PoseFrame(time: 0, joints: [.leftKnee: JointPoint(x: 0.3, y: 0.4)])
        #expect(s.smooth(f) == f)
    }

    @Test func emaMovesHalfway() {
        var s = PoseSmoother(alpha: 0.5)
        _ = s.smooth(PoseFrame(time: 0, joints: [.leftKnee: JointPoint(x: 0.0, y: 0.0)]))
        let out = s.smooth(PoseFrame(time: 1, joints: [.leftKnee: JointPoint(x: 1.0, y: 0.5)]))
        #expect(abs(out[.leftKnee]!.x - 0.5) < 1e-9)
        #expect(abs(out[.leftKnee]!.y - 0.25) < 1e-9)
    }

    @Test func lowConfidenceHoldsLastPosition() {
        var s = PoseSmoother(alpha: 0.5, minConfidence: 0.3)
        _ = s.smooth(PoseFrame(time: 0, joints: [.leftKnee: JointPoint(x: 0.2, y: 0.2)]))
        let out = s.smooth(PoseFrame(time: 1, joints: [.leftKnee: JointPoint(x: 0.9, y: 0.9, confidence: 0.1)]))
        #expect(abs(out[.leftKnee]!.x - 0.2) < 1e-9)
        #expect(out[.leftKnee]!.confidence == 0.1)
        // Recovering confidence resumes from the held position, not the bad sample.
        let back = s.smooth(PoseFrame(time: 2, joints: [.leftKnee: JointPoint(x: 0.4, y: 0.2)]))
        #expect(abs(back[.leftKnee]!.x - 0.3) < 1e-9)
    }

    @Test func noisySyntheticIsSmootherAfterFiltering() {
        let gen = SyntheticSquat(noise: 0.01, seed: 7)
        let frames = gen.frames(duration: 5)
        var s = PoseSmoother(alpha: 0.3)
        let smoothed = frames.map { s.smooth($0) }
        func jitter(_ fs: [PoseFrame]) -> Double {
            zip(fs, fs.dropFirst()).map { PoseGeometry.distance($0[.leftKnee]!, $1[.leftKnee]!) }.reduce(0, +)
        }
        #expect(jitter(smoothed) < jitter(frames) * 0.6)
    }

    @Test func scalarSmoother() {
        var s = ScalarSmoother(alpha: 0.25)
        #expect(s.smooth(100) == 100)
        #expect(abs(s.smooth(200) - 125) < 1e-9)
    }
}
