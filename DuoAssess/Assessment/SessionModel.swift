import SwiftUI
import AVFoundation
import ImageIO

/// The one shared session. Both displays read it; the clinician's controls, the hinge and the
/// engine write it. Holds the current `Profile` and the readout it last produced.
@MainActor
@Observable
final class SessionModel {
    enum Source: Equatable {
        case synthetic
        case video(URL)

        var label: String {
            switch self {
            case .synthetic: return "synthetic"
            case .video(let url): return url.lastPathComponent
            }
        }
    }

    let profiles: [any Profile]
    private(set) var profile: any Profile
    private let sink: ProfileSink

    private(set) var source: Source = .synthetic
    private(set) var readout: Readout = .empty
    private(set) var framesAnalysed = 0
    private(set) var log: [LogEntry] = []
    /// Bumped on every readout refresh so views bound to `controls` closures re-read them.
    private(set) var revision = 0

    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 10
    var videoSize = CGSize(width: 1080, height: 1920)
    private(set) var videoOrientation: CGImagePropertyOrientation = .up
    var isPlaying = false
    var isReady = false
    var errorMessage: String?
    /// Restart from the top when the clip ends.
    var loops = true

    // Hinge
    var hingeDegrees: Double?
    var hingeScrubEnabled = true
    /// Fold angle range that maps onto 0…duration. Fully open (180°) clamps to the end.
    var scrubRange: ClosedRange<Double> = 30...170
    private var lastScrubDegrees: Double?
    var isScrubbing = false

    private(set) var engine: AssessmentEngine?
    var player: AVPlayer? { engine?.player }

    init(profiles: [any Profile]) {
        precondition(!profiles.isEmpty)
        self.profiles = profiles
        self.profile = profiles[0]
        self.sink = ProfileSink(profile: profiles[0])
    }

    static func makeDefault() -> SessionModel {
        SessionModel(profiles: [SquatProfile(), FaceSymmetryProfile()])
    }

    // MARK: - Derived

    var progress: Double { duration > 0 ? min(max(currentTime / duration, 0), 1) : 0 }
    var sourceLabel: String { "\(profile.displayName) · \(source.label)" }

    // MARK: - Profiles

    /// Video if `design/<videoName>.mp4` is bundled, synthetic otherwise.
    static func source(for profile: any Profile) -> Source {
        if let url = Bundle.main.url(forResource: profile.videoName, withExtension: "mp4", subdirectory: "design") {
            return .video(url)
        }
        return .synthetic
    }

    /// Swap the running assessment. One assignment plus reset(); the engine is rebuilt because the
    /// two profiles may consume different videos.
    func select(_ next: any Profile) {
        guard next !== profile else { return }
        engine?.stop()
        next.reset()
        profile = next
        sink.profile = next
        start()
    }

    func selectProfile(id: String) {
        if let p = profiles.first(where: { $0.id == id }) { select(p) }
    }

    // MARK: - Engine lifecycle

    func start() {
        engine?.stop()
        profile.reset()
        readout = .empty
        log = []
        framesAnalysed = 0
        isReady = false
        errorMessage = nil
        currentTime = 0
        lastScrubDegrees = nil
        source = Self.source(for: profile)

        let e: AssessmentEngine
        switch source {
        case .synthetic:
            e = SyntheticEngine(sink: sink, duration: profile.syntheticDuration, videoSize: profile.syntheticVideoSize)
        case .video(let url):
            e = VideoEngine(url: url, sink: sink)
        }
        e.delegate = self
        engine = e
        e.start()
        isPlaying = true
    }

    func stop() {
        engine?.stop()
        engine = nil
        isPlaying = false
    }

    func play() {
        isScrubbing = false
        engine?.play()
        isPlaying = true
    }

    func pause() {
        engine?.pause()
        isPlaying = false
    }

    func togglePlayback() { isPlaying ? pause() : play() }

    func seek(to time: TimeInterval) {
        let t = min(max(time, 0), duration)
        currentTime = t
        engine?.seek(to: t)
    }

    /// Drop the profile's calibration/history and keep going from the playhead.
    func recalibrate() {
        profile.recalibrate()
        refresh()
    }

    /// Pull the latest readout from the profile (after a frame, a threshold change, a swap).
    func refresh() {
        readout = profile.readout()
        framesAnalysed = profile.framesAnalysed
        log = profile.log
        revision &+= 1
    }

    // MARK: - Hinge → scrub

    /// Fold angle drives the playhead. The first sample only calibrates (so launching in Open
    /// pose does not jump to the end); after that any movement over half a degree pauses playback
    /// and seeks. Press Play to hand control back to the transport.
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

extension SessionModel: AssessmentEngineDelegate {
    func engine(_ engine: AssessmentEngine, isReadyWithDuration duration: TimeInterval, videoSize: CGSize,
                orientation: CGImagePropertyOrientation) {
        self.duration = duration
        self.videoSize = videoSize
        self.videoOrientation = orientation
        profile.imageOrientation = orientation
        isReady = true
    }

    func engineDidProcessFrame(_ engine: AssessmentEngine) {
        refresh()
    }

    func engine(_ engine: AssessmentEngine, timeDidChange time: TimeInterval) {
        currentTime = time
    }

    func engine(_ engine: AssessmentEngine, didFail message: String) {
        errorMessage = message
        isPlaying = false
    }

    func engineDidReachEnd(_ engine: AssessmentEngine) {
        if loops, !isScrubbing {
            seek(to: 0)
            play()
        } else {
            isPlaying = false
        }
    }
}
