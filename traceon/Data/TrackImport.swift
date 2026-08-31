import CoreLocation
import Foundation

enum TrackImportError: LocalizedError {
    case unsupportedFormat
    case invalidFile
    case noPoints

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: "暂不支持这种文件格式"
        case .invalidFile: "文件内容损坏或格式不正确"
        case .noPoints: "文件中没有可导入的轨迹点"
        }
    }
}

enum TrackImport {
    static func parse(data: Data, fileExtension: String) throws -> [TrackPoint] {
        switch fileExtension.lowercased() {
        case "gpx", "xml":
            let parser = GPXTrackParser(data: data)
            guard parser.parse() else { throw parser.parserError ?? TrackImportError.invalidFile }
            guard !parser.points.isEmpty else { throw TrackImportError.noPoints }
            return parser.points
        case "geojson", "json":
            let points = try parseGeoJSON(data)
            guard !points.isEmpty else { throw TrackImportError.noPoints }
            return points
        default:
            throw TrackImportError.unsupportedFormat
        }
    }

    private static func parseGeoJSON(_ data: Data) throws -> [TrackPoint] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TrackImportError.invalidFile
        }
        let features = root["features"] as? [[String: Any]] ?? [root]
        var coordinates: [[Double]] = []
        for feature in features {
            let geometry = (feature["geometry"] as? [String: Any]) ?? feature
            guard let type = geometry["type"] as? String else { continue }
            if type == "LineString", let line = geometry["coordinates"] as? [[Double]] {
                coordinates.append(contentsOf: line)
            } else if type == "MultiLineString", let lines = geometry["coordinates"] as? [[[Double]]] {
                coordinates.append(contentsOf: lines.flatMap { $0 })
            }
        }
        let baseDate = Date()
        return coordinates.enumerated().compactMap { index, coordinate in
            guard coordinate.count >= 2,
                  (-180...180).contains(coordinate[0]),
                  (-90...90).contains(coordinate[1]) else { return nil }
            return TrackPoint(
                timestamp: baseDate.addingTimeInterval(Double(index)),
                latitude: coordinate[1],
                longitude: coordinate[0],
                altitude: coordinate.count > 2 ? coordinate[2] : 0,
                source: "import"
            )
        }
    }
}

private final class GPXTrackParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private var latitude: Double?
    private var longitude: Double?
    private var elevation: Double = 0
    private var timestamp: Date?
    private var currentElement = ""
    private var buffer = ""
    private var fallbackIndex = 0

    private(set) var points: [TrackPoint] = []
    var parserError: Error? { parser.parserError }

    init(data: Data) {
        parser = XMLParser(data: data)
        super.init()
        parser.delegate = self
    }

    func parse() -> Bool { parser.parse() }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        buffer = ""
        if elementName == "trkpt" || elementName == "rtept" || elementName == "wpt" {
            latitude = attributeDict["lat"].flatMap(Double.init)
            longitude = attributeDict["lon"].flatMap(Double.init)
            elevation = 0
            timestamp = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentElement == "ele" || currentElement == "time" { buffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if elementName == "ele" {
            elevation = Double(value) ?? 0
        } else if elementName == "time" {
            timestamp = Self.fractionalDateFormatter.date(from: value) ?? Self.dateFormatter.date(from: value)
        } else if elementName == "trkpt" || elementName == "rtept" || elementName == "wpt" {
            appendPoint()
        }
        currentElement = ""
        buffer = ""
    }

    private func appendPoint() {
        guard let latitude, let longitude,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return }
        let date = timestamp ?? Date().addingTimeInterval(Double(fallbackIndex))
        points.append(TrackPoint(
            timestamp: date,
            latitude: latitude,
            longitude: longitude,
            altitude: elevation,
            source: "import"
        ))
        fallbackIndex += 1
    }

    private static let fractionalDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let dateFormatter = ISO8601DateFormatter()
}
