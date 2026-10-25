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

/// The sky is drawn once here and never torn down; every screen floats above it.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            DreamBackground()
            if app.account.isSignedIn && app.account.hasCompletedOnboarding {
                MainView(app: app)
                    .transition(.blurReplace)
            } else {
                OnboardingFlow()
                    .transition(.blurReplace)
            }
        }
        .foregroundStyle(Theme.ink)
        .animation(.smooth(duration: 0.8), value: app.account.hasCompletedOnboarding)
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
        case .create: "photo.stack"
        case .stories: "book.closed"
        case .you: "person.crop.circle"
        }
    }
}

struct MainView: View {
    @State private var vm: RunViewModel
    @State private var tab: MainTab = .create
    @State private var storiesRefresh = 0

    init(app: AppModel) {
        _vm = State(initialValue: RunViewModel(app: app))
    }

    private var showsTabBar: Bool { tab != .create || vm.screen == .setup }

    var body: some View {
        ZStack(alignment: .bottom) {
            // All three tabs stay alive (no rebuilds, scroll positions kept); only the visible one takes touches.
            CreateView(vm: vm)
                .tabLayer(visible: tab == .create)
            StoriesView(refresh: storiesRefresh) { run in
                vm.open(run)
                tab = .create
            }
            .tabLayer(visible: tab == .stories)
            ProfileView()
                .tabLayer(visible: tab == .you)
            if showsTabBar {
                if tab != .create { BottomFade(height: 130) }
                GlassTabBar(selection: $tab)
                    .padding(.bottom, 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.45), value: showsTabBar)
        .animation(.smooth(duration: 0.35), value: tab)
        .sensoryFeedback(.selection, trigger: tab)
        .onChange(of: tab) { _, new in if new == .stories { storiesRefresh += 1 } }
    }
}

private extension View {
    func tabLayer(visible: Bool) -> some View {
        self
            .opacity(visible ? 1 : 0)
            .scaleEffect(visible ? 1 : 0.985)
            .allowsHitTesting(visible)
            .accessibilityHidden(!visible)
    }
}

/// Floating glass tab bar.
struct GlassTabBar: View {
    @Binding var selection: MainTab
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 4) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol).font(.system(size: 18, weight: selection == tab ? .semibold : .regular))
                        Text(tab.title).font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Theme.ink.opacity(selection == tab ? 1 : 0.55))
                    .frame(width: 84, height: 52)
                    .background {
                        if selection == tab {
                            Capsule().fill(.white.opacity(0.45)).matchedGeometryEffect(id: "pill", in: pill)
                        }
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
        .animation(.spring(duration: 0.4, bounce: 0.25), value: selection)
    }
}
