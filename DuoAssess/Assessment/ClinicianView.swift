import SwiftUI

/// Inner display: video + skeleton, live metrics, rep list, transport and hinge-scrub control.
struct ClinicianView: View {
    @Bindable var session: SessionModel
    var accessoryAvailable: Bool

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                StageView(session: session, showDetails: true)
                    .overlay(alignment: .topLeading) { statusBadge.padding(10) }
                    .overlay(alignment: .topTrailing) { repBadge.padding(10) }
                Transport(session: session)
            }
            MetricsPanel(session: session)
                .frame(width: 250)
        }
        .background(Color(white: 0.08))
    }

    private var statusBadge: some View {
        HStack(spacing: 8) {
            Label(accessoryAvailable ? "outer live" : "outer off",
                  systemImage: accessoryAvailable ? "rectangle.on.rectangle.fill" : "rectangle.on.rectangle.slash")
            Text(session.source.label)
            if let d = session.hingeDegrees { Text(String(format: "hinge %.0f°", d)).monospacedDigit() } else { Text("no hinge") }
            if let e = session.errorMessage { Text(e).foregroundStyle(.red) }
        }
        .font(.caption).lineLimit(1).fixedSize()
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }

    private var repBadge: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text("REPS").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text("\(session.repCount)")
                .font(.title.weight(.bold).monospacedDigit())
                .contentTransition(.numericText(value: Double(session.repCount)))
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .animation(.snappy, value: session.repCount)
    }
}

/// Play/pause, scrub slider, time, hinge-scrub toggle.
struct Transport: View {
    @Bindable var session: SessionModel

    var body: some View {
        HStack(spacing: 12) {
            Button {
                session.togglePlayback()
            } label: {
                Image(systemName: session.isPlaying ? "pause.fill" : "play.fill").frame(width: 20)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel(session.isPlaying ? "Pause" : "Play")

            Slider(value: Binding(get: { session.currentTime },
                                  set: { session.seek(to: $0) }),
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

/// Live numbers and the rep table.
struct MetricsPanel: View {
    var session: SessionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let m = session.metrics
            Text("LIVE").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            metricRow("Phase", session.phase.rawValue.capitalized)
            metricRow("Knee L", m?.leftKneeAngle.map { String(format: "%.0f°", $0) } ?? "—")
            metricRow("Knee R", m?.rightKneeAngle.map { String(format: "%.0f°", $0) } ?? "—")
            metricRow("Depth", m.map { String(format: "%.0f%%", $0.depth * 100) } ?? "—")
            metricRow("Knee/ankle sep.", m?.kneeSeparationRatio.map { String(format: "%.2f", $0) } ?? "—",
                      highlight: m?.isValgus == true)
            metricRow("Valgus", m?.isValgus == true ? "YES" : "no", highlight: m?.isValgus == true)

            Divider()
            Text("REPS").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            if session.analysis.reps.isEmpty {
                Text("none yet").font(.caption).foregroundStyle(.tertiary)
            }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(session.analysis.reps) { rep in
                        HStack {
                            Text("#\(rep.id)").font(.caption.weight(.bold)).frame(width: 28, alignment: .leading)
                            Text(String(format: "min %.0f°", rep.minKneeAngle)).font(.caption.monospacedDigit())
                            Spacer()
                            Text(String(format: "%.1fs", rep.duration)).font(.caption2).foregroundStyle(.secondary)
                            Image(systemName: rep.hadValgus ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(rep.hadValgus ? .red : .green)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(session.current?.repNumber == rep.id ? Color.accentColor.opacity(0.25) : Color.white.opacity(0.05),
                                    in: RoundedRectangle(cornerRadius: 6))
                        .onTapGesture { session.pause(); session.seek(to: rep.bottomTime) }
                    }
                }
            }
            Spacer(minLength: 0)
            Text("\(session.timeline.count) frames analysed")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(.regularMaterial)
    }

    private func metricRow(_ name: String, _ value: String, highlight: Bool = false) -> some View {
        HStack {
            Text(name).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(highlight ? .red : .primary)
        }
    }
}
