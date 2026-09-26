import SwiftUI

@main
struct DuoAssessApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// Owns the shared session and both displays (PT pivot).
/// - Inner display: ClinicianView. When the outer accessory is unavailable (closed/book pose,
///   non-Duo device) a patient pane is shown beside/below it instead.
/// - Outer display: PatientView via the scene accessory. Presents on Open pose only.
/// ClinicianView keeps its identity across availability changes (always the first child); only
/// the fallback pane comes and goes, and all session state lives in `session`.
struct RootView: View {
    @State private var session = SessionModel.makeDefault()
    @State private var accessoryEnabled = true
    @State private var accessoryAvailable = false
    @State private var isWide = true

    var body: some View {
        let layout = isWide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
        layout {
            ClinicianView(session: session, accessoryAvailable: accessoryAvailable)
            if !accessoryAvailable {
                FallbackPatientPane(session: session)
                    .frame(maxWidth: isWide ? 340 : .infinity, maxHeight: isWide ? .infinity : 300)
            }
        }
        .onGeometryChange(for: Bool.self) { $0.size.width > $0.size.height } action: { isWide = $0 }
        .animation(.snappy, value: accessoryAvailable)
        .sceneAccessory {
            CameraCaptureAccessory(isEnabled: $accessoryEnabled) {
                OuterDisplayView { PatientView(session: session) }
            }
            .onAvailabilityChange { accessoryAvailable = $0 }
        }
        .hingeScrub(session)
        .onAppear { session.start() }
    }
}

/// Patient view shown on the inner display when the outer one is not available.
struct FallbackPatientPane: View {
    var session: SessionModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "person.crop.rectangle")
                Text("Patient view · outer display unavailable").font(.caption)
                Spacer()
            }
            .padding(8)
            .background(.regularMaterial)
            PatientView(session: session)
        }
        .background(Color.black)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }
}

