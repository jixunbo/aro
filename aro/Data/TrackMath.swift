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

    static func trackComplicationSnapshot(
        of points: [TrackPoint],
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> TrackComplicationSnapshot {
        let todayPoints = points.filter { calendar.isDate($0.timestamp, inSameDayAs: now) }
        let sourceSegments = routeSegments(todayPoints).suffix(4)
        let sampledSegments = sourceSegments.map { downsample($0, maximum: 8) }
        let projected = projectedSegments(sampledSegments)

        return TrackComplicationSnapshot(
            distanceMeters: distance(of: todayPoints),
            segments: projected,
            updatedAt: now,
            dayStart: calendar.startOfDay(for: now)
        )
    }

    private static func routeSegments(_ points: [TrackPoint]) -> [[TrackPoint]] {
        guard let first = points.first else { return [] }
        var result = [[first]]

        for point in points.dropFirst() {
            guard let previous = result.last?.last else { continue }
            let gap = point.timestamp.timeIntervalSince(previous.timestamp)
            let jump = previous.location.distance(from: point.location)
            if gap > 90 * 60 || (gap > 0 && jump / gap > 80) {
                result.append([point])
            } else {
                result[result.count - 1].append(point)
            }
        }
        return result
    }

    private static func projectedSegments(_ segments: [[TrackPoint]]) -> [TrackComplicationSegment] {
        let allPoints = segments.flatMap { $0 }
        guard !allPoints.isEmpty else { return [] }

        let meanLatitude = allPoints.map(\.latitude).reduce(0, +) / Double(allPoints.count)
        let longitudeScale = cos(meanLatitude * .pi / 180)
        let projected = segments.map { segment in
            segment.map { point in
                (x: point.longitude * longitudeScale, y: point.latitude)
            }
        }
        let flattened = projected.flatMap { $0 }
        guard let minX = flattened.map(\.x).min(),
              let maxX = flattened.map(\.x).max(),
              let minY = flattened.map(\.y).min(),
              let maxY = flattened.map(\.y).max() else {
            return []
        }

        let width = maxX - minX
        let height = maxY - minY
        let span = max(width, height)
        guard span > 1e-12 else {
            return segments.map { segment in
                TrackComplicationSegment(points: segment.map { _ in TrackComplicationPoint(x: 0.5, y: 0.5) })
            }
        }

        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2
        let usableSpan = 0.84

        return projected.map { segment in
            TrackComplicationSegment(
                points: segment.map { point in
                    TrackComplicationPoint(
                        x: 0.5 + ((point.x - centerX) / span) * usableSpan,
                        y: 0.5 - ((point.y - centerY) / span) * usableSpan
                    )
                }
            )
        }
    }
}
