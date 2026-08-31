# Architectural decisions

## Local-only persistence

**Decision:** Store tracks on-device in SQLite; do not require an account, backend, analytics service, or cloud synchronization.

**Reason:** The product describes itself as privacy-first and intended for long-term local accumulation without a server.

**Implications:** Export is the only implemented backup/transfer path. Deletion and uninstall can permanently remove unexported data. Any future external data flow is a product and privacy change, not an incidental implementation detail.

## Adaptive native background location

**Decision:** Combine significant-location-change and visit monitoring with mode-dependent standard location updates, adapting standard updates using motion activity.

**Reason:** The app must continue collecting while not foregrounded while offering explicit battery-versus-detail trade-offs.

**Implications:** Always authorization and the location background mode are required for the strongest background behavior. Eco mode is intentionally coarse; Workout mode is intentionally more power intensive. Core Location delivery remains system-scheduled and must be verified on real hardware.

## Raw points plus daily summaries

**Decision:** Keep raw track points and a separate `daily_summary` table, with uniqueness enforced on timestamp and coordinates.

**Reason:** History and lifetime statistics read the summary table instead of recalculating the complete track history. Deduplication allows recording and imports to coexist.

**Implications:** Every data mutation must preserve summary consistency. Batch imports rebuild summaries in timestamp order, and schema evolution currently belongs in `TrackDatabase.openAndMigrate()`.

## Actor-isolated UI state and serialized database access

**Decision:** Keep observable location/repository state on the main actor and serialize all SQLite work through `TrackDatabase`'s private queue.

**Reason:** UI-visible state must be published on the main thread, while the shared SQLite connection must not receive concurrent unsynchronized access.

**Implications:** Expensive reads are dispatched away from the main actor, then published back on it. New database APIs must continue using the database queue rather than exposing the connection.

## Platform-native dependency set

**Decision:** Build with SwiftUI and Apple frameworks, using a UIKit `MKMapView` bridge and the system SQLite library; do not use third-party packages.

**Reason:** No separate rationale is recorded in the repository.

**Implications:** Prefer existing Apple APIs and the current SQLite layer. Adding a package requires a concrete need plus review of binary size, privacy-manifest impact, compatibility, and maintenance cost.

## One surviving iOS host with an embedded watch companion

**Decision:** Keep the existing `traceon` target and Xcode project as the sole iOS host, add the existing Companio functionality as an embedded `Companio Watch App` target, and expose device functionality as a separate iOS feature within the host.

**Reason:** The combined product needs both established Traceon location history and Companio watch battery behavior without creating a third project or replacing the source-of-truth host.

**Implications:** The host depends on and embeds the watch target. Shared WatchConnectivity payload code is compiled into both targets. Location, track storage, device UI/connectivity, and watch source remain in separate directories and target memberships.

## Preserve the Traceon application identity and data container

**Decision:** Change the user-visible application name to Companio while retaining the iOS bundle identifier `com.xunbo.traceon`, the `Application Support/traceon/tracks.sqlite3` database path, and existing tracking/onboarding `UserDefaults` keys.

**Reason:** Existing installed Traceon users must retain their local SQLite history and settings through an upgrade.

**Implications:** No bundle-ID or data-path migration is introduced. The embedded watch target uses `com.xunbo.traceon.watchkitapp` and declares `com.xunbo.traceon` as `WKCompanionAppBundleIdentifier`.

## Separate location and device lifecycles

**Decision:** WatchConnectivity activation is passive, and iPhone live battery requests are limited to explicit Devices UI use or the App Intent. Device connectivity is not initialized or driven by `LocationService`, does not poll on iPhone, and does not add periodic iPhone background work.

**Reason:** Adding watch battery functionality must not meaningfully increase the existing background-location energy cost, especially during a Core Location relaunch.

**Implications:** Activation and connectivity callbacks may accept opportunistic application-context state but must not send live requests. The Devices tab owns its selected/refresh flow; a location-triggered launch defaults to the Today tab and does not request watch data. The watch keeps its existing foreground timer and system-scheduled background refresh because those execute on watchOS, not as added iPhone location work.

## Latest timestamped watch snapshot

**Decision:** Keep Apple Watch as the battery source, application context for opportunistic latest-state synchronization, reachable messages for explicit live request/reply, and an iPhone `UserDefaults` cache where newer timestamps win.

**Reason:** Device UI and Shortcuts need a useful last known value when the watch is temporarily unreachable without implying that cached state is live.

**Implications:** The UI presents the synchronization timestamp and explicitly labels unreachable data as cached. Payload key/type changes remain a coordinated cross-target compatibility change.
