import SwiftUI

/// Outer display: the finished room only. No catalog, prices, handles or selection.
struct CustomerView: View {
    var model: RoomModel

    var body: some View {
        RoomCanvas(model: model) { _, _, _ in EmptyView() }
            .background(Color.black)
    }
}
