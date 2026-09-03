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

    /// Decides whether a delivered Core Location fix is useful route geometry.
    ///
    /// Live Updates and Standard location callbacks may deliver queued fixes after a background
    /// relaunch, so wall-clock age is deliberately not used as a freshness gate. Instead, a fix
    /// must belong to the current tracking session and be newer than the last persisted point.
    static func shouldRecordLiveLocation(
        _ location: CLLocation,
        after previous: TrackPoint?,
        mode: TrackingMode,
        trackingStartedAt: Date,
        observedTurnDegrees: CLLocationDirection? = nil,
        now: Date = .now
    ) -> Bool {
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= mode.maximumAcceptedAccuracy,
              location.timestamp >= trackingStartedAt.addingTimeInterval(-1),
              location.timestamp <= now.addingTimeInterval(60),
              CLLocationCoordinate2DIsValid(location.coordinate)
        else { return false }

        guard let previous else { return true }
        let interval = location.timestamp.timeIntervalSince(previous.timestamp)
        guard interval > 0 else { return false }

        let distance = previous.location.distance(from: location)
        guard distance >= 5 else { return false }

        if interval < 10 * 60, distance / interval > 100 {
            return false
        }

        let previousAccuracy = previous.horizontalAccuracy >= 0 ? previous.horizontalAccuracy : 0
        let noiseRadius = max(previousAccuracy, location.horizontalAccuracy) * 0.5
        let normalDistance = max(mode.minimumRecordingDistance, noiseRadius)
        if distance >= normalDistance {
            return true
        }

        let timedDistance = max(mode.minimumTimedRecordingDistance, noiseRadius)
        if interval >= mode.maximumRecordingInterval, distance >= timedDistance {
            return true
        }

        let turnDistance = max(mode.minimumTurnDistance, noiseRadius)
        if distance >= turnDistance,
           isMeaningfulTurn(
               from: previous,
               to: location,
               observedTurnDegrees: observedTurnDegrees,
               threshold: mode.turnThresholdDegrees
           ) {
            return true
        }

        return false
    }

    /// Returns a stable center only when recent good fixes prove the device has remained in one
    /// place for the complete idle interval. A robust median center plus a high inlier fraction
    /// prevents one or two GPS spikes from keeping Balanced awake forever, while the first/last
    /// cluster drift check prevents a slowly translating path from being mistaken for jitter.
    static func idleMonitorCenter(
        for locations: [CLLocation],
        mode: TrackingMode,
        now: Date = .now
    ) -> CLLocationCoordinate2D? {
        guard mode.usesSpatialIdleDetection else { return nil }

        let usable = locations
            .filter {
                $0.horizontalAccuracy >= 0
                    && $0.horizontalAccuracy <= mode.idleDetectionMaximumAccuracy
                    && $0.timestamp <= now.addingTimeInterval(60)
                    && CLLocationCoordinate2DIsValid($0.coordinate)
            }
            .sorted { $0.timestamp < $1.timestamp }

        guard let newest = usable.last,
              now.timeIntervalSince(newest.timestamp) <= 90 else { return nil }

        let cutoff = newest.timestamp.addingTimeInterval(-mode.idleDetectionInterval)
        let window = usable.filter { $0.timestamp >= cutoff }
        guard window.count >= mode.minimumIdleSamples,
              let oldest = window.first,
              newest.timestamp.timeIntervalSince(oldest.timestamp) >= mode.idleDetectionInterval,
              let center = medianCoordinate(of: window) else {
            return nil
        }

        let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let inlierCount = window.reduce(into: 0) { count, location in
            if centerLocation.distance(from: location) <= mode.idleDetectionRadius {
                count += 1
            }
        }
        let requiredInliers = Int(ceil(Double(window.count) * mode.idleDetectionRequiredFraction))
        guard inlierCount >= requiredInliers else { return nil }

        let clusterCount = max(3, window.count / 4)
        guard let earlyCenter = medianCoordinate(of: Array(window.prefix(clusterCount))),
              let lateCenter = medianCoordinate(of: Array(window.suffix(clusterCount))) else {
            return nil
        }
        let drift = CLLocation(latitude: earlyCenter.latitude, longitude: earlyCenter.longitude)
            .distance(from: CLLocation(latitude: lateCenter.latitude, longitude: lateCenter.longitude))
        guard drift <= mode.idleDetectionMaximumCenterDrift else { return nil }

        return center
    }

    /// Bearing of the path segment in degrees clockwise from true north.
    static func bearing(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> CLLocationDirection {
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let deltaLongitude = (end.longitude - start.longitude) * .pi / 180
        let y = sin(deltaLongitude) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLongitude)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    static func headingDifference(_ first: CLLocationDirection, _ second: CLLocationDirection) -> CLLocationDirection {
        let difference = abs(first - second).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
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

    private static func isMeaningfulTurn(
        from previous: TrackPoint,
        to location: CLLocation,
        observedTurnDegrees: CLLocationDirection?,
        threshold: CLLocationDirection
    ) -> Bool {
        if let observedTurnDegrees, observedTurnDegrees >= threshold {
            return true
        }

        guard previous.course >= 0, location.course >= 0 else { return false }
        if location.speed >= 0, location.speed < 0.5 { return false }
        return headingDifference(previous.course, location.course) >= threshold
    }

    private static func medianCoordinate(of locations: [CLLocation]) -> CLLocationCoordinate2D? {
        guard !locations.isEmpty else { return nil }
        let latitudes = locations.map(\.coordinate.latitude).sorted()
        let longitudes = locations.map(\.coordinate.longitude).sorted()
        return CLLocationCoordinate2D(
            latitude: median(of: latitudes),
            longitude: median(of: longitudes)
        )
    }

    private static func median(of values: [Double]) -> Double {
        let middle = values.count / 2
        if values.count.isMultiple(of: 2) {
            return (values[middle - 1] + values[middle]) / 2
        }
        return values[middle]
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
