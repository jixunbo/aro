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
        let firstSample = try XCTUnwrap(overview.first?.timestamp)
        let firstPoint = try XCTUnwrap(points.first?.timestamp)
        XCTAssertLessThanOrEqual(firstSample.timeIntervalSince(firstPoint), 1)
        XCTAssertEqual(overview.last?.timestamp, points.last?.timestamp)
        XCTAssertEqual(overview.map(\.timestamp), overview.map(\.timestamp).sorted())
    }
}
