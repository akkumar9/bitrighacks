import Foundation
import AVFoundation

/// Something that produces PoseFrames over time and can be played, paused and scrubbed.
/// Two implementations: `SyntheticPoseEngine` (development, no video) and `VideoPoseEngine`
/// (AVPlayer + Vision). `SessionModel.makeEngine()` is the one-line swap point.
@MainActor
protocol PoseEngine: AnyObject {
    var delegate: PoseEngineDelegate? { get set }
    /// Non-nil for video sources; views hang an AVPlayerLayer on it.
    var player: AVPlayer? { get }
    func start()
    func play()
    func pause()
    func seek(to time: TimeInterval)
    func stop()
}

@MainActor
protocol PoseEngineDelegate: AnyObject {
    func engine(_ engine: PoseEngine, isReadyWithDuration duration: TimeInterval, videoSize: CGSize)
    func engine(_ engine: PoseEngine, didProduce frame: PoseFrame)
    func engine(_ engine: PoseEngine, timeDidChange time: TimeInterval)
    func engine(_ engine: PoseEngine, didFail message: String)
    func engineDidReachEnd(_ engine: PoseEngine)
}

/// Plays a SyntheticSquat on a 30 fps timer. Same delegate traffic as the video engine, so every
/// consumer is exercised before squat.mp4 exists.
@MainActor
final class SyntheticPoseEngine: PoseEngine {
    weak var delegate: PoseEngineDelegate?
    var player: AVPlayer? { nil }

    var generator: SyntheticSquat
    let duration: TimeInterval
    /// Portrait phone video is the expected real input; match its aspect for layout.
    let videoSize = CGSize(width: 1080, height: 1920)
    let fps: Double = 30

    private(set) var time: TimeInterval = 0
    private var timer: Timer?
    private var isPlaying = false

    init(generator: SyntheticSquat = SyntheticSquat(), duration: TimeInterval = 10) {
        self.generator = generator
        self.duration = duration
    }

    func start() {
        delegate?.engine(self, isReadyWithDuration: duration, videoSize: videoSize)
        emit()
        play()
    }

    func play() {
        guard !isPlaying else { return }
        isPlaying = true
        if time >= duration { time = 0 }
        timer = Timer.scheduledTimer(withTimeInterval: 1 / fps, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func pause() {
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }

    func seek(to t: TimeInterval) {
        time = min(max(t, 0), duration)
        emit()
    }

    func stop() { pause() }

    private func tick() {
        guard isPlaying else { return }
        time += 1 / fps
        if time >= duration {
            time = duration
            emit()
            pause()
            delegate?.engineDidReachEnd(self)
            return
        }
        emit()
    }

    private func emit() {
        delegate?.engine(self, didProduce: generator.frame(at: time))
        delegate?.engine(self, timeDidChange: time)
    }
}
