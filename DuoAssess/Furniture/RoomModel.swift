import SwiftUI

/// The one shared scene. Both displays read this; only the editor writes it.
@Observable
final class RoomModel {
    var roomImage: String = "room-1"
    var placed: [PlacedItem] = []
    /// 0 = bare room, 1 = fully furnished. Driven by the hinge (smoothed), or the debug slider.
    var revealAmount: Double = 1.0
    var selectedID: UUID? = nil

    /// Last raw hinge angle in degrees, for the on-screen readout. nil = no hinge data yet.
    var hingeDegrees: Double? = nil

    var total: Int {
        placed.compactMap { Catalog.shared.item(for: $0.catalogID)?.price }.reduce(0, +)
    }

    var selectedItem: PlacedItem? {
        guard let id = selectedID else { return nil }
        return placed.first { $0.id == id }
    }

    // MARK: - Editing

    @discardableResult
    func add(_ catalogID: String, at position: CGPoint) -> PlacedItem {
        var item = PlacedItem(catalogID: catalogID, position: position.clampedUnit)
        item.zIndex = nextZ
        placed.append(item)
        selectedID = item.id
        return item
    }

    func update(_ id: UUID, _ change: (inout PlacedItem) -> Void) {
        guard let i = placed.firstIndex(where: { $0.id == id }) else { return }
        change(&placed[i])
    }

    func remove(_ id: UUID) {
        placed.removeAll { $0.id == id }
        if selectedID == id { selectedID = nil }
    }

    func bringToFront(_ id: UUID) {
        // Read nextZ *before* update: reading `placed` inside the closure while `placed[i]` is
        // under inout access is a Swift exclusivity violation (crashed the app, 2026-09-25).
        let z = nextZ
        update(id) { $0.zIndex = z }
    }

    func sendToBack(_ id: UUID) {
        let minZ = placed.map(\.zIndex).min() ?? 0
        update(id) { $0.zIndex = minZ - 1 }
    }

    func clear() {
        placed.removeAll()
        selectedID = nil
    }

    private var nextZ: Double { (placed.map(\.zIndex).max() ?? 0) + 1 }

    // MARK: - Hinge → reveal

    /// Raw hinge angle jitters, so never write it straight into `revealAmount`. Animating to the
    /// clamped target lets SwiftUI merge a burst of tiny updates into one smooth motion, and the
    /// value always converges even if the last hinge event is a big jump (a plain exponential
    /// filter stalled at 0.55 after `hinge close` because no further events arrived).
    func setHinge(radians: Double, degrees: Double) {
        hingeDegrees = degrees
        let target = min(max(radians / .pi, 0), 1)
        withAnimation(.smooth(duration: 0.35)) {
            revealAmount = target
        }
    }
}

struct PlacedItem: Identifiable, Equatable {
    let id = UUID()
    let catalogID: String
    var position: CGPoint          // normalized 0...1 within the room image rect
    var scale: CGFloat = 1.0
    var zIndex: Double = 0
    var tint: Color? = nil
}

extension CGPoint {
    var clampedUnit: CGPoint {
        CGPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
    }
}

/// Staggered reveal. Each item fades in across a narrow band; bands are spread across 0...1 by
/// placement order so furniture appears piece by piece as the hinge opens.
/// Identical math on both displays keeps them locked.
enum Reveal {
    /// Width of one item's fade band, in reveal units.
    static let band = 0.22

    static func opacity(index: Int, count: Int, reveal: Double) -> Double {
        guard count > 0 else { return 0 }
        let threshold = (Double(index) + 0.5) / Double(count)   // 0...1, evenly spaced
        let start = threshold * (1 - band)                       // last item finishes exactly at 1
        return min(max((reveal - start) / band, 0), 1)
    }
}
