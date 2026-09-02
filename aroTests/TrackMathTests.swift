import CoreLocation
import XCTest
@testable import aro

final class TrackMathTests: XCTestCase {
    func testDistanceAddsPlausibleSegments() {
        let start = Date()
        let points = [
            point(latitude: 52.5200, longitude: 13.4050, date: start),
            point(latitude: 52.5210, longitude: 13.4050, date: start.addingTimeInterval(120))
        ]
        XCTAssertEqual(TrackMath.distance(of: points), 111, accuracy: 3)
    }

    func testDistanceRejectsImpossibleJump() {
        let start = Date()
        let points = [
            point(latitude: 52.5200, longitude: 13.4050, date: start),
            point(latitude: 48.8566, longitude: 2.3522, date: start.addingTimeInterval(60))
        ]
        XCTAssertEqual(TrackMath.distance(of: points), 0)
    }

    func testFilterRejectsStaleAndInaccurateLocations() {
        let now = Date()
        let stale = location(latitude: 52.52, longitude: 13.405, date: now.addingTimeInterval(-1_000), accuracy: 10)
        let inaccurate = location(latitude: 52.52, longitude: 13.405, date: now, accuracy: 800)
        XCTAssertFalse(TrackMath.shouldAccept(stale, after: nil, mode: .balanced, now: now))
        XCTAssertFalse(TrackMath.shouldAccept(inaccurate, after: nil, mode: .balanced, now: now))
    }

    func testFilterRejectsNearDuplicate() {
        let now = Date()
        let previous = point(latitude: 52.52, longitude: 13.405, date: now)
        let duplicate = location(latitude: 52.52001, longitude: 13.40501, date: now.addingTimeInterval(30), accuracy: 8)
        XCTAssertFalse(TrackMath.shouldAccept(duplicate, after: previous, mode: .balanced, now: now.addingTimeInterval(30)))
    }

    func testEcoModeUsesHighQualityFixesOnlyForEventBursts() {
        XCTAssertFalse(TrackingMode.eco.usesContinuousUpdates)
        XCTAssertEqual(TrackingMode.eco.desiredAccuracy, kCLLocationAccuracyNearestTenMeters)
        XCTAssertEqual(TrackingMode.eco.maximumAcceptedAccuracy, 150)

        let now = Date()
        let acceptable = location(latitude: 52.52, longitude: 13.405, date: now, accuracy: 120)
        let tooInaccurate = location(latitude: 52.52, longitude: 13.405, date: now, accuracy: 180)
        XCTAssertTrue(TrackMath.shouldAccept(acceptable, after: nil, mode: .eco, now: now))
        XCTAssertFalse(TrackMath.shouldAccept(tooInaccurate, after: nil, mode: .eco, now: now))
    }

    func testBalancedModeUsesHighQualityLowFrequencyContinuousUpdates() {
        XCTAssertTrue(TrackingMode.balanced.usesContinuousUpdates)
        XCTAssertEqual(TrackingMode.balanced.desiredAccuracy, kCLLocationAccuracyNearestTenMeters)
        XCTAssertEqual(TrackingMode.balanced.distanceFilter, 75)
        XCTAssertEqual(TrackingMode.balanced.maximumAcceptedAccuracy, 100)

        let now = Date()
        let acceptable = location(latitude: 52.52, longitude: 13.405, date: now, accuracy: 80)
        let tooInaccurate = location(latitude: 52.52, longitude: 13.405, date: now, accuracy: 120)
        XCTAssertTrue(TrackMath.shouldAccept(acceptable, after: nil, mode: .balanced, now: now))
        XCTAssertFalse(TrackMath.shouldAccept(tooInaccurate, after: nil, mode: .balanced, now: now))
    }

    func testTrackComplicationSnapshotNormalizesAndSplitsLongGap() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_735_732_800) // 2025-01-01 12:00 UTC
        let points = [
            point(latitude: 50.0000, longitude: 8.0000, date: now.addingTimeInterval(-3_600)),
            point(latitude: 50.0010, longitude: 8.0010, date: now.addingTimeInterval(-3_480)),
            point(latitude: 50.0100, longitude: 8.0100, date: now.addingTimeInterval(-10_000)),
            point(latitude: 50.0110, longitude: 8.0110, date: now.addingTimeInterval(-9_880))
        ].sorted { $0.timestamp < $1.timestamp }

        let snapshot = TrackMath.trackComplicationSnapshot(of: points, now: now, calendar: calendar)

        XCTAssertEqual(snapshot.segments.count, 2)
        XCTAssertGreaterThan(snapshot.distanceMeters, 0)
        for point in snapshot.segments.flatMap(\.points) {
            XCTAssertTrue((0...1).contains(point.x))
            XCTAssertTrue((0...1).contains(point.y))
        }
    }

    func testTrackComplicationSnapshotIgnoresPreviousDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_735_732_800)
        let yesterday = now.addingTimeInterval(-24 * 60 * 60)
        let points = [
            point(latitude: 50.0, longitude: 8.0, date: yesterday),
            point(latitude: 50.001, longitude: 8.001, date: yesterday.addingTimeInterval(120))
        ]

        let snapshot = TrackMath.trackComplicationSnapshot(of: points, now: now, calendar: calendar)

        XCTAssertEqual(snapshot.distanceMeters, 0)
        XCTAssertTrue(snapshot.segments.isEmpty)
    }

    func testGPXAndGeoJSONExport() throws {
        let points = [point(latitude: 52.52, longitude: 13.405, date: Date(timeIntervalSince1970: 1_700_000_000))]
        let gpx = String(decoding: TrackExport.gpx(points: points, name: "A & B"), as: UTF8.self)
        XCTAssertTrue(gpx.contains("A &amp; B"))
        XCTAssertTrue(gpx.contains("<trkpt lat=\"52.52\" lon=\"13.405\">"))

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: TrackExport.geoJSON(points: points, name: "Track")) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "FeatureCollection")
    }

    func testGPXImportPreservesCoordinatesAndTime() throws {
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1"><trk><trkseg>
          <trkpt lat="52.52" lon="13.405"><ele>34.5</ele><time>2025-01-02T03:04:05Z</time></trkpt>
          <trkpt lat="52.521" lon="13.406"><time>2025-01-02T03:05:05.500Z</time></trkpt>
        </trkseg></trk></gpx>
        """
        let points = try TrackImport.parse(data: Data(gpx.utf8), fileExtension: "gpx")
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[0].latitude, 52.52)
        XCTAssertEqual(points[0].longitude, 13.405)
        XCTAssertEqual(points[0].altitude, 34.5)
        XCTAssertEqual(points[1].timestamp.timeIntervalSince(points[0].timestamp), 60.5, accuracy: 0.01)
    }

    private func point(latitude: Double, longitude: Double, date: Date) -> TrackPoint {
        TrackPoint(timestamp: date, latitude: latitude, longitude: longitude, horizontalAccuracy: 8)
    }

    private func location(latitude: Double, longitude: Double, date: Date, accuracy: Double) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: 0,
            horizontalAccuracy: accuracy,
            verticalAccuracy: -1,
            timestamp: date
        )
    }
}
