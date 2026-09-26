import SwiftUI

/// Maps normalized room coordinates (0...1 across the room *image*) to points inside a canvas.
/// The room image is letterboxed (scaledToFit) so both displays show the identical crop; item
/// positions and sizes are always relative to `rect`, never the canvas.
struct RoomGeometry: Equatable {
    /// The room image's rect inside the canvas, in canvas points.
    let rect: CGRect
    /// Real-world width the room image spans. Drives furniture size from `widthCm`.
    /// TODO: make this per-room once real photos arrive (a wide-angle shot spans more cm).
    let roomWidthCm: Double

    init(canvas: CGSize, imageAspect: CGFloat, roomWidthCm: Double = 500) {
        var w = canvas.width
        var h = w / imageAspect
        if h > canvas.height {
            h = canvas.height
            w = h * imageAspect
        }
        rect = CGRect(x: (canvas.width - w) / 2, y: (canvas.height - h) / 2, width: w, height: h)
        self.roomWidthCm = roomWidthCm
    }

    func point(for normalized: CGPoint) -> CGPoint {
        CGPoint(x: rect.minX + normalized.x * rect.width,
                y: rect.minY + normalized.y * rect.height)
    }

    func normalized(for point: CGPoint) -> CGPoint {
        guard rect.width > 0, rect.height > 0 else { return .zero }
        return CGPoint(x: (point.x - rect.minX) / rect.width,
                       y: (point.y - rect.minY) / rect.height).clampedUnit
    }

    func width(forCm cm: Double, scale: CGFloat) -> CGFloat {
        CGFloat(cm / roomWidthCm) * rect.width * scale
    }

    /// Frame of a placed item in canvas points.
    func frame(for item: PlacedItem, catalog: CatalogItem, aspect: CGFloat) -> CGRect {
        let w = width(forCm: catalog.widthCm, scale: item.scale)
        let h = w / aspect
        let c = point(for: item.position)
        return CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
    }
}
