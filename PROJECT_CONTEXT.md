# Project context

## Purpose and current capabilities

traceon is a privacy-first iOS/iPadOS app that records a user's location history with selectable power/accuracy trade-offs. It can record in the background, show today's route and per-day history, render a sampled lifetime overview, calculate distance and point counts, import/export GPX and GeoJSON, and delete all local track data. It has no account, backend, analytics, or cloud synchronization.

## Architecture and data flow

- The SwiftUI app uses an `AppDelegate` only to receive location-triggered launches. Onboarding stages When In Use and Always location authorization; the main UI has Today, History, Insights, and Settings tabs.
- `LocationService` owns two `CLLocationManager` instances. One monitors significant location changes and visits for low-power wakeups; the other supplies standard updates in Balanced, Precise, and Workout modes. Motion activity reduces detail-manager accuracy while stationary and selects an appropriate Core Location activity type.
- Incoming locations pass through `TrackMath` accuracy, freshness, duplicate, time-order, and implausible-speed filters before insertion. Accepted points include their source and current motion label.
- `TrackDatabase` owns the SQLite connection and serializes access on a utility queue. `TrackRepository` moves reads to detached tasks and publishes view state on the main actor. The UI does not query SQLite directly except for Settings' detached full export/import work.
- `TrackMapView` bridges SwiftUI to `MKMapView`, splits routes at long gaps or impossible jumps, and renders native gradient polylines.
- GPX import/export preserves coordinates, elevation, and available timestamps. GeoJSON handles `LineString` and `MultiLineString` imports and exports a `FeatureCollection` containing one `LineString`.

## Storage

- The database is `Application Support/traceon/tracks.sqlite3`, uses SQLite WAL with `synchronous=NORMAL`, and is protected until the first device unlock.
- `track_points` stores raw samples. A unique index on timestamp, latitude, and longitude provides import/recording deduplication. `daily_summary` stores per-local-calendar-day point counts, distance, and first/last timestamps for history and lifetime statistics.
- Normal inserts increment the relevant daily summary. Batch imports run in a transaction and rebuild every daily summary from timestamp-ordered raw points.
- Today/day queries are capped at 50,000 points; the lifetime map reads at most 8,000 row-ID-sampled points. Full export reads all points.
- Tracking enabled state, tracking mode, and onboarding completion are in `UserDefaults`. Deleting all data clears both SQLite tables; uninstalling the app removes unexported data.

## Runtime and dependencies

- Minimum deployment target: iOS/iPadOS 17.0. Targets support iPhone and iPad, not Mac Catalyst.
- Project settings use Swift 5 with minimal strict-concurrency checking. `README.md` requires Xcode 26+; the project was last created/upgraded with Xcode 26.3.
- Dependencies are Apple frameworks plus the system SQLite library linked with `-lsqlite3`. There are no package-manager dependencies or external service APIs.
- The app declares the `location` background mode, location/motion permission strings, and a privacy manifest with no collected data or tracking.

## Known limitations

- iOS schedules background location delivery. Even with Always authorization, significant-change and visit monitoring do not guarantee a continuous, point-by-point route after suspension or termination.
- GeoJSON export contains no timestamps, and GeoJSON import assigns points sequential timestamps starting at import time. A GeoJSON round trip therefore changes dates and timing.
- GPX points without a timestamp also receive import-time sequential fallback timestamps.
- Full export and daily-summary rebuild load the complete point history into memory. Large-history behavior has no dedicated automated test.
- Unit tests cover filtering, distance, GPX import, and GPX/GeoJSON export. SQLite integration, authorization transitions, background relaunch, timezone/DST grouping, and energy use remain dependent on manual or real-device validation in `TESTING.md`.
