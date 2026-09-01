import CoreLocation
import Foundation
import SQLite3

final class TrackDatabase: @unchecked Sendable {
    static let shared = TrackDatabase()

    private let queue = DispatchQueue(label: "app.aro.database", qos: .utility)
    private var database: OpaquePointer?
    private let databaseURL: URL

    private convenience init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = support.appendingPathComponent("traceon", isDirectory: true)
        self.init(databaseURL: folder.appendingPathComponent("tracks.sqlite3"))
    }

    init(databaseURL: URL) {
        self.databaseURL = databaseURL
        try? FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        queue.sync { openAndMigrate() }
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    @discardableResult
    func insert(_ point: TrackPoint) -> Int64 {
        queue.sync { insertLocked(point, updatesSummary: true, cloudSynced: false) }
    }

    @discardableResult
    func insertImported(_ points: [TrackPoint]) -> Int {
        queue.sync {
            guard !points.isEmpty else { return 0 }
            execute("BEGIN IMMEDIATE")
            var inserted = 0
            for point in points.sorted(by: { $0.timestamp < $1.timestamp }) {
                if insertLocked(point, updatesSummary: false, cloudSynced: false) > 0 { inserted += 1 }
            }
            rebuildDailySummariesLocked()
            execute("COMMIT")
            return inserted
        }
    }

    @discardableResult
    func applyCloudPoints(_ points: [TrackPoint]) -> Int {
        queue.sync {
            guard !points.isEmpty else { return 0 }
            execute("BEGIN IMMEDIATE")
            var inserted = 0
            for point in points.sorted(by: { $0.timestamp < $1.timestamp }) {
                if insertLocked(point, updatesSummary: false, cloudSynced: true) > 0 {
                    inserted += 1
                } else if let syncID = point.syncID {
                    markCloudSyncedLocked(syncID: syncID)
                }
            }
            if inserted > 0 { rebuildDailySummariesLocked() }
            execute("COMMIT")
            return inserted
        }
    }

    func latestPoint() -> TrackPoint? {
        queue.sync { latestPointLocked() }
    }

    func point(syncID: String) -> TrackPoint? {
        queue.sync {
            queryPoints(
                sql: "SELECT \(pointColumns) FROM track_points WHERE sync_id = ? LIMIT 1",
                bindings: { statement in bindText(syncID, to: statement, index: 1) }
            ).first
        }
    }

    func unsyncedPoints(limit: Int = 500) -> [TrackPoint] {
        queue.sync {
            guard limit > 0 else { return [] }
            return queryPoints(
                sql: "SELECT \(pointColumns) FROM track_points WHERE cloud_synced = 0 ORDER BY timestamp ASC, id ASC LIMIT ?",
                bindings: { statement in sqlite3_bind_int(statement, 1, Int32(limit)) }
            )
        }
    }

    func markCloudSynced(syncIDs: [String]) {
        queue.sync {
            guard !syncIDs.isEmpty else { return }
            execute("BEGIN IMMEDIATE")
            for syncID in Set(syncIDs) { markCloudSyncedLocked(syncID: syncID) }
            execute("COMMIT")
        }
    }

    func resetCloudSyncState() {
        queue.sync { execute("UPDATE track_points SET cloud_synced = 0") }
    }

    @discardableResult
    func deleteCloudPoints(syncIDs: [String]) -> Int {
        queue.sync {
            guard let database, !syncIDs.isEmpty else { return 0 }
            execute("BEGIN IMMEDIATE")
            var deleted = 0
            let sql = "DELETE FROM track_points WHERE sync_id = ?"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                execute("ROLLBACK")
                return 0
            }
            defer { sqlite3_finalize(statement) }
            for syncID in Set(syncIDs) {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                bindText(syncID, to: statement, index: 1)
                guard sqlite3_step(statement) == SQLITE_DONE else { continue }
                deleted += Int(sqlite3_changes(database))
            }
            if deleted > 0 { rebuildDailySummariesLocked() }
            execute("COMMIT")
            return deleted
        }
    }

    func points(from start: Date, to end: Date, limit: Int = 50_000) -> [TrackPoint] {
        queue.sync {
            queryPoints(
                sql: "SELECT \(pointColumns) FROM track_points WHERE timestamp >= ? AND timestamp < ? ORDER BY timestamp ASC LIMIT ?",
                bindings: { statement in
                    sqlite3_bind_double(statement, 1, start.timeIntervalSince1970)
                    sqlite3_bind_double(statement, 2, end.timeIntervalSince1970)
                    sqlite3_bind_int(statement, 3, Int32(limit))
                }
            )
        }
    }

    func points(on date: Date, limit: Int = 50_000) -> [TrackPoint] {
        let interval = Calendar.current.dateInterval(of: .day, for: date)!
        return points(from: interval.start, to: interval.end, limit: limit)
    }

    func overviewPoints(maximum: Int = 8_000) -> [TrackPoint] {
        queue.sync {
            guard maximum > 0 else { return [] }
            let total = scalarInt("SELECT COUNT(*) FROM track_points")
            guard total > 0 else { return [] }

            if total <= maximum {
                return queryPoints(
                    sql: "SELECT \(pointColumns) FROM track_points ORDER BY timestamp ASC, id ASC",
                    bindings: { _ in }
                )
            }

            if maximum == 1 {
                return queryPoints(
                    sql: "SELECT \(pointColumns) FROM track_points ORDER BY timestamp DESC, id DESC LIMIT 1",
                    bindings: { _ in }
                )
            }

            let span = total - 1
            let stride = max(1, (span + maximum - 2) / (maximum - 1))
            return queryPoints(
                sql: """
                    WITH ordered_points AS (
                        SELECT \(pointColumns),
                               ROW_NUMBER() OVER (ORDER BY timestamp ASC, id ASC) - 1 AS sample_index,
                               COUNT(*) OVER () AS total_count
                        FROM track_points
                    )
                    SELECT \(pointColumns) FROM ordered_points
                    WHERE sample_index = 0
                       OR sample_index = total_count - 1
                       OR (sample_index % ?) = 0
                    ORDER BY timestamp ASC, id ASC
                    LIMIT ?
                    """,
                bindings: { statement in
                    sqlite3_bind_int(statement, 1, Int32(stride))
                    sqlite3_bind_int(statement, 2, Int32(maximum))
                }
            )
        }
    }

    func allPoints() -> [TrackPoint] {
        queue.sync {
            queryPoints(sql: "SELECT \(pointColumns) FROM track_points ORDER BY timestamp ASC", bindings: { _ in })
        }
    }

    func trackDays(limit: Int = 3650) -> [TrackDay] {
        queue.sync {
            guard let database else { return [] }
            let sql = """
                SELECT day, point_count, distance, first_timestamp, last_timestamp
                FROM daily_summary ORDER BY day DESC LIMIT ?
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int(statement, 1, Int32(limit))

            let formatter = Self.dayFormatter
            var result: [TrackDay] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let rawDay = string(statement, 0), let date = formatter.date(from: rawDay) else { continue }
                result.append(TrackDay(
                    date: date,
                    pointCount: Int(sqlite3_column_int64(statement, 1)),
                    distance: sqlite3_column_double(statement, 2),
                    firstPointAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                    lastPointAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
                ))
            }
            return result
        }
    }

    func lifetimeStats() -> LifetimeStats {
        queue.sync {
            guard let database else { return .empty }
            let sql = "SELECT COALESCE(SUM(point_count), 0), COUNT(*), COALESCE(SUM(distance), 0), MIN(first_timestamp), MAX(last_timestamp) FROM daily_summary"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
                  sqlite3_step(statement) == SQLITE_ROW else { return .empty }
            defer { sqlite3_finalize(statement) }

            let first = sqlite3_column_type(statement, 3) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
            let last = sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
            return LifetimeStats(
                pointCount: Int(sqlite3_column_int64(statement, 0)),
                dayCount: Int(sqlite3_column_int64(statement, 1)),
                distance: sqlite3_column_double(statement, 2),
                firstDate: first,
                lastDate: last
            )
        }
    }

    func fileSize() -> Int64 {
        queue.sync {
            let urls = [
                databaseURL,
                URL(fileURLWithPath: databaseURL.path + "-wal"),
                URL(fileURLWithPath: databaseURL.path + "-shm")
            ]
            return urls.reduce(0) { partial, url in
                let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
                return partial + ((attributes?[.size] as? NSNumber)?.int64Value ?? 0)
            }
        }
    }

    func deleteAll() {
        queue.sync {
            execute("BEGIN IMMEDIATE")
            execute("DELETE FROM track_points")
            execute("DELETE FROM daily_summary")
            execute("COMMIT")
            execute("PRAGMA wal_checkpoint(TRUNCATE)")
        }
    }

    private var pointColumns: String {
        "id, timestamp, latitude, longitude, altitude, horizontal_accuracy, speed, course, source, activity, sync_id"
    }

    private func openAndMigrate() {
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            database = nil
            return
        }
        execute("PRAGMA journal_mode=WAL")
        execute("PRAGMA synchronous=NORMAL")
        execute("PRAGMA foreign_keys=ON")
        execute("PRAGMA busy_timeout=3000")
        execute("PRAGMA secure_delete=ON")
        execute("""
            CREATE TABLE IF NOT EXISTS track_points (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp REAL NOT NULL,
                latitude REAL NOT NULL,
                longitude REAL NOT NULL,
                altitude REAL NOT NULL DEFAULT 0,
                horizontal_accuracy REAL NOT NULL DEFAULT -1,
                speed REAL NOT NULL DEFAULT -1,
                course REAL NOT NULL DEFAULT -1,
                source TEXT NOT NULL,
                activity TEXT,
                sync_id TEXT,
                cloud_synced INTEGER NOT NULL DEFAULT 0
            )
            """)
        if !columnExists("sync_id", in: "track_points") {
            execute("ALTER TABLE track_points ADD COLUMN sync_id TEXT")
        }
        if !columnExists("cloud_synced", in: "track_points") {
            execute("ALTER TABLE track_points ADD COLUMN cloud_synced INTEGER NOT NULL DEFAULT 0")
        }
        execute("UPDATE track_points SET sync_id = lower(hex(randomblob(16))) WHERE sync_id IS NULL OR sync_id = ''")
        execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_track_points_sync_id ON track_points(sync_id)")
        execute("CREATE INDEX IF NOT EXISTS idx_track_points_cloud_synced ON track_points(cloud_synced, id)")
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: databaseURL.path
        )
        execute("CREATE INDEX IF NOT EXISTS idx_track_points_timestamp ON track_points(timestamp)")
        execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_track_points_deduplicate ON track_points(timestamp, latitude, longitude)")
        execute("""
            CREATE TABLE IF NOT EXISTS daily_summary (
                day TEXT PRIMARY KEY,
                point_count INTEGER NOT NULL,
                distance REAL NOT NULL,
                first_timestamp REAL NOT NULL,
                last_timestamp REAL NOT NULL,
                last_latitude REAL NOT NULL,
                last_longitude REAL NOT NULL
            )
            """)
    }

    private func latestPointLocked() -> TrackPoint? {
        queryPoints(sql: "SELECT \(pointColumns) FROM track_points ORDER BY timestamp DESC LIMIT 1", bindings: { _ in }).first
    }

    private func insertLocked(_ point: TrackPoint, updatesSummary: Bool, cloudSynced: Bool) -> Int64 {
        guard let database else { return 0 }
        let previous = updatesSummary ? latestPointLocked() : nil
        let syncID = point.syncID.flatMap { $0.isEmpty ? nil : $0 } ?? UUID().uuidString.lowercased()
        let sql = """
            INSERT OR IGNORE INTO track_points
            (timestamp, latitude, longitude, altitude, horizontal_accuracy, speed, course, source, activity, sync_id, cloud_synced)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, point.timestamp.timeIntervalSince1970)
        sqlite3_bind_double(statement, 2, point.latitude)
        sqlite3_bind_double(statement, 3, point.longitude)
        sqlite3_bind_double(statement, 4, point.altitude)
        sqlite3_bind_double(statement, 5, point.horizontalAccuracy)
        sqlite3_bind_double(statement, 6, point.speed)
        sqlite3_bind_double(statement, 7, point.course)
        bindText(point.source, to: statement, index: 8)
        bindText(point.activity, to: statement, index: 9)
        bindText(syncID, to: statement, index: 10)
        sqlite3_bind_int(statement, 11, cloudSynced ? 1 : 0)

        guard sqlite3_step(statement) == SQLITE_DONE, sqlite3_changes(database) > 0 else { return 0 }
        let rowID = sqlite3_last_insert_rowid(database)
        if updatesSummary { updateDailySummaryLocked(with: point, previous: previous) }
        return rowID
    }

    private func markCloudSyncedLocked(syncID: String) {
        guard let database else { return }
        let sql = "UPDATE track_points SET cloud_synced = 1 WHERE sync_id = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        bindText(syncID, to: statement, index: 1)
        sqlite3_step(statement)
    }

    private func rebuildDailySummariesLocked() {
        execute("DELETE FROM daily_summary")
        let points = queryPoints(sql: "SELECT \(pointColumns) FROM track_points ORDER BY timestamp ASC", bindings: { _ in })
        var previous: TrackPoint?
        for point in points {
            updateDailySummaryLocked(with: point, previous: previous)
            previous = point
        }
    }

    private func updateDailySummaryLocked(with point: TrackPoint, previous: TrackPoint?) {
        guard let database else { return }
        let day = Self.dayFormatter.string(from: point.timestamp)
        var segment: CLLocationDistance = 0
        if let previous,
           Self.dayFormatter.string(from: previous.timestamp) == day {
            let interval = point.timestamp.timeIntervalSince(previous.timestamp)
            let candidate = previous.location.distance(from: point.location)
            if interval > 0, interval < 6 * 60 * 60, candidate / interval < 100 {
                segment = candidate
            }
        }

        let sql = """
            INSERT INTO daily_summary
            (day, point_count, distance, first_timestamp, last_timestamp, last_latitude, last_longitude)
            VALUES (?, 1, ?, ?, ?, ?, ?)
            ON CONFLICT(day) DO UPDATE SET
                point_count = point_count + 1,
                distance = distance + excluded.distance,
                first_timestamp = MIN(first_timestamp, excluded.first_timestamp),
                last_timestamp = MAX(last_timestamp, excluded.last_timestamp),
                last_latitude = excluded.last_latitude,
                last_longitude = excluded.last_longitude
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        bindText(day, to: statement, index: 1)
        sqlite3_bind_double(statement, 2, segment)
        sqlite3_bind_double(statement, 3, point.timestamp.timeIntervalSince1970)
        sqlite3_bind_double(statement, 4, point.timestamp.timeIntervalSince1970)
        sqlite3_bind_double(statement, 5, point.latitude)
        sqlite3_bind_double(statement, 6, point.longitude)
        sqlite3_step(statement)
    }

    private func queryPoints(sql: String, bindings: (OpaquePointer?) -> Void) -> [TrackPoint] {
        guard let database else { return [] }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        bindings(statement)
        var result: [TrackPoint] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(TrackPoint(
                id: sqlite3_column_int64(statement, 0),
                syncID: string(statement, 10),
                timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                latitude: sqlite3_column_double(statement, 2),
                longitude: sqlite3_column_double(statement, 3),
                altitude: sqlite3_column_double(statement, 4),
                horizontalAccuracy: sqlite3_column_double(statement, 5),
                speed: sqlite3_column_double(statement, 6),
                course: sqlite3_column_double(statement, 7),
                source: string(statement, 8) ?? "unknown",
                activity: string(statement, 9)
            ))
        }
        return result
    }

    private func columnExists(_ column: String, in table: String) -> Bool {
        guard let database else { return false }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(\(table))", -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            if string(statement, 1) == column { return true }
        }
        return false
    }

    private func scalarInt(_ sql: String) -> Int {
        guard let database else { return 0 }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        defer { sqlite3_finalize(statement) }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func execute(_ sql: String) {
        guard let database else { return }
        sqlite3_exec(database, sql, nil, nil, nil)
    }

    private func bindText(_ value: String?, to statement: OpaquePointer?, index: Int32) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_text(statement, index, value, -1, Self.sqliteTransient)
    }

    private func string(_ statement: OpaquePointer?, _ column: Int32) -> String? {
        guard let bytes = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: bytes)
    }

    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
