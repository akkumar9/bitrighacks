import Foundation

/// Exponential moving average per joint. Low-confidence joints hold their last good position
/// instead of jumping, so a single bad Vision frame does not twitch the skeleton.
struct PoseSmoother {
    /// 1 = no smoothing, 0.5 = each frame moves halfway to the new sample. Applied per frame,
    /// so it assumes a roughly constant frame rate. TODO: make time-aware if the video's fps varies.
    var alpha: Double = 0.5
    var minConfidence: Double = 0.3

    private var last: [Joint: JointPoint] = [:]

    init(alpha: Double = 0.5, minConfidence: Double = 0.3) {
        self.alpha = alpha
        self.minConfidence = minConfidence
    }

    mutating func reset() { last.removeAll() }

    mutating func smooth(_ frame: PoseFrame) -> PoseFrame {
        var out = frame
        for (joint, raw) in frame.joints {
            if raw.confidence < minConfidence {
                if let held = last[joint] {
                    // Keep the position, report the low confidence so consumers can still hide it.
                    out.joints[joint] = JointPoint(x: held.x, y: held.y, confidence: raw.confidence)
                }
                continue
            }
            if let prev = last[joint] {
                let x = prev.x + alpha * (raw.x - prev.x)
                let y = prev.y + alpha * (raw.y - prev.y)
                let p = JointPoint(x: x, y: y, confidence: raw.confidence)
                out.joints[joint] = p
                last[joint] = p
            } else {
                last[joint] = raw
            }
        }
        return out
    }
}

/// Same idea for a single number (e.g. a knee angle shown on screen).
struct ScalarSmoother {
    var alpha: Double = 0.5
    private var value: Double?

    init(alpha: Double = 0.5) { self.alpha = alpha }

    mutating func reset() { value = nil }

    mutating func smooth(_ sample: Double) -> Double {
        guard let v = value else { value = sample; return sample }
        let next = v + alpha * (sample - v)
        value = next
        return next
    }
}
