import SwiftUI

/// One row of design/catalog.json. `category` drives placeholder color/shape only.
struct CatalogItem: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let category: String
    let price: Int
    let file: String
    let widthCm: Double

    var categoryColor: Color {
        switch category {
        case "sofa":  return Color(red: 0.24, green: 0.35, blue: 0.62)
        case "chair": return Color(red: 0.72, green: 0.50, blue: 0.30)
        case "table": return Color(red: 0.45, green: 0.32, blue: 0.22)
        case "rug":   return Color(red: 0.62, green: 0.28, blue: 0.30)
        case "lamp":  return Color(red: 0.92, green: 0.72, blue: 0.25)
        case "plant": return Color(red: 0.28, green: 0.55, blue: 0.32)
        default:      return .gray
        }
    }

    /// width / height used for the placeholder when no PNG exists.
    var placeholderAspect: CGFloat {
        switch category {
        case "sofa":  return 2.4
        case "chair": return 1.0
        case "table": return 1.8
        case "rug":   return 2.6
        case "lamp":  return 0.3
        case "plant": return 0.6
        default:      return 1.0
        }
    }
}

/// Loads design/catalog.json from the bundle once. Falls back to a tiny built-in list if the
/// file is missing or malformed so the app never launches empty.
final class Catalog {
    static let shared = Catalog()

    let items: [CatalogItem]
    private let byID: [String: CatalogItem]
    /// Non-nil when the bundled JSON could not be read; surfaced in the editor for debugging.
    let loadError: String?

    private init() {
        var loaded: [CatalogItem] = []
        var loadError: String? = nil
        if let url = Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "design") {
            do {
                loaded = try JSONDecoder().decode([CatalogItem].self, from: Data(contentsOf: url))
            } catch {
                loadError = "catalog.json failed to decode: \(error)"
            }
        } else {
            loadError = "design/catalog.json not found in bundle"
        }
        if loaded.isEmpty {
            loaded = [
                CatalogItem(id: "sofa-navy", name: "Halden Sofa", category: "sofa", price: 1499, file: "sofa-navy.png", widthCm: 210),
                CatalogItem(id: "chair-oak", name: "Fjell Armchair", category: "chair", price: 649, file: "chair-oak.png", widthCm: 78),
            ]
        }
        items = loaded
        byID = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        self.loadError = loadError
    }

    func item(for id: String) -> CatalogItem? { byID[id] }
}
