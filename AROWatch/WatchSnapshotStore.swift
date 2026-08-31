import Foundation

/// Shared persistence for the watch app and its WidgetKit extension.
///
/// The watch app remains the only component that samples the battery. The
/// widget reads this latest locally persisted value without starting its own
/// monitoring loop.
enum WatchSnapshotStore {
    static let appGroupIdentifier = "group.com.xunbo.traceon.watch"
    // Keep the original kind stable so an installed complication survives the
    // display-name and source-file rename to ARO.
    static let widgetKind = "CompanioBatteryWidget"

    private static let storageKey = "latestAppleWatchBatterySnapshot"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    static func load() -> BatterySnapshot? {
        guard let defaults,
              let data = defaults.data(forKey: storageKey),
              let snapshot = try? JSONDecoder().decode(BatterySnapshot.self, from: data),
              (0...100).contains(snapshot.level) else {
            return nil
        }
        return snapshot
    }

    /// Persists only newer snapshots and reports whether the widget's displayed
    /// values changed. A timestamp-only update is still stored, but does not
    /// require a timeline reload.
    @discardableResult
    static func save(_ snapshot: BatterySnapshot) -> Bool {
        guard (0...100).contains(snapshot.level), let defaults else { return false }

        if let existing = load() {
            guard snapshot.updatedAt >= existing.updatedAt, snapshot != existing else { return false }

            guard let data = try? JSONEncoder().encode(snapshot) else { return false }
            defaults.set(data, forKey: storageKey)
            return existing.level != snapshot.level
                || existing.state != snapshot.state
                || existing.deviceName != snapshot.deviceName
        }

        guard let data = try? JSONEncoder().encode(snapshot) else { return false }
        defaults.set(data, forKey: storageKey)
        return true
    }
}
