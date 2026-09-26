import Foundation

/// Generates a plausible squat as joint coordinates over time, so everything downstream of
/// pose detection can be built and tested before real video exists.
///
/// A stick figure is posed in 3D (lateral x, vertical y, forward z) and projected onto the image
/// plane from a camera `cameraAzimuthDegrees` off the subject's front. 0° = pure frontal (knee
/// flexion invisible, valgus visible); 90° = pure side view (the reverse). ~35° shows both.
///
/// `frame(at:)` is a pure function of `t`, so scrubbing backwards is exact and tests are stable.
struct SyntheticSquat: Equatable {
    /// Seconds per full squat (stand → bottom → stand).
    var period: TimeInterval = 2.5
    /// 0 = clean form, 1 = knees collapse fully inward at the bottom.
    var valgus: Double = 0
    var cameraAzimuthDegrees: Double = 35
    /// Standard deviation of positional noise in normalized units (0 = none). Deterministic per (seed, t, joint).
    var noise: Double = 0
    var seed: UInt64 = 1
    /// Confidence reported for every joint.
    var confidence: Double = 0.9
    /// Rest of the standing pose: ankles sit this high in the frame, figure centred at x = 0.5.
    var groundY: Double = 0.12
    var centerX: Double = 0.5

    // Body proportions in normalized frame units.
    private let thigh = 0.20
    private let shank = 0.20
    private let torso = 0.28
    private let hipHalfWidth = 0.055
    private let kneeHalfWidth = 0.065
    private let ankleHalfWidth = 0.07
    private let shoulderHalfWidth = 0.10

    /// 0 at standing, 1 at the bottom of the squat; smooth cosine cycle.
    func depth(at t: TimeInterval) -> Double {
        let phase = (t / period).truncatingRemainder(dividingBy: 1)
        return 0.5 * (1 - cos(2 * .pi * phase))
    }

    func frame(at t: TimeInterval) -> PoseFrame {
        let d = depth(at: t)
        // Joint angles at the bottom: shank leans 40° forward, thigh 60° back from vertical
        // → 3D knee angle 180 - 100 = 80°.
        let shankAngle = d * 40 * Double.pi / 180
        let thighAngle = d * 60 * Double.pi / 180
        let torsoLean = d * 35 * Double.pi / 180

        // Side-plane (forward z, up y) leg chain from the ankle.
        let ankle3 = (y: 0.0, z: 0.0)
        let knee3 = (y: shank * cos(shankAngle), z: shank * sin(shankAngle))
        let hip3 = (y: knee3.y + thigh * cos(thighAngle), z: knee3.z - thigh * sin(thighAngle))
        let neck3 = (y: hip3.y + torso * cos(torsoLean), z: hip3.z + torso * sin(torsoLean))
        let nose3 = (y: neck3.y + 0.08, z: neck3.z + 0.02)

        // Lateral positions. Subject faces the camera: their left is at +x on screen.
        let collapse = valgus * d * (kneeHalfWidth - 0.01)   // knees move toward the midline
        func leg(side: Double) -> (hip: (x: Double, y: Double, z: Double), knee: (x: Double, y: Double, z: Double), ankle: (x: Double, y: Double, z: Double)) {
            (hip: (side * hipHalfWidth, hip3.y, hip3.z),
             knee: (side * (kneeHalfWidth - collapse), knee3.y, knee3.z),
             ankle: (side * ankleHalfWidth, ankle3.y, ankle3.z))
        }
        let left = leg(side: 1), right = leg(side: -1)

        let az = cameraAzimuthDegrees * Double.pi / 180
        func project(_ p: (x: Double, y: Double, z: Double)) -> (x: Double, y: Double) {
            (x: centerX + p.x * cos(az) + p.z * sin(az), y: groundY + p.y)
        }

        var joints: [Joint: (x: Double, y: Double)] = [
            .leftHip: project(left.hip), .leftKnee: project(left.knee), .leftAnkle: project(left.ankle),
            .rightHip: project(right.hip), .rightKnee: project(right.knee), .rightAnkle: project(right.ankle),
            .root: project((0, hip3.y, hip3.z)),
            .neck: project((0, neck3.y, neck3.z)),
            .nose: project((0, nose3.y, nose3.z)),
            .leftShoulder: project((shoulderHalfWidth, neck3.y - 0.02, neck3.z)),
            .rightShoulder: project((-shoulderHalfWidth, neck3.y - 0.02, neck3.z)),
        ]
        // Arms hang, then come forward for balance as the squat deepens.
        let armDrop = 0.16, armForward = d * 0.18
        joints[.leftElbow] = project((shoulderHalfWidth + 0.02, neck3.y - 0.02 - armDrop * 0.55, neck3.z + armForward * 0.5))
        joints[.rightElbow] = project((-shoulderHalfWidth - 0.02, neck3.y - 0.02 - armDrop * 0.55, neck3.z + armForward * 0.5))
        joints[.leftWrist] = project((shoulderHalfWidth + 0.03, neck3.y - 0.02 - armDrop, neck3.z + armForward))
        joints[.rightWrist] = project((-shoulderHalfWidth - 0.03, neck3.y - 0.02 - armDrop, neck3.z + armForward))

        var out: [Joint: JointPoint] = [:]
        for (joint, p) in joints {
            var x = p.x, y = p.y
            if noise > 0 {
                let (nx, ny) = gaussianPair(seed: seed, t: t, joint: joint)
                x += nx * noise; y += ny * noise
            }
            out[joint] = JointPoint(x: x, y: y, confidence: confidence)
        }
        return PoseFrame(time: t, joints: out)
    }

    func frames(duration: TimeInterval, fps: Double = 30) -> [PoseFrame] {
        let n = Int((duration * fps).rounded(.down))
        return (0...n).map { frame(at: Double($0) / fps) }
    }

    // MARK: - Deterministic noise

    private func gaussianPair(seed: UInt64, t: TimeInterval, joint: Joint) -> (Double, Double) {
        var h = seed &* 0x9E3779B97F4A7C15
        h ^= UInt64(bitPattern: Int64((t * 1000).rounded())) &* 0xBF58476D1CE4E5B9
        h ^= UInt64(joint.hashValueStable) &* 0x94D049BB133111EB
        var state = h
        func next() -> Double {          // SplitMix64 → uniform (0, 1)
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            z ^= z >> 31
            return (Double(z >> 11) + 0.5) / Double(1 << 53)
        }
        let u1 = next(), u2 = next()
        let r = (-2 * log(u1)).squareRoot()
        return (r * cos(2 * .pi * u2), r * sin(2 * .pi * u2))
    }
}

private extension Joint {
    /// `hashValue` is randomized per process; tests need the same noise every run.
    var hashValueStable: Int { Joint.allCases.firstIndex(of: self)! + 1 }
}
