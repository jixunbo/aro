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
}
