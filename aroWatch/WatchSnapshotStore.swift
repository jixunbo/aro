import Foundation

/// Shared persistence for the watch app and its WidgetKit extension.
///
/// The watch app and system-budgeted widget timeline refreshes can each take a
/// short-lived battery sample. Both persist through this newest-timestamp-wins
/// store; neither leaves battery monitoring enabled between reads. The iPhone
/// also sends a compact today-route snapshot for the track complication.
enum WatchSnapshotStore {
    static let appGroupIdentifier = "group.com.xunbo.traceon.watch"
    // Keep the original battery kind stable so an installed complication survives
    // the display-name rename to aro and source-directory rename to aroWatch.
    static let widgetKind = "CompanioBatteryWidget"
    static let trackWidgetKind = "AROTrackWidget"

    private static let storageKey = "latestAppleWatchBatterySnapshot"
    private static let trackStorageKey = "latestAROTrackComplicationSnapshot"

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

    static func loadTrack() -> TrackComplicationSnapshot? {
        guard let defaults,
              let data = defaults.data(forKey: trackStorageKey),
              let snapshot = try? JSONDecoder().decode(TrackComplicationSnapshot.self, from: data),
              Calendar.autoupdatingCurrent.isDateInToday(snapshot.dayStart) else {
            return nil
        }
        return snapshot
    }

    /// Saves the newest route snapshot and reports whether the complication's
    /// visible route or distance changed.
    @discardableResult
    static func saveTrack(_ snapshot: TrackComplicationSnapshot) -> Bool {
        guard let defaults else { return false }
        let existing = loadTrack()
        if let existing {
            guard snapshot.updatedAt >= existing.updatedAt, snapshot != existing else { return false }
        }

        guard let data = try? JSONEncoder().encode(snapshot) else { return false }
        defaults.set(data, forKey: trackStorageKey)

        guard let existing else { return true }
        return existing.distanceMeters != snapshot.distanceMeters
            || existing.segments != snapshot.segments
            || !Calendar.autoupdatingCurrent.isDate(existing.dayStart, inSameDayAs: snapshot.dayStart)
    }
}
