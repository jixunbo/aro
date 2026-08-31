import Foundation

enum TrackExport {
    static func gpx(points: [TrackPoint], name: String) -> Data {
        let formatter = ISO8601DateFormatter()
        let escapedName = escapeXML(name)
        let body = points.map { point in
            let elevation = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), point.altitude)
            return "<trkpt lat=\"\(point.latitude)\" lon=\"\(point.longitude)\"><ele>\(elevation)</ele><time>\(formatter.string(from: point.timestamp))</time></trkpt>"
        }.joined(separator: "\n")

        let value = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="LifePath" xmlns="http://www.topografix.com/GPX/1/1">
          <trk><name>\(escapedName)</name><trkseg>
        \(body)
          </trkseg></trk>
        </gpx>
        """
        return Data(value.utf8)
    }

    static func geoJSON(points: [TrackPoint], name: String) -> Data {
        let coordinates = points.map { [$0.longitude, $0.latitude, $0.altitude] }
        let object: [String: Any] = [
            "type": "FeatureCollection",
            "features": [[
                "type": "Feature",
                "properties": ["name": name],
                "geometry": ["type": "LineString", "coordinates": coordinates]
            ]]
        ]
        return (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    private static func escapeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
