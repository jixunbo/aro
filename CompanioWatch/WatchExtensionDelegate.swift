import WatchKit

final class WatchExtensionDelegate: NSObject, WKExtensionDelegate {
    func applicationDidFinishLaunching() {
        Task { @MainActor in CompanioBatteryReporter.shared.refreshAndSend() }
        scheduleNextRefresh()
    }

    func applicationWillResignActive() {
        Task { @MainActor in CompanioBatteryReporter.shared.refreshAndSend() }
        scheduleNextRefresh()
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            guard let refreshTask = task as? WKApplicationRefreshBackgroundTask else {
                task.setTaskCompletedWithSnapshot(false)
                continue
            }

            Task { @MainActor in
                CompanioBatteryReporter.shared.refreshAndSend {
                    self.scheduleNextRefresh()
                    refreshTask.setTaskCompletedWithSnapshot(false)
                }
            }
        }
    }

    private func scheduleNextRefresh() {
        let preferredDate = Date(timeIntervalSinceNow: 30 * 60)
        WKExtension.shared().scheduleBackgroundRefresh(
            withPreferredDate: preferredDate,
            userInfo: nil,
            scheduledCompletion: { _ in }
        )
    }
}
