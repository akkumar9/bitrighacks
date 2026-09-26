import SwiftUI

/// The real PNG from design/furniture if it exists, otherwise a labeled placeholder shape.
struct FurnitureImage: View {
    let item: CatalogItem
    var tint: Color? = nil

    var body: some View {
        if let ui = AssetStore.shared.furnitureImage(item.file) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFit()
                .colorMultiply(tint ?? .white)   // TODO: real tinting may want a masked overlay instead
        } else {
            FurniturePlaceholder(item: item, tint: tint)
        }
    }

    /// width / height, from the real image if present, else the category default.
    static func aspect(for item: CatalogItem) -> CGFloat {
        if let ui = AssetStore.shared.furnitureImage(item.file), ui.size.height > 0 {
            return ui.size.width / ui.size.height
        }
        return item.placeholderAspect
    }
}

struct FurniturePlaceholder: View {
    let item: CatalogItem
    var tint: Color? = nil

    var body: some View {
        GeometryReader { geo in
            let r = min(geo.size.width, geo.size.height) * 0.18
            ZStack {
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .fill((tint ?? item.categoryColor).gradient)
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .strokeBorder(.white.opacity(0.35), lineWidth: 1.5)
                Text(item.name)
                    .font(.system(size: max(9, min(geo.size.width, geo.size.height) * 0.22), weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.3)
                    .lineLimit(item.placeholderAspect < 0.8 ? 4 : 2)
                    .allowsTightening(true)
                    .padding(4)
                    .shadow(radius: 2)
            }
        }
        .aspectRatio(item.placeholderAspect, contentMode: .fit)
    }
}

/// The room photo, or a gradient with a horizon and floor line when the file is missing.
struct RoomBackground: View {
    let name: String

    var body: some View {
        if let ui = AssetStore.shared.roomImage(name) {
            Image(uiImage: ui).resizable().scaledToFit()
        } else {
            RoomPlaceholder(name: name)
        }
    }

    /// width / height of the room image; the placeholder is 16:10.
    static func aspect(for name: String) -> CGFloat {
        if let ui = AssetStore.shared.roomImage(name), ui.size.height > 0 {
            return ui.size.width / ui.size.height
        }
        return 1.6
    }
}

struct RoomPlaceholder: View {
    let name: String
    /// Horizon as a fraction of height, top-down.
    static let horizon: CGFloat = 0.62

    var body: some View {
        GeometryReader { geo in
            let hz = geo.size.height * Self.horizon
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color(red: 0.93, green: 0.92, blue: 0.89),
                                        Color(red: 0.84, green: 0.82, blue: 0.78)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: hz)
                LinearGradient(colors: [Color(red: 0.62, green: 0.50, blue: 0.38),
                                        Color(red: 0.47, green: 0.36, blue: 0.27)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: geo.size.height - hz)
                    .offset(y: hz)
                Rectangle().fill(.black.opacity(0.25)).frame(height: 2).offset(y: hz - 1)
                Text("\(name) · placeholder")
                    .font(.caption2).foregroundStyle(.black.opacity(0.35))
                    .padding(6)
            }
        }
        .aspectRatio(1.6, contentMode: .fit)
    }
}
