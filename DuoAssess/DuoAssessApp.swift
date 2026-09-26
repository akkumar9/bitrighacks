import SwiftUI

@main
struct DuoAssessApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// What the app is doing. Copy-me (two cameras, two people) or a single-person assessment
/// profile (squat, face symmetry). The furniture build is separate (`FurnitureRootView`).
enum AppMode: String, CaseIterable, Identifiable {
    case copyMe = "Copy me"
    case assess = "Assess"
    var id: String { rawValue }
}

/// Owns both sessions and both displays. One view tree: the mode switches which session's views
/// render, availability only adds or removes the fallback pane, and all state lives on the models.
struct RootView: View {
    @State private var mode: AppMode = .copyMe
    @State private var copyMe = CopyMeSession.makeDefault()
    @State private var assess = SessionModel.makeDefault()
    @State private var accessoryEnabled = true
    @State private var accessoryAvailable = false
    @State private var isWide = true

    var body: some View {
        let layout = isWide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
        layout {
            innerView
            if !accessoryAvailable {
                FallbackOuterPane(mode: mode, copyMe: copyMe, assess: assess)
                    .frame(maxWidth: isWide ? 340 : .infinity, maxHeight: isWide ? .infinity : 300)
            }
        }
        .onGeometryChange(for: Bool.self) { $0.size.width > $0.size.height } action: { isWide = $0 }
        .animation(.snappy, value: accessoryAvailable)
        .sceneAccessory {
            CameraCaptureAccessory(isEnabled: $accessoryEnabled) {
                OuterDisplayView { outerView }
            }
            .onAvailabilityChange { accessoryAvailable = $0 }
        }
        .onHingeChange { _, context in
            guard let hinge = context.hinge else { return }
            switch mode {
            case .copyMe: copyMe.hingeChanged(degrees: hinge.angle.degrees)
            case .assess: assess.hingeChanged(degrees: hinge.angle.degrees)
            }
        }
        .onAppear { start(mode) }
        .onChange(of: mode) { old, new in
            switch old {
            case .copyMe: copyMe.stop()
            case .assess: assess.stop()
            }
            start(new)
        }
    }

    private func start(_ m: AppMode) {
        switch m {
        case .copyMe: copyMe.start()
        case .assess: assess.start()
        }
    }

    @ViewBuilder private var innerView: some View {
        switch mode {
        case .copyMe: CopyMeClinicianView(session: copyMe, accessoryAvailable: accessoryAvailable, isWide: isWide, modePicker: AnyView(modePicker))
        case .assess: ClinicianView(session: assess, accessoryAvailable: accessoryAvailable, isWide: isWide, modePicker: AnyView(modePicker))
        }
    }

    @ViewBuilder private var outerView: some View {
        switch mode {
        case .copyMe: LearnerView(session: copyMe)
        case .assess: PatientView(session: assess)
        }
    }

    private var modePicker: some View {
        Picker("Mode", selection: $mode) {
            ForEach(AppMode.allCases) { m in Text(m.rawValue).tag(m) }
        }
        .pickerStyle(.segmented)
        .frame(width: 150)
        .controlSize(.small)
    }
}

/// Outer-display content shown on the inner display when the accessory is unavailable.
struct FallbackOuterPane: View {
    var mode: AppMode
    var copyMe: CopyMeSession
    var assess: SessionModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "person.crop.rectangle")
                Text("\(mode == .copyMe ? "Learner" : "Patient") view · outer display unavailable").font(.caption)
                Spacer()
            }
            .padding(8)
            .background(.regularMaterial)
            switch mode {
            case .copyMe: LearnerView(session: copyMe)
            case .assess: PatientView(session: assess)
            }
        }
        .background(Color.black)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }
}
