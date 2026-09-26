import SwiftUI
import AVFoundation

// MARK: - Shared drawing

extension Skeleton {
    /// Joints in image coordinates, dropping low-confidence ones.
    init(frame: PoseFrame, minConfidence: Double) {
        var joints: [Joint: CGPoint] = [:]
        for (j, p) in frame.joints where p.confidence >= minConfidence { joints[j] = CGPoint(x: p.x, y: p.y) }
        self.init(joints: joints)
    }
}

/// Bones and joints for one skeleton in one colour.
struct SkeletonCanvas: View {
    var skeleton: Skeleton?
    var geometry: StageGeometry
    var color: Color
    var lineScale: CGFloat = 1
    /// Joints to ring in red (the bad limbs' vertices).
    var flagged: Set<Joint> = []

    var body: some View {
        Canvas { ctx, _ in
            guard let skeleton else { return }
            let stroke = max(3, geometry.rect.width * 0.012) * lineScale
            for (a, b) in skeleton.segments {
                var path = Path()
                path.move(to: geometry.point(a))
                path.addLine(to: geometry.point(b))
                ctx.stroke(path, with: .color(color.opacity(0.9)), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
            }
            for (j, p) in skeleton.joints {
                let c = geometry.point(p)
                let bad = flagged.contains(j)
                let r = stroke * (bad ? 1.9 : 1.1)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(bad ? .red : .white))
            }
        }
        .shadow(color: .black.opacity(0.6), radius: 2)
    }
}

/// One stream's picture (video or studio backdrop) sized to its aspect, with overlays supplied
/// by the caller in that stream's image geometry.
struct StreamStage<Overlays: View>: View {
    var stream: PoseStream
    var label: String
    @ViewBuilder var overlays: (StageGeometry) -> Overlays

    var body: some View {
        GeometryReader { geo in
            let g = StageGeometry(canvas: geo.size, videoSize: stream.videoSize)
            ZStack {
                Color.black
                if let player = stream.player {
                    PlayerLayerView(player: player)
                        .frame(width: g.rect.width, height: g.rect.height)
                        .position(x: g.rect.midX, y: g.rect.midY)
                } else {
                    StudioBackdrop(label: label)
                        .frame(width: g.rect.width, height: g.rect.height)
                        .position(x: g.rect.midX, y: g.rect.midY)
                }
                overlays(g)
            }
        }
    }
}

extension LimbAngle {
    /// The joint at the vertex of this limb angle, for highlighting.
    var vertexJoint: Joint? { joints?.1 }
}

extension CopyMeSession {
    static let ownColor = Color(red: 0.35, green: 0.9, blue: 1.0)
    static let ghostColor = Color(red: 1.0, green: 0.6, blue: 0.2)

    var flaggedJoints: Set<Joint> {
        Set((result?.jointErrors ?? []).filter(\.isBad).compactMap(\.limb.vertexJoint))
    }
}

// MARK: - Outer display: learner

/// The learner's own video and skeleton with the demonstrator's pose ghosted over it, and one
/// cue naming only the worst limb. No numbers.
struct LearnerView: View {
    var session: CopyMeSession

    private var cue: (text: String, tone: CueTone) {
        guard let r = session.result, r.isValid else { return ("Step into frame", .neutral) }
        guard let worst = r.worst, worst.isBad else { return ("Matching — keep going", .good) }
        return ("Fix your \(worst.limb.label.lowercased())", .correct)
    }

    var body: some View {
        StreamStage(stream: session.learner, label: "learner · synthetic · no learner.mp4") { g in
            let own = session.learner.latest.map { Skeleton(frame: $0, minConfidence: session.thresholds.minConfidence) }
            SkeletonCanvas(skeleton: own, geometry: g, color: CopyMeSession.ownColor, flagged: session.flaggedJoints)
            if let r = session.result, r.isValid {
                SkeletonCanvas(skeleton: r.ghost, geometry: g, color: CopyMeSession.ghostColor, lineScale: 0.7)
                    .opacity(0.85)
            }
        }
        .overlay(alignment: .bottom) {
            CueLabel(cue: Cue(text: cue.text, tone: cue.tone))
                .padding(.bottom, 18)
        }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 10) {
                Label("you", systemImage: "circle.fill").foregroundStyle(CopyMeSession.ownColor)
                Label("copy this", systemImage: "circle.fill").foregroundStyle(CopyMeSession.ghostColor)
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.black.opacity(0.45), in: Capsule())
            .padding(12)
        }
        .background(Color.black)
    }
}

// MARK: - Inner display: demonstrator

/// Split across the fold: demonstrator's video, score and per-joint errors on one half, the
/// control deck on the other.
struct CopyMeClinicianView: View {
    @Bindable var session: CopyMeSession
    var accessoryAvailable: Bool
    var isWide: Bool
    /// The app-level mode switch, shown beside the status badge.
    var modePicker: AnyView = AnyView(EmptyView())

    var body: some View {
        FoldSplit(isWide: isWide) { foldActive in
            CopyMeAboveFold(session: session, accessoryAvailable: accessoryAvailable, foldActive: foldActive, modePicker: modePicker)
        } secondary: {
            CopyMeDeck(session: session)
        }
        .background(Color(white: 0.08))
    }
}

struct CopyMeAboveFold: View {
    var session: CopyMeSession
    var accessoryAvailable: Bool
    var foldActive: Bool
    var modePicker: AnyView = AnyView(EmptyView())

    var body: some View {
        HStack(spacing: 0) {
            StreamStage(stream: session.demonstrator, label: "demonstrator · synthetic · no demo.mp4") { g in
                let own = session.demonstrator.latest.map { Skeleton(frame: $0, minConfidence: session.thresholds.minConfidence) }
                SkeletonCanvas(skeleton: own, geometry: g, color: CopyMeSession.ownColor)
            }
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    modePicker
                    CopyMeStatusBadge(session: session, accessoryAvailable: accessoryAvailable, foldActive: foldActive)
                }
                .padding(8)
            }
            MatchPanel(session: session)
                .frame(width: 200)
        }
    }
}

struct CopyMeStatusBadge: View {
    var session: CopyMeSession
    var accessoryAvailable: Bool
    var foldActive: Bool

    var body: some View {
        HStack(spacing: 8) {
            Label(accessoryAvailable ? "outer live" : "outer off",
                  systemImage: accessoryAvailable ? "rectangle.on.rectangle.fill" : "rectangle.on.rectangle.slash")
            Text(session.sourceLabel)
            if let d = session.hingeDegrees { Text(String(format: "hinge %.0f°%@", d, foldActive ? " · folded" : "")).monospacedDigit() } else { Text("no hinge") }
            if let e = session.errorMessage { Text(e).foregroundStyle(.red) }
        }
        .font(.caption).lineLimit(1).fixedSize()
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }
}

/// Score large, per-joint errors in monospaced digits, worst named, lag.
struct MatchPanel: View {
    var session: CopyMeSession

    var body: some View {
        let r = session.result
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("MATCH").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(r?.isValid == true ? String(format: "%.0f", r!.score) : "—")
                    .font(.system(size: 40, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle((r?.score ?? 0) >= 70 ? Color.green : ((r?.score ?? 0) >= 40 ? Color.orange : Color.red))
                    .contentTransition(.numericText(value: r?.score ?? 0))
            }
            HStack {
                Text("Worst").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(r?.worst.map { $0.isBad ? $0.limb.label : "none" } ?? "—")
                    .font(.callout.weight(.semibold)).foregroundStyle(r?.worst?.isBad == true ? .red : .primary)
            }
            HStack {
                Text("Lag").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(r?.isValid == true ? String(format: "%.2f s", r!.lag) : "—").font(.callout.monospacedDigit().weight(.semibold))
            }
            Divider()
            ForEach(r?.jointErrors ?? []) { e in
                HStack {
                    Text(e.limb.label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Text(String(format: "%.0f°", e.degrees))
                        .font(.callout.monospacedDigit().weight(.semibold))
                        .foregroundStyle(e.isBad ? .red : (e.degrees <= session.thresholds.goodJointError ? .green : .primary))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.regularMaterial)
        .animation(.snappy, value: r?.score ?? 0)
    }
}

/// Mirror toggle, thresholds, transport, reset, lag readout.
struct CopyMeDeck: View {
    @Bindable var session: CopyMeSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button { session.togglePlayback() } label: {
                    Image(systemName: session.isPlaying ? "pause.fill" : "play.fill").frame(width: 20)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(session.isPlaying ? "Pause" : "Play")
                Slider(value: Binding(get: { session.currentTime }, set: { session.seek(to: $0) }),
                       in: 0...max(session.duration, 0.01)) { editing in
                    if editing, session.isPlaying { session.pause() }
                }
                Text(String(format: "%05.2f / %05.2f", session.currentTime, session.duration))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary).fixedSize()
            }
            HStack(spacing: 10) {
                Toggle(isOn: $session.thresholds.mirrored) { Label("Mirrored", systemImage: "arrow.left.and.right") }
                    .toggleStyle(.button).font(.caption)
                Toggle(isOn: $session.hingeScrubEnabled) { Label("Hinge scrub", systemImage: "iphone.gen3.motion") }
                    .toggleStyle(.button).font(.caption)
                Button { session.reset() } label: { Label("Reset", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(.bordered).font(.caption)
                Spacer()
                Text(session.result.map { String(format: "lag %.2f s", $0.lag) } ?? "lag —")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text("THRESHOLDS").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            slider("Good ≤", value: $session.thresholds.goodJointError, range: 2...30, step: 1, format: "%.0f°")
            slider("Bad >", value: $session.thresholds.badJointError, range: 5...60, step: 1, format: "%.0f°")
            slider("Max lag", value: $session.thresholds.maxLag, range: 0...2, step: 0.05, format: "%.2f s")
            slider("Smoothing", value: Binding(get: { Double(session.thresholds.smoothingWindow) },
                                              set: { session.thresholds.smoothingWindow = Int($0) }),
                   range: 1...15, step: 1, format: "%.0f")
            slider("Min conf.", value: $session.thresholds.minConfidence, range: 0.05...0.9, step: 0.05, format: "%.2f")
            Text("demo \(session.demonstrator.framesAnalysed) · learner \(session.learner.framesAnalysed) frames analysed")
                .font(.caption2).foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial)
    }

    private func slider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, format: String) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.caption).frame(width: 80, alignment: .leading)
            Slider(value: value, in: range, step: step)
            Text(String(format: format, value.wrappedValue)).font(.caption.monospacedDigit()).frame(width: 50, alignment: .trailing)
        }
    }
}
