import SwiftUI

/// Outer display: the picture and overlay, one big count, one cue, a target bar. No numbers.
struct PatientView: View {
    var session: SessionModel

    var body: some View {
        StageView(session: session, showDetails: false)
            .overlay(alignment: .topTrailing) {
                VStack(alignment: .trailing, spacing: -6) {
                    Text("\(session.readout.completedCount)")
                        .font(.system(size: 64, weight: .heavy, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText(value: Double(session.readout.completedCount)))
                    Text("DONE").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                }
                .foregroundStyle(.white)
                .padding(16)
                .animation(.snappy, value: session.readout.completedCount)
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 10) {
                    if let p = session.readout.progress {
                        TargetBar(progress: p)
                            .frame(width: 220, height: 10)
                    }
                    CueLabel(cue: session.readout.cue)
                }
                .padding(.bottom, 18)
            }
            .background(Color.black)
    }
}

struct CueLabel: View {
    var cue: Cue

    private var tint: Color {
        switch cue.tone {
        case .neutral: return .black
        case .good: return Color(red: 0.1, green: 0.55, blue: 0.3)
        case .correct: return Color(red: 0.75, green: 0.2, blue: 0.15)
        }
    }

    var body: some View {
        Text(cue.text)
            .font(.title2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18).padding(.vertical, 10)
            .background(tint.opacity(0.6), in: Capsule())
            .animation(.snappy, value: cue.text)
    }
}

/// Fills toward the target as `progress` goes 0…1.
struct TargetBar: View {
    var progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule().fill(progress >= 0.999 ? Color.green : Color(red: 0.35, green: 0.9, blue: 1.0))
                    .frame(width: geo.size.width * min(max(progress, 0), 1))
            }
        }
        .animation(.interactiveSpring(duration: 0.25), value: progress)
    }
}
