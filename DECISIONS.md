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
