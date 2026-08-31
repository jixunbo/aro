import CoreLocation
import Foundation

struct TrackPoint: Identifiable, Hashable, Sendable {
    let id: Int64
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let horizontalAccuracy: Double
    let speed: Double
    let course: Double
    let source: String
    let activity: String?

    init(
        id: Int64 = 0,
        timestamp: Date,
        latitude: Double,
        longitude: Double,
        altitude: Double = 0,
        horizontalAccuracy: Double = -1,
        speed: Double = -1,
        course: Double = -1,
        source: String = "standard",
        activity: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.speed = speed
        self.course = course
        self.source = source
        self.activity = activity
    }

    init(location: CLLocation, source: String, activity: String?) {
        self.init(
            timestamp: location.timestamp,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.altitude,
            horizontalAccuracy: location.horizontalAccuracy,
            speed: location.speed,
            course: location.course,
            source: source,
            activity: activity
        )
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(
            coordinate: coordinate,
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: -1,
            course: course,
            speed: speed,
            timestamp: timestamp
        )
    }
}

struct TrackDay: Identifiable, Hashable, Sendable {
    let date: Date
    let pointCount: Int
    let distance: CLLocationDistance
    let firstPointAt: Date
    let lastPointAt: Date

    var id: Date { date }
}

struct LifetimeStats: Sendable {
    let pointCount: Int
    let dayCount: Int
    let distance: CLLocationDistance
    let firstDate: Date?
    let lastDate: Date?

    static let empty = LifetimeStats(pointCount: 0, dayCount: 0, distance: 0, firstDate: nil, lastDate: nil)
}

