import Foundation

/// Any sample with a timestamp, for `Timeline`.
protocol TimedSample {
    var time: Double { get }
}

extension FaceLandmarks: TimedSample {}

/// Time-sorted samples; scrubbing delivers frames out of order and analysis must run in time order.
/// (`PoseTimeline` predates this and is kept as is.)
struct Timeline<Element: TimedSample & Equatable>: Equatable {
    private(set) var samples: [Element] = []
    var mergeTolerance: Double = 1.0 / 120

    var count: Int { samples.count }

    mutating func insert(_ sample: Element) {
        var lo = 0, hi = samples.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if samples[mid].time < sample.time { lo = mid + 1 } else { hi = mid }
        }
        if lo < samples.count, abs(samples[lo].time - sample.time) < mergeTolerance {
            samples[lo] = sample
        } else if lo > 0, abs(samples[lo - 1].time - sample.time) < mergeTolerance {
            samples[lo - 1] = sample
        } else {
            samples.insert(sample, at: lo)
        }
    }

    mutating func removeAll() { samples.removeAll() }
}

struct AnalyzedFace: Equatable, Identifiable {
    var id: Double { time }
    var time: Double
    var landmarks: FaceLandmarks
    /// Smoothed over the window; nil when the frame could not be measured.
    var measures: FaceMeasures?
    /// nil until calibrated.
    var metrics: FaceMetrics?
    var phase: GestureCounter.Phase
    var gestureNumber: Int?
}

struct FaceAnalysis: Equatable {
    var frames: [AnalyzedFace] = []
    var gestures: [Gesture] = []
    var baseline: FaceMeasures?
    /// Landmarks of the last frame that fed the baseline: the patient's resting face, for the ghost.
    var baselineLandmarks: FaceLandmarks?
    /// Frames collected toward the baseline so far (== baselineFrameCount once calibrated).
    var baselineProgress: Int = 0
    var thresholds = FaceThresholds()

    static let empty = FaceAnalysis()

    var isCalibrated: Bool { baseline != nil }
    var gestureCount: Int { gestures.count }

    func frame(at time: Double) -> AnalyzedFace? {
        guard !frames.isEmpty else { return nil }
        var lo = 0, hi = frames.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if frames[mid].time < time { lo = mid + 1 } else { hi = mid }
        }
        if lo > 0, abs(frames[lo - 1].time - time) < abs(frames[lo].time - time) { return frames[lo - 1] }
        return frames[lo]
    }
}

/// Runs measures → moving-average smoothing → baseline calibration → metrics → gesture counting
/// over a time-ordered list of landmarks. Deterministic; the profile re-runs it on every ingest.
enum FaceAnalyzer {
    static func analyze(_ frames: [FaceLandmarks], thresholds t: FaceThresholds = FaceThresholds()) -> FaceAnalysis {
        var out = FaceAnalysis(thresholds: t)
        var window: [FaceMeasures] = []
        var baselineBuffer: [FaceMeasures] = []
        var counter = GestureCounter(thresholds: t)
        out.frames.reserveCapacity(frames.count)

        for lm in frames {
            var analyzed = AnalyzedFace(time: lm.time, landmarks: lm, measures: nil, metrics: nil,
                                        phase: counter.phase, gestureNumber: counter.currentGestureNumber)
            guard lm.confidence >= t.minConfidence, let raw = FaceGeometry.measures(lm) else {
                out.frames.append(analyzed)
                continue
            }

            window.append(raw)
            if window.count > max(t.smoothingWindow, 1) { window.removeFirst() }
            let smoothed = FaceGeometry.mean(window)!
            analyzed.measures = smoothed

            if out.baseline == nil {
                // Resting geometry: the first N stable frames. A jump in mouth position means the
                // person moved, so start over.
                if let running = FaceGeometry.mean(baselineBuffer) {
                    let jump = (abs(smoothed.leftMouthCorner - running.leftMouthCorner)
                                + abs(smoothed.rightMouthCorner - running.rightMouthCorner)) / 2
                    if jump > t.gestureOnsetExcursion { baselineBuffer.removeAll() }
                }
                baselineBuffer.append(smoothed)
                out.baselineProgress = baselineBuffer.count
                if baselineBuffer.count >= t.baselineFrameCount {
                    out.baseline = FaceGeometry.mean(baselineBuffer)
                    out.baselineLandmarks = lm
                }
                out.frames.append(analyzed)
                continue
            }

            let m = FaceGeometry.metrics(current: smoothed, baseline: out.baseline!, thresholds: t)
            analyzed.metrics = m
            counter.update(excursion: m.meanMouthExcursion, left: m.mouthCornerDeltaLeft,
                           right: m.mouthCornerDeltaRight, symmetryScore: m.symmetryScore, time: lm.time)
            analyzed.phase = counter.phase
            analyzed.gestureNumber = counter.currentGestureNumber
            out.frames.append(analyzed)
        }
        out.gestures = counter.gestures
        return out
    }
}
