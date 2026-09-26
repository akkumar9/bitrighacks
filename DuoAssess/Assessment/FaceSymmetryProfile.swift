import Foundation
import CoreGraphics
import CoreVideo
import Vision

/// Facial symmetry: mouth-corner, eyebrow and eye-aperture travel per side, relative to a resting
/// baseline, with gesture counting. Adapter over `FaceGeometry`, `GestureCounter` and `FaceAnalyzer`.
final class FaceSymmetryProfile: Profile {
    let id = "face"
    let displayName = "Face symmetry"
    let videoName = "face"
    var imageOrientation: CGImagePropertyOrientation = .up
    var syntheticDuration: Double { synthetic.period * 4 + 1 }   // last release needs a beat to finish
    let syntheticVideoSize = CGSize(width: 1080, height: 1920)

    private let lock = NSLock()
    private var thresholds = FaceThresholds()
    private var timeline = Timeline<FaceLandmarks>()
    private var analysis = FaceAnalysis.empty
    private var lastTime: Double?
    private var synthetic = SyntheticFace()

    var framesAnalysed: Int { lock.withLock { timeline.count } }

    // MARK: - Ingest

    func ingest(pixelBuffer: CVPixelBuffer, at time: Double) {
        guard let lm = Self.detectLandmarks(in: pixelBuffer, at: time, orientation: imageOrientation) else { return }
        lock.withLock {
            timeline.insert(lm)
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

    /// Drop the baseline: keep only frames from the playhead on, so calibration restarts there.
    func recalibrate() {
        lock.withLock {
            let from = lastTime ?? 0
            var kept = Timeline<FaceLandmarks>()
            for s in timeline.samples where s.time >= from { kept.insert(s) }
            timeline = kept
            reanalyze()
        }
    }

    private func reanalyze() {
        analysis = FaceAnalyzer.analyze(timeline.samples, thresholds: thresholds)
    }

    // MARK: - Output

    func readout() -> Readout {
        lock.withLock {
            let current = lastTime.flatMap { analysis.frame(at: $0) }
            let m = current?.metrics
            let phase = current?.phase ?? .rest
            let calibrated = analysis.isCalibrated
            let t = thresholds

            func d(_ v: Double?) -> String { v.map { String(format: "%+.3f", $0) } ?? "—" }
            var metrics: [Metric] = [
                Metric(id: "cal", label: "Baseline", value: calibrated ? "ready" : "\(analysis.baselineProgress)/\(t.baselineFrameCount)",
                       flagged: !calibrated),
                Metric(id: "score", label: "Symmetry", value: m.map { String(format: "%.0f", $0.symmetryScore) } ?? "—",
                       flagged: (m?.symmetryScore ?? 100) < 70),
                Metric(id: "phase", label: "Phase", value: phase.rawValue.capitalized),
                Metric(id: "mouthL", label: "Mouth L", value: d(m?.mouthCornerDeltaLeft)),
                Metric(id: "mouthR", label: "Mouth R", value: d(m?.mouthCornerDeltaRight)),
                Metric(id: "browL", label: "Brow L", value: d(m?.eyebrowDeltaLeft)),
                Metric(id: "browR", label: "Brow R", value: d(m?.eyebrowDeltaRight)),
                Metric(id: "eyeL", label: "Eye L", value: d(m?.eyeApertureDeltaLeft)),
                Metric(id: "eyeR", label: "Eye R", value: d(m?.eyeApertureDeltaRight)),
                Metric(id: "side", label: "Affected side", value: m?.affectedSide.rawValue ?? "—",
                       flagged: (m?.affectedSide ?? .none) != .none),
            ]
            if let g = current?.gestureNumber { metrics.append(Metric(id: "gesture", label: "Gesture in progress", value: "#\(g)")) }

            var overlay: Overlay = .none
            if let lm = current?.landmarks {
                overlay = .face(points: lm.allPoints, midline: FaceGeometry.midline(lm),
                                ghost: analysis.baselineLandmarks?.allPoints ?? [])
            }

            let progress = m.map { min(max($0.meanMouthExcursion / (2 * t.gesturePeakExcursion), 0), 1) }

            return Readout(metrics: metrics,
                           cue: Self.cue(calibrated: calibrated, metrics: m, phase: phase, count: analysis.gestureCount),
                           progress: calibrated ? progress : nil,
                           overlay: overlay,
                           completedCount: analysis.gestureCount,
                           phase: phase.rawValue)
        }
    }

    private static func cue(calibrated: Bool, metrics m: FaceMetrics?, phase: GestureCounter.Phase, count: Int) -> Cue {
        guard calibrated else { return Cue(text: "Hold still and relax your face") }
        guard let m else { return Cue(text: "Face the camera") }
        switch phase {
        case .rest:
            return count == 0 ? Cue(text: "Now smile as big as you can") : Cue(text: "Relax, then again", tone: .good)
        case .onset:
            return Cue(text: "Keep going")
        case .peak:
            return m.affectedSide == .none ? Cue(text: "Hold it there", tone: .good) : Cue(text: "Lift both sides evenly", tone: .correct)
        case .release:
            return Cue(text: "And relax")
        }
    }

    var log: [LogEntry] {
        lock.withLock {
            analysis.gestures.map {
                LogEntry(id: $0.id, title: "Gesture #\($0.id)",
                         detail: String(format: "min %.0f · L %+.2f R %+.2f", $0.minSymmetryScore, $0.peakExcursionLeft, $0.peakExcursionRight),
                         flagged: $0.affectedSide != .none, time: $0.peakTime)
            }
        }
    }

    var controls: [ThresholdControl] {
        [
            ThresholdControl(id: "onset", label: "Onset", range: 0.01...0.15, step: 0.005,
                             format: { String(format: "%.3f", $0) },
                             get: { [unowned self] in lock.withLock { thresholds.gestureOnsetExcursion } },
                             set: { [unowned self] v in lock.withLock { thresholds.gestureOnsetExcursion = v; reanalyze() } }),
            ThresholdControl(id: "peakExc", label: "Peak", range: 0.02...0.3, step: 0.005,
                             format: { String(format: "%.3f", $0) },
                             get: { [unowned self] in lock.withLock { thresholds.gesturePeakExcursion } },
                             set: { [unowned self] v in lock.withLock { thresholds.gesturePeakExcursion = v; reanalyze() } }),
            ThresholdControl(id: "asym", label: "Asymmetry", range: 0.005...0.1, step: 0.005,
                             format: { String(format: "%.3f", $0) },
                             get: { [unowned self] in lock.withLock { thresholds.asymmetryFlag } },
                             set: { [unowned self] v in lock.withLock { thresholds.asymmetryFlag = v; reanalyze() } }),
            ThresholdControl(id: "window", label: "Smoothing", range: 1...15, step: 1,
                             format: { String(format: "%.0f", $0) },
                             get: { [unowned self] in lock.withLock { Double(thresholds.smoothingWindow) } },
                             set: { [unowned self] v in lock.withLock { thresholds.smoothingWindow = Int(v); reanalyze() } }),
        ]
    }

    // MARK: - Vision

    /// Runs on the engine's queue. Region points are normalized to the face bounding box; they
    /// are converted to image space here so no math downstream sees box coordinates.
    static func detectLandmarks(in pixelBuffer: CVPixelBuffer, at time: Double,
                                orientation: CGImagePropertyOrientation) -> FaceLandmarks? {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        do { try handler.perform([request]) } catch { return nil }
        guard let face = request.results?.first, let landmarks = face.landmarks else { return nil }

        let bb = face.boundingBox
        func toImage(_ region: VNFaceLandmarkRegion2D?) -> [CGPoint] {
            guard let region else { return [] }
            return region.normalizedPoints.map {
                CGPoint(x: bb.origin.x + $0.x * bb.width, y: bb.origin.y + $0.y * bb.height)
            }
        }
        var lm = FaceLandmarks(time: time)
        lm.leftEye = toImage(landmarks.leftEye)
        lm.rightEye = toImage(landmarks.rightEye)
        lm.leftEyebrow = toImage(landmarks.leftEyebrow)
        lm.rightEyebrow = toImage(landmarks.rightEyebrow)
        lm.outerLips = toImage(landmarks.outerLips)
        lm.innerLips = toImage(landmarks.innerLips)
        lm.nose = toImage(landmarks.nose)
        lm.medianLine = toImage(landmarks.medianLine)
        lm.confidence = landmarks.confidence
        return lm
    }
}
