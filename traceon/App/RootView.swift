import SwiftUI

struct RootView: View {
    @AppStorage("onboarding.completed") private var hasCompletedOnboarding = false
    @EnvironmentObject private var repository: TrackRepository
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingView(isComplete: $hasCompletedOnboarding)
            }
        }
        .task { repository.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { repository.refresh() }
        }
    }
}

private struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack { TodayView() }
                .tabItem { Label("今日", systemImage: "location.fill") }

            NavigationStack { HistoryView() }
                .tabItem { Label("历史", systemImage: "calendar") }

            NavigationStack { InsightsView() }
                .tabItem { Label("足迹", systemImage: "globe.asia.australia.fill") }

            NavigationStack { SettingsView() }
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
        .tint(.cyan)
    }
}

