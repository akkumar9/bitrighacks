import Foundation
import AVFoundation

/// Feeds frames to the current profile and drives the clock. Two implementations:
/// `SyntheticEngine` (no video) and `VideoEngine` (AVPlayer + Vision).
@MainActor
protocol AssessmentEngine: AnyObject {
    var delegate: AssessmentEngineDelegate? { get set }
    /// Non-nil for video sources; views hang an AVPlayerLayer on it.
    var player: AVPlayer? { get }
    func start()
    func play()
    func pause()
    func seek(to time: TimeInterval)
    func stop()
}

@MainActor
protocol AssessmentEngineDelegate: AnyObject {
    func engine(_ engine: AssessmentEngine, isReadyWithDuration duration: TimeInterval, videoSize: CGSize,
                orientation: CGImagePropertyOrientation)
    /// The profile has finished ingesting a frame; read `profile.readout()` now.
    func engineDidProcessFrame(_ engine: AssessmentEngine)
    func engine(_ engine: AssessmentEngine, timeDidChange time: TimeInterval)
    func engine(_ engine: AssessmentEngine, didFail message: String)
    func engineDidReachEnd(_ engine: AssessmentEngine)
}

/// Routes frames from an engine's background queue to whichever profile is current.
/// Swapping the profile is one assignment; the engine never knows.
final class ProfileSink: @unchecked Sendable {
    private let lock = NSLock()
    private var _profile: any Profile

    init(profile: any Profile) { _profile = profile }

    var profile: any Profile {
        get { lock.withLock { _profile } }
        set { lock.withLock { _profile = newValue } }
    }

    func ingest(pixelBuffer: CVPixelBuffer, at time: Double) {
        profile.ingest(pixelBuffer: pixelBuffer, at: time)
    }

    func ingestSynthetic(at time: Double) {
        profile.ingestSynthetic(at: time)
    }
}

/// Runs the profile's own synthetic generator on a 30 fps timer, off the main thread, with the
/// same delegate traffic as the video engine.
@MainActor
final class SyntheticEngine: AssessmentEngine {
    weak var delegate: AssessmentEngineDelegate?
    var player: AVPlayer? { nil }

    private let sink: ProfileSink
    let duration: TimeInterval
    let videoSize: CGSize
    let fps: Double = 30

    private(set) var time: TimeInterval = 0
    private var timer: Timer?
    private var isPlaying = false
    private var inFlight = false
    private let queue = DispatchQueue(label: "duoassess.synthetic", qos: .userInitiated)

    init(sink: ProfileSink, duration: TimeInterval, videoSize: CGSize) {
        self.sink = sink
        self.duration = duration
        self.videoSize = videoSize
    }

    func start() {
        delegate?.engine(self, isReadyWithDuration: duration, videoSize: videoSize, orientation: .up)
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
        let t = time
        delegate?.engine(self, timeDidChange: t)
        guard !inFlight else { return }        // skip, never queue
        inFlight = true
        queue.async { [sink] in
            sink.ingestSynthetic(at: t)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.inFlight = false
                self.delegate?.engineDidProcessFrame(self)
            }
        }
    }
}
