import SwiftUI
import AVFoundation

/// The one shared session. Both displays read it; the clinician's controls, the hinge and the
/// pose engine write it.
@MainActor
@Observable
final class SessionModel {
    enum Source: Equatable {
        case synthetic
        case video(URL)

        var label: String {
            switch self {
            case .synthetic: return "synthetic squat"
            case .video(let url): return url.lastPathComponent
            }
        }
    }

    /// Where the video is expected. Drop `squat.mp4` into ~/duo-hack/design/ and rebuild.
    static let videoName = "squat"
    static let videoExtension = "mp4"

    var source: Source
    var thresholds = SquatThresholds()
    var smoothingAlpha = 0.5

    private(set) var timeline = PoseTimeline()
    private(set) var analysis = SquatAnalysis.empty
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 10
    var videoSize = CGSize(width: 1080, height: 1920)
    var isPlaying = false
    var isReady = false
    /// Restart from the top when the clip ends (demo-friendly). TODO: expose in the UI if wanted.
    var loops = true
    var errorMessage: String?

    // Hinge
    var hingeDegrees: Double?
    var hingeScrubEnabled = true
    /// Fold angle range that maps onto 0…duration. Fully open (180°) clamps to the end.
    var scrubRange: ClosedRange<Double> = 30...170
    private var lastScrubDegrees: Double?
    var isScrubbing = false

    private(set) var engine: PoseEngine?
    var player: AVPlayer? { engine?.player }

    init(source: Source) {
        self.source = source
    }

    /// Video if bundled, synthetic otherwise.
    static func makeDefault() -> SessionModel {
        if let url = Bundle.main.url(forResource: videoName, withExtension: videoExtension, subdirectory: "design") {
            return SessionModel(source: .video(url))
        }
        return SessionModel(source: .synthetic)
    }

    // MARK: - Derived

    var current: AnalyzedFrame? { analysis.frame(at: currentTime) }
    var metrics: SquatMetrics? { current?.metrics }
    var repCount: Int { analysis.repCount }
    var phase: RepCounter.Phase { current?.phase ?? .standing }
    var progress: Double { duration > 0 ? min(max(currentTime / duration, 0), 1) : 0 }

    /// Simple, patient-facing cue for the current frame.
    var patientCue: String {
        guard let m = metrics else { return "Step into frame" }
        if m.isValgus { return "Push your knees out" }
        switch phase {
        case .standing: return repCount == 0 ? "Ready when you are" : "Nice — \(repCount) done"
        case .descending: return "Sit back and down"
        case .bottom: return m.depth >= 1 ? "Good depth" : "A little lower"
        case .ascending: return "Drive up"
        }
    }

    // MARK: - Engine lifecycle

    /// The swap point: synthetic ↔ video.
    private func makeEngine() -> PoseEngine {
        switch source {
        case .synthetic: return SyntheticPoseEngine()
        case .video(let url): return VideoPoseEngine(url: url)
        }
    }

    func start() {
        engine?.stop()
        timeline.removeAll()
        analysis = .empty
        isReady = false
        errorMessage = nil
        let e = makeEngine()
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

    /// Re-run the analysis with new thresholds/smoothing (e.g. after editing them in the UI).
    func reanalyze() {
        analysis = SquatAnalyzer.analyze(timeline.frames, thresholds: thresholds, smoothingAlpha: smoothingAlpha)
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

extension SessionModel: PoseEngineDelegate {
    func engine(_ engine: PoseEngine, isReadyWithDuration duration: TimeInterval, videoSize: CGSize) {
        self.duration = duration
        self.videoSize = videoSize
        isReady = true
    }

    func engine(_ engine: PoseEngine, didProduce frame: PoseFrame) {
        timeline.insert(frame)
        reanalyze()
    }

    func engine(_ engine: PoseEngine, timeDidChange time: TimeInterval) {
        currentTime = time
    }

    func engine(_ engine: PoseEngine, didFail message: String) {
        errorMessage = message
        isPlaying = false
    }

    func engineDidReachEnd(_ engine: PoseEngine) {
        if loops, !isScrubbing {
            seek(to: 0)
            play()
        } else {
            isPlaying = false
        }
    }
}
