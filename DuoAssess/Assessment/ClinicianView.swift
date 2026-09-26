import SwiftUI

/// Inner display: stage with overlay, metrics, transport, thresholds and log. Renders the
/// session's `Readout`; it does not know which profile is running.
struct ClinicianView: View {
    @Bindable var session: SessionModel
    var accessoryAvailable: Bool
    /// Decided by RootView from the whole window, not this pane's own frame (which is
    /// landscape-ish even in the stacked portrait layout).
    var isWide: Bool

    var body: some View {
        // Side by side when wide (inner display), stacked with a scrolling deck when tall
        // (closed pose puts the app on the portrait outer display).
        let layout = isWide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
        layout {
            VStack(spacing: 0) {
                StageView(session: session, showDetails: true)
                    .overlay(alignment: .topLeading) { StatusBadge(session: session, accessoryAvailable: accessoryAvailable).padding(10) }
                    .overlay(alignment: .topTrailing) { CountBadge(count: session.readout.completedCount).padding(10) }
                Transport(session: session)
            }
            if isWide {
                ControlDeck(session: session).frame(width: 260)
            } else {
                ScrollView { ControlDeck(session: session) }.frame(maxHeight: 260)
            }
        }
        .background(Color(white: 0.08))
    }
}

struct StatusBadge: View {
    var session: SessionModel
    var accessoryAvailable: Bool

    var body: some View {
        HStack(spacing: 8) {
            Label(accessoryAvailable ? "outer live" : "outer off",
                  systemImage: accessoryAvailable ? "rectangle.on.rectangle.fill" : "rectangle.on.rectangle.slash")
            Text(session.sourceLabel)
            if let d = session.hingeDegrees { Text(String(format: "hinge %.0f°", d)).monospacedDigit() } else { Text("no hinge") }
            if let e = session.errorMessage { Text(e).foregroundStyle(.red) }
        }
        .font(.caption).lineLimit(1).fixedSize()
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }
}

struct CountBadge: View {
    var count: Int
    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text("DONE").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text("\(count)")
                .font(.title.weight(.bold).monospacedDigit())
                .contentTransition(.numericText(value: Double(count)))
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .animation(.snappy, value: count)
    }
}

/// Play/pause, scrub slider, time, hinge-scrub toggle.
struct Transport: View {
    @Bindable var session: SessionModel

    var body: some View {
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
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .fixedSize()

            Toggle(isOn: $session.hingeScrubEnabled) {
                Label("Hinge scrub", systemImage: "iphone.gen3.motion")
            }
            .toggleStyle(.button)
            .font(.caption)
            .fixedSize()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.regularMaterial)
    }
}

/// Live metrics from the readout.
struct MetricsList: View {
    var session: SessionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LIVE").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(session.readout.metrics) { m in
                HStack {
                    Text(m.label).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(m.value).font(.body.monospacedDigit().weight(.semibold))
                        .foregroundStyle(m.flagged ? .red : .primary)
                }
            }
        }
    }
}

/// Profile picker, thresholds, recalibrate, log.
struct ControlDeck: View {
    @Bindable var session: SessionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Profile", selection: Binding(get: { session.profile.id }, set: { session.selectProfile(id: $0) })) {
                ForEach(session.profiles, id: \.id) { p in Text(p.displayName).tag(p.id) }
            }
            .pickerStyle(.segmented)

            MetricsList(session: session)
            Divider()
            ThresholdSliders(session: session)
            Divider()
            HStack {
                Text("LOG").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button("Recalibrate") { session.recalibrate() }
                    .font(.caption).buttonStyle(.bordered).controlSize(.small)
            }
            LogList(session: session)
            Spacer(minLength: 0)
            Text("\(session.framesAnalysed) frames analysed")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(.regularMaterial)
    }
}

struct ThresholdSliders: View {
    var session: SessionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("THRESHOLDS").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            // `revision` is read so the rows re-render when the model refreshes.
            let _ = session.revision
            ForEach(session.profile.controls) { c in
                HStack(spacing: 8) {
                    Text(c.label).font(.caption).frame(width: 96, alignment: .leading).lineLimit(1)
                    Slider(value: Binding(get: { c.get() }, set: { c.set($0); session.refresh() }),
                           in: c.range, step: c.step)
                    Text(c.format(c.get())).font(.caption.monospacedDigit()).frame(width: 44, alignment: .trailing)
                }
            }
        }
    }
}

struct LogList: View {
    var session: SessionModel

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                if session.log.isEmpty {
                    Text("nothing completed yet").font(.caption).foregroundStyle(.tertiary)
                }
                ForEach(session.log) { e in
                    HStack {
                        Text(e.title).font(.caption.weight(.bold))
                        Text(e.detail).font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Image(systemName: e.flagged ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(e.flagged ? .red : .green)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                    .onTapGesture { session.pause(); session.seek(to: e.time) }
                }
            }
        }
    }
}
