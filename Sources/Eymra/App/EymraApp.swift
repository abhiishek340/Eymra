import SwiftUI

@main
struct EymraApp: App {
    @State private var app = AppModel()

    var body: some SwiftUI.Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(app.settings)
                .environment(app.account)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if app.account.isSignedIn && app.account.hasCompletedOnboarding {
                MainView(app: app)
                    .transition(.opacity)
            } else {
                OnboardingFlow()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: app.account.hasCompletedOnboarding)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { app.refreshAccess() }
        }
    }
}

enum MainTab: String, CaseIterable {
    case create, stories, you

    var title: String {
        switch self {
        case .create: String(localized: "Create")
        case .stories: String(localized: "Stories")
        case .you: String(localized: "You")
        }
    }

    var symbol: String {
        switch self {
        case .create: "sparkles"
        case .stories: "book.closed"
        case .you: "person.crop.circle"
        }
    }
}

struct MainView: View {
    @State private var vm: RunViewModel
    @State private var tab: MainTab = .create

    init(app: AppModel) {
        _vm = State(initialValue: RunViewModel(app: app))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            switch tab {
            case .create: HomeView(vm: vm)
            case .stories: StoriesView { run in
                vm.open(run)
                tab = .create
            }
            case .you: ProfileView()
            }
            if !vm.showResults {
                if tab != .create { BottomFade(height: 130) }
                GlassTabBar(selection: $tab)
                    .padding(.bottom, 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: vm.showResults)
    }
}

/// Floating glass tab bar.
struct GlassTabBar: View {
    @Binding var selection: MainTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(duration: 0.3)) { selection = tab }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol).font(.system(size: 18, weight: selection == tab ? .semibold : .regular))
                        Text(tab.title).font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Theme.ink.opacity(selection == tab ? 1 : 0.55))
                    .frame(width: 84, height: 52)
                    .background {
                        if selection == tab { Capsule().fill(.white.opacity(0.45)) }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tab-\(tab.rawValue)")
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(6)
        .glassCapsule(interactive: false)
    }
}
