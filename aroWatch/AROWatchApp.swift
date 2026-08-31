import SwiftUI

@main
struct AROWatchApp: App {
    @WKExtensionDelegateAdaptor(WatchExtensionDelegate.self) private var extensionDelegate
    @StateObject private var reporter = WatchBatteryService.shared

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(reporter)
        }
    }
}
