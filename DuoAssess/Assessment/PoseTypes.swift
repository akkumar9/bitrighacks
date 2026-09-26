import Foundation
import CoreGraphics

/// Joints the app tracks. Vision's VNHumanBodyPoseObservation names are mapped onto these in
/// VideoPoseEngine; the synthetic generator emits them directly.
enum Joint: String, CaseIterable, Codable, Hashable {
    case nose, neck, root
    case leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist
    case leftHip, rightHip, leftKnee, rightKnee, leftAnkle, rightAnkle
}

/// A joint position in **normalized image coordinates, Vision convention**:
/// (0, 0) is the bottom-left of the frame, (1, 1) the top-right, y grows upward.
/// Convert to screen points with `StageGeometry` at render time, never before.
struct JointPoint: Equatable, Codable {
    var x: Double
    var y: Double
    var confidence: Double = 1

    init(x: Double, y: Double, confidence: Double = 1) {
        self.x = x; self.y = y; self.confidence = confidence
    }
}

/// One detected (or generated) pose at a moment in the video.
struct PoseFrame: Equatable {
    var time: TimeInterval
    var joints: [Joint: JointPoint]

    subscript(_ joint: Joint) -> JointPoint? { joints[joint] }

    /// The joint if present and confident enough, else nil.
    func joint(_ joint: Joint, minConfidence: Double) -> JointPoint? {
        guard let p = joints[joint], p.confidence >= minConfidence else { return nil }
        return p
    }
}

/// A set of joint positions (any coordinate space) plus the bone list used to draw them.
struct Skeleton: Equatable {
    var joints: [Joint: CGPoint] = [:]

    /// Bones to draw, as joint pairs.
    static let bones: [(Joint, Joint)] = [
        (.nose, .neck),
        (.neck, .leftShoulder), (.neck, .rightShoulder),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.neck, .root),
        (.root, .leftHip), (.root, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
    ]

    /// Bone segments for which both ends are present.
    var segments: [(CGPoint, CGPoint)] {
        Skeleton.bones.compactMap { a, b in
            guard let pa = joints[a], let pb = joints[b] else { return nil }
            return (pa, pb)
        }
    }
}

/// Frames sorted by time. Scrubbing produces frames out of order, so analysis always runs over
/// this ordered list rather than the arrival order.
struct PoseTimeline: Equatable {
    private(set) var frames: [PoseFrame] = []
    /// Frames closer together than this replace each other (same video frame re-analyzed).
    var mergeTolerance: TimeInterval = 1.0 / 120

    var isEmpty: Bool { frames.isEmpty }
    var count: Int { frames.count }
    var duration: TimeInterval { frames.last?.time ?? 0 }

    mutating func insert(_ frame: PoseFrame) {
        // Binary search for the insertion point.
        var lo = 0, hi = frames.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if frames[mid].time < frame.time { lo = mid + 1 } else { hi = mid }
        }
        if lo < frames.count, abs(frames[lo].time - frame.time) < mergeTolerance {
            frames[lo] = frame
        } else if lo > 0, abs(frames[lo - 1].time - frame.time) < mergeTolerance {
            frames[lo - 1] = frame
        } else {
            frames.insert(frame, at: lo)
        }
    }

    mutating func removeAll() { frames.removeAll() }

    /// Nearest frame to `time`, or nil when empty.
    func frame(nearest time: TimeInterval) -> PoseFrame? {
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
