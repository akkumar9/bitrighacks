import SwiftUI

/// Inner display: the operator's editor. Room canvas fills the top, catalog strip along the
/// bottom, running total in a corner. All gestures live here; CustomerView is read-only.
///
/// Coordinate spaces: everything gesture-related uses the named space "editor" (the root of this
/// view). `canvasFrame` is the RoomCanvas frame in that space and `geometry` is the room image rect
/// inside the canvas, so an "editor" point converts to a normalized room position with:
///     geometry.normalized(for: point - canvasFrame.origin)
struct EditorView: View {
    @Bindable var model: RoomModel
    var accessoryAvailable: Bool

    @State private var canvasFrame: CGRect = .zero
    @State private var geometry: RoomGeometry? = nil
    /// Catalog item currently being dragged out of the strip, and where the finger is (editor space).
    @State private var catalogDrag: (item: CatalogItem, location: CGPoint)? = nil
    /// Position of the placed item when its drag started, so translation applies to a fixed origin.
    @State private var dragOrigin: CGPoint? = nil
    @State private var scaleOrigin: CGFloat? = nil

    static let stripHeight: CGFloat = 116
    static let coordinateSpace = "editor"

    var body: some View {
        VStack(spacing: 0) {
            canvas
            CatalogStrip(model: model, drag: $catalogDrag, onDrop: drop)
                .frame(height: Self.stripHeight)
        }
        .coordinateSpace(name: Self.coordinateSpace)
        .overlay { dragGhost }
        .background(Color(white: 0.1))
    }

    // MARK: - Canvas + chrome

    private var canvas: some View {
        RoomCanvas(model: model, itemChrome: { item, frame, geometry in
            PlacedItemChrome(
                item: item, frame: frame,
                isSelected: model.selectedID == item.id,
                onTap: { model.selectedID = item.id; model.bringToFront(item.id) },
                onDragChanged: { translation in moveItem(item, translation: translation, geometry: geometry) },
                onDragEnded: { dragOrigin = nil },
                onScaleChanged: { translation in scaleItem(item, translation: translation, frame: frame) },
                onScaleEnded: { scaleOrigin = nil }
            )
        }, onGeometry: { geometry = $0 })
        .contentShape(Rectangle())
        .onTapGesture { model.selectedID = nil }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.coordinateSpace)) } action: { canvasFrame = $0 }
        .overlay(alignment: .topTrailing) { TotalBadge(total: model.total).padding(12) }
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 8) {
                RoomStatusBadge(model: model, accessoryAvailable: accessoryAvailable)
                RevealSlider(model: model)
            }
            .padding(12)
        }
        // Inspector sits at the bottom so it never covers the badges above.
        .overlay(alignment: .bottom) {
            if let selected = model.selectedItem, let catalog = Catalog.shared.item(for: selected.catalogID) {
                SelectionInspector(model: model, item: selected, catalog: catalog)
                    .padding(.bottom, 12)
            }
        }
    }

    @ViewBuilder
    private var dragGhost: some View {
        if let drag = catalogDrag, let geometry {
            let width = geometry.width(forCm: drag.item.widthCm, scale: 1)
            FurnitureImage(item: drag.item)
                .frame(width: width, height: width / FurnitureImage.aspect(for: drag.item))
                .opacity(0.75)
                .position(drag.location)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Gesture math

    /// Drop from the catalog strip. `location` is in editor space.
    private func drop(_ item: CatalogItem, at location: CGPoint) {
        guard let geometry, canvasFrame.contains(location) else { return }
        let inCanvas = CGPoint(x: location.x - canvasFrame.minX, y: location.y - canvasFrame.minY)
        model.add(item.id, at: geometry.normalized(for: inCanvas))
    }

    private func moveItem(_ item: PlacedItem, translation: CGSize, geometry: RoomGeometry) {
        if dragOrigin == nil {
            dragOrigin = item.position
            model.selectedID = item.id
        }
        guard let origin = dragOrigin, geometry.rect.width > 0 else { return }
        let next = CGPoint(x: origin.x + translation.width / geometry.rect.width,
                           y: origin.y + translation.height / geometry.rect.height)
        model.update(item.id) { $0.position = next.clampedUnit }
    }

    private func scaleItem(_ item: PlacedItem, translation: CGSize, frame: CGRect) {
        if scaleOrigin == nil { scaleOrigin = item.scale }
        guard let origin = scaleOrigin else { return }
        // Dragging the corner handle out by the item's own width doubles it.
        let baseWidth = frame.width / item.scale
        guard baseWidth > 0 else { return }
        let next = origin + translation.width / baseWidth
        model.update(item.id) { $0.scale = min(max(next, 0.3), 4.0) }
    }
}

/// Selection outline, corner scale handle and gesture surface for one placed item.
struct PlacedItemChrome: View {
    let item: PlacedItem
    let frame: CGRect
    let isSelected: Bool
    let onTap: () -> Void
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: () -> Void
    let onScaleChanged: (CGSize) -> Void
    let onScaleEnded: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                .background(Color.white.opacity(0.001))   // hit-testable but invisible
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
                .onTapGesture(perform: onTap)
                .gesture(
                    DragGesture(minimumDistance: 4, coordinateSpace: .named(EditorView.coordinateSpace))
                        .onChanged { onDragChanged($0.translation) }
                        .onEnded { _ in onDragEnded() }
                )

            if isSelected {
                ScaleHandle()
                    .position(x: frame.maxX, y: frame.maxY)
                    .gesture(
                        DragGesture(minimumDistance: 2, coordinateSpace: .named(EditorView.coordinateSpace))
                            .onChanged { onScaleChanged($0.translation) }
                            .onEnded { _ in onScaleEnded() }
                    )
            }
        }
    }
}

struct ScaleHandle: View {
    var body: some View {
        ZStack {
            Circle().fill(Color.accentColor)
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 26, height: 26)
        .shadow(radius: 2)
        .contentShape(Circle().scale(1.8))
    }
}

/// Floating bar for the selected item: name, price, tint swatches, z-order and delete.
struct SelectionInspector: View {
    var model: RoomModel
    let item: PlacedItem
    let catalog: CatalogItem

    static let swatches: [Color?] = [nil, .white, Color(red: 0.85, green: 0.80, blue: 0.70),
                                      Color(red: 0.55, green: 0.65, blue: 0.75), Color(red: 0.75, green: 0.55, blue: 0.55),
                                      Color(red: 0.55, green: 0.70, blue: 0.55), Color(red: 0.35, green: 0.35, blue: 0.40)]

    var body: some View {
        // One row when it fits (inner display); two rows on narrow fallback layouts so the
        // delete button never ends up off-screen.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { titleBlock; divider; swatchRow; divider; buttons }
                .modifier(InspectorChrome())
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 14) { titleBlock; Spacer(); buttons }
                swatchRow
            }
            .modifier(InspectorChrome())
        }
    }

    private var divider: some View { Divider().frame(height: 28) }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(catalog.name).font(.headline)
            Text(catalog.price, format: .currency(code: "USD").precision(.fractionLength(0)))
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .lineLimit(1)
    }

    private var swatchRow: some View {
        HStack(spacing: 6) {
            ForEach(Array(Self.swatches.enumerated()), id: \.offset) { _, color in
                Swatch(color: color, isOn: item.tint == color)
                    .onTapGesture { model.update(item.id) { $0.tint = color } }
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            Button { model.sendToBack(item.id) } label: { Image(systemName: "square.3.layers.3d.bottom.filled") }
                .accessibilityLabel("Send to back")
            Button { model.bringToFront(item.id) } label: { Image(systemName: "square.3.layers.3d.top.filled") }
                .accessibilityLabel("Bring to front")
            Button(role: .destructive) { model.remove(item.id) } label: { Image(systemName: "trash") }
                .accessibilityLabel("Delete")
        }
        .buttonStyle(.bordered)
    }

    struct InspectorChrome: ViewModifier {
        func body(content: Content) -> some View {
            content
                .fixedSize()
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .shadow(radius: 6, y: 2)
        }
    }

    struct Swatch: View {
        let color: Color?
        let isOn: Bool
        var body: some View {
            ZStack {
                Circle().fill(color ?? .clear)
                if color == nil {
                    Image(systemName: "slash.circle").font(.system(size: 18)).foregroundStyle(.secondary)
                }
                Circle().strokeBorder(isOn ? Color.accentColor : .gray.opacity(0.4), lineWidth: isOn ? 3 : 1)
            }
            .frame(width: 26, height: 26)
        }
    }
}

struct TotalBadge: View {
    let total: Int
    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text("TOTAL").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(total, format: .currency(code: "USD").precision(.fractionLength(0)))
                .font(.title2.weight(.bold).monospacedDigit())
                .contentTransition(.numericText(value: Double(total)))
                .lineLimit(1).fixedSize()
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .animation(.snappy, value: total)
    }
}

/// Hinge / accessory readout. Cheap insurance for the demo.
struct RoomStatusBadge: View {
    var model: RoomModel
    var accessoryAvailable: Bool
    var body: some View {
        HStack(spacing: 8) {
            Label(accessoryAvailable ? "outer live" : "outer off", systemImage: accessoryAvailable ? "rectangle.on.rectangle.fill" : "rectangle.on.rectangle.slash")
            if let deg = model.hingeDegrees {
                Text(String(format: "hinge %.0f°", deg)).monospacedDigit()
            } else {
                Text("no hinge")
            }
            Text(String(format: "reveal %.2f", model.revealAmount)).monospacedDigit()
        }
        .font(.caption)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }
}

/// Manual reveal control. On a Duo the hinge overrides it on the next hinge update; on other
/// devices / previews it is the only way to drive the reveal.
/// TODO: hide this for the demo if it distracts (set `RevealSlider.visible = false`).
struct RevealSlider: View {
    @Bindable var model: RoomModel
    static let visible = true
    var body: some View {
        if Self.visible {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").font(.caption)
                Slider(value: $model.revealAmount, in: 0...1).frame(width: 140)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
        }
    }
}

/// Horizontally scrolling catalog. Tap a cell to add at a default spot; press-and-drag to place.
struct CatalogStrip: View {
    var model: RoomModel
    @Binding var drag: (item: CatalogItem, location: CGPoint)?
    let onDrop: (CatalogItem, CGPoint) -> Void

    /// Where a tapped (not dragged) item lands: centre of the floor.
    static let defaultPosition = CGPoint(x: 0.5, y: 0.7)

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Catalog.shared.items) { item in
                    CatalogCell(item: item)
                        .onTapGesture { model.add(item.id, at: CatalogStrip.defaultPosition) }
                        // Long-press then drag, so the horizontal scroll still owns plain swipes.
                        .gesture(
                            LongPressGesture(minimumDuration: 0.15)
                                .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(EditorView.coordinateSpace)))
                                .onChanged { value in
                                    if case .second(true, let d?) = value { drag = (item, d.location) }
                                }
                                .onEnded { value in
                                    // A press with no real movement is left to onTapGesture (which
                                    // also fires for slow presses); only genuine drags place here.
                                    if case .second(true, let d?) = value,
                                       abs(d.translation.width) > 6 || abs(d.translation.height) > 6 {
                                        onDrop(item, d.location)
                                    }
                                    drag = nil
                                }
                        )
                }
                if let error = Catalog.shared.loadError {
                    Text(error).font(.caption2).foregroundStyle(.red).frame(width: 160)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.regularMaterial)
    }
}

struct CatalogCell: View {
    let item: CatalogItem
    var body: some View {
        VStack(spacing: 4) {
            FurnitureImage(item: item)
                .frame(width: 64, height: 56)
            Text(item.name).font(.caption2).lineLimit(1)
            Text(item.price, format: .currency(code: "USD").precision(.fractionLength(0)))
                .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        }
        .frame(width: 96)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }
}
