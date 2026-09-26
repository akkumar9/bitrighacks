import SwiftUI

/// Feeds hinge angle into the model as a smoothed reveal amount.
/// - `context.hinge` is nil on non-Duo hardware and (per the DuoLab notes) inside the outer
///   display's own hierarchy, so this must sit on the inner display's tree.
/// - Only `angle` is used. `status` lags and is inconsistent between 20° and 90°.
struct HingeRevealModifier: ViewModifier {
    var model: RoomModel

    func body(content: Content) -> some View {
        content.onHingeChange { _, context in
            guard let hinge = context.hinge else { return }
            model.setHinge(radians: hinge.angle.radians, degrees: hinge.angle.degrees)
        }
    }
}

extension View {
    func hingeReveal(_ model: RoomModel) -> some View {
        modifier(HingeRevealModifier(model: model))
    }
}
