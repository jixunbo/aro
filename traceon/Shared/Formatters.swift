import Foundation

enum AppFormatters {
    static let distance: MeasurementFormatter = {
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        formatter.numberFormatter.maximumFractionDigits = 1
        return formatter
    }()

    static func distance(_ meters: Double) -> String {
        if meters >= 1_000 {
            return distance.string(from: Measurement(value: meters / 1_000, unit: UnitLength.kilometers))
        }
        return distance.string(from: Measurement(value: meters, unit: UnitLength.meters))
    }

    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}

