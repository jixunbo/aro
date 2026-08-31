# aro repository instructions

## Before making changes

- Treat the current implementation as the source of truth. Inspect the affected code and its callers before writing new code.
- Read `PROJECT_CONTEXT.md` before substantial implementation work, then read the relevant entries in `DECISIONS.md`. Read `TODO.md` when planning work or reporting project status.
- Use `README.md` for setup and `TESTING.md` for real-device location, watch connectivity, data-upgrade, and energy validation.

## Working approach

- Prefer existing project code over new code.
- Prefer standard-library and Apple platform functionality over custom implementations.
- Prefer existing dependencies over adding new dependencies. This project currently has no third-party packages.
- Make the smallest change that fully solves the requested task.
- Avoid speculative abstractions, unnecessary wrappers, premature generalization, and unrelated refactoring.
- Prefer simplification or deletion when appropriate.
- Never sacrifice correctness, validation, security, error handling, or data integrity merely to reduce code.

## Build, test, analyze, and run

Run commands from the repository root. The checked-in shared scheme is `aro`.

```sh
# Simulator build
xcodebuild -project aro.xcodeproj -scheme aro -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO build

# Unit tests; substitute another installed simulator name if needed
xcodebuild -project aro.xcodeproj -scheme aro \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO test

# Xcode static analyzer
xcodebuild -project aro.xcodeproj -scheme aro -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO analyze

# Generic iOS/device compile; also compiles and embeds the watchOS target
xcodebuild -project aro.xcodeproj -scheme aro \
  -destination 'generic/platform=iOS' -derivedDataPath DerivedData-device \
  CODE_SIGNING_ALLOWED=NO build
```

There is no separate lint or formatter configuration; use compiler warnings and the analyzer. For interactive running, open `aro.xcodeproj`, select a signing team, and run on an iOS device. Simulator location is useful for basic behavior only. Background relaunch and energy behavior require the real-device checks in `TESTING.md`.

## Repository conventions and constraints

- Deployment is iOS/iPadOS 17.0+ and watchOS 10.0+, Swift 5; the iOS target supports iPhone and iPad, and Mac Catalyst is disabled. The repository setup instructions require Xcode 26+.
- Keep the implementation platform-native unless a task demonstrates a need otherwise: SwiftUI, UIKit/MapKit, Core Location, Core Motion, Foundation, and system SQLite (`-lsqlite3`).
- `LocationService` and `TrackRepository` are main-actor state owners. `TrackDatabase` serializes SQLite access on its private queue; do not bypass those concurrency boundaries.
- Keep raw points and `daily_summary` consistent across recording, import, deletion, and schema changes. Preserve timestamp/coordinate deduplication and validate distance calculations against implausible jumps.
- Preserve the privacy-first, local-only behavior unless a task explicitly changes product scope. Do not add analytics, accounts, network upload, or cloud synchronization incidentally.
- Background location behavior depends on `Info.plist`, staged authorization, and both significant-change/visit and standard location updates. Changes in this area must be tested on a real device and keep permission copy, background modes, and runtime behavior aligned.
- `BatterySnapshot.swift` is compiled into the iOS and watchOS targets and defines the WatchConnectivity contract. Preserve newest-timestamp-wins cache semantics and label cached data as non-live.
- Keep `PhoneConnectivity` passive during initialization and activation. A Core Location background relaunch must not send a live watch request; live requests belong only to explicit Devices UI use or the App Intent. Do not add iPhone polling or battery-only background tasks, and do not couple connectivity to `LocationService`.
- Preserve the watch target dependency, Embed Watch Content phase, `com.xunbo.aro.watchkitapp` identifier, and `WKCompanionAppBundleIdentifier = com.xunbo.aro` relationship. The target and project display names are ARO. The iOS host identifier is `com.xunbo.aro`; do not assume an existing Traceon/Companio installation upgrades in place.
- Keep `PrivacyInfo.xcprivacy` accurate when introducing dependencies or required-reason API usage.
- New source or resource files must also be added to the appropriate target in `aro.xcodeproj/project.pbxproj`; the project does not auto-discover files.
- User-facing text and the Xcode development region are currently Simplified Chinese; follow the surrounding language unless the task includes localization.
- Add focused XCTest coverage for changed filtering, distance, import, or export behavior. Do not treat simulator tests as proof of background delivery or battery performance.

## Files normally left alone

- Do not edit or commit generated output under `DerivedData/`, `DerivedData-device/`, `build/`, or Xcode user-state directories.
- Modify `aro.xcodeproj/project.pbxproj` only when target membership or build settings must change.
- Modify `aro/Resources/Info.plist`, `PrivacyInfo.xcprivacy`, signing/capability settings, and asset catalogs only when the requested behavior requires it; they define runtime, privacy, and distribution contracts.
