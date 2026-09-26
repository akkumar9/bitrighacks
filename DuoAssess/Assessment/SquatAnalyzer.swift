import Foundation

/// A frame after smoothing, with its metrics and where it sits in the rep sequence.
struct AnalyzedFrame: Equatable, Identifiable {
    var id: TimeInterval { time }
    var time: TimeInterval
    var raw: PoseFrame
    var smoothed: PoseFrame
    var metrics: SquatMetrics?
    var phase: RepCounter.Phase
    /// 1-based number of the rep this frame belongs to, nil while standing.
    var repNumber: Int?
}

struct SquatAnalysis: Equatable {
    var frames: [AnalyzedFrame] = []
    var reps: [Rep] = []
    var thresholds = SquatThresholds()

    static let empty = SquatAnalysis()

    var repCount: Int { reps.count }
    var isEmpty: Bool { frames.isEmpty }

    /// Frame nearest to `time`.
    func frame(at time: TimeInterval) -> AnalyzedFrame? {
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

/// Runs smoothing → metrics → rep counting over a time-ordered list of frames.
/// Deterministic and cheap (a few hundred frames), so the model just re-runs it on every ingest.
enum SquatAnalyzer {
    static func analyze(_ frames: [PoseFrame], thresholds: SquatThresholds = SquatThresholds(),
                        smoothingAlpha: Double = 0.5) -> SquatAnalysis {
        var smoother = PoseSmoother(alpha: smoothingAlpha, minConfidence: thresholds.minConfidence)
        var counter = RepCounter(thresholds: thresholds)
        var out: [AnalyzedFrame] = []
        out.reserveCapacity(frames.count)

        for raw in frames {
            let smoothed = smoother.smooth(raw)
            let metrics = SquatMetrics.compute(from: smoothed, thresholds: thresholds)
            if let m = metrics, let angle = m.kneeAngle {
                counter.update(kneeAngle: angle, isValgus: m.isValgus, time: raw.time)
            }
            out.append(AnalyzedFrame(time: raw.time, raw: raw, smoothed: smoothed, metrics: metrics,
                                     phase: counter.phase, repNumber: counter.currentRepNumber))
        }
        return SquatAnalysis(frames: out, reps: counter.reps, thresholds: thresholds)
    }
}
