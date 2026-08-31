# Project context

## Purpose and current capabilities

aro (Everything Around You) is a privacy-first combined iOS/iPadOS and watchOS app. The surviving `aro` iOS host records a user's location history with selectable power/accuracy trade-offs, while its embedded watchOS companion reports Apple Watch battery and device state to the iPhone dashboard and Shortcuts. The app can record location in the background, show today's route and per-day history, render a sampled lifetime overview, calculate distance and point counts, import/export GPX and GeoJSON, delete all local track data, display the latest watch battery snapshot, manually refresh it when reachable, and provide the “获取设备电量” App Intent. It has no account, backend, analytics, or cloud synchronization.

## Architecture and data flow

- The SwiftUI iOS app uses an `AppDelegate` only to receive location-triggered launches. Onboarding stages When In Use and Always location authorization; the main UI has Today, History, Insights, Devices, and Settings tabs.
- `LocationService` owns two `CLLocationManager` instances. One monitors significant location changes and visits for low-power wakeups; the other supplies standard updates in Balanced, Precise, and Workout modes. Motion activity reduces detail-manager accuracy while stationary and selects an appropriate Core Location activity type.
- Incoming locations pass through `TrackMath` accuracy, freshness, duplicate, time-order, and implausible-speed filters before insertion. Accepted points include their source and current motion label.
- `TrackDatabase` owns the SQLite connection and serializes access on a utility queue. `TrackRepository` moves reads to detached tasks and publishes view state on the main actor. The UI does not query SQLite directly except for Settings' detached full export/import work.
- `TrackMapView` bridges SwiftUI to `MKMapView`, splits routes at long gaps or impossible jumps, renders native gradient polylines, and lets users inspect the nearest recorded timestamp by tapping a route.
- GPX import/export preserves coordinates, elevation, and available timestamps. GeoJSON handles `LineString` and `MultiLineString` imports and exports a `FeatureCollection` containing one `LineString`.
- The Devices feature is separate from location/data code. `BatterySnapshot` is compiled into both targets and defines the WatchConnectivity payload. The watch is the battery source; it publishes its latest snapshot through application context and can reply to explicit reachable messages. `BatteryStore` caches the newest valid timestamped snapshot in iOS `UserDefaults` under `latestAppleWatchBatterySnapshot`.
- The watch app also persists the newest `BatterySnapshot` in the Watch App Group `group.com.xunbo.traceon.watch`. A WidgetKit complication extension reads that shared snapshot and renders circular, corner, inline, and rectangular families. The complication never samples `WKInterfaceDevice`; `WatchBatteryService` remains the sole watch battery reader and reloads the complication only when displayed battery/status values change (timestamp-only samples are persisted without a reload). Its original WidgetKit kind string remains stable so an installed complication survives the display-name rename. Autonomous watch refreshes publish only application context; a WatchConnectivity `sendMessage` is reserved for an explicit iPhone request/reply.
- `PhoneConnectivity` is main-actor isolated and passive at initialization. Session activation and WatchConnectivity callbacks update connection state or accept opportunistic snapshots but never trigger a live battery request. Live requests occur only when the Devices tab is selected/refreshed or the App Intent runs. It has no polling timer or iPhone background task and is not coupled to `LocationService`.
- The watch app samples on launch/activation, once per minute while its UI is visible, when leaving the foreground, during watchOS-scheduled application refresh, and in response to an explicit reachable iPhone request. Each valid sample is persisted to the Watch App Group, published through WatchConnectivity, and may trigger a WidgetKit timeline reload when displayed values change. Its preferred next background refresh remains 30 minutes, subject to watchOS scheduling; neither WidgetKit nor `WKApplicationRefreshBackgroundTask` is an exact interval guarantee.

## Storage

- The database is `Application Support/traceon/tracks.sqlite3`, uses SQLite WAL with `synchronous=NORMAL`, and is protected until the first device unlock.
- `track_points` stores raw samples. A unique index on timestamp, latitude, and longitude provides import/recording deduplication. `daily_summary` stores per-local-calendar-day point counts, distance, and first/last timestamps for history and lifetime statistics.
- Normal inserts increment the relevant daily summary. Batch imports run in a transaction and rebuild every daily summary from timestamp-ordered raw points.
- Today/day queries are capped at 50,000 points; the lifetime map reads at most 8,000 row-ID-sampled points. Full export reads all points.
- Tracking enabled state, tracking mode, and onboarding completion are in `UserDefaults`. Deleting all data clears both SQLite tables; uninstalling the app removes unexported data.
- The user-visible name is aro and the product bundle identifiers use the aro namespace: iOS `com.xunbo.aro`, Watch App `com.xunbo.aro.watchkitapp`, and Widget Extension `com.xunbo.aro.watchkitapp.widget`. These identifiers intentionally create a new app identity; an existing Traceon/Companio install does not receive an in-place upgrade or automatic SQLite/UserDefaults migration. The database path remains `Application Support/traceon/tracks.sqlite3` within the new container, and the watch snapshot cache remains independent of the SQLite track database.

## Runtime and dependencies

- Minimum deployment targets: iOS/iPadOS 17.0 and watchOS 10.0. The iOS target supports iPhone and iPad, not Mac Catalyst.
- The project has four targets: `aro` (`com.xunbo.aro`), embedded `ARO Watch App` (`com.xunbo.aro.watchkitapp`, companion identifier `com.xunbo.aro`), embedded `ARO Watch Widget Extension` (`com.xunbo.aro.watchkitapp.widget`), and `aroTests`. The shipped iOS, Watch App, and Widget display name is `aro`; the Watch App and Widget Extension share the stable Watch App Group `group.com.xunbo.traceon.watch`; the iOS host does not need that group.
- The repository and Xcode project are named `aro` (`aro.xcodeproj`); the former Traceon/Companio names remain only in the stable data path, WidgetKit kind, App Group, or historical upgrade notes.
- Project settings use Swift 5 with minimal strict-concurrency checking. `README.md` requires Xcode 26+; the project was last created/upgraded with Xcode 26.3.
- Dependencies are Apple frameworks plus the system SQLite library linked with `-lsqlite3`. The device feature uses WatchConnectivity, WatchKit, and AppIntents. There are no package-manager dependencies or external service APIs.
- The app declares the `location` background mode, location/motion permission strings, and a privacy manifest with no collected data or tracking.

## Known limitations

- iOS schedules background location delivery. Even with Always authorization, significant-change and visit monitoring do not guarantee a continuous, point-by-point route after suspension or termination.
- GeoJSON export contains no timestamps, and GeoJSON import assigns points sequential timestamps starting at import time. A GeoJSON round trip therefore changes dates and timing.
- GPX points without a timestamp also receive import-time sequential fallback timestamps.
- Full export and daily-summary rebuild load the complete point history into memory. Large-history behavior has no dedicated automated test.
- Unit tests cover filtering, distance, GPX import, GPX/GeoJSON export, and lifetime-overview SQLite sampling. Broader SQLite integration, authorization transitions, background relaunch, timezone/DST grouping, and energy use remain dependent on manual or real-device validation in `TESTING.md`.
- iOS cannot read Apple Watch battery through a public API. The companion must be installed and opened at least once; when it is unreachable, the UI and App Intent return the latest timestamped cache rather than guaranteed live state.
- WatchConnectivity delivery and watchOS background refresh timing are system-controlled. The active complication adds a legitimate watchOS refresh opportunity and direct watch-face visibility, but does not guarantee a fixed update interval. Simulator compilation does not validate paired-device transfer, complication scheduling, Shortcut results, background refresh, or the combined app's real-world energy impact.
