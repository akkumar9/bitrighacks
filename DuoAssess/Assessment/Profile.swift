import Foundation
import CoreGraphics
import CoreVideo
import ImageIO

/// One row on the clinician's metrics list. `value` is preformatted ("134°", "0.93").
struct Metric: Identifiable {
    let id: String
    var label: String
    var value: String
    var flagged: Bool = false
}

enum CueTone { case neutral, good, correct }

/// The single line the patient sees. No numbers.
struct Cue {
    var text: String
    var tone: CueTone = .neutral
}

/// What to draw over the picture. All points are in **normalized image space, origin
/// bottom-left, y up** (Vision's convention); `StageGeometry` maps them onto the screen.
enum Overlay {
    case skeleton(bones: [(CGPoint, CGPoint)], joints: [CGPoint])
    case face(points: [CGPoint], midline: (CGPoint, CGPoint)?, ghost: [CGPoint])
    case none
}

/// Everything both displays render. Neither view knows which profile produced it.
struct Readout {
    var metrics: [Metric] = []          // inner display
    var cue: Cue                        // outer display, one at a time
    var progress: Double?               // 0…1, drives the patient's target bar
    var overlay: Overlay = .none
    var completedCount: Int = 0         // reps, or gestures
    var phase: String = ""

    static let empty = Readout(cue: Cue(text: ""))
}

/// A slider on the clinician's control deck, bound to one of the profile's live thresholds.
struct ThresholdControl: Identifiable {
    let id: String
    var label: String
    var range: ClosedRange<Double>
    var step: Double
    var format: (Double) -> String
    var get: () -> Double
    var set: (Double) -> Void
}

/// One completed rep or gesture for the deck's log. `time` is where tapping the row seeks to.
struct LogEntry: Identifiable {
    let id: Int
    var title: String
    var detail: String
    var flagged: Bool
    var time: Double
}

/// An assessment. Owns its own Vision request and all of its math.
///
/// Threading: `ingest(pixelBuffer:at:)` and `ingestSynthetic(at:)` are called on the engine's
/// background queue; everything else is called on the main actor. Implementations serialize their
/// state with a lock. Video frames may arrive out of time order (scrubbing), so profiles keep a
/// time-ordered timeline and re-run their analysis over it rather than trusting arrival order.
protocol Profile: AnyObject {
    var id: String { get }
    var displayName: String { get }
    var framesAnalysed: Int { get }
    func ingest(pixelBuffer: CVPixelBuffer, at time: Double)
    func readout() -> Readout
    func reset()

    // Beyond the minimum contract:

    /// Rotation Vision must apply so the frame is upright. Set by the video engine from the
    /// track's preferredTransform; `.up` for synthetic input.
    var imageOrientation: CGImagePropertyOrientation { get set }
    /// Base name of the bundled video this profile consumes (`design/<videoName>.mp4`).
    var videoName: String { get }
    /// No video: generate this profile's own synthetic sample at `time` and analyse it.
    func ingestSynthetic(at time: Double)
    var syntheticDuration: Double { get }
    var syntheticVideoSize: CGSize { get }
    /// Live thresholds for the control deck.
    var controls: [ThresholdControl] { get }
    /// Completed reps/gestures, newest last.
    var log: [LogEntry] { get }
    /// Drop any calibration and re-collect it from the frames that follow.
    func recalibrate()
}
