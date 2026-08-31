import CoreLocation
import Foundation

enum TrackMath {
    static func distance(of points: [TrackPoint]) -> CLLocationDistance {
        guard points.count > 1 else { return 0 }
        var result: CLLocationDistance = 0

        for (previous, current) in zip(points, points.dropFirst()) {
            let interval = current.timestamp.timeIntervalSince(previous.timestamp)
            guard interval > 0, interval < 6 * 60 * 60 else { continue }

            let segment = previous.location.distance(from: current.location)
            let inferredSpeed = segment / interval
            guard inferredSpeed < 100 else { continue }
            result += segment
        }
        return result
    }

    static func shouldAccept(
        _ location: CLLocation,
        after previous: TrackPoint?,
        mode: TrackingMode,
        maximumAge: TimeInterval = 180,
        now: Date = Date()
    ) -> Bool {
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= mode.maximumAcceptedAccuracy,
              abs(location.timestamp.timeIntervalSince(now)) < maximumAge,
              CLLocationCoordinate2DIsValid(location.coordinate)
        else { return false }

        guard let previous else { return true }
        let interval = location.timestamp.timeIntervalSince(previous.timestamp)
        guard interval > 0 else { return false }

        let distance = previous.location.distance(from: location)
        if distance < max(5, mode.distanceFilter * 0.25), interval < 90 {
            return false
        }

        if interval < 10 * 60, distance / interval > 100 {
            return false
        }
        return true
    }

    static func downsample(_ points: [TrackPoint], maximum: Int) -> [TrackPoint] {
        guard maximum > 1, points.count > maximum else { return points }
        let stride = Double(points.count - 1) / Double(maximum - 1)
        return (0..<maximum).map { points[Int((Double($0) * stride).rounded())] }
    }
}
