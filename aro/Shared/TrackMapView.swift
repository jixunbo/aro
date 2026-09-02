import MapKit
import SwiftUI

struct TrackMapView: UIViewRepresentable {
    let points: [TrackPoint]
    var showsUserLocation = false
    var overview = false

    private static let maximumPointMarkers = 500

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.showsCompass = true
        map.showsScale = false
        map.showsUserLocation = showsUserLocation
        map.pointOfInterestFilter = .excludingAll
        map.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: overview ? .realistic : .flat)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.inspectRoute(_:)))
        tap.delegate = context.coordinator
        tap.cancelsTouchesInView = false
        map.addGestureRecognizer(tap)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.showsUserLocation = showsUserLocation
        let signature = points.last?.id ?? Int64(points.count)
        guard context.coordinator.lastSignature != signature || context.coordinator.lastCount != points.count else { return }
        context.coordinator.lastSignature = signature
        context.coordinator.lastCount = points.count
        map.removeOverlays(map.overlays)
        let previousPointAnnotations = map.annotations.compactMap { $0 as? TrackPointAnnotation }
        map.removeAnnotations(previousPointAnnotations)
        context.coordinator.clearInspection(on: map)

        let segments = makeSegments(points)
        let displayedPoints = segments.flatMap { $0 }
        context.coordinator.displayedPoints = displayedPoints
        context.coordinator.overview = overview
        let markerPoints = TrackMath.downsample(displayedPoints, maximum: Self.maximumPointMarkers)
        map.addAnnotations(markerPoints.map(TrackPointAnnotation.init))
        for segment in segments where segment.count > 1 {
            let polyline = MKPolyline(coordinates: segment.map(\.coordinate), count: segment.count)
            map.addOverlay(polyline)
        }

        guard !map.overlays.isEmpty else { return }
        let rect = map.overlays.reduce(MKMapRect.null) { $0.union($1.boundingMapRect) }
        map.setVisibleMapRect(
            rect,
            edgePadding: UIEdgeInsets(top: 70, left: 44, bottom: 70, right: 44),
            animated: context.coordinator.hasPositioned
        )
        context.coordinator.hasPositioned = true
    }

    private func makeSegments(_ source: [TrackPoint]) -> [[TrackPoint]] {
        guard !source.isEmpty else { return [] }
        var result: [[TrackPoint]] = [[source[0]]]
        for point in source.dropFirst() {
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

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var lastSignature: Int64 = -1
        var lastCount = -1
        var hasPositioned = false
        var displayedPoints: [TrackPoint] = []
        var overview = false
        private var inspectedAnnotation: InspectedTrackPointAnnotation?

        @objc func inspectRoute(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let map = recognizer.view as? MKMapView else { return }
            let tappedPoint = recognizer.location(in: map)
            let tolerance: CGFloat = 26
            let toleranceSquared = tolerance * tolerance
            var nearestPoint: TrackPoint?
            var nearestDistanceSquared = toleranceSquared

            for point in displayedPoints {
                let screenPoint = map.convert(point.coordinate, toPointTo: map)
                let horizontalDistance = screenPoint.x - tappedPoint.x
                let verticalDistance = screenPoint.y - tappedPoint.y
                guard abs(horizontalDistance) <= tolerance, abs(verticalDistance) <= tolerance else { continue }
                let distanceSquared = horizontalDistance * horizontalDistance + verticalDistance * verticalDistance
                if distanceSquared <= nearestDistanceSquared {
                    nearestDistanceSquared = distanceSquared
                    nearestPoint = point
                }
            }

            guard let nearestPoint else {
                clearInspection(on: map)
                return
            }
            showInspection(for: nearestPoint, on: map)
        }

        func clearInspection(on map: MKMapView) {
            guard let inspectedAnnotation else { return }
            map.removeAnnotation(inspectedAnnotation)
            self.inspectedAnnotation = nil
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKGradientPolylineRenderer(polyline: polyline)
            renderer.setColors([.systemCyan, .systemBlue, .systemPurple], locations: [0, 0.55, 1])
            renderer.lineWidth = 5
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is TrackPointAnnotation {
                let identifier = "track-point"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                view.annotation = annotation
                view.frame = CGRect(x: 0, y: 0, width: 8, height: 8)
                view.layer.cornerRadius = 4
                view.layer.borderWidth = 1
                view.layer.borderColor = UIColor.systemCyan.withAlphaComponent(0.9).cgColor
                view.backgroundColor = UIColor.white.withAlphaComponent(0.9)
                view.canShowCallout = false
                view.collisionMode = .none
                view.displayPriority = .required
                return view
            }

            guard annotation is InspectedTrackPointAnnotation else { return nil }
            let identifier = "inspected-track-point"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            view.canShowCallout = true
            view.markerTintColor = .systemBlue
            view.glyphImage = UIImage(systemName: "clock.fill")
            return view
        }

        private func showInspection(for point: TrackPoint, on map: MKMapView) {
            clearInspection(on: map)

            var details: [String] = []
            if !overview {
                details.append(Self.dateFormatter.string(from: point.timestamp))
            }
            if point.horizontalAccuracy > 0 {
                details.append("精度 ±\(Int(point.horizontalAccuracy.rounded())) m")
            }
            if let activity = point.activity, !activity.isEmpty, activity != "未知" {
                details.append(activity)
            }

            let annotation = InspectedTrackPointAnnotation(
                coordinate: point.coordinate,
                title: (overview ? Self.dateTimeFormatter : Self.timeFormatter).string(from: point.timestamp),
                subtitle: details.isEmpty ? nil : details.joined(separator: " · ")
            )
            inspectedAnnotation = annotation
            map.addAnnotation(annotation)
            map.selectAnnotation(annotation, animated: true)
        }

        private static let timeFormatter: DateFormatter = formatter("HH:mm:ss")
        private static let dateFormatter: DateFormatter = formatter("yyyy年M月d日")
        private static let dateTimeFormatter: DateFormatter = formatter("yyyy年M月d日 HH:mm:ss")

        private static func formatter(_ format: String) -> DateFormatter {
            let formatter = DateFormatter()
            formatter.calendar = .autoupdatingCurrent
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.timeZone = .autoupdatingCurrent
            formatter.dateFormat = format
            return formatter
        }
    }
}

private final class TrackPointAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D

    init(point: TrackPoint) {
        coordinate = point.coordinate
        super.init()
    }
}

private final class InspectedTrackPointAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?

    init(coordinate: CLLocationCoordinate2D, title: String, subtitle: String?) {
        self.coordinate = coordinate
        self.title = title
        self.subtitle = subtitle
    }
}
