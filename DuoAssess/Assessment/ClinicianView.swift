import SwiftUI

/// Inner display, split across the fold:
/// - one half: the picture with the profile's overlay, live metrics, phase and count
/// - other half: the control deck (profile picker, transport, thresholds, recalibrate, log)
///
/// On the simulator's landscape inner display the fold is a vertical 40 pt band down the middle
/// (measured 2026-09-26: frame x 455…495 of 951, full height), so the split axis is horizontal:
/// picture left, deck right. The split is an `ArrangementView` when the display has a fold (Duo
/// inner display, any pose); elsewhere (outer display in Closed pose, non-Duo devices) the same
/// two surfaces stack in a VStack. Everything renders from the session's `Readout`.
struct ClinicianView: View {
    @Bindable var session: SessionModel
    var accessoryAvailable: Bool
    /// Decided by RootView from the whole window.
    var isWide: Bool
    /// The app-level mode switch, shown beside the status badge.
    var modePicker: AnyView = AnyView(EmptyView())

    var body: some View {
        FoldSplit(isWide: isWide) { foldActive in
            AboveFold(session: session, accessoryAvailable: accessoryAvailable, foldActive: foldActive, modePicker: modePicker)
        } secondary: {
            ControlDeck(session: session, wide: false)
        }
        .background(Color(white: 0.08))
    }
}

/// Picture + overlay on the left, numbers on the right.
struct AboveFold: View {
    var session: SessionModel
    var accessoryAvailable: Bool
    var foldActive: Bool
    var modePicker: AnyView = AnyView(EmptyView())

    var body: some View {
        HStack(spacing: 0) {
            StageView(session: session, showDetails: true)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 6) {
                        modePicker
                        StatusBadge(session: session, accessoryAvailable: accessoryAvailable, foldActive: foldActive)
                    }
                    .padding(8)
                }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(session.profile.displayName.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    CountBadge(count: session.readout.completedCount)
                }
                HStack {
                    Text("Phase").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(session.readout.phase.capitalized).font(.body.weight(.semibold))
                }
                MetricsList(session: session)
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(width: 190)
            .background(.regularMaterial)
        }
    }
}

struct StatusBadge: View {
    var session: SessionModel
    var accessoryAvailable: Bool
    var foldActive: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Label(accessoryAvailable ? "outer live" : "outer off",
                  systemImage: accessoryAvailable ? "rectangle.on.rectangle.fill" : "rectangle.on.rectangle.slash")
            Text(session.source.label)
            if let d = session.hingeDegrees { Text(String(format: "hinge %.0f°%@", d, foldActive ? " · folded" : "")).monospacedDigit() } else { Text("no hinge") }
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
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(count)")
                .font(.title2.weight(.bold).monospacedDigit())
                .contentTransition(.numericText(value: Double(count)))
            Text("done").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        }
        .animation(.snappy, value: count)
    }
}

/// Live metrics from the readout, monospaced digits.
struct MetricsList: View {
    var session: SessionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(session.readout.metrics) { m in
                HStack {
                    Text(m.label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Text(m.value).font(.callout.monospacedDigit().weight(.semibold))
                        .foregroundStyle(m.flagged ? .red : .primary)
                }
            }
        }
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
    }
}

/// Profile picker, transport, thresholds, recalibrate, log. Three columns when wide.
struct ControlDeck: View {
    @Bindable var session: SessionModel
    var wide: Bool

    var body: some View {
        let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 16)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Profile", selection: Binding(get: { session.profile.id }, set: { session.selectProfile(id: $0) })) {
                    ForEach(session.profiles, id: \.id) { p in Text(p.displayName).tag(p.id) }
                }
                .pickerStyle(.segmented)
                Transport(session: session)
                Button { session.recalibrate() } label: {
                    Label("Recalibrate", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered).controlSize(.small)
                Text("\(session.framesAnalysed) frames analysed")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: wide ? 380 : .infinity)

            ThresholdSliders(session: session)
                .frame(maxWidth: wide ? 300 : .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Text("LOG").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                LogList(session: session)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                    Text(c.label).font(.caption).frame(width: 90, alignment: .leading).lineLimit(1)
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
