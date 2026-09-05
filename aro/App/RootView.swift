import SwiftUI

struct RootView: View {
    @AppStorage("onboarding.completed") private var hasCompletedOnboarding = false
    @EnvironmentObject private var repository: TrackRepository
    @EnvironmentObject private var locationService: LocationService
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingView(isComplete: $hasCompletedOnboarding)
            }
        }
        .task {
            repository.refresh()
            if scenePhase == .active {
                locationService.appBecameActive()
                AROShortcuts.updateAppShortcutParameters()
                PhoneConnectivity.shared.appBecameActive()
                PhoneConnectivity.shared.publishTrackComplication(points: repository.todayPoints, force: true)
#if ARO_CLOUDKIT_ENABLED
                CloudSyncService.shared.appBecameActive()
#endif
            }
        }
        .onChange(of: repository.todayPoints) { _, points in
            PhoneConnectivity.shared.publishTrackComplication(points: points, force: scenePhase == .active)
        }
        .onChange(of: repository.isLoading) { wasLoading, isLoading in
            guard wasLoading, !isLoading, scenePhase == .active else { return }
            PhoneConnectivity.shared.publishTrackComplication(points: repository.todayPoints, force: true)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                repository.refresh()
                locationService.appBecameActive()
                AROShortcuts.updateAppShortcutParameters()
                PhoneConnectivity.shared.appBecameActive()
                PhoneConnectivity.shared.publishTrackComplication(points: repository.todayPoints, force: true)
#if ARO_CLOUDKIT_ENABLED
                CloudSyncService.shared.appBecameActive()
#endif
            }
        }
    }
}

private struct MainTabView: View {
    @State private var selectedTab: Tab = .today

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { TodayView() }
                .tabItem { Label("今日", systemImage: "location.fill") }
                .tag(Tab.today)

            NavigationStack { HistoryView() }
                .tabItem { Label("历史", systemImage: "calendar") }
                .tag(Tab.history)

            NavigationStack { InsightsView() }
                .tabItem { Label("足迹", systemImage: "globe.asia.australia.fill") }
                .tag(Tab.insights)

            NavigationStack { DevicesView(isSelected: selectedTab == .devices) }
                .tabItem { Label("设备", systemImage: "applewatch") }
                .tag(Tab.devices)

            NavigationStack { SettingsView() }
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
        .tint(.cyan)
    }

    private enum Tab: Hashable {
        case today
        case history
        case insights
        case devices
        case settings
    }
}
