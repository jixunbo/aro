# Architectural decisions

## Semantic versioning for every delivered change

**Decision:** Every user-visible change or bug fix includes an appropriate marketing-version bump before delivery. Use a patch increment for fixes, a minor increment for backward-compatible features, and a major increment for breaking changes. Keep every target and Local/Cloud build configuration on the same marketing version.

**Reason:** Installed iPhone, Watch, and Widget builds must be distinguishable during testing and distribution, especially when validating fixes that require reinstalling the Watch App.

**Implications:** A code or behavior change is not considered delivery-ready until the version has been reviewed and updated. Documentation-only edits may retain the current version when they do not alter the shipped product. The Watch energy and complication refresh fixes advanced the project from `1.3.1` to `1.3.2`; adding the track complication advanced the backward-compatible feature version to `1.4.0`; the background route-publication fix advanced the patch version to `1.4.1`; the battery sampling/cache race fix advanced it to `1.4.2`; the map point-marker improvement advanced it to `1.4.3`; the Eco/Balanced route-quality fix advances it to `1.4.4`. The Watch App displays the bundle-derived marketing and build versions on its main screen so a tester can verify the installed build without relying on Xcode's build-number-only device list.

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

**Decision:** Use significant-location-change and visit monitoring as low-power wake signals rather than route geometry. Eco mode keeps standard location updates off between wake events; each wake starts an at-most-eight-second `kCLLocationAccuracyNearestTenMeters` burst, stores only the best fresh fix that is no worse than 150 m, and stops early when a fix reaches 65 m or better. Balanced uses the same high-quality requested accuracy continuously but with a 75 m distance filter and a 100 m acceptance ceiling. Balanced and Precise allow Core Location to automatically pause the standard service when the device appears stationary; when a pause occurs, motion updates stop, and a later significant-location event or visit departure explicitly restarts the standard location service.

**Reason:** A route should be built from comparatively trustworthy GPS fixes, not from coarse significant-change or visit coordinates. The previous strategy could accept 350 m Balanced fixes and 1.5 km Eco/visit fixes, so a larger number of points could still produce visibly worse geometry and distance than a competitor using fewer high-quality fixes. Spending a few seconds on a good fix after a low-power wake is preferable to permanently storing a coarse wake coordinate.

**Implications:** Always authorization and the location background mode are required for the strongest background behavior. Eco remains the lowest-power mode because standard GPS is normally off, but its point cadence is system-controlled and a burst that cannot obtain a fix inside the 150 m ceiling is intentionally dropped. Balanced now asks for substantially better single-fix quality than before and therefore may use more energy than the old 100 m requested-accuracy configuration even though its 75 m distance filter limits stored-point cadence. Significant-change and visit event coordinates are not inserted into `track_points`; they only wake Eco or restart paused continuous modes. Precise remains 25 m / nearest-ten-metre detail, Workout remains continuously high accuracy without automatic pausing. Route density, pause/resume behavior, Eco burst success rate, and energy use must be verified on real hardware.

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

**Implications:** Session activation and connectivity callbacks may accept opportunistic application-context state but must not send live battery requests. The Devices tab and App Intent own explicit live requests. The watch performs its own system-scheduled background sampling on watchOS. CloudKit follows the same cold-launch isolation principle: a launch identified as Core Location-triggered skips cloud-engine startup. Track-complication publication is allowed only through the already-existing WatchConnectivity session and never activates that session from a location-only cold launch.

## Latest timestamped watch snapshot

**Decision:** Keep Apple Watch as the battery source, application context for opportunistic latest-state synchronization, reachable messages for explicit live request/reply, and an iPhone `UserDefaults` cache where newer timestamps win.

**Reason:** Device UI and Shortcuts need a useful last known value when the watch is temporarily unreachable without implying that cached state is live.

**Implications:** The UI presents the synchronization timestamp and explicitly labels unreachable data as cached. Payload key/type changes remain a coordinated cross-target compatibility change.

## Watch-owned snapshot and WidgetKit complication

**Decision:** Persist the newest valid `BatterySnapshot` in the Watch App Group `group.com.xunbo.traceon.watch`. `WatchBatteryService` samples for the Watch App UI and WatchConnectivity, while the WidgetKit timeline provider takes one local `WKInterfaceDevice` battery sample whenever WidgetKit grants it a timeline refresh and writes that sample to the same store. Continue using the single-target watch app's `WKApplicationDelegate.handle(_:)` with `WKApplication.scheduleBackgroundRefresh` for opportunistic Watch App background sampling. Schedule the next app task before sampling, await the battery read, and explicitly complete every delivered WatchKit background task.

**Reason:** The complication must remain useful when current watchOS releases decline to deliver requested Watch App background refreshes. WidgetKit's separately budgeted timeline execution is the reliable opportunity to sample the same local device for complication display. The fallback remains local, system-triggered, and short-lived, without a timer, cloud path, iPhone polling path, or fabricated value.

**Implications:** Battery monitoring is enabled only during a one-shot read and disabled immediately afterward in both the Watch App and Widget Extension. Watch App foreground sampling runs every five minutes only while `scenePhase` is active, persists newer timestamps locally, and suppresses unchanged WatchConnectivity application-context writes. Autonomous watch refreshes and WidgetKit timeline refreshes do not send unsolicited `sendMessage` calls that could wake the iPhone; only an explicit iPhone request receives a live reply. The Widget extension can advance the shared Watch snapshot without advancing the iPhone cache until WatchConnectivity next publishes from the Watch App. The original WidgetKit kind string stays stable so an installed complication survives the aro display-name rename. The one-hour preferred app refresh and the complication's 30-minute requested timeline refresh remain system-controlled and may be deferred or throttled. The Watch App disables Always On display because its battery dashboard has no continuous-display use case. The circular battery presentation uses an Ultra-style gauge while the existing non-circular families remain available.

## iPhone-owned track snapshot for the Watch face

**Decision:** Add a second WidgetKit complication kind, `AROTrackWidget`, for an accessory-circular “aro 轨迹” complication. The iPhone derives a compact display snapshot from today's local `TrackPoint` history: cumulative distance plus normalized route geometry, keeping at most the latest four display segments and downsampling each to at most eight points. The watch does not start a second location recorder. The iPhone sends this snapshot with `WCSession.updateApplicationContext`; the watch stores the newest snapshot in the existing Watch App Group and reloads only the track complication when its visible data changes.

**Reason:** The selected design needs the shape of the user's actual iPhone-recorded route on the watch face, but duplicating Core Location recording on Apple Watch would increase energy use and create a second source of truth. A compact application-context snapshot reuses the existing companion channel and keeps SQLite on iPhone as the authoritative track store.

**Implications:** Foreground iPhone activation can publish immediately. While the same WatchConnectivity session remains activated in the background, route updates are opportunistically throttled to five minutes or 250 metres of additional distance, with a first-route/new-day update allowed immediately. `publishTrackComplication` never activates WatchConnectivity by itself, so a Core Location-only cold launch still performs no incidental watch startup. Delivery is therefore eventual rather than point-by-point real time and may be coalesced by watchOS. The snapshot is scoped to the iPhone's current local day; the Watch store hides an old-day route and the Widget timeline schedules a day-boundary refresh. This path is independent of CloudKit and works in Local builds.

## Freshness and retryable WatchConnectivity activation

**Decision:** After activation, ingest `WCSession.receivedApplicationContext` through the existing newest-timestamp-wins `BatteryStore` path before checking reachability or falling back to cache. Track activation-in-progress separately so an explicit call retries `.notActivated` sessions after an activation error, while avoiding duplicate activation calls and continuation resumes. Also activate the session passively on ordinary iPhone launch and foreground activation so a background-produced Watch snapshot is not unnecessarily left unread until the Devices UI is opened.

**Reason:** A newer opportunistic Watch sample can already be available when the app starts, a Shortcut runs, or a Devices refresh begins, and failed activation must not permanently disable later explicit refreshes.

**Implications:** Reachable sessions still receive an explicit live request; unreachable sessions return the newest cache available after context ingestion. Passive activation never sends a live battery message and remains excluded from Core Location-triggered cold launches.
