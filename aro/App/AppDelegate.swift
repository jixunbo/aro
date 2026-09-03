import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // iOS 26 deprecates the legacy location launch-option discriminator. LocationService is
        // deliberately the only subsystem restored here so a Core Location background relaunch
        // cannot incidentally start WatchConnectivity or CloudKit.
        LocationService.shared.handleApplicationLaunch()
        return true
    }

#if ARO_CLOUDKIT_ENABLED
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Cloud work is entered through its own delivery path rather than generic process launch.
        Task { @MainActor in
            await CloudSyncService.shared.syncNow()
            completionHandler(.noData)
        }
    }
#endif
}
