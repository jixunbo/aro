import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let locationTriggered = launchOptions?[.location] != nil
        LocationService.shared.handleApplicationLaunch(locationTriggered: locationTriggered)
        if !locationTriggered {
            Task { @MainActor in
                CloudSyncService.shared.prepareForLaunch()
            }
        }
        return true
    }
}

