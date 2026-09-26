import Foundation
import CoreGraphics
import CoreVideo
import Vision

/// Squat form: knee angle, depth, valgus, rep counting. A thin adapter over `PoseGeometry`,
/// `RepCounter`, `PoseTimeline` and `SquatAnalyzer`; none of that math lives here.
final class SquatProfile: Profile {
    let id = "squat"
    let displayName = "Squat"
    let videoName = "squat"
    var imageOrientation: CGImagePropertyOrientation = .up
    var syntheticDuration: Double { synthetic.period * 4 }
    let syntheticVideoSize = CGSize(width: 1080, height: 1920)

    private let lock = NSLock()
    private var thresholds = SquatThresholds()
    private var smoothingAlpha = 0.5
    private var timeline = PoseTimeline()
    private var analysis = SquatAnalysis.empty
    private var lastTime: Double?
    private var synthetic = SyntheticSquat()

    var framesAnalysed: Int { lock.withLock { timeline.count } }

    // MARK: - Ingest

    func ingest(pixelBuffer: CVPixelBuffer, at time: Double) {
        guard let frame = Self.detectPose(in: pixelBuffer, at: time, orientation: imageOrientation) else { return }
        lock.withLock {
            timeline.insert(frame)
            lastTime = time
            reanalyze()
        }
    }

    func ingestSynthetic(at time: Double) {
        lock.withLock {
            timeline.insert(synthetic.frame(at: time))
            lastTime = time
            reanalyze()
        }
    }

    func reset() {
        lock.withLock {
            timeline.removeAll()
            analysis = .empty
            lastTime = nil
        }
    }

    func recalibrate() { reset() }

    private func reanalyze() {
        analysis = SquatAnalyzer.analyze(timeline.frames, thresholds: thresholds, smoothingAlpha: smoothingAlpha)
    }

    // MARK: - Output

    func readout() -> Readout {
        lock.withLock {
            let current = lastTime.flatMap { analysis.frame(at: $0) }
            let m = current?.metrics
            let phase = current?.phase ?? .standing
            let count = analysis.repCount

            var metrics: [Metric] = [
                Metric(id: "kneeL", label: "Knee L", value: m?.leftKneeAngle.map { String(format: "%.0f°", $0) } ?? "—"),
                Metric(id: "kneeR", label: "Knee R", value: m?.rightKneeAngle.map { String(format: "%.0f°", $0) } ?? "—"),
                Metric(id: "depth", label: "Depth", value: m.map { String(format: "%.0f%%", $0.depth * 100) } ?? "—"),
                Metric(id: "sep", label: "Knee/ankle sep.", value: m?.kneeSeparationRatio.map { String(format: "%.2f", $0) } ?? "—",
                       flagged: m?.isValgus == true),
                Metric(id: "valgus", label: "Valgus", value: m?.isValgus == true ? "YES" : "no", flagged: m?.isValgus == true),
            ]
            if let rep = current?.repNumber { metrics.append(Metric(id: "rep", label: "Rep in progress", value: "#\(rep)")) }

            var overlay: Overlay = .none
            if let frame = current?.smoothed {
                let c = thresholds.minConfidence
                var bones: [(CGPoint, CGPoint)] = []
                for (a, b) in Skeleton.bones {
                    guard let pa = frame.joint(a, minConfidence: c), let pb = frame.joint(b, minConfidence: c) else { continue }
                    bones.append((CGPoint(x: pa.x, y: pa.y), CGPoint(x: pb.x, y: pb.y)))
                }
                let joints = frame.joints.values.filter { $0.confidence >= c }.map { CGPoint(x: $0.x, y: $0.y) }
                overlay = .skeleton(bones: bones, joints: joints)
            }

            return Readout(metrics: metrics,
                           cue: Self.cue(metrics: m, phase: phase, reps: count),
                           progress: m?.depth,
                           overlay: overlay,
                           completedCount: count,
                           phase: phase.rawValue)
        }
    }

    private static func cue(metrics m: SquatMetrics?, phase: RepCounter.Phase, reps: Int) -> Cue {
        guard let m else { return Cue(text: "Step into frame") }
        if m.isValgus { return Cue(text: "Push your knees out", tone: .correct) }
        switch phase {
        case .standing:  return reps == 0 ? Cue(text: "Ready when you are") : Cue(text: "Nice — \(reps) done", tone: .good)
        case .descending: return Cue(text: "Sit back and down")
        case .bottom:    return m.depth >= 1 ? Cue(text: "Good depth", tone: .good) : Cue(text: "A little lower", tone: .correct)
        case .ascending: return Cue(text: "Drive up")
        }
    }

    var log: [LogEntry] {
        lock.withLock {
            analysis.reps.map {
                LogEntry(id: $0.id, title: "Rep #\($0.id)",
                         detail: String(format: "min %.0f° · %.1fs", $0.minKneeAngle, $0.duration),
                         flagged: $0.hadValgus, time: $0.bottomTime)
            }
        }
    }

    var controls: [ThresholdControl] {
        [
            ThresholdControl(id: "standing", label: "Standing angle", range: 120...178, step: 1,
                             format: { String(format: "%.0f°", $0) },
                             get: { [unowned self] in lock.withLock { thresholds.standingAngle } },
                             set: { [unowned self] v in lock.withLock { thresholds.standingAngle = v; reanalyze() } }),
            ThresholdControl(id: "bottom", label: "Bottom angle", range: 60...150, step: 1,
                             format: { String(format: "%.0f°", $0) },
                             get: { [unowned self] in lock.withLock { thresholds.bottomAngle } },
                             set: { [unowned self] v in lock.withLock { thresholds.bottomAngle = v; reanalyze() } }),
            ThresholdControl(id: "valgusRatio", label: "Valgus ratio", range: 0.4...1.0, step: 0.01,
                             format: { String(format: "%.2f", $0) },
                             get: { [unowned self] in lock.withLock { thresholds.valgusSeparationRatio } },
                             set: { [unowned self] v in lock.withLock { thresholds.valgusSeparationRatio = v; reanalyze() } }),
            ThresholdControl(id: "smoothing", label: "Smoothing", range: 0.1...1.0, step: 0.05,
                             format: { String(format: "%.2f", $0) },
                             get: { [unowned self] in lock.withLock { smoothingAlpha } },
                             set: { [unowned self] v in lock.withLock { smoothingAlpha = v; reanalyze() } }),
        ]
    }

    // MARK: - Vision

    /// Runs on the engine's queue. Returns nil when no body is found.
    static func detectPose(in pixelBuffer: CVPixelBuffer, at time: Double,
                           orientation: CGImagePropertyOrientation) -> PoseFrame? {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        do { try handler.perform([request]) } catch { return nil }
        guard let observation = request.results?.first,
              let points = try? observation.recognizedPoints(.all) else { return nil }

        var joints: [Joint: JointPoint] = [:]
        for (visionName, joint) in jointMap {
            guard let p = points[visionName] else { continue }
            // Vision: normalized, origin bottom-left, y up — exactly our JointPoint convention.
            joints[joint] = JointPoint(x: Double(p.location.x), y: Double(p.location.y), confidence: Double(p.confidence))
        }
        guard !joints.isEmpty else { return nil }
        return PoseFrame(time: time, joints: joints)
    }

    static let jointMap: [VNHumanBodyPoseObservation.JointName: Joint] = [
        .nose: .nose, .neck: .neck, .root: .root,
        .leftShoulder: .leftShoulder, .rightShoulder: .rightShoulder,
        .leftElbow: .leftElbow, .rightElbow: .rightElbow,
        .leftWrist: .leftWrist, .rightWrist: .rightWrist,
        .leftHip: .leftHip, .rightHip: .rightHip,
        .leftKnee: .leftKnee, .rightKnee: .rightKnee,
        .leftAnkle: .leftAnkle, .rightAnkle: .rightAnkle,
    ]
}
