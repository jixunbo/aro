import SQLite3
import XCTest
@testable import aro

final class TrackDatabaseTests: XCTestCase {
    func testOverviewSamplingSpansCompleteHistory() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrackDatabaseTests-\(UUID().uuidString)", isDirectory: true)
        var database: TrackDatabase? = TrackDatabase(databaseURL: folder.appendingPathComponent("tracks.sqlite3"))
        defer {
            database = nil
            try? FileManager.default.removeItem(at: folder)
        }

        let points = (0..<12_000).map { index in
            TrackPoint(
                timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
                latitude: 52.52,
                longitude: 13.405 + Double(index) / 1_000_000
            )
        }
        XCTAssertEqual(database?.insertImported(points), points.count)

        let overview = try XCTUnwrap(database?.overviewPoints(maximum: 8_000))

        XCTAssertLessThanOrEqual(overview.count, 8_000)
        XCTAssertEqual(overview.first?.timestamp, points.first?.timestamp)
        XCTAssertEqual(overview.last?.timestamp, points.last?.timestamp)
        XCTAssertEqual(overview.map(\.timestamp), overview.map(\.timestamp).sorted())
    }

    func testOverviewSamplingBoundaries() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrackDatabaseTests-\(UUID().uuidString)", isDirectory: true)
        var database: TrackDatabase? = TrackDatabase(databaseURL: folder.appendingPathComponent("tracks.sqlite3"))
        defer {
            database = nil
            try? FileManager.default.removeItem(at: folder)
        }

        XCTAssertTrue(database?.overviewPoints(maximum: 8).isEmpty == true)

        let points = (0..<4).map { index in
            TrackPoint(
                timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
                latitude: 52.52,
                longitude: 13.405 + Double(index) / 1_000_000
            )
        }
        XCTAssertEqual(database?.insertImported(points), points.count)

        XCTAssertTrue(database?.overviewPoints(maximum: 0).isEmpty == true)

        let newest = try XCTUnwrap(database?.overviewPoints(maximum: 1))
        XCTAssertEqual(newest.count, 1)
        XCTAssertEqual(newest.first?.timestamp, points.last?.timestamp)

        let endpoints = try XCTUnwrap(database?.overviewPoints(maximum: 2))
        XCTAssertEqual(endpoints.map(\.timestamp), [points.first?.timestamp, points.last?.timestamp].compactMap { $0 })

        let allPoints = try XCTUnwrap(database?.overviewPoints(maximum: points.count + 1))
        XCTAssertEqual(allPoints.map(\.timestamp), points.map(\.timestamp))
    }

    func testSyncIDsAreAssignedAndProvidedIDsArePreserved() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrackDatabaseTests-\(UUID().uuidString)", isDirectory: true)
        var database: TrackDatabase? = TrackDatabase(databaseURL: folder.appendingPathComponent("tracks.sqlite3"))
        defer {
            database = nil
            try? FileManager.default.removeItem(at: folder)
        }

        XCTAssertGreaterThan(
            database?.insert(TrackPoint(timestamp: Date(timeIntervalSince1970: 1), latitude: 52.52, longitude: 13.405)) ?? 0,
            0
        )
        let suppliedID = "cloud-record-id"
        XCTAssertEqual(
            database?.insertImported([
                TrackPoint(
                    syncID: suppliedID,
                    timestamp: Date(timeIntervalSince1970: 2),
                    latitude: 52.521,
                    longitude: 13.406
                )
            ]),
            1
        )

        let stored = try XCTUnwrap(database?.allPoints())
        XCTAssertEqual(stored.count, 2)
        XCTAssertFalse(try XCTUnwrap(stored[0].syncID).isEmpty)
        XCTAssertEqual(stored[1].syncID, suppliedID)
        XCTAssertEqual(Set(stored.compactMap(\.syncID)).count, 2)
    }

    func testCloudSyncBookkeepingSeparatesLocalAndRemotePoints() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrackDatabaseTests-Cloud-\(UUID().uuidString)", isDirectory: true)
        var database: TrackDatabase? = TrackDatabase(databaseURL: folder.appendingPathComponent("tracks.sqlite3"))
        defer {
            database = nil
            try? FileManager.default.removeItem(at: folder)
        }
        let db = try XCTUnwrap(database)

        XCTAssertGreaterThan(
            db.insert(TrackPoint(timestamp: Date(timeIntervalSince1970: 1), latitude: 52.52, longitude: 13.405)),
            0
        )
        let local = try XCTUnwrap(db.allPoints().first)
        let localSyncID = try XCTUnwrap(local.syncID)
        XCTAssertEqual(db.unsyncedPoints().map(\.syncID), [localSyncID])

        db.markCloudSynced(syncIDs: [localSyncID])
        XCTAssertTrue(db.unsyncedPoints().isEmpty)

        let remoteSyncID = "remote-record-id"
        XCTAssertEqual(
            db.applyCloudPoints([
                TrackPoint(
                    syncID: remoteSyncID,
                    timestamp: Date(timeIntervalSince1970: 2),
                    latitude: 52.521,
                    longitude: 13.406
                )
            ]),
            1
        )
        XCTAssertNotNil(db.point(syncID: remoteSyncID))
        XCTAssertTrue(db.unsyncedPoints().isEmpty)

        db.resetCloudSyncState()
        XCTAssertEqual(Set(db.unsyncedPoints().compactMap(\.syncID)), Set([localSyncID, remoteSyncID]))

        XCTAssertEqual(db.deleteCloudPoints(syncIDs: [remoteSyncID]), 1)
        XCTAssertNil(db.point(syncID: remoteSyncID))
    }

    func testRemoteDuplicateAdoptsCloudIdentityBeforeUpload() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrackDatabaseTests-Reconcile-\(UUID().uuidString)", isDirectory: true)
        var database: TrackDatabase? = TrackDatabase(databaseURL: folder.appendingPathComponent("tracks.sqlite3"))
        defer {
            database = nil
            try? FileManager.default.removeItem(at: folder)
        }
        let db = try XCTUnwrap(database)
        let timestamp = Date(timeIntervalSince1970: 10)

        XCTAssertGreaterThan(
            db.insert(TrackPoint(timestamp: timestamp, latitude: 52.52, longitude: 13.405)),
            0
        )
        let originalSyncID = try XCTUnwrap(db.allPoints().first?.syncID)
        XCTAssertEqual(db.unsyncedPoints().map(\.syncID), [originalSyncID])

        let cloudSyncID = "canonical-cloud-record"
        XCTAssertEqual(
            db.applyCloudPoints([
                TrackPoint(
                    syncID: cloudSyncID,
                    timestamp: timestamp,
                    latitude: 52.52,
                    longitude: 13.405
                )
            ]),
            0
        )

        let stored = db.allPoints()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.syncID, cloudSyncID)
        XCTAssertNil(db.point(syncID: originalSyncID))
        XCTAssertTrue(db.unsyncedPoints().isEmpty)
    }

    func testLegacyDatabaseMigrationBackfillsUniqueSyncIDs() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrackDatabaseTests-Legacy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let databaseURL = folder.appendingPathComponent("tracks.sqlite3")
        defer { try? FileManager.default.removeItem(at: folder) }

        var rawDatabase: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &rawDatabase), SQLITE_OK)
        defer { if let rawDatabase { sqlite3_close(rawDatabase) } }

        let createSQL = """
            CREATE TABLE track_points (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp REAL NOT NULL,
                latitude REAL NOT NULL,
                longitude REAL NOT NULL,
                altitude REAL NOT NULL DEFAULT 0,
                horizontal_accuracy REAL NOT NULL DEFAULT -1,
                speed REAL NOT NULL DEFAULT -1,
                course REAL NOT NULL DEFAULT -1,
                source TEXT NOT NULL,
                activity TEXT
            );
            INSERT INTO track_points
                (timestamp, latitude, longitude, altitude, horizontal_accuracy, speed, course, source, activity)
            VALUES
                (1, 52.52, 13.405, 0, 5, -1, -1, 'standard', NULL),
                (2, 52.521, 13.406, 0, 5, -1, -1, 'standard', NULL);
            """
        XCTAssertEqual(sqlite3_exec(rawDatabase, createSQL, nil, nil, nil), SQLITE_OK)
        sqlite3_close(rawDatabase)
        rawDatabase = nil

        let migratedDatabase = TrackDatabase(databaseURL: databaseURL)
        let points = migratedDatabase.allPoints()

        XCTAssertEqual(points.count, 2)
        XCTAssertTrue(points.allSatisfy { !($0.syncID ?? "").isEmpty })
        XCTAssertEqual(Set(points.compactMap(\.syncID)).count, 2)
        XCTAssertEqual(migratedDatabase.unsyncedPoints().count, 2)
    }
}
