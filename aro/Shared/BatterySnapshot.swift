import Foundation

struct BatterySnapshot: Codable, Equatable, Sendable {
    let level: Int
    let state: BatteryChargeState
    let updatedAt: Date
    let deviceName: String

    init(level: Int, state: BatteryChargeState, updatedAt: Date = .now, deviceName: String = "Apple Watch") {
        self.level = min(max(level, 0), 100)
        self.state = state
        self.updatedAt = updatedAt
        self.deviceName = deviceName
    }

    init?(payload: [String: Any]) {
        guard let rawLevel = payload[PayloadKey.level] as? NSNumber else { return nil }

        let rawState = payload[PayloadKey.state] as? String ?? BatteryChargeState.unknown.rawValue
        let timestamp = (payload[PayloadKey.updatedAt] as? NSNumber)?.doubleValue ?? Date.now.timeIntervalSince1970

        self.init(
            level: rawLevel.intValue,
            state: BatteryChargeState(rawValue: rawState) ?? .unknown,
            updatedAt: Date(timeIntervalSince1970: timestamp),
            deviceName: payload[PayloadKey.deviceName] as? String ?? "Apple Watch"
        )
    }

    var payload: [String: Any] {
        [
            PayloadKey.level: level,
            PayloadKey.state: state.rawValue,
            PayloadKey.updatedAt: updatedAt.timeIntervalSince1970,
            PayloadKey.deviceName: deviceName
        ]
    }
}

struct TrackComplicationPoint: Codable, Equatable, Sendable {
    let x: Double
    let y: Double

    init(x: Double, y: Double) {
        self.x = min(max(x, 0), 1)
        self.y = min(max(y, 0), 1)
    }
}

struct TrackComplicationSegment: Codable, Equatable, Sendable {
    let points: [TrackComplicationPoint]
}

struct TrackComplicationSnapshot: Codable, Equatable, Sendable {
    let distanceMeters: Double
    let segments: [TrackComplicationSegment]
    let updatedAt: Date
    let dayStart: Date

    init(
        distanceMeters: Double,
        segments: [TrackComplicationSegment],
        updatedAt: Date = .now,
        dayStart: Date
    ) {
        self.distanceMeters = max(0, distanceMeters)
        self.segments = segments.filter { !$0.points.isEmpty }
        self.updatedAt = updatedAt
        self.dayStart = dayStart
    }

    init?(payload: [String: Any]) {
        guard let data = payload[PayloadKey.trackComplicationSnapshot] as? Data,
              let snapshot = try? JSONDecoder().decode(Self.self, from: data) else {
            return nil
        }
        self = snapshot
    }

    var payload: [String: Any] {
        guard let data = try? JSONEncoder().encode(self) else { return [:] }
        return [PayloadKey.trackComplicationSnapshot: data]
    }
}

enum BatteryChargeState: String, Codable, Sendable {
    case unknown
    case unplugged
    case charging
    case full

    var label: String {
        switch self {
        case .unknown: "未知"
        case .unplugged: "使用中"
        case .charging: "正在充电"
        case .full: "已充满"
        }
    }

    var symbolName: String {
        switch self {
        case .unknown: "battery.0percent"
        case .unplugged: "battery.50percent"
        case .charging: "battery.75percent"
        case .full: "battery.100percent.bolt"
        }
    }
}

enum PayloadKey {
    static let level = "batteryLevel"
    static let state = "batteryState"
    static let updatedAt = "updatedAt"
    static let deviceName = "deviceName"
    static let trackComplicationSnapshot = "trackComplicationSnapshot"
    static let command = "command"
    static let requestBattery = "requestBattery"
}
