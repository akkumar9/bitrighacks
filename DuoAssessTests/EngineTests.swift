import Testing
import Foundation
import CoreGraphics
@testable import DuoAssess

@Suite("Engines")
struct EngineTests {
    @Test @MainActor func orientationFromPreferredTransform() {
        #expect(VideoEngine.orientation(for: .identity) == .up)
        #expect(VideoEngine.orientation(for: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 0, ty: 0)) == .right)
        #expect(VideoEngine.orientation(for: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 0)) == .left)
        #expect(VideoEngine.orientation(for: CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 0, ty: 0)) == .down)
    }

    @Test @MainActor func missingVideoFallsBackToSynthetic() {
        // The test host bundle has no design/*.mp4 (none have landed yet).
        #expect(SessionModel.source(for: SquatProfile()) == .synthetic)
        #expect(SessionModel.source(for: FaceSymmetryProfile()) == .synthetic)
        #expect(SessionModel.source(for: SquatProfile(), in: Bundle(for: SessionModel.self)) == .synthetic)
    }

    @Test @MainActor func profileSwapResetsAndRoutesFrames() {
        let squat = SquatProfile(), face = FaceSymmetryProfile()
        let sink = ProfileSink(profile: squat)
        sink.ingestSynthetic(at: 0.5)
        #expect(squat.framesAnalysed == 1 && face.framesAnalysed == 0)
        sink.profile = face
        sink.ingestSynthetic(at: 0.5)
        #expect(face.framesAnalysed == 1 && squat.framesAnalysed == 1)
        face.reset()
        #expect(face.framesAnalysed == 0)
    }

    @Test func squatProfileReadoutMatchesAnalyzer() {
        let p = SquatProfile()
        let gen = SyntheticSquat()
        for i in 0...300 { p.ingestSynthetic(at: Double(i) / 30) }
        let r = p.readout()
        #expect(r.completedCount == 4)
        #expect(p.log.count == 4)
        if case .skeleton(let bones, let joints) = r.overlay { #expect(!bones.isEmpty && !joints.isEmpty) } else { Issue.record("expected skeleton overlay") }
        #expect(r.metrics.contains { $0.id == "kneeL" })
        #expect(SquatAnalyzer.analyze(gen.frames(duration: 10)).repCount == 4)
    }

    @Test func faceProfileReadoutCalibratesAndCounts() {
        let p = FaceSymmetryProfile()
        for i in 0...390 { p.ingestSynthetic(at: Double(i) / 30) }
        let r = p.readout()
        #expect(r.completedCount == 4)
        #expect(r.metrics.first { $0.id == "cal" }?.value == "ready")
        #expect(r.progress != nil)
        if case .face(let pts, let mid, let ghost) = r.overlay { #expect(!pts.isEmpty && mid != nil && !ghost.isEmpty) } else { Issue.record("expected face overlay") }
        p.recalibrate()
        #expect(p.readout().metrics.first { $0.id == "cal" }?.value != "ready")
    }
}
