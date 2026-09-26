import SwiftUI

/// Outer display: the same picture and skeleton, one big rep count, one plain-language cue.
/// No angles, no ratios, no controls.
struct PatientView: View {
    var session: SessionModel

    var body: some View {
        StageView(session: session, showDetails: false)
            .overlay(alignment: .topTrailing) {
                VStack(alignment: .trailing, spacing: -6) {
                    Text("\(session.repCount)")
                        .font(.system(size: 64, weight: .heavy, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText(value: Double(session.repCount)))
                    Text(session.repCount == 1 ? "REP" : "REPS")
                        .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                }
                .foregroundStyle(.white)
                .padding(16)
                .animation(.snappy, value: session.repCount)
            }
            .overlay(alignment: .bottom) {
                Text(session.patientCue)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background((session.metrics?.isValgus == true ? Color.red : Color.black).opacity(0.55), in: Capsule())
                    .padding(.bottom, 18)
                    .animation(.snappy, value: session.patientCue)
            }
            .background(Color.black)
    }
}
