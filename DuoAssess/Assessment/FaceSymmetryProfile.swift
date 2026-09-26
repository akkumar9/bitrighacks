import Foundation
import CoreGraphics
import CoreVideo
import ImageIO

/// Placeholder until Stage 2; proves the swap path with a second profile in the list.
final class FaceSymmetryProfile: Profile {
    let id = "face"
    let displayName = "Face symmetry"
    let videoName = "face"
    var imageOrientation: CGImagePropertyOrientation = .up
    var framesAnalysed: Int { 0 }
    let syntheticDuration: Double = 12
    let syntheticVideoSize = CGSize(width: 1080, height: 1920)
    func ingest(pixelBuffer: CVPixelBuffer, at time: Double) {}
    func ingestSynthetic(at time: Double) {}
    func readout() -> Readout { Readout(cue: Cue(text: "Face profile coming in Stage 2")) }
    func reset() {}
    func recalibrate() {}
    var controls: [ThresholdControl] { [] }
    var log: [LogEntry] { [] }
}
