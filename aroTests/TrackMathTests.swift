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
