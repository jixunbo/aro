import SwiftUI

@main
struct TraceonApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var repository = TrackRepository.shared
    @StateObject private var locationService = LocationService.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(repository)
                .environmentObject(locationService)
                .preferredColorScheme(.dark)
        }
    }
}
