import UIKit

/// Loads PNG/JPG assets out of the bundled `design/` folder and caches them.
/// A missing file returns nil; views then draw a placeholder. Swap point: drop real files into
/// ~/duo-hack/design/furniture and ~/duo-hack/design/rooms, rebuild, done.
@MainActor
final class AssetStore {
    static let shared = AssetStore()

    private var cache: [String: UIImage] = [:]
    private var misses: Set<String> = []

    /// `design/furniture/<file>`
    func furnitureImage(_ file: String) -> UIImage? {
        image(at: "furniture/" + file)
    }

    /// `design/rooms/<name>.png` (or .jpg / .jpeg)
    func roomImage(_ name: String) -> UIImage? {
        for ext in ["png", "jpg", "jpeg"] {
            if let img = image(at: "rooms/\(name).\(ext)") { return img }
        }
        return nil
    }

    private func image(at relativePath: String) -> UIImage? {
        if let hit = cache[relativePath] { return hit }
        if misses.contains(relativePath) { return nil }
        guard let base = Bundle.main.resourceURL?.appendingPathComponent("design"),
              let img = UIImage(contentsOfFile: base.appendingPathComponent(relativePath).path) else {
            misses.insert(relativePath)
            return nil
        }
        cache[relativePath] = img
        return img
    }
}
