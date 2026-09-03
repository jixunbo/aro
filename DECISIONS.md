# Architectural decisions

## Semantic versioning for every delivered change

**Decision:** Every user-visible change or bug fix includes an appropriate marketing-version bump before delivery. Use a patch increment for fixes, a minor increment for backward-compatible features, and a major increment for breaking changes. Keep every target and Local/Cloud build configuration on the same marketing version.

**Reason:** Installed iPhone, Watch, and Widget builds must be distinguishable during testing and distribution, especially when validating fixes that require reinstalling the Watch App.

**Implications:** A code or behavior change is not considered delivery-ready until the version has been reviewed and updated. Documentation-only edits may retain the current version when they do not alter the shipped product. The Watch energy and complication refresh fixes advanced the project from `1.3.1` to `1.3.2`; adding the track complication advanced the backward-compatible feature version to `1.4.0`; the background route-publication fix advanced the patch version to `1.4.1`; the battery sampling/cache race fix advanced it to `1.4.2`; the map point-marker improvement advanced it to `1.4.3`; the Eco/Balanced redesign advanced it to `1.5.0`. Dropping iOS 17–25 and replacing the legacy recorder with the iOS 26 Live Updates architecture is a breaking platform/runtime change and advances all shipped targets to `2.0.0`.

## iOS 26+ platform baseline

**Decision:** aro 2.0 supports iOS/iPadOS 26.0 and later. Do not maintain iOS 17–25 compatibility code or a legacy Core Location fallback. Keep watchOS 10.0+ unless Watch-specific requirements independently change.

**Reason:** The product is self-directed and can target current iOS. Removing old compatibility constraints allows the location recorder to use modern Core Location lifecycle semantics directly rather than carrying two competing background-location architectures.

**Implications:** The iOS app/test deployment target is 26.0 in Local and Cloud configurations. Code may use the iOS 26 SDK without availability branches for older iOS. Future iOS 27 support is through the normal minimum-target model; there is no maximum OS gate. This breaking support change is part of aro 2.0.0.

## iOS 26 native Live Updates tracking

This decision supersedes “Adaptive native background location” below.

**Decision:** Use `CLLocationUpdate.liveUpdates` as the only route-producing location API, with an explicit `CLServiceSession(authorization: .always)` tied to the user's automatic-recording feature. Enable `NSLocationRequireExplicitServiceSession`. Keep one `CLLocationManager` only for authorization/full-accuracy requests, not as a recorder. Do not reintroduce significant-location-change, visit, Core Motion wake logic, Eco GPS bursts, or a second standard-location manager as fallback. For Eco/Balanced, a persistent `CLMonitor` geographic condition is a first-class idle state rather than a fallback recorder.

**Reason:** aro 1.5 improved single-fix quality but real-device comparison still showed severe undersampling. Early aro 2.0 real-device diagnostics then showed that `.default` Live Updates could continue delivering hundreds of high-quality fixes during more than 30 minutes of physical inactivity without producing a `stationary` event. Relying exclusively on `CLLocationUpdate.isStationary` therefore did not meet the all-day energy goal. Apple explicitly recommends stopping location updates and using `CLMonitor` for significant location changes when the device is stationary and movement is not expected soon.

**Implications:** Automatic recording requires Always authorization. The tracking feature persists a `tracking.startedAt` boundary so queued Live Updates from the active session remain eligible after suspension/relaunch while arbitrary pre-session cached locations are rejected. Core Location diagnostics remain visible, but aro also performs conservative spatial idle detection for Eco/Balanced and can transition to `CLMonitor` even if the system never sets `stationary`.

## Suspendable Balanced/Eco vs timely Precise/Workout background delivery

**Decision:** Eco and Balanced use `.default` Live Updates and intentionally do not retain `CLBackgroundActivitySession`. Precise uses `.otherNavigation` and Workout uses `.fitness`; those two modes retain `CLBackgroundActivitySession` for timely background execution.

**Reason:** aro's normal all-day footprint mode prioritizes battery life over point-by-point real-time UI delivery. `CLBackgroundActivitySession` keeps an app effectively in use in the background and is therefore reserved for modes where timely delivery justifies the higher energy cost.

**Implications:** Balanced/Eco may receive queued/coalesced Live Updates while moving. Valid queued fixes must not be thrown away because they are several minutes old. When stationary is established, Eco/Balanced stop the Live Updates sequence entirely and use the idle monitor until movement crosses the monitored boundary. Precise/Workout do not use this idle transition and have intentionally different energy behavior.

## Persistent idle CLMonitor for Eco/Balanced

**Decision:** After a fresh sequence of sufficiently accurate fixes remains spatially stable for a mode-specific interval, Eco/Balanced register one `CLMonitor.CircularGeographicCondition`, assume the initial condition is satisfied, persist that the idle monitor is armed, and only then cancel Live Updates. Leaving the monitored circle is the normal wake path: remove the condition, reset transient geometry/idle state, and resume Live Updates. A system-provided stationary fix may enter the same path immediately. Monitor setup failure never cancels a working Live Updates stream; if an already-armed monitor becomes unsupported/unmonitored, aro resumes Live Updates and surfaces the error.

**Reason:** The first iOS 26 real-device build received 537 update events and 526 locations while the phone had been physically still for about half an hour, while only one location was worth saving. Database filtering cannot save the energy already spent generating those fixes. A deliberate Live Updates → CLMonitor transition moves the power optimization to the hardware-generation side without reintroducing old significant-change/visit/Core Motion architectures.

**Implications:** Balanced currently requires about five minutes of fresh stable fixes within roughly 30 m, then monitors a 60 m circle. Eco uses a shorter three-minute idle window and a larger 120 m monitored circle. Only good recent fixes participate in idle detection, and starting/restarting Live Updates resets the idle window so delayed queued fixes cannot immediately re-arm idle monitoring. `tracking.idleMonitorActive` records only that aro expects a persistent monitor to exist; after relaunch the monitor itself remains Core Location's source of truth. If its identifier is absent, aro clears the flag and starts Live Updates instead of inventing a legacy fallback.

## Adaptive route persistence independent of hardware cadence

**Decision:** Treat Core Location generation and SQLite persistence as separate concerns. Do not use a fixed `distanceFilter` to define route quality. Persist a valid Live Update based on an accuracy-aware combination of normal movement distance, elapsed time with real movement, or meaningful direction change. Track short-term geometric bearings in memory so pedestrian turns can be retained even when `CLLocation.course` is unavailable.

**Reason:** Fewer database points can still represent a route accurately if turns are preserved, while fixed sparse thresholds can cut corners badly. Conversely, saving every Live Update wastes storage/refresh work and can accumulate GPS jitter. Real-device diagnostics showed that once iOS has already generated a good moving fix, aggressively discarding it provides negligible hardware-energy benefit; energy savings should come primarily from the idle transition.

**Implications:** Balanced accepts horizontal accuracy up to 80 m, normally saves at roughly 35 m movement, may save after one minute with at least 12 m real movement, and can save a meaningful turn after roughly 12 m with a 35-degree direction change. Accuracy contributes a noise floor so poor fixes do not fabricate short turns. Eco/Precise/Workout use their own thresholds. These values are tuning targets and remain subject to same-route real-device validation.

## Preserve queued current-session locations

**Decision:** Do not reject a Live Update solely because its timestamp is more than a few minutes behind wall-clock time. Accept queued fixes if they belong to the persisted current tracking session, are time-ordered relative to the persisted route, satisfy accuracy/coordinate checks, are not implausibly future-dated, and do not imply impossible motion.

**Reason:** iOS may suspend aro and queue location updates for later delivery. The old 180-second freshness test could discard exactly the background route points the low-power architecture depends on.

**Implications:** `tracking.startedAt` is persisted while automatic recording is enabled. Disabling/re-enabling tracking establishes a new boundary. Tests cover queued-current-session acceptance and pre-session/future/inaccurate rejection.

## Location relaunch isolation without deprecated launch-option detection

**Decision:** On every process launch, `AppDelegate` immediately restores only `LocationService` if tracking is enabled. Do not use the deprecated iOS 26 `UIApplication.LaunchOptionsKey.location` discriminator. WatchConnectivity and CloudKit are not initialized from generic launch; ordinary foreground activation owns WatchConnectivity/normal cloud startup, and CloudKit remote notifications have their own delegate callback.

**Reason:** Core Location can relaunch an app in the background and requires outstanding modern sessions/sequences or monitors to be recreated promptly. Without the old launch discriminator, the safe invariant is to make generic launch location-only rather than trying to guess why the process started.

**Implications:** A Core Location relaunch cannot accidentally send a Watch request or start cloud network work. If `tracking.idleMonitorActive` is set, launch restores the named CLMonitor and awaits its events rather than starting Live Updates immediately; if the persisted monitor identifier no longer exists, Live Updates resumes. Normal foreground behavior remains available from `RootView`.

## Adaptive native background location (superseded)

This 1.5 decision is retained for history and superseded by “iOS 26 native Live Updates tracking”.

**Decision:** Use significant-location-change and visit monitoring as low-power wake signals rather than route geometry. Eco keeps standard location updates off between wake events; Balanced uses continuous high-quality standard updates with automatic stationary pausing and low-power wake restart.

**Reason:** This removed coarse wake coordinates from route geometry and improved point quality compared with pre-1.5 behavior.

**Why superseded:** Real-device 1.5 comparison still showed too few useful route points and long corner-cutting segments. The restart dependency after automatic pause remained a structural weakness, and the app no longer needs to support pre-iOS-26 APIs.

## Local-only persistence (superseded)

This decision was superseded by “Opt-in private CloudKit sync” below.

**Decision:** Store tracks on-device in SQLite; do not require an account, backend, analytics service, or cloud synchronization.

**Reason:** The product describes itself as privacy-first and intended for long-term local accumulation without a server.

**Implications:** Export was originally the only backup/transfer path. External data flow must remain an explicit privacy/product decision rather than an incidental implementation detail.

## Opt-in private CloudKit sync

**Decision:** Keep SQLite as the local source of truth and add explicit opt-in synchronization of raw `TrackPoint` records through `CKSyncEngine` and the user's private CloudKit database in container `iCloud.com.xunbo.aro`. Do not upload `daily_summary`, Watch battery data, analytics, or unrelated app state.

**Reason:** The app needs optional multi-device track continuity without introducing an aro account or self-hosted backend, while preserving local-first recording and privacy boundaries.

**Implications:** Every stored point has a stable `sync_id`; local writes are committed to SQLite first and tracked as unsynced until CloudKit acknowledges them. Remote records are merged into SQLite and summaries are derived locally. Cloud remote-notification handling is independent of the generic Core Location relaunch path. CloudKit/private-database behavior requires signed real-device validation.

Disabling sync stops future synchronization but does not delete existing CloudKit data. “Delete all tracks” must delete the private `AROTracks` record zone before clearing local SQLite whenever a cloud footprint may exist. A fetched deletion of that zone is treated as a global delete and clears local tracks on the receiving device. Account changes pause sync and preserve local data rather than silently assigning it to a different Apple account.

## CloudKit optional build capability

**Decision:** CloudKit capability must not be required for the local/self-signed build. Keep `Debug`/`Release` as Local configurations with an empty iOS entitlements file and compile out the CloudKit service; provide `CloudDebug`/`CloudRelease` configurations that retain CloudKit/APNs entitlements and `ARO_CLOUDKIT_ENABLED`.

**Reason:** Apple Personal Teams cannot provision iCloud/CloudKit or Push Notifications, while local SQLite, Core Location, Watch, and Widget features must remain installable and usable with free development signing.

**Implications:** Local builds have no CloudKit runtime. Cloud builds require `iCloud.com.xunbo.aro`, Push Notifications, Remote notifications, and a matching paid-team profile. CI compiles both `Debug` and `CloudDebug` unsigned so Cloud-only source remains compile-checked.

## Raw points plus daily summaries

**Decision:** Keep raw track points and a separate `daily_summary` table, with uniqueness enforced on timestamp and coordinates.

**Reason:** History and lifetime statistics read the summary table instead of recalculating the complete track history. Deduplication allows recording, imports, and remote CloudKit changes to coexist.

**Implications:** Every data mutation must preserve summary consistency. Batch imports and remote changes rebuild summaries when needed in timestamp order, and schema evolution belongs in `TrackDatabase.openAndMigrate()`. Cloud sync identity is additional metadata and does not replace the timestamp/latitude/longitude natural deduplication key.

## Actor-isolated UI state and serialized database access

**Decision:** Keep observable location/repository state on the main actor and serialize all SQLite work through `TrackDatabase`'s private queue.

**Reason:** UI-visible state must be published on the main thread, while the shared SQLite connection must not receive concurrent unsynchronized access.

**Implications:** Expensive reads are dispatched away from the main actor, then published back on it. New database APIs must continue using the database queue.

## Platform-native dependency set

**Decision:** Build with SwiftUI and Apple frameworks, using a UIKit `MKMapView` bridge and the system SQLite library; do not use third-party packages.

**Reason:** The app's requirements are covered by platform APIs and avoiding external packages reduces privacy, binary, compatibility, and maintenance surface.

**Implications:** Prefer existing Apple APIs and the current SQLite layer. Adding a package requires a concrete need plus explicit review.

## One surviving iOS host with an embedded watch companion

**Decision:** Keep the `aro` target and Xcode project as the sole iOS host and expose Apple Watch device functionality through an embedded `ARO Watch App` target and separate iOS feature within the host.

**Reason:** aro needs location history and Apple Watch battery behavior without creating another iOS host or source of truth.

**Implications:** The host depends on and embeds the watch target. Shared WatchConnectivity payload code is compiled into both targets. Location, track storage/cloud sync, device UI/connectivity, and watch source remain logically separate.

## Preserve the legacy application identity and data container (superseded)

This earlier decision was superseded by “Adopt aro bundle identifiers”.

**Decision:** Change the user-visible application name to aro while retaining the earlier Traceon identity/data container.

**Reason:** It originally attempted an in-place product rename.

**Implications:** Superseded; current Bundle IDs are defined below. The relative SQLite path and Watch App Group remain stable compatibility identifiers inside the current product.

## aro repository and source naming

**Decision:** Use `aro`/`aroWatch` for the repository-facing project, scheme, iOS source directory, and Watch source directory, while keeping persistent data identifiers that intentionally remain stable.

**Reason:** aro is the product name and “Everything Around You” is the intended identity.

**Implications:** Open `aro.xcodeproj` and build the shared `aro` scheme. The iOS module/test target are `aro`/`aroTests`; Watch sources live under `aroWatch`.

## Adopt aro bundle identifiers

**Decision:** Use `com.xunbo.aro` for the iOS host, `com.xunbo.aro.watchkitapp` for the embedded Watch App, `com.xunbo.aro.watchkitapp.widget` for the Widget Extension, and `com.xunbo.aro` as `WKCompanionAppBundleIdentifier`. Keep the existing Watch App Group and relative SQLite filename unchanged.

**Reason:** The product identity is aro and the user explicitly chose the aro Bundle ID namespace.

**Implications:** aro is a new system app identity rather than an in-place Traceon upgrade. Existing Traceon/Companio containers, UserDefaults, permissions, and SQLite history are not automatically visible; users export/import data if needed. The iOS host owns `iCloud.com.xunbo.aro` for opt-in sync.

## Separate location and device lifecycles

**Decision:** WatchConnectivity activation is passive, and iPhone live battery requests are limited to explicit Devices UI use or the App Intent. Generic process launch restores location only. Normal foreground activation may activate WatchConnectivity to ingest queued application context; `LocationService` never drives connectivity or polling.

**Reason:** Watch battery functionality must not meaningfully increase background-location energy cost or turn a location relaunch into device communication work.

**Implications:** Devices UI and App Intent own explicit live requests. Track-complication publication can use an already-active session but never activates one from location-only work. CloudKit follows the same isolation principle via foreground lifecycle and its own remote-notification entry point.

## Latest timestamped watch snapshot

**Decision:** Keep Apple Watch as the battery source, application context for opportunistic latest-state synchronization, reachable messages for explicit live request/reply, and an iPhone `UserDefaults` cache where newer timestamps win.

**Reason:** Device UI and Shortcuts need a useful last known value when the watch is temporarily unreachable without implying cached data is live.

**Implications:** The UI presents synchronization timestamp and labels unreachable data as cached. Payload changes remain coordinated across targets.

## Watch-owned snapshot and WidgetKit complication

**Decision:** Persist the newest valid `BatterySnapshot` in Watch App Group `group.com.xunbo.traceon.watch`. `WatchBatteryService` samples for Watch App UI and WatchConnectivity, while the WidgetKit timeline provider takes one local `WKInterfaceDevice` battery sample whenever WidgetKit grants a timeline refresh and writes it to the same store. Continue using `WKApplicationDelegate.handle(_:)` with `WKApplication.scheduleBackgroundRefresh` for opportunistic Watch App background sampling.

**Reason:** The complication must remain useful when watchOS declines to deliver requested Watch App background refreshes. WidgetKit provides a separately budgeted local execution opportunity without waking iPhone or network.

**Implications:** Battery monitoring is enabled only for a one-shot read and disabled immediately afterward. Foreground sampling is every five minutes only while active. Background/task/timeline schedules are system-controlled and not guaranteed. The original WidgetKit battery kind remains stable. The Watch App disables Always On display.

## iPhone-owned track snapshot for the Watch face

**Decision:** Keep `AROTrackWidget` as an accessory-circular track complication. iPhone derives a compact current-day route/distance snapshot and sends it by `WCSession.updateApplicationContext`; Watch persists it in the existing App Group. Watch does not start a second location recorder.

**Reason:** The selected design needs the user's actual iPhone route on the Watch face without duplicating GPS recording or creating a second source of truth.

**Implications:** Foreground publication can be immediate. While a WatchConnectivity session is already active, background publication is opportunistically throttled to five minutes or 250 metres. A location-only process relaunch never activates WatchConnectivity. Delivery is eventual and may be coalesced by watchOS.

## Freshness and retryable WatchConnectivity activation

**Decision:** After activation, ingest `WCSession.receivedApplicationContext` through the newest-timestamp-wins `BatteryStore` before checking reachability. Track activation-in-progress so explicit calls can retry after activation errors without duplicate continuation resumes. Activate passively on normal foreground use.

**Reason:** Newer opportunistic Watch data can already exist when UI/Shortcut access begins, and an activation error must not permanently disable later explicit refreshes.

**Implications:** Reachable sessions still receive an explicit live request; unreachable sessions return the newest available cache. Passive activation never sends a live battery message and is not part of generic location restoration.