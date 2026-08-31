import MapKit
import SwiftUI

struct TrackMapView: UIViewRepresentable {
    let points: [TrackPoint]
    var showsUserLocation = false
    var overview = false

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.showsCompass = true
        map.showsScale = false
        map.showsUserLocation = showsUserLocation
        map.pointOfInterestFilter = .excludingAll
        map.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: overview ? .realistic : .flat)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.showsUserLocation = showsUserLocation
        let signature = points.last?.id ?? Int64(points.count)
        guard context.coordinator.lastSignature != signature || context.coordinator.lastCount != points.count else { return }
        context.coordinator.lastSignature = signature
        context.coordinator.lastCount = points.count
        map.removeOverlays(map.overlays)

        let segments = makeSegments(points)
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

    final class Coordinator: NSObject, MKMapViewDelegate {
        var lastSignature: Int64 = -1
        var lastCount = -1
        var hasPositioned = false

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKGradientPolylineRenderer(polyline: polyline)
            renderer.setColors([.systemCyan, .systemBlue, .systemPurple], locations: [0, 0.55, 1])
            renderer.lineWidth = 5
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }
    }
}
