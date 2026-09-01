import SwiftUI
import WatchKit

@main
struct AROWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchExtensionDelegate.self) private var applicationDelegate
    @StateObject private var reporter = WatchBatteryService.shared

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(reporter)
        }
        .backgroundTask(.appRefresh(WatchBackgroundRefresh.identifier)) {
            await MainActor.run {
                WatchBackgroundRefresh.scheduleNext()
            }
            await WatchBatteryService.shared.refreshAndSendAsync()
        }
    }
}
