import SwiftUI

/// The one render function. Both displays call this; the editor adds chrome through `itemChrome`.
/// Coordinates: every placed item is positioned relative to the room image rect (`RoomGeometry`),
/// so the same model renders identically on displays with different sizes and orientations.
struct RoomCanvas<ItemChrome: View>: View {
    var model: RoomModel
    /// Called for each placed item with its frame in canvas points. Return EmptyView for no chrome.
    @ViewBuilder var itemChrome: (PlacedItem, CGRect, RoomGeometry) -> ItemChrome
    /// Reports the geometry each layout pass so the editor can convert drop points.
    var onGeometry: ((RoomGeometry) -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            let geometry = RoomGeometry(canvas: geo.size, imageAspect: RoomBackground.aspect(for: model.roomImage))
            ZStack(alignment: .topLeading) {
                RoomBackground(name: model.roomImage)
                    .frame(width: geometry.rect.width, height: geometry.rect.height)
                    .offset(x: geometry.rect.minX, y: geometry.rect.minY)

                ForEach(model.placed.sorted { $0.zIndex < $1.zIndex }) { item in
                    if let catalog = Catalog.shared.item(for: item.catalogID) {
                        let frame = geometry.frame(for: item, catalog: catalog, aspect: FurnitureImage.aspect(for: catalog))
                        let index = model.placed.firstIndex { $0.id == item.id } ?? 0
                        let opacity = Reveal.opacity(index: index, count: model.placed.count, reveal: model.revealAmount)

                        FurnitureImage(item: catalog, tint: item.tint)
                            .frame(width: frame.width, height: frame.height)
                            .scaleEffect(0.85 + 0.15 * opacity)
                            .opacity(opacity)
                            .position(x: frame.midX, y: frame.midY)
                            .animation(.interactiveSpring(duration: 0.25), value: opacity)

                        itemChrome(item, frame, geometry)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .onChange(of: geometry, initial: true) { _, g in onGeometry?(g) }
        }
    }
}
