import Foundation
import WatchKit

@MainActor
enum WatchBackgroundRefresh {
    static let identifier = "aro.watch.battery-refresh"
    static let preferredInterval: TimeInterval = 60 * 60

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

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            guard let refreshTask = task as? WKApplicationRefreshBackgroundTask else {
                task.setTaskCompletedWithSnapshot(false)
                continue
            }

            Task { @MainActor in
                WatchBackgroundRefresh.scheduleNext()
                await WatchBatteryService.shared.refreshAndSendAsync()
                refreshTask.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}
