import SwiftUI

/// Two surfaces split across the fold on a display that has one, stacked otherwise.
///
/// The division region exists (inactive, zero width) whenever the display can fold and is active
/// only while the phone is partly folded; no region at all means no fold (outer display in Closed
/// pose, non-Duo devices). On the simulator's landscape inner display the fold is a vertical band
/// down the middle, so the split axis is horizontal. `.split.axes(.vertical)` hid the secondary
/// pane on that display. Swapping between the two layouts resets view identity, so callers keep
/// their state on the model.
struct FoldSplit<Primary: View, Secondary: View>: View {
    /// Wide window (inner display) vs tall (closed pose); decided by the root from the whole window.
    var isWide: Bool
    @ViewBuilder var primary: (_ foldActive: Bool) -> Primary
    @ViewBuilder var secondary: () -> Secondary

    var body: some View {
        GeometryReader { proxy in
            let folds = proxy.reservedRegions(kind: .division, options: .includeInactive)
            let foldActive = folds.contains { $0.isActive }
            if !folds.isEmpty && isWide {
                ArrangementView {
                    primary(foldActive)
                } secondary: {
                    secondary()
                }
                .arrangementViewStyle(.split.axes(.horizontal))
            } else {
                VStack(spacing: 0) {
                    primary(false)
                    ScrollView { secondary() }
                        .frame(maxHeight: isWide ? .infinity : 280)
                }
            }
        }
    }
}
