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

**Decision:** Keep the existing `aro` target and Xcode project as the sole iOS host, retain the existing location functionality, and expose Apple Watch device functionality through an embedded `ARO Watch App` target and separate iOS feature within the host.

**Reason:** aro needs both established Traceon location history and Apple Watch battery behavior without creating a third project or replacing the source-of-truth host.

**Implications:** The host depends on and embeds the watch target. Shared WatchConnectivity payload code is compiled into both targets. Location, track storage, device UI/connectivity, and watch source remain in separate directories and target memberships.

## Preserve the legacy application identity and data container (superseded)

This earlier decision applied while the product was being renamed without changing its system identity. It was superseded by “Adopt aro bundle identifiers” below after the user explicitly requested a new Bundle ID namespace.

**Decision:** Change the user-visible application name to aro and rename the local project/source targets, while retaining the iOS bundle identifier `com.xunbo.traceon`, the `Application Support/traceon/tracks.sqlite3` database path, and existing tracking/onboarding `UserDefaults` keys.

**Reason:** Existing installed Traceon/Companio users must retain their local SQLite history and settings through an upgrade even though the product is now called aro.

**Implications:** No bundle-ID or data-path migration is introduced. The embedded watch target is internally named `ARO Watch App`; its on-device display name is `aro`.

## aro repository and source naming

**Decision:** Rename the repository-facing project, scheme, iOS source directory, and Watch source directory to `aro`/`aroWatch`, while keeping internal Watch target/type names and persistent data names unchanged.

**Reason:** aro is the product name and “Everything Around You” is the intended identity; the codebase should expose that name consistently while preserving stable on-device data and Watch snapshot names.

**Implications:** Open `aro.xcodeproj` and build the shared `aro` scheme. The iOS module and test target are `aro` and `aroTests`; Watch sources live under `aroWatch`, while the internal Watch targets and battery/widget symbols retain their existing names. The Watch App Group and `Application Support/traceon/tracks.sqlite3` remain stable data identifiers; Bundle IDs are defined by the newer decision below.

## Adopt aro bundle identifiers

**Decision:** Use `com.xunbo.aro` for the iOS host, `com.xunbo.aro.watchkitapp` for the embedded Watch App, `com.xunbo.aro.watchkitapp.widget` for the Widget Extension, and `com.xunbo.aro` as `WKCompanionAppBundleIdentifier`. Keep the existing Watch App Group and relative SQLite filename unchanged.

**Reason:** The product identity is now aro, and the user explicitly chose a new Bundle ID namespace for all three shipped targets.

**Implications:** aro is a new system app identity rather than an in-place Traceon upgrade. Existing Traceon/Companio containers, UserDefaults, permissions, and SQLite history are not automatically visible to aro; users should export/import data if they need to move history. The stable Watch App Group remains a deliberate compatibility choice for the watch snapshot store, while the iOS host does not gain that entitlement.

## Separate location and device lifecycles

**Decision:** WatchConnectivity activation is passive, and iPhone live battery requests are limited to explicit Devices UI use or the App Intent. Device connectivity is not initialized or driven by `LocationService`, does not poll on iPhone, and does not add periodic iPhone background work.

**Reason:** Adding watch battery functionality must not meaningfully increase the existing background-location energy cost, especially during a Core Location relaunch.

**Implications:** Activation and connectivity callbacks may accept opportunistic application-context state but must not send live requests. The Devices tab owns its selected/refresh flow; a location-triggered launch defaults to the Today tab and does not request watch data. The watch keeps its existing foreground timer and system-scheduled background refresh because those execute on watchOS, not as added iPhone location work.

## Latest timestamped watch snapshot

**Decision:** Keep Apple Watch as the battery source, application context for opportunistic latest-state synchronization, reachable messages for explicit live request/reply, and an iPhone `UserDefaults` cache where newer timestamps win.

**Reason:** Device UI and Shortcuts need a useful last known value when the watch is temporarily unreachable without implying that cached state is live.

**Implications:** The UI presents the synchronization timestamp and explicitly labels unreachable data as cached. Payload key/type changes remain a coordinated cross-target compatibility change.

## Watch-owned snapshot and WidgetKit complication

**Decision:** Keep `WatchBatteryService` as the only component that reads `WKInterfaceDevice.current().batteryLevel`. Persist its newest valid `BatterySnapshot` in the Watch App Group `group.com.xunbo.traceon.watch`, and have the WidgetKit complication display that shared snapshot.

**Reason:** The complication should improve watch-face visibility and provide another watchOS refresh opportunity without creating a second battery-monitoring architecture or an iPhone polling path.

**Implications:** Battery samples continue to use application context and explicit reachable replies. Autonomous watch refreshes do not send unsolicited `sendMessage` calls that could wake the iPhone; only an explicit iPhone request receives a live reply. The watch app persists every newer timestamp but reloads the complication timeline only when displayed battery/status values meaningfully change. The original WidgetKit kind string stays stable so an installed complication survives the aro display-name rename. WidgetKit and watchOS background refresh are system scheduled; a preferred interval is not a guarantee.

## Freshness and retryable WatchConnectivity activation

**Decision:** After activation, ingest `WCSession.receivedApplicationContext` through the existing newest-timestamp-wins `BatteryStore` path before checking reachability or falling back to cache. Track activation-in-progress separately so an explicit call retries `.notActivated` sessions after an activation error, while avoiding duplicate activation calls and continuation resumes.

**Reason:** A newer opportunistic Watch sample can already be available when a Shortcut or Devices refresh starts, and failed activation must not permanently disable later explicit refreshes.

**Implications:** Reachable sessions still receive an explicit live request; unreachable sessions return the newest cache available after context ingestion. Location lifecycle and background energy behavior remain unchanged.
