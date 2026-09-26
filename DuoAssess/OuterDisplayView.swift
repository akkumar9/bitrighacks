import SwiftUI

/// Wraps any content for the outer display, which lays out portrait but is viewed sideways
/// relative to the inner display. We render a landscape canvas and rotate it into place.
/// Verified in the simulator 2026-09-25: with no rotation, the --display=primary screenshot shows
/// the content turned 90° clockwise; -90° here makes it read upright in that screenshot.
/// TODO: confirm the sign on hardware. Flip `rotation` to +90 if the patient sees it upside down.
struct OuterDisplayView<Content: View>: View {
    static var rotation: Angle { .degrees(-90) }
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geo in
            content()
                .frame(width: geo.size.height, height: geo.size.width)
                .rotationEffect(Self.rotation)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Color.black)
        .ignoresSafeArea()
    }
}
