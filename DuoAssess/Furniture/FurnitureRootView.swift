import SwiftUI

/// The original two-sided furniture placement build, kept intact. Not reachable from the app's
/// mode switch; swap `RootView()` for `FurnitureRootView()` in DuoAssessApp to run it.
struct FurnitureRootView: View {
    @State private var model = RoomModel()
    @State private var accessoryEnabled = true
    @State private var accessoryAvailable = false
    @State private var isWide = true

    var body: some View {
        let layout = isWide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
        layout {
            EditorView(model: model, accessoryAvailable: accessoryAvailable)
            if !accessoryAvailable {
                FallbackCustomerPane(model: model)
                    .frame(maxHeight: isWide ? .infinity : 260)
            }
        }
        .onGeometryChange(for: Bool.self) { $0.size.width > $0.size.height } action: { isWide = $0 }
        .animation(.snappy, value: accessoryAvailable)
        .sceneAccessory {
            CameraCaptureAccessory(isEnabled: $accessoryEnabled) {
                OuterDisplayView { CustomerView(model: model) }
            }
            .onAvailabilityChange { accessoryAvailable = $0 }
        }
        .hingeReveal(model)
    }
}

/// Side-by-side customer preview for when the outer display is not available.
struct FallbackCustomerPane: View {
    var model: RoomModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "person.crop.rectangle")
                Text("Customer view · outer display unavailable").font(.caption)
                Spacer()
            }
            .padding(8)
            .background(.regularMaterial)
            CustomerView(model: model)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }
}
