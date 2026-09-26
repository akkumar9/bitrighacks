import SwiftUI
import AVFoundation

/// The shared "copy me" session: two pose streams, one clock, one match result.
/// Both displays read it; the deck, the hinge and the streams write it.
@MainActor
@Observable
final class CopyMeSession {
    private(set) var demonstrator: PoseStream
    private(set) var learner: PoseStream

    var thresholds = MatchThresholds() {
        didSet { smoother = MatchSmoother(window: thresholds.smoothingWindow, badJointError: thresholds.badJointError); refresh() }
    }
    /// Smoothed comparison of the learner's latest frame against the demonstrator's timeline.
    private(set) var result: MatchResult?
    private var smoother = MatchSmoother(window: 5, badJointError: 25)

    var currentTime: Double = 0
    var duration: Double = 10
    var isPlaying = false
    var errorMessage: String?
    var loops = true

    // Hinge
    var hingeDegrees: Double?
    var hingeScrubEnabled = true
    var scrubRange: ClosedRange<Double> = 30...170
    private var lastScrubDegrees: Double?
    var isScrubbing = false

    init(demonstrator: PoseStream, learner: PoseStream) {
        self.demonstrator = demonstrator
        self.learner = learner
    }

    /// Video per role if `design/<name>.mp4` is bundled, synthetic otherwise. Independent per stream.
    static func makeStream(role: Role, bundle: Bundle = .main) -> PoseStream {
        if let url = bundle.url(forResource: role.videoName, withExtension: "mp4", subdirectory: "design") {
            return VideoPoseStream(role: role, url: url)
        }
        return SyntheticPoseStream(role: role)
    }

    static func makeDefault() -> CopyMeSession {
        CopyMeSession(demonstrator: makeStream(role: .demonstrator), learner: makeStream(role: .learner))
    }

    var sourceLabel: String { "demo \(demonstrator.sourceLabel) · learner \(learner.sourceLabel)" }

    // MARK: - Lifecycle

    func start() {
        for s in [demonstrator, learner] {
            s.delegate = self
            s.reset()
            s.start()
        }
        currentTime = 0
        lastScrubDegrees = nil
        errorMessage = nil
        play()
    }

    func stop() {
        demonstrator.stop()
        learner.stop()
        isPlaying = false
    }

    func play() {
        isScrubbing = false
        demonstrator.play()
        learner.play()
        isPlaying = true
    }

    func pause() {
        demonstrator.pause()
        learner.pause()
        isPlaying = false
    }

    func togglePlayback() { isPlaying ? pause() : play() }

    /// Both streams together, so they stay locked.
    func seek(to time: Double) {
        let t = min(max(time, 0), duration)
        currentTime = t
        demonstrator.seek(to: t)
        learner.seek(to: t)
    }

    /// Drop both timelines and the smoothing, keep the playhead.
    func reset() {
        demonstrator.reset()
        learner.reset()
        smoother = MatchSmoother(window: thresholds.smoothingWindow, badJointError: thresholds.badJointError)
        result = nil
    }

    // MARK: - Matching

    /// Compare the learner's latest frame against the demonstrator's recent frames, smoothed.
    func refresh() {
        guard let l = learner.latest else { result = nil; return }
        let raw = PoseMatch.match(learner: l, against: demonstrator.timeline, thresholds: thresholds)
        result = smoother.push(raw)
    }

    // MARK: - Hinge → scrub

    /// Fold angle drives the shared playhead. The first sample only calibrates; movement beyond
    /// half a degree (the jitter band) pauses playback and seeks both streams.
    func hingeChanged(degrees: Double) {
        hingeDegrees = degrees
        guard hingeScrubEnabled, duration > 0 else { return }
        guard let last = lastScrubDegrees else { lastScrubDegrees = degrees; return }
        guard abs(degrees - last) >= 0.5 else { return }
        lastScrubDegrees = degrees
        let span = scrubRange.upperBound - scrubRange.lowerBound
        let t = min(max((degrees - scrubRange.lowerBound) / span, 0), 1)
        if isPlaying { pause() }
        isScrubbing = true
        seek(to: t * duration)
    }
}

extension CopyMeSession: PoseStreamDelegate {
    func stream(_ stream: PoseStream, isReadyWithDuration d: Double, videoSize: CGSize) {
        // The shared clock runs to the shorter clip.
        let other = stream.role == .demonstrator ? learner : demonstrator
        duration = other.duration > 0 ? min(d, other.duration) : d
    }

    func stream(_ stream: PoseStream, didProduce frame: PoseFrame) {
        refresh()
    }

    func stream(_ stream: PoseStream, timeDidChange time: Double) {
        if stream.role == .demonstrator { currentTime = time }
    }

    func streamDidReachEnd(_ stream: PoseStream) {
        guard stream.role == .demonstrator else { return }
        if loops, !isScrubbing {
            seek(to: 0)
            play()
        } else {
            pause()
        }
    }

    func stream(_ stream: PoseStream, didFail message: String) {
        errorMessage = "\(stream.role.rawValue): \(message)"
        // TODO: swap this stream for a SyntheticPoseStream instead of stopping it.
    }
}
