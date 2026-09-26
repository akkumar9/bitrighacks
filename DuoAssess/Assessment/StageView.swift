import SwiftUI
import AVFoundation

/// Letterboxes the video's aspect ratio into a canvas and maps Vision-normalized joints to points.
/// Both displays use this, so the skeleton lands on the same pixels of the picture on each.
struct StageGeometry: Equatable {
    let rect: CGRect

    init(canvas: CGSize, videoSize: CGSize) {
        let aspect = videoSize.height > 0 ? videoSize.width / videoSize.height : 1
        var w = canvas.width
        var h = w / aspect
        if h > canvas.height { h = canvas.height; w = h * aspect }
        rect = CGRect(x: (canvas.width - w) / 2, y: (canvas.height - h) / 2, width: w, height: h)
    }

    /// Vision coordinates are y-up; SwiftUI's are y-down.
    func point(_ j: JointPoint) -> CGPoint {
        CGPoint(x: rect.minX + CGFloat(j.x) * rect.width,
                y: rect.minY + CGFloat(1 - j.y) * rect.height)
    }
}

/// Video (or a studio backdrop for synthetic data) with the skeleton drawn over it.
struct StageView: View {
    var session: SessionModel
    /// Clinician: angle labels at the knees and phase colouring. Patient: plain skeleton.
    var showDetails: Bool

    var body: some View {
        GeometryReader { geo in
            let g = StageGeometry(canvas: geo.size, videoSize: session.videoSize)
            ZStack {
                Color.black
                if let player = session.player {
                    PlayerLayerView(player: player)
                        .frame(width: g.rect.width, height: g.rect.height)
                        .position(x: g.rect.midX, y: g.rect.midY)
                } else {
                    StudioBackdrop()
                        .frame(width: g.rect.width, height: g.rect.height)
                        .position(x: g.rect.midX, y: g.rect.midY)
                }
                SkeletonView(frame: session.current?.smoothed, metrics: session.metrics,
                             geometry: g, showDetails: showDetails,
                             minConfidence: session.thresholds.minConfidence)
            }
        }
    }
}

/// Draws bones and joints. Knees turn red while valgus is flagged.
struct SkeletonView: View {
    var frame: PoseFrame?
    var metrics: SquatMetrics?
    var geometry: StageGeometry
    var showDetails: Bool
    var minConfidence: Double

    var body: some View {
        Canvas { ctx, _ in
            guard let frame else { return }
            let valgus = metrics?.isValgus ?? false
            let boneWidth = max(3, geometry.rect.width * 0.012)

            for (a, b) in Skeleton.bones {
                guard let pa = frame.joints[a], let pb = frame.joints[b],
                      pa.confidence >= minConfidence, pb.confidence >= minConfidence else { continue }
                var path = Path()
                path.move(to: geometry.point(pa))
                path.addLine(to: geometry.point(pb))
                let isLeg = [a, b].contains { [.leftKnee, .rightKnee].contains($0) }
                let color: Color = (isLeg && valgus) ? .red : Color(red: 0.35, green: 0.9, blue: 1.0)
                ctx.stroke(path, with: .color(color.opacity(0.9)), style: StrokeStyle(lineWidth: boneWidth, lineCap: .round))
            }

            for (joint, p) in frame.joints where p.confidence >= minConfidence {
                let c = geometry.point(p)
                let r = boneWidth * (joint == .leftKnee || joint == .rightKnee ? 1.6 : 1.1)
                let isKnee = joint == .leftKnee || joint == .rightKnee
                let fill: Color = (isKnee && valgus) ? .red : .white
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(fill))
            }

            if showDetails, let m = metrics {
                func label(_ text: String, at joint: Joint, dx: CGFloat) {
                    guard let p = frame.joints[joint], p.confidence >= minConfidence else { return }
                    let c = geometry.point(p)
                    let t = Text(text).font(.system(size: max(11, geometry.rect.width * 0.035), weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    ctx.draw(t, at: CGPoint(x: c.x + dx, y: c.y), anchor: dx > 0 ? .leading : .trailing)
                }
                if let l = m.leftKneeAngle { label(String(format: "%.0f°", l), at: .leftKnee, dx: boneWidth * 3) }
                if let r = m.rightKneeAngle { label(String(format: "%.0f°", r), at: .rightKnee, dx: -boneWidth * 3) }
            }
        }
        .shadow(color: .black.opacity(0.6), radius: 2)
    }
}

/// AVPlayerLayer host. Several of these can share one AVPlayer (one per display).
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerHostView {
        let v = PlayerLayerHostView()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspect
        return v
    }

    func updateUIView(_ uiView: PlayerLayerHostView, context: Context) {
        if uiView.playerLayer.player !== player { uiView.playerLayer.player = player }
    }

    final class PlayerLayerHostView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

/// Stand-in for the video while running on synthetic data: a wall, a floor line, a hint.
struct StudioBackdrop: View {
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(white: 0.22), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)
                Rectangle().fill(Color(white: 0.09))
                    .frame(height: geo.size.height * 0.12)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                Text("synthetic squat · no squat.mp4")
                    .font(.caption2).foregroundStyle(.white.opacity(0.4)).padding(8)
            }
        }
    }
}
