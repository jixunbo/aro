# Architectural decisions

## Local-only persistence (superseded)

This decision was superseded by “Opt-in private CloudKit sync” below.

**Decision:** Store tracks on-device in SQLite; do not require an account, backend, analytics service, or cloud synchronization.

**Reason:** The product describes itself as privacy-first and intended for long-term local accumulation without a server.

**Implications:** Export was originally the only backup/transfer path. External data flow must remain an explicit privacy/product decision rather than an incidental implementation detail.

## Opt-in private CloudKit sync

**Decision:** Keep SQLite as the local source of truth and add explicit opt-in synchronization of raw `TrackPoint` records through `CKSyncEngine` and the user's private CloudKit database in container `iCloud.com.xunbo.aro`. Do not upload `daily_summary`, Watch battery data, analytics, or unrelated app state.

**Reason:** The app needs optional multi-device track continuity without introducing an aro account or self-hosted backend, while preserving local-first recording and privacy boundaries.

**Implications:** Every stored point has a stable `sync_id`; local writes are committed to SQLite first and are tracked as unsynced until CloudKit acknowledges them. Remote records are merged into SQLite and summaries are derived locally. Remote notification support is part of the iOS CloudKit capability, but Core Location-triggered cold launches deliberately do not initialize CloudKit so a location wake does not gain incidental network work. CloudKit/private-database behavior requires signed real-device validation; simulator and unsigned CI only validate compile and local logic.

Disabling sync stops future synchronization but does not delete existing CloudKit data. “Delete all tracks” must delete the private `AROTracks` record zone before clearing local SQLite whenever a cloud footprint may exist. A fetched deletion of that zone is treated as a global delete and clears local tracks on the receiving device, preventing stale rows from recreating deleted cloud history. Account changes pause sync and preserve local data rather than silently assigning it to a different Apple account.

## CloudKit optional build capability

**Decision:** CloudKit capability must not be required for the local/self-signed build. Keep `Debug`/`Release` as Local configurations with an empty iOS entitlements file and compile out the CloudKit service; provide `CloudDebug`/`CloudRelease` configurations that retain the existing CloudKit/APNs entitlements and `ARO_CLOUDKIT_ENABLED` condition.

**Reason:** Apple Personal Teams cannot provision iCloud/CloudKit or Push Notifications, while the app's local SQLite, Core Location, Watch, and Widget features must remain installable and usable with free development signing.

**Implications:** The Local build has no CloudKit runtime or iCloud controls beyond a clear unavailable status in Settings. The Cloud build still requires the `iCloud.com.xunbo.aro` container, Push Notifications, Remote notifications, and a matching paid-team provisioning profile. Both builds preserve the same local-first SQLite data model, bundle identifiers, Watch App Group, and Watch battery architecture.

## Adaptive native background location

**Decision:** Combine significant-location-change and visit monitoring with mode-dependent standard location updates. Balanced and Precise allow Core Location to automatically pause the standard service when the device appears stationary; motion activity is used for activity labeling and `activityType` while detail updates are active, not to downgrade Balanced/Precise accuracy to kilometer scale. When Core Location pauses detail updates, stop motion updates and explicitly restart the standard location service after a significant-location wake or a visit departure.

**Reason:** The app needs route detail closer to the configured mode while moving, but should let Core Location power down location hardware during genuine stationary periods. The previous manual stationary downgrade could leave the detail manager at very coarse accuracy, while an unhandled automatic pause could leave the route relying mostly on sparse significant-change events after movement resumed.

**Implications:** Always authorization and the location background mode are required for the strongest background behavior. Eco mode remains intentionally coarse and does not run standard updates; Workout mode remains intentionally more power intensive and does not auto-pause. Balanced and Precise preserve their configured accuracy/distance filters when active. A paused app still depends on a low-power movement/departure signal before detail tracking restarts, so the first segment after a long stop can remain coarser than a continuously running navigation/workout session. Route density, pause/resume behavior, and energy use must be verified on real hardware.

## Raw points plus daily summaries

**Decision:** Keep raw track points and a separate `daily_summary` table, with uniqueness enforced on timestamp and coordinates.

**Reason:** History and lifetime statistics read the summary table instead of recalculating the complete track history. Deduplication allows recording, imports, and remote CloudKit changes to coexist.

**Implications:** Every data mutation must preserve summary consistency. Batch imports and remote changes rebuild summaries when needed in timestamp order, and schema evolution currently belongs in `TrackDatabase.openAndMigrate()`. Cloud sync identity is additional metadata and does not replace the timestamp/latitude/longitude natural deduplication key.

## Actor-isolated UI state and serialized database access

**Decision:** Keep observable location/repository state on the main actor and serialize all SQLite work through `TrackDatabase`'s private queue.

**Reason:** UI-visible state must be published on the main thread, while the shared SQLite connection must not receive concurrent unsynchronized access.

**Implications:** Expensive reads are dispatched away from the main actor, then published back on it. New database APIs, including CloudKit apply/delete/bookkeeping operations, must continue using the database queue rather than exposing the connection.

## Platform-native dependency set

**Decision:** Build with SwiftUI and Apple frameworks, using a UIKit `MKMapView` bridge and the system SQLite library; do not use third-party packages.

**Reason:** No separate rationale is recorded in the repository.

**Implications:** Prefer existing Apple APIs and the current SQLite layer. Cloud sync uses CloudKit/CKSyncEngine because they are platform-native. Adding a package requires a concrete need plus review of binary size, privacy-manifest impact, compatibility, and maintenance cost.

## One surviving iOS host with an embedded watch companion

**Decision:** Keep the existing `aro` target and Xcode project as the sole iOS host, retain the existing location functionality, and expose Apple Watch device functionality through an embedded `ARO Watch App` target and separate iOS feature within the host.

**Reason:** aro needs both established Traceon location history and Apple Watch battery behavior without creating a third project or replacing the source-of-truth host.

**Implications:** The host depends on and embeds the watch target. Shared WatchConnectivity payload code is compiled into both targets. Location, track storage/cloud sync, device UI/connectivity, and watch source remain logically separate; CloudKit must not be driven by Watch battery code.

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

**Implications:** aro is a new system app identity rather than an in-place Traceon upgrade. Existing Traceon/Companio containers, UserDefaults, permissions, and SQLite history are not automatically visible to aro; users should export/import data if they need to move history. The stable Watch App Group remains a deliberate compatibility choice for the watch snapshot store, while the iOS host does not gain that group entitlement. The iOS host additionally owns the separate CloudKit container `iCloud.com.xunbo.aro` for opt-in track sync.

## Separate location and device lifecycles

**Decision:** WatchConnectivity activation is passive, and iPhone live battery requests are limited to explicit Devices UI use or the App Intent. Ordinary iPhone launch and foreground activation may activate the WatchConnectivity session to receive queued application context, but a Core Location-triggered cold launch skips WatchConnectivity startup. Device connectivity is not driven by `LocationService`, does not poll on iPhone, and does not add periodic iPhone background work.

**Reason:** Opportunistic Watch battery snapshots need to be ingested without requiring the Devices tab to have been opened, while adding watch battery functionality must not meaningfully increase background-location energy cost or turn a location relaunch into device communication work.

**Implications:** Session activation and connectivity callbacks may accept opportunistic application-context state but must not send live requests. The Devices tab and App Intent own explicit live requests. The watch performs its own system-scheduled background sampling on watchOS. CloudKit follows the same cold-launch isolation principle: a launch identified as Core Location-triggered skips cloud-engine startup.

## Latest timestamped watch snapshot

**Decision:** Keep Apple Watch as the battery source, application context for opportunistic latest-state synchronization, reachable messages for explicit live request/reply, and an iPhone `UserDefaults` cache where newer timestamps win.

**Reason:** Device UI and Shortcuts need a useful last known value when the watch is temporarily unreachable without implying that cached state is live.

**Implications:** The UI presents the synchronization timestamp and explicitly labels unreachable data as cached. Payload key/type changes remain a coordinated cross-target compatibility change.

## Watch-owned snapshot and WidgetKit complication

**Decision:** Keep `WatchBatteryService` as the only component that reads `WKInterfaceDevice.current().batteryLevel`. Persist its newest valid `BatterySnapshot` in the Watch App Group `group.com.xunbo.traceon.watch`, have the WidgetKit complication display that shared snapshot, and use watchOS SwiftUI `backgroundTask(.appRefresh(...))` with `WKApplication.scheduleBackgroundRefresh` to request autonomous sampling. Schedule the next task before sampling and await the battery read before the background task returns.

**Reason:** The complication should improve watch-face visibility and provide legitimate watchOS background budget without creating a second battery-monitoring architecture, cloud path, or iPhone polling path. The previous legacy extension-delegate scheduling path did not reliably execute in the modern single-target SwiftUI Watch app.

**Implications:** Battery samples continue to use application context and explicit reachable replies. Autonomous watch refreshes do not send unsolicited `sendMessage` calls that could wake the iPhone; only an explicit iPhone request receives a live reply. The watch app persists every newer timestamp but reloads the complication timeline only when displayed battery/status values meaningfully change. The original WidgetKit kind string stays stable so an installed complication survives the aro display-name rename. The preferred app-refresh interval is 15 minutes, matching the useful budget of an app with an active complication, but watchOS may defer or throttle tasks and no fixed refresh interval is guaranteed.

## Freshness and retryable WatchConnectivity activation

**Decision:** After activation, ingest `WCSession.receivedApplicationContext` through the existing newest-timestamp-wins `BatteryStore` path before checking reachability or falling back to cache. Track activation-in-progress separately so an explicit call retries `.notActivated` sessions after an activation error, while avoiding duplicate activation calls and continuation resumes. Also activate the session passively on ordinary iPhone launch and foreground activation so a background-produced Watch snapshot is not unnecessarily left unread until the Devices UI is opened.

**Reason:** A newer opportunistic Watch sample can already be available when the app starts, a Shortcut runs, or a Devices refresh begins, and failed activation must not permanently disable later explicit refreshes.

**Implications:** Reachable sessions still receive an explicit live request; unreachable sessions return the newest cache available after context ingestion. Passive activation never sends a live message and remains excluded from Core Location-triggered cold launches.
