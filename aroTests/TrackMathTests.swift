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

    func testLiveFilterRejectsInaccurateAndPreSessionLocations() {
        let now = Date()
        let startedAt = now.addingTimeInterval(-300)
        let inaccurate = location(latitude: 52.52, longitude: 13.405, date: now, accuracy: 120)
        let beforeSession = location(latitude: 52.52, longitude: 13.405, date: startedAt.addingTimeInterval(-10), accuracy: 10)

        XCTAssertFalse(TrackMath.shouldRecordLiveLocation(
            inaccurate,
            after: nil,
            mode: .balanced,
            trackingStartedAt: startedAt,
            now: now
        ))
        XCTAssertFalse(TrackMath.shouldRecordLiveLocation(
            beforeSession,
            after: nil,
            mode: .balanced,
            trackingStartedAt: startedAt,
            now: now
        ))
    }

    func testLiveFilterAcceptsQueuedLocationFromCurrentTrackingSession() {
        let now = Date()
        let startedAt = now.addingTimeInterval(-30 * 60)
        let queued = location(
            latitude: 52.52,
            longitude: 13.405,
            date: now.addingTimeInterval(-15 * 60),
            accuracy: 12
        )

        XCTAssertTrue(TrackMath.shouldRecordLiveLocation(
            queued,
            after: nil,
            mode: .balanced,
            trackingStartedAt: startedAt,
            now: now
        ))
    }

    func testLiveFilterRejectsFutureLocation() {
        let now = Date()
        let future = location(latitude: 52.52, longitude: 13.405, date: now.addingTimeInterval(120), accuracy: 10)

        XCTAssertFalse(TrackMath.shouldRecordLiveLocation(
            future,
            after: nil,
            mode: .balanced,
            trackingStartedAt: now.addingTimeInterval(-60),
            now: now
        ))
    }

    func testLiveFilterRejectsNearDuplicate() {
        let now = Date()
        let previous = point(latitude: 52.52, longitude: 13.405, date: now, course: 0)
        let duplicate = location(
            latitude: 52.52001,
            longitude: 13.40501,
            date: now.addingTimeInterval(30),
            accuracy: 8,
            course: 5,
            speed: 1
        )

        XCTAssertFalse(TrackMath.shouldRecordLiveLocation(
            duplicate,
            after: previous,
            mode: .balanced,
            trackingStartedAt: now.addingTimeInterval(-60),
            now: now.addingTimeInterval(30)
        ))
    }

    func testBalancedRecordsNormalMovementDistance() {
        let now = Date()
        let previous = point(latitude: 52.5200, longitude: 13.4050, date: now, course: 0)
        let moved = location(
            latitude: 52.52055,
            longitude: 13.4050,
            date: now.addingTimeInterval(60),
            accuracy: 10,
            course: 0,
            speed: 1.2
        )

        XCTAssertTrue(TrackMath.shouldRecordLiveLocation(
            moved,
            after: previous,
            mode: .balanced,
            trackingStartedAt: now.addingTimeInterval(-60),
            now: now.addingTimeInterval(60)
        ))
    }

    func testBalancedPreservesMeaningfulTurnBeforeNormalDistance() {
        let now = Date()
        let previous = point(latitude: 52.5200, longitude: 13.4050, date: now, course: 0)
        let turn = location(
            latitude: 52.52027,
            longitude: 13.4050,
            date: now.addingTimeInterval(30),
            accuracy: 8,
            course: 90,
            speed: 1.4
        )

        XCTAssertTrue(TrackMath.shouldRecordLiveLocation(
            turn,
            after: previous,
            mode: .balanced,
            trackingStartedAt: now.addingTimeInterval(-60),
            now: now.addingTimeInterval(30)
        ))
    }

    func testBalancedPreservesObservedTurnWhenCourseUnavailable() {
        let now = Date()
        let previous = point(latitude: 52.5200, longitude: 13.4050, date: now)
        let turn = location(
            latitude: 52.52027,
            longitude: 13.4050,
            date: now.addingTimeInterval(30),
            accuracy: 8
        )

        XCTAssertTrue(TrackMath.shouldRecordLiveLocation(
            turn,
            after: previous,
            mode: .balanced,
            trackingStartedAt: now.addingTimeInterval(-60),
            observedTurnDegrees: 90,
            now: now.addingTimeInterval(30)
        ))
    }

    func testBalancedRejectsShortStraightMovement() {
        let now = Date()
        let previous = point(latitude: 52.5200, longitude: 13.4050, date: now, course: 0)
        let shortMove = location(
            latitude: 52.52027,
            longitude: 13.4050,
            date: now.addingTimeInterval(30),
            accuracy: 8,
            course: 5,
            speed: 1.4
        )

        XCTAssertFalse(TrackMath.shouldRecordLiveLocation(
            shortMove,
            after: previous,
            mode: .balanced,
            trackingStartedAt: now.addingTimeInterval(-60),
            now: now.addingTimeInterval(30)
        ))
    }

    func testBalancedRecordsSlowMovementAfterMaximumInterval() {
        let now = Date()
        let previous = point(latitude: 52.5200, longitude: 13.4050, date: now, course: 0)
        let slowMove = location(
            latitude: 52.52023,
            longitude: 13.4050,
            date: now.addingTimeInterval(130),
            accuracy: 8,
            course: 5,
            speed: 0.8
        )

        XCTAssertTrue(TrackMath.shouldRecordLiveLocation(
            slowMove,
            after: previous,
            mode: .balanced,
            trackingStartedAt: now.addingTimeInterval(-60),
            now: now.addingTimeInterval(130)
        ))
    }

    func testAccuracyNoiseFloorPreventsFalseShortTurn() {
        let now = Date()
        let previous = point(
            latitude: 52.5200,
            longitude: 13.4050,
            date: now,
            horizontalAccuracy: 70,
            course: 0
        )
        let noisyTurn = location(
            latitude: 52.52027,
            longitude: 13.4050,
            date: now.addingTimeInterval(130),
            accuracy: 70,
            course: 90,
            speed: 1
        )

        XCTAssertFalse(TrackMath.shouldRecordLiveLocation(
            noisyTurn,
            after: previous,
            mode: .balanced,
            trackingStartedAt: now.addingTimeInterval(-60),
            now: now.addingTimeInterval(130)
        ))
    }

    func testBearingAndHeadingDifference() {
        let origin = CLLocationCoordinate2D(latitude: 52.52, longitude: 13.405)
        let north = CLLocationCoordinate2D(latitude: 52.521, longitude: 13.405)
        let east = CLLocationCoordinate2D(latitude: 52.52, longitude: 13.406)

        XCTAssertEqual(TrackMath.bearing(from: origin, to: north), 0, accuracy: 1)
        XCTAssertEqual(TrackMath.bearing(from: origin, to: east), 90, accuracy: 1)
        XCTAssertEqual(TrackMath.headingDifference(350, 10), 20, accuracy: 0.001)
    }

    func testTrackingModeSamplingAndBackgroundPolicies() {
        XCTAssertEqual(TrackingMode.eco.maximumAcceptedAccuracy, 120)
        XCTAssertEqual(TrackingMode.balanced.maximumAcceptedAccuracy, 80)
        XCTAssertEqual(TrackingMode.balanced.minimumRecordingDistance, 55)
        XCTAssertEqual(TrackingMode.balanced.maximumRecordingInterval, 120)
        XCTAssertFalse(TrackingMode.eco.requiresTimelyBackgroundDelivery)
        XCTAssertFalse(TrackingMode.balanced.requiresTimelyBackgroundDelivery)
        XCTAssertTrue(TrackingMode.precise.requiresTimelyBackgroundDelivery)
        XCTAssertTrue(TrackingMode.workout.requiresTimelyBackgroundDelivery)
        XCTAssertEqual(TrackingMode.precise.minimumRecordingDistance, 20)
        XCTAssertEqual(TrackingMode.workout.minimumRecordingDistance, 8)
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

    private func point(
        latitude: Double,
        longitude: Double,
        date: Date,
        horizontalAccuracy: Double = 8,
        course: Double = -1
    ) -> TrackPoint {
        TrackPoint(
            timestamp: date,
            latitude: latitude,
            longitude: longitude,
            horizontalAccuracy: horizontalAccuracy,
            course: course
        )
    }

    private func location(
        latitude: Double,
        longitude: Double,
        date: Date,
        accuracy: Double,
        course: Double = -1,
        speed: Double = -1
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: 0,
            horizontalAccuracy: accuracy,
            verticalAccuracy: -1,
            course: course,
            speed: speed,
            timestamp: date
        )
    }
}
