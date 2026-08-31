import SwiftUI

@main
struct CompanioWatchApp: App {
    @WKExtensionDelegateAdaptor(WatchExtensionDelegate.self) private var extensionDelegate
    @StateObject private var reporter = CompanioBatteryReporter.shared

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(reporter)
        }
    }
}
