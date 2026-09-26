import SwiftUI
import AVFoundation

/// Letterboxes the video's aspect ratio into a canvas and maps normalized (y-up) points to it.
/// Both displays use this, so overlays land on the same pixels of the picture on each.
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
    func point(_ p: CGPoint) -> CGPoint {
        CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + (1 - p.y) * rect.height)
    }
}

/// Video (or a studio backdrop for synthetic data) with the profile's overlay drawn on top.
struct StageView: View {
    var session: SessionModel
    /// Clinician: extra detail (e.g. the face midline). Patient: the plain overlay.
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
                    StudioBackdrop(label: "\(session.profile.displayName.lowercased()) · synthetic · no \(session.profile.videoName).mp4")
                        .frame(width: g.rect.width, height: g.rect.height)
                        .position(x: g.rect.midX, y: g.rect.midY)
                }
                OverlayView(overlay: session.readout.overlay, geometry: g, showDetails: showDetails)
            }
        }
    }
}

/// Draws whatever the profile handed back. Knows nothing about the profile.
struct OverlayView: View {
    var overlay: Overlay
    var geometry: StageGeometry
    var showDetails: Bool

    var body: some View {
        Canvas { ctx, _ in
            let stroke = max(3, geometry.rect.width * 0.012)
            switch overlay {
            case .none:
                break

            case .skeleton(let bones, let joints):
                let color = Color(red: 0.35, green: 0.9, blue: 1.0)
                for (a, b) in bones {
                    var path = Path()
                    path.move(to: geometry.point(a))
                    path.addLine(to: geometry.point(b))
                    ctx.stroke(path, with: .color(color.opacity(0.9)), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                }
                for j in joints {
                    let c = geometry.point(j), r = stroke * 1.1
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(.white))
                }

            case .face(let points, let midline, let ghost):
                let r = max(1.5, geometry.rect.width * 0.004)
                for p in ghost {
                    let c = geometry.point(p)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(.white.opacity(0.25)))
                }
                for p in points {
                    let c = geometry.point(p)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(Color(red: 0.35, green: 0.9, blue: 1.0)))
                }
                if showDetails, let (a, b) = midline {
                    var path = Path()
                    path.move(to: geometry.point(a))
                    path.addLine(to: geometry.point(b))
                    ctx.stroke(path, with: .color(.yellow.opacity(0.8)), style: StrokeStyle(lineWidth: max(1, stroke * 0.4), dash: [6, 4]))
                }
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

/// Stand-in for the video while running on synthetic data.
struct StudioBackdrop: View {
    var label: String

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(white: 0.22), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)
                Rectangle().fill(Color(white: 0.09))
                    .frame(height: geo.size.height * 0.12)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                Text(label)
                    .font(.caption2).foregroundStyle(.white.opacity(0.4)).padding(8)
            }
        }
    }
}
