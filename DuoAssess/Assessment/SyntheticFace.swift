import Foundation
import CoreGraphics

/// Deterministic face landmarks over time so the face profile runs before face.mp4 exists.
/// Rest for half of each `period`, then a smile where the left mouth corner rises by `smile`
/// and the right by `smile * weakSideFactor` (a right-sided deficit by default). Brows and eye
/// aperture follow with their own factors. `frame(at:)` is pure in `t`.
struct SyntheticFace: Equatable {
    var period: Double = 3
    /// Peak lift of the left mouth corner, in interocular units.
    var smile: Double = 0.14
    /// Right side moves this fraction of the left. 1 = symmetric.
    var weakSideFactor: Double = 0.35
    var browFactor: Double = 0.5
    var eyeFactor: Double = 0.35
    /// Resting drop of the right mouth corner (asymmetric at rest, before any gesture).
    var restingAsymmetry: Double = 0
    /// Gaussian noise (normalized image units), deterministic per (seed, t, point). 0 = none.
    var noise: Double = 0
    var seed: UInt64 = 1
    var confidence: Float = 0.95
    /// Face placement in the frame.
    var center = CGPoint(x: 0.5, y: 0.55)
    /// Interocular distance in normalized image units; everything else scales with it.
    var interocular: Double = 0.16

    /// 0 at rest, 1 at the fullest smile. Each period is half rest, then one smooth smile bump,
    /// so a clip opens with enough resting frames for the baseline to calibrate.
    func excursion(at t: Double) -> Double {
        let phase = (t / period).truncatingRemainder(dividingBy: 1)
        guard phase >= 0.5 else { return 0 }
        let s = sin(.pi * (phase - 0.5) / 0.5)
        return s * s
    }

    func frame(at t: Double) -> FaceLandmarks {
        let e = excursion(at: t)
        let iod = interocular
        let cx = Double(center.x), cy = Double(center.y)
        // Subject's left is at +x (facing the camera, unmirrored footage).
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: cx + x * iod, y: cy + y * iod) }

        let liftL = smile * e
        let liftR = smile * weakSideFactor * e
        let browL = smile * browFactor * e, browR = smile * browFactor * weakSideFactor * e
        let squintL = smile * eyeFactor * e, squintR = smile * eyeFactor * weakSideFactor * e

        var lm = FaceLandmarks(time: t)
        // Eyes: six points around each, aperture 0.30 iod at rest, narrowing with the smile.
        func eye(sign: Double, squint: Double) -> [CGPoint] {
            let ex = sign * 0.5, ap = 0.30 - squint
            return [p(ex - 0.18, 0), p(ex - 0.08, ap / 2), p(ex + 0.08, ap / 2),
                    p(ex + 0.18, 0), p(ex + 0.08, -ap / 2), p(ex - 0.08, -ap / 2)]
        }
        lm.leftEye = eye(sign: 1, squint: squintL)
        lm.rightEye = eye(sign: -1, squint: squintR)
        // Brows: five points arched above each eye.
        func brow(sign: Double, lift: Double) -> [CGPoint] {
            let ex = sign * 0.5
            return [p(ex - 0.24, 0.30 + lift), p(ex - 0.12, 0.38 + lift), p(ex, 0.42 + lift),
                    p(ex + 0.12, 0.38 + lift), p(ex + 0.24, 0.30 + lift)]
        }
        lm.leftEyebrow = brow(sign: 1, lift: browL)
        lm.rightEyebrow = brow(sign: -1, lift: browR)
        // Lips: corners at ±0.40, resting 1.05 iod below the eyes; each corner lifts with its side.
        let cornerY = -1.05
        let lY = cornerY + liftL, rY = cornerY - restingAsymmetry + liftR
        lm.outerLips = [p(0.40, lY), p(0.25, cornerY + 0.10 + liftL * 0.5), p(0.08, cornerY + 0.14), p(0, cornerY + 0.15),
                        p(-0.08, cornerY + 0.14), p(-0.25, cornerY + 0.10 + liftR * 0.5), p(-0.40, rY),
                        p(-0.25, cornerY - 0.12 + liftR * 0.5), p(0, cornerY - 0.16), p(0.25, cornerY - 0.12 + liftL * 0.5)]
        lm.innerLips = [p(0.28, lY + 0.02), p(0, cornerY + 0.04), p(-0.28, rY + 0.02), p(0, cornerY - 0.05)]
        lm.nose = [p(0, -0.10), p(0, -0.30), p(0, -0.50), p(-0.16, -0.58), p(0, -0.62), p(0.16, -0.58)]
        lm.medianLine = [p(0, 0.55), p(0, 0.20), p(0, -0.20), p(0, -0.60), p(0, -1.00), p(0, -1.40)]
        lm.confidence = confidence

        if noise > 0 {
            func jitter(_ pts: inout [CGPoint], _ region: Int) {
                for i in pts.indices {
                    let (nx, ny) = gaussianPair(t: t, region: region, index: i)
                    pts[i].x += CGFloat(nx * noise); pts[i].y += CGFloat(ny * noise)
                }
            }
            jitter(&lm.leftEye, 1); jitter(&lm.rightEye, 2); jitter(&lm.leftEyebrow, 3); jitter(&lm.rightEyebrow, 4)
            jitter(&lm.outerLips, 5); jitter(&lm.innerLips, 6); jitter(&lm.nose, 7); jitter(&lm.medianLine, 8)
        }
        return lm
    }

    func frames(duration: Double, fps: Double = 30) -> [FaceLandmarks] {
        let n = Int((duration * fps).rounded(.down))
        return (0...n).map { frame(at: Double($0) / fps) }
    }

    // SplitMix64 → Box–Muller, keyed by (seed, t, region, index) so every frame is reproducible.
    private func gaussianPair(t: Double, region: Int, index: Int) -> (Double, Double) {
        var state = seed &* 0x9E3779B97F4A7C15
        state ^= UInt64(bitPattern: Int64((t * 1000).rounded())) &* 0xBF58476D1CE4E5B9
        state ^= UInt64(region * 131 + index + 1) &* 0x94D049BB133111EB
        func next() -> Double {
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
