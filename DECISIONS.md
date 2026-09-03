# Architectural decisions

## Semantic versioning for every delivered change

**Decision:** Every user-visible change or bug fix includes an appropriate marketing-version bump before delivery. Use a patch increment for fixes, a minor increment for backward-compatible features, and a major increment for breaking changes. Keep every target and Local/Cloud build configuration on the same marketing version.

**Reason:** Installed iPhone, Watch, and Widget builds must be distinguishable during testing and distribution, especially when validating fixes that require reinstalling the Watch App.

**Implications:** A code or behavior change is not considered delivery-ready until the version has been reviewed and updated. Documentation-only edits may retain the current version when they do not alter the shipped product. The Watch energy and complication refresh fixes advanced the project from `1.3.1` to `1.3.2`; adding the track complication advanced the backward-compatible feature version to `1.4.0`; the background route-publication fix advanced the patch version to `1.4.1`; the battery sampling/cache race fix advanced it to `1.4.2`; the map point-marker improvement advanced it to `1.4.3`; the Eco/Balanced redesign advanced it to `1.5.0`. Dropping iOS 17–25 and replacing the legacy recorder with the iOS 26 architecture advanced all shipped targets to `2.0.0`. Watch complication fixes advanced the unreleased line to `2.0.1`; robust idle detection and the distance-filtered Eco redesign advance it to `2.0.2`.

## iOS 26+ platform baseline

**Decision:** aro 2.0 supports iOS/iPadOS 26.0 and later. Do not maintain iOS 17–25 compatibility code or a legacy Core Location fallback. Keep watchOS 10.0+ unless Watch-specific requirements independently change.

**Reason:** The product is self-directed and can target current iOS. Removing old compatibility constraints allows the location recorder to use current Core Location lifecycle semantics directly rather than carrying compatibility branches.

**Implications:** The iOS app/test deployment target is 26.0 in Local and Cloud configurations. Code may use the iOS 26 SDK without availability branches for older iOS. Future iOS 27 support is through the normal minimum-target model; there is no maximum OS gate. This breaking support change is part of aro 2.0.0.

## iOS 26 Core Location tracking architecture

This decision supersedes “iOS 26 native Live Updates tracking” as an all-modes rule while retaining Live Updates for Balanced/Precise/Workout.

**Decision:** Keep an explicit `CLServiceSession(authorization: .always)` tied to automatic recording and enable `NSLocationRequireExplicitServiceSession`. Balanced/Precise/Workout use `CLLocationUpdate.liveUpdates`; Eco intentionally uses the Standard location service through the existing single `CLLocationManager`, because only Standard location exposes `distanceFilter` and therefore lets Core Location reduce update generation at the hardware/service layer. Do not add significant-location-change, Visits, Core Motion wake logic, Eco bursts, or a second recorder as fallback. `CLMonitor` is the first-class idle/wake state for Eco and Balanced.

**Reason:** Real-device 2.0 diagnostics showed `.default` Live Updates could produce hundreds of high-quality fixes while the phone was physically stationary, and exported data from the target footprint app's power-saving mode showed a very strong roughly-100-metre point-spacing signature while retaining high-quality (~10 m) fixes. Apple documents `distanceFilter` as the minimum horizontal movement before a Standard-location update event is generated and recommends using the largest useful value to reduce power. A dedicated Eco Standard-location path therefore maps more closely to the target behavior than receiving high-cadence Live Updates and discarding most of them later.

**Implications:** `LocationService` owns one `CLLocationManager`; in Eco it is both the authorization manager and the Standard recorder, while in all other modes it remains authorization-only. Eco configures `kCLLocationAccuracyNearestTenMeters`, `distanceFilter ≈ 100 m`, background updates, and automatic pause. Balanced uses `.default`, Precise `.otherNavigation`, and Workout `.fitness`. Automatic recording still requires Always authorization and a persisted `tracking.startedAt` session boundary.

## Suspendable low-power modes vs timely Precise/Workout background delivery

**Decision:** Eco and Balanced intentionally do not retain `CLBackgroundActivitySession`. Eco uses distance-filtered Standard updates; Balanced uses `.default` Live Updates. Precise uses `.otherNavigation` and Workout uses `.fitness`; those two modes retain `CLBackgroundActivitySession` for timely background execution.

**Reason:** aro's all-day modes prioritize battery life over point-by-point real-time UI delivery. `CLBackgroundActivitySession` is reserved for modes where timely delivery justifies higher energy cost. Eco additionally reduces the frequency of Standard-location generation itself with `distanceFilter`.

**Implications:** Balanced may receive queued/coalesced Live Updates while moving, and valid queued fixes must not be discarded solely because they are several minutes old. Eco receives Standard-location callbacks primarily after about 100 m of movement, though Core Location may also deliver startup or improved-accuracy fixes. Precise/Workout do not use the idle transition and have intentionally different energy behavior.

## Persistent idle CLMonitor for Eco/Balanced

**Decision:** Eco and Balanced both enter one persistent `CLMonitor.CircularGeographicCondition` before stopping their moving recorder, but they establish stationary state differently. Eco uses the Standard-location automatic-pause callback as its primary stationary confirmation and arms a roughly 100 m monitor around the latest reliable fix. Balanced uses a robust spatial stability detector over fresh Live Updates, then arms a roughly 60 m monitor. Leaving the monitored circle is the normal wake path: remove the condition, reset transient geometry/idle state, and resume that mode's own primary recorder. Monitor setup failure never stops a working moving recorder; if an armed monitor becomes unavailable/unmonitored, aro resumes the primary recorder and surfaces the error.

**Reason:** The first iOS 26 Live Updates build received 537 update events and 526 locations while the phone was physically still for about half an hour, with only one location worth saving. Database filtering cannot recover the energy already spent generating those fixes. The target footprint app's observed power-saving behavior also strongly suggests a “moving high-quality distance-triggered GPS / stationary no continuous points” model.

**Implications:** Eco's monitored radius is currently about 100 m to stay close to the observed competitor spacing/wake behavior. Balanced still uses about a five-minute stability window and a 60 m monitor. `tracking.idleMonitorActive` records only that aro expects a persistent monitor to exist; after relaunch the monitor itself remains Core Location's source of truth. If its identifier is absent, aro clears the flag and starts the selected mode's primary recorder rather than inventing another fallback.

## Robust Balanced idle detection

**Decision:** Balanced must not require every single location in the idle window to be within the stability radius. Use a median geographic center, require at least 90% of a full five-minute window (minimum 12 samples) inside roughly 30 m, require a fresh newest fix, and require the robust early/late cluster centers to drift no more than roughly 20 m.

**Reason:** Real-device 2.0.1 testing produced long periods with hundreds of locations, zero saved points, and no stationary transition. The previous `allSatisfy` rule let one 30–40 m GPS outlier reset the entire idle proof even when the route sampler already classified essentially all updates as stationary noise.

**Implications:** A small number of GPS spikes no longer keeps Balanced awake forever. The center-drift check prevents a slowly translating but locally clustered path from being misclassified as stationary. UI state does not equate `CLLocationUpdate.stationary == false` with actual movement; it remains `监测中` until meaningful displacement is observed.

## Adaptive route persistence independent of hardware cadence

**Decision:** For Live Updates modes, treat Core Location generation and SQLite persistence as separate concerns. Persist valid locations based on an accuracy-aware combination of normal movement distance, elapsed time with real movement, or meaningful direction change. Track short-term geometric bearings in memory so pedestrian turns can be retained even when `CLLocation.course` is unavailable. Eco is the intentional exception at the generation layer: its Standard service uses about a 100 m `distanceFilter`, while its software persistence threshold stays much lower so useful extra system-delivered fixes are not discarded.

**Reason:** Fewer database points can still represent a route accurately if turns are preserved, while fixed sparse storage thresholds can cut corners badly. Conversely, once Live Updates has already generated a good fix, aggressively discarding it provides negligible hardware-energy benefit. Eco needs a different trade-off: the target behavior specifically shows distance-driven system callbacks, and `distanceFilter` is the public API that moves that saving upstream.

**Implications:** Balanced accepts horizontal accuracy up to 80 m, normally saves at roughly 35 m movement, may save after one minute with at least 12 m real movement, and can save a meaningful turn after roughly 12 m with a 35-degree direction change. Eco requests nearest-ten-metre Standard location, accepts up to 50 m horizontal accuracy, uses a 100 m system distance filter, but keeps a 25 m software movement threshold to retain legitimate extra fixes. These values remain subject to same-route real-device validation.

## Preserve queued current-session locations

**Decision:** Do not reject a delivered location solely because its timestamp is more than a few minutes behind wall-clock time. Accept queued fixes if they belong to the persisted current tracking session, are time-ordered relative to the persisted route, satisfy accuracy/coordinate checks, are not implausibly future-dated, and do not imply impossible motion.

**Reason:** iOS may suspend aro and queue location updates for later delivery. The old 180-second freshness test could discard exactly the background route points the low-power architecture depends on.

**Implications:** `tracking.startedAt` is persisted while automatic recording is enabled. Disabling/re-enabling tracking establishes a new boundary. Tests cover queued-current-session acceptance and pre-session/future/inaccurate rejection.

## Location relaunch isolation without deprecated launch-option detection

**Decision:** On every process launch, `AppDelegate` immediately restores only `LocationService` if tracking is enabled. Do not use the deprecated iOS 26 `UIApplication.LaunchOptionsKey.location` discriminator. WatchConnectivity and CloudKit are not initialized from generic launch; ordinary foreground activation owns WatchConnectivity/normal cloud startup, and CloudKit remote notifications have their own delegate callback.

**Reason:** Core Location can relaunch an app in the background and requires outstanding sessions/sequences or monitors to be recreated promptly. Without the old launch discriminator, the safe invariant is to make generic launch location-only rather than trying to guess why the process started.

**Implications:** A Core Location relaunch cannot accidentally send a Watch request or start cloud network work. If `tracking.idleMonitorActive` is set, launch restores the named CLMonitor and awaits its events rather than starting the moving recorder immediately; if the persisted monitor identifier no longer exists, the selected mode's recorder resumes. Normal foreground behavior remains available from `RootView`.

## Adaptive native background location (superseded)

This 1.5 decision is retained for history and superseded by the iOS 26 Core Location decisions above.

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

**Implications:** Battery monitoring is enabled only for a one-shot read and disabled immediately afterward. Foreground sampling is every five minutes only while active. Background/task/timeline schedules are system-controlled and not guaranteed. The original WidgetKit battery kind remains stable. The Watch App disables Always On display. Public WatchKit exposes `WKInterfaceDevice.batteryLevel` but does not guarantee one-percent granularity; aro does not use private APIs to infer hidden values. Circular complication color is green above 50%, orange from 21–50%, red at 20% or below, with charging/full always green.

## iPhone-owned track snapshot for the Watch face

**Decision:** Keep `AROTrackWidget` as an accessory-circular track complication. iPhone derives a compact current-day route/distance snapshot and keeps latest state in `WCSession.updateApplicationContext`. When the Watch reports the complication active and the system has complication-transfer budget, iPhone also sends route changes using `transferCurrentComplicationUserInfo`. Watch accepts both delivery paths, persists the newest snapshot in the App Group, and reloads the WidgetKit timeline. Watch does not start a second location recorder.

**Reason:** Application context is correct for eventual latest-state convergence but does not reliably wake the Watch extension specifically for a complication. The dedicated complication transfer API is intended for this case and improves freshness without turning location recording into a WatchConnectivity polling loop.

**Implications:** Foreground publication can be immediate. Background publication remains opportunistic and throttled. A location-only process relaunch never activates WatchConnectivity. Complication transfer is system-budgeted and can still be delayed/coalesced.

## Freshness and retryable WatchConnectivity activation

**Decision:** After activation, ingest `WCSession.receivedApplicationContext` through the newest-timestamp-wins `BatteryStore` before checking reachability. Track activation-in-progress so explicit calls can retry after activation errors without duplicate continuation resumes. Activate passively on normal foreground use.

**Reason:** Newer opportunistic Watch data can already exist when UI/Shortcut access begins, and an activation error must not permanently disable later explicit refreshes.

**Implications:** Reachable sessions still receive an explicit live request; unreachable sessions return the newest available cache. Passive activation never sends a live battery message and is not part of generic location restoration.
