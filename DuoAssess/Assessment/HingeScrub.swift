import SwiftUI

/// Feeds the hinge angle into the session, which turns it into a video scrub.
/// Must sit on the inner display's view tree: `context.hinge` is nil on non-Duo hardware and
/// inside the outer accessory scene, and the guard makes both harmless.
struct HingeScrubModifier: ViewModifier {
    var session: SessionModel

    func body(content: Content) -> some View {
        content.onHingeChange { _, context in
            guard let hinge = context.hinge else { return }
            session.hingeChanged(degrees: hinge.angle.degrees)
        }
    }
}

extension View {
    func hingeScrub(_ session: SessionModel) -> some View {
        modifier(HingeScrubModifier(session: session))
    }
}
