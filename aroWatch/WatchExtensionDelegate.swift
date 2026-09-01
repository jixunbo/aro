import Foundation
import WatchKit

@MainActor
enum WatchBackgroundRefresh {
    static let identifier = "aro.watch.battery-refresh"
    static let preferredInterval: TimeInterval = 15 * 60

    static func scheduleNext() {
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: Date(timeIntervalSinceNow: preferredInterval),
            userInfo: identifier as NSString,
            scheduledCompletion: { _ in }
        )
    }
}

final class WatchExtensionDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        Task { @MainActor in
            WatchBackgroundRefresh.scheduleNext()
        }
    }

    func applicationWillResignActive() {
        Task { @MainActor in
            WatchBatteryService.shared.refreshAndSend()
            WatchBackgroundRefresh.scheduleNext()
        }
    }
}
