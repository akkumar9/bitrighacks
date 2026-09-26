import Foundation
import AVFoundation
import Vision
import QuartzCore
import ImageIO

enum Role: String, CaseIterable {
    case demonstrator, learner

    /// Bundled video for this role: `design/<videoName>.mp4`.
    var videoName: String {
        switch self {
        case .demonstrator: return "demo"
        case .learner: return "learner"
        }
    }
}

/// One person's pose over time. Two of these run side by side, one per camera.
/// Today both are backed by bundled video (`VideoPoseStream`) or a generator
/// (`SyntheticPoseStream`); an `AVCaptureMultiCamSession` port would conform to the same protocol
/// and feed `ingest(pixelBuffer:at:)`-style frames from its two outputs.
@MainActor
protocol PoseStream: AnyObject {
    var role: Role { get }
    var latest: PoseFrame? { get }
    var timeline: PoseTimeline { get }
    var framesAnalysed: Int { get }
    func start()
    func seek(to time: Double)
    func reset()

    // Beyond the minimum contract:
    var delegate: PoseStreamDelegate? { get set }
    /// Non-nil for video; views hang an AVPlayerLayer on it.
    var player: AVPlayer? { get }
    var videoSize: CGSize { get }
    var duration: Double { get }
    var sourceLabel: String { get }
    func play()
    func pause()
    func stop()
}

@MainActor
protocol PoseStreamDelegate: AnyObject {
    func stream(_ stream: PoseStream, isReadyWithDuration duration: Double, videoSize: CGSize)
    func stream(_ stream: PoseStream, didProduce frame: PoseFrame)
    func stream(_ stream: PoseStream, timeDidChange time: Double)
    func streamDidReachEnd(_ stream: PoseStream)
    func stream(_ stream: PoseStream, didFail message: String)
}

// MARK: - Video

/// AVPlayer + AVPlayerItemVideoOutput + its own `VNDetectHumanBodyPoseRequest` on its own serial
/// queue. One request in flight; frames that arrive while busy are skipped, never queued.
/// Detection happens off the main thread; the resulting frame is inserted into the timeline on
/// the main actor so the model reads a consistent picture.
///
/// TODO: unverified against a real file (no demo.mp4 / learner.mp4 yet). Orientation comes from
/// the track's preferredTransform; `applyPreferredTransform` is the switch if the overlay lands
/// sideways.
@MainActor
final class VideoPoseStream: NSObject, PoseStream {
    let role: Role
    weak var delegate: PoseStreamDelegate?
    private(set) var latest: PoseFrame?
    private(set) var timeline = PoseTimeline()
    var framesAnalysed: Int { timeline.count }
    var player: AVPlayer? { avPlayer }
    private(set) var videoSize = CGSize(width: 1080, height: 1920)
    private(set) var duration: Double = 0
    var sourceLabel: String { url.lastPathComponent }

    static let applyPreferredTransform = true

    private let url: URL
    private let avPlayer: AVPlayer
    private let item: AVPlayerItem
    private let output: AVPlayerItemVideoOutput
    private let visionQueue: DispatchQueue
    private var displayLink: CADisplayLink?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var orientation: CGImagePropertyOrientation = .up
    private var inFlight = false
    private var reportedReady = false

    init(role: Role, url: URL) {
        self.role = role
        self.url = url
        visionQueue = DispatchQueue(label: "duoassess.vision.\(role.rawValue)", qos: .userInitiated)
        item = AVPlayerItem(url: url)
        output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        item.add(output)
        avPlayer = AVPlayer(playerItem: item)
        avPlayer.actionAtItemEnd = .pause
        super.init()
    }

    func start() {
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in self?.statusChanged() }
        }
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] t in
            Task { @MainActor in
                guard let self else { return }
                self.delegate?.stream(self, timeDidChange: t.seconds)
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.delegate?.streamDidReachEnd(self)
            }
        }
    }

    func play() { avPlayer.play() }
    func pause() { avPlayer.pause() }

    func seek(to time: Double) {
        avPlayer.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func reset() {
        timeline.removeAll()
        latest = nil
    }

    func stop() {
        avPlayer.pause()
        displayLink?.invalidate()
        displayLink = nil
        if let timeObserver { avPlayer.removeTimeObserver(timeObserver) }
        timeObserver = nil
        statusObservation = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }

    private func statusChanged() {
        switch item.status {
        case .readyToPlay:
            guard !reportedReady else { return }
            reportedReady = true
            Task { await prepareAndReport() }
        case .failed:
            delegate?.stream(self, didFail: item.error?.localizedDescription ?? "AVPlayerItem failed")
        default:
            break
        }
    }

    private func prepareAndReport() async {
        var size = item.presentationSize
        var dur = item.duration.seconds
        if let track = try? await item.asset.loadTracks(withMediaType: .video).first,
           let (natural, transform) = try? await track.load(.naturalSize, .preferredTransform) {
            if Self.applyPreferredTransform { orientation = VideoEngine.orientation(for: transform) }
            let rect = CGRect(origin: .zero, size: natural).applying(transform)
            if rect.width > 0, rect.height > 0 { size = CGSize(width: abs(rect.width), height: abs(rect.height)) }
        }
        if !dur.isFinite || dur <= 0, let d = try? await item.asset.load(.duration) { dur = d.seconds }
        videoSize = size
        duration = dur
        delegate?.stream(self, isReadyWithDuration: dur, videoSize: size)

        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard !inFlight else { return }
        let itemTime = output.itemTime(forHostTime: link.timestamp + link.duration)
        guard output.hasNewPixelBuffer(forItemTime: itemTime) else { return }
        var displayTime = CMTime.zero
        guard let pixelBuffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: &displayTime) else { return }
        inFlight = true
        let seconds = displayTime.seconds
        let orientation = self.orientation
        visionQueue.async { [weak self] in
            let frame = SquatProfile.detectPose(in: pixelBuffer, at: seconds, orientation: orientation)
            Task { @MainActor in
                guard let self else { return }
                self.inFlight = false
                if let frame { self.record(frame) }
            }
        }
    }

    private func record(_ frame: PoseFrame) {
        timeline.insert(frame)
        latest = frame
        delegate?.stream(self, didProduce: frame)
    }
}

// MARK: - Synthetic

/// Plays a `SyntheticSquat` on a timer. The learner variant is the demonstrator mirrored (as two
/// people facing each other are), delayed by `learnerLag`, with one wrist pushed off its true
/// position so there is always visible error to render.
@MainActor
final class SyntheticPoseStream: PoseStream {
    let role: Role
    weak var delegate: PoseStreamDelegate?
    private(set) var latest: PoseFrame?
    private(set) var timeline = PoseTimeline()
    var framesAnalysed: Int { timeline.count }
    var player: AVPlayer? { nil }
    let videoSize = CGSize(width: 1080, height: 1920)
    let duration: Double
    var sourceLabel: String { "synthetic" }

    var generator = SyntheticSquat()
    /// Seconds the synthetic learner trails the demonstrator.
    var learnerLag: Double = 0.3
    /// Joint the synthetic learner gets wrong, and by how much (normalized image units).
    var learnerOffset: (joint: Joint, dx: Double, dy: Double) = (.leftWrist, 0.07, 0.03)

    private let fps: Double = 30
    private(set) var time: Double = 0
    private var timer: Timer?
    private var isPlaying = false
    private var inFlight = false
    private let queue: DispatchQueue

    init(role: Role, duration: Double = 10) {
        self.role = role
        self.duration = duration
        queue = DispatchQueue(label: "duoassess.synthetic.\(role.rawValue)", qos: .userInitiated)
    }

    func start() {
        delegate?.stream(self, isReadyWithDuration: duration, videoSize: videoSize)
        emit()
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

    func seek(to t: Double) {
        time = min(max(t, 0), duration)
        emit()
    }

    func reset() {
        timeline.removeAll()
        latest = nil
    }

    func stop() { pause() }

    private func tick() {
        guard isPlaying else { return }
        time += 1 / fps
        if time >= duration {
            time = duration
            emit()
            pause()
            delegate?.streamDidReachEnd(self)
            return
        }
        emit()
    }

    /// Pure in `t`, so scrubbing is exact.
    func frame(at t: Double) -> PoseFrame {
        switch role {
        case .demonstrator:
            return generator.frame(at: t)
        case .learner:
            var f = generator.frame(at: max(t - learnerLag, 0)).mirrored()
            f.time = t
            if var p = f.joints[learnerOffset.joint] {
                p.x += learnerOffset.dx; p.y += learnerOffset.dy
                f.joints[learnerOffset.joint] = p
            }
            return f
        }
    }

    private func emit() {
        let t = time
        delegate?.stream(self, timeDidChange: t)
        guard !inFlight else { return }
        inFlight = true
        let frame = self.frame(at: t)
        queue.async { [weak self] in
            // Nothing heavy here; the hop mirrors the video path so timing behaves the same.
            Task { @MainActor in
                guard let self else { return }
                self.inFlight = false
                self.timeline.insert(frame)
                self.latest = frame
                self.delegate?.stream(self, didProduce: frame)
            }
        }
    }
}

extension PoseFrame {
    /// Flip left/right in the image and relabel the joints, i.e. the same pose seen from the
    /// other side of the phone.
    func mirrored() -> PoseFrame {
        var out = PoseFrame(time: time, joints: [:])
        for (joint, p) in joints {
            out.joints[joint.mirrored] = JointPoint(x: 1 - p.x, y: p.y, confidence: p.confidence)
        }
        return out
    }
}

extension Joint {
    /// The same joint on the other side of the body.
    var mirrored: Joint {
        switch self {
        case .leftShoulder: return .rightShoulder
        case .rightShoulder: return .leftShoulder
        case .leftElbow: return .rightElbow
        case .rightElbow: return .leftElbow
        case .leftWrist: return .rightWrist
        case .rightWrist: return .leftWrist
        case .leftHip: return .rightHip
        case .rightHip: return .leftHip
        case .leftKnee: return .rightKnee
        case .rightKnee: return .leftKnee
        case .leftAnkle: return .rightAnkle
        case .rightAnkle: return .leftAnkle
        case .nose, .neck, .root: return self
        }
    }
}
