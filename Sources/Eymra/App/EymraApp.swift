import SwiftUI

@main
struct EymraApp: App {
    @State private var app = AppModel()

    var body: some SwiftUI.Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(app.settings)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if app.access.isUsable {
                HomeView(app: app)
            } else {
                PermissionView()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { app.refreshAccess() }
        }
    }
}
