import Foundation
import AVFoundation
import QuartzCore
import ImageIO

/// AVPlayer → AVPlayerItemVideoOutput → the current profile's `ingest(pixelBuffer:at:)`.
///
/// A CADisplayLink on the main thread pulls the pixel buffer for the current item time and hands
/// it to a serial background queue where the profile runs its Vision request. At most one frame
/// is in flight; frames that arrive while busy are skipped, never queued. Scrubbing works the same
/// way: after a seek the output has a new pixel buffer, the link picks it up, the profile gets it.
///
/// TODO: verify on real footage: (1) the overlay lines up with the AVPlayerLayer picture — if it
/// is rotated, `applyPreferredTransform` is the switch; (2) Vision keeps up at 30 fps on the sim.
@MainActor
final class VideoEngine: NSObject, AssessmentEngine {
    weak var delegate: AssessmentEngineDelegate?
    var player: AVPlayer? { avPlayer }

    private let sink: ProfileSink
    private let avPlayer: AVPlayer
    private let item: AVPlayerItem
    private let output: AVPlayerItemVideoOutput
    private var displayLink: CADisplayLink?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var inFlight = false
    private var reportedReady = false

    /// Rotate frames by the track's preferredTransform before Vision runs. Portrait iPhone
    /// recordings are stored landscape + transform; the player applies the transform when
    /// drawing, so Vision must too or the overlay lands sideways.
    static let applyPreferredTransform = true

    private let visionQueue = DispatchQueue(label: "duoassess.vision", qos: .userInitiated)

    init(url: URL, sink: ProfileSink) {
        self.sink = sink
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
                self.delegate?.engine(self, timeDidChange: t.seconds)
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.delegate?.engineDidReachEnd(self)
            }
        }
    }

    func play() { avPlayer.play() }
    func pause() { avPlayer.pause() }

    func seek(to time: TimeInterval) {
        avPlayer.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
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

    // MARK: - Setup once the item is ready

    private func statusChanged() {
        switch item.status {
        case .readyToPlay:
            guard !reportedReady else { return }
            reportedReady = true
            Task { await prepareAndReport() }
        case .failed:
            delegate?.engine(self, didFail: item.error?.localizedDescription ?? "AVPlayerItem failed")
        default:
            break
        }
    }

    private func prepareAndReport() async {
        var size = item.presentationSize
        var duration = item.duration.seconds
        var orientation = CGImagePropertyOrientation.up
        if let track = try? await item.asset.loadTracks(withMediaType: .video).first,
           let (natural, transform) = try? await track.load(.naturalSize, .preferredTransform) {
            if Self.applyPreferredTransform { orientation = Self.orientation(for: transform) }
            let rect = CGRect(origin: .zero, size: natural).applying(transform)
            if rect.width > 0, rect.height > 0 { size = CGSize(width: abs(rect.width), height: abs(rect.height)) }
        }
        if !duration.isFinite || duration <= 0, let d = try? await item.asset.load(.duration) {
            duration = d.seconds
        }
        delegate?.engine(self, isReadyWithDuration: duration, videoSize: size, orientation: orientation)

        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
        link.add(to: .main, forMode: .common)
        displayLink = link
        avPlayer.play()
    }

    /// Maps a track transform onto the orientation Vision needs to see the frame upright.
    static func orientation(for t: CGAffineTransform) -> CGImagePropertyOrientation {
        switch (t.a, t.b, t.c, t.d) {
        case (0, 1, -1, 0):  return .right      // portrait, typical iPhone recording
        case (0, -1, 1, 0):  return .left       // portrait upside down
        case (-1, 0, 0, -1): return .down       // landscape, rotated 180
        default:             return .up
        }
    }

    // MARK: - Frame pump

    @objc private func tick(_ link: CADisplayLink) {
        guard !inFlight else { return }
        let itemTime = output.itemTime(forHostTime: link.timestamp + link.duration)
        guard output.hasNewPixelBuffer(forItemTime: itemTime) else { return }
        var displayTime = CMTime.zero
        guard let pixelBuffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: &displayTime) else { return }
        inFlight = true
        let seconds = displayTime.seconds
        visionQueue.async { [sink] in
            sink.ingest(pixelBuffer: pixelBuffer, at: seconds)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.inFlight = false
                self.delegate?.engineDidProcessFrame(self)
            }
        }
    }
}
