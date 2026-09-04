import CoreLocation

enum MotionActivityKind: String, Equatable {
    case stationary
    case walking
    case running
    case cycling
    case automotive
    case unknown

    static func resolve(
        stationary: Bool,
        walking: Bool,
        running: Bool,
        cycling: Bool,
        automotive: Bool
    ) -> MotionActivityKind {
        if automotive { return .automotive }
        if cycling { return .cycling }
        if running { return .running }
        if walking { return .walking }
        if stationary { return .stationary }
        return .unknown
    }

    var label: String {
        switch self {
        case .stationary: "静止"
        case .walking: "步行"
        case .running: "跑步"
        case .cycling: "骑行"
        case .automotive: "驾车"
        case .unknown: "未知"
        }
    }

    var isMoving: Bool {
        switch self {
        case .walking, .running, .cycling, .automotive: true
        case .stationary, .unknown: false
        }
    }

    var locationActivityType: CLActivityType {
        switch self {
        case .automotive: .automotiveNavigation
        case .walking, .running, .cycling: .fitness
        case .stationary, .unknown: .other
        }
    }
}

enum TrackingMode: String, CaseIterable, Codable, Identifiable {
    case eco
    case balanced
    case precise
    case workout

    var id: String { rawValue }

    var title: String {
        switch self {
        case .eco: "极省电"
        case .balanced: "均衡"
        case .precise: "精确"
        case .workout: "运动"
        }
    }

    var subtitle: String {
        switch self {
        case .eco: "运动识别 + 高质量定位约 100 米触发，静止后低功耗守候"
        case .balanced: "运动识别辅助休眠，自适应保留约 35 米级轨迹"
        case .precise: "保持及时后台更新，约 20 米级保存，轨迹更完整"
        case .workout: "保持及时健身级后台更新，优先保留完整运动轨迹"
        }
    }

    var symbol: String {
        switch self {
        case .eco: "leaf.fill"
        case .balanced: "scale.3d"
        case .precise: "location.fill"
        case .workout: "figure.run"
        }
    }

    var engineLabel: String {
        usesDistanceFilteredStandardUpdates ? "iOS 标准定位" : "iOS Live Updates"
    }

    var usesDistanceFilteredStandardUpdates: Bool { self == .eco }
    var usesMotionActivity: Bool { self == .eco || self == .balanced }

    var standardDesiredAccuracy: CLLocationAccuracy { kCLLocationAccuracyNearestTenMeters }
    var standardDistanceFilter: CLLocationDistance { self == .eco ? 100 : kCLDistanceFilterNone }

    var liveConfiguration: CLLocationUpdate.LiveConfiguration {
        switch self {
        case .eco, .balanced: .default
        case .precise: .otherNavigation
        case .workout: .fitness
        }
    }

    var requiresTimelyBackgroundDelivery: Bool { self == .precise || self == .workout }
    var usesIdleMonitoring: Bool { self == .eco || self == .balanced }
    var usesSpatialIdleDetection: Bool { self == .balanced }

    var idleDetectionInterval: TimeInterval {
        switch self {
        case .balanced: 5 * 60
        case .eco, .precise, .workout: .infinity
        }
    }

    var idleDetectionRadius: CLLocationDistance {
        switch self {
        case .balanced: 30
        case .eco, .precise, .workout: 0
        }
    }

    var idleDetectionMaximumAccuracy: CLLocationAccuracy {
        switch self {
        case .balanced: 40
        case .eco, .precise, .workout: 0
        }
    }

    var motionAssistedIdleInterval: TimeInterval { self == .balanced ? 90 : .infinity }
    var motionAssistedMinimumIdleSamples: Int { self == .balanced ? 6 : .max }
    var idleDetectionRequiredFraction: Double { self == .balanced ? 0.90 : 1 }
    var idleDetectionMaximumCenterDrift: CLLocationDistance { self == .balanced ? 20 : 0 }

    var idleMonitorRadius: CLLocationDistance {
        switch self {
        case .eco: 50
        case .balanced: 60
        case .precise, .workout: 0
        }
    }

    var minimumIdleSamples: Int {
        switch self {
        case .balanced: 12
        case .eco, .precise, .workout: .max
        }
    }

    var maximumAcceptedAccuracy: CLLocationAccuracy {
        switch self {
        case .eco: 30
        case .balanced: 80
        case .precise: 65
        case .workout: 50
        }
    }

    var minimumRecordingDistance: CLLocationDistance {
        switch self {
        case .eco: 10
        case .balanced: 35
        case .precise: 20
        case .workout: 8
        }
    }

    var maximumRecordingInterval: TimeInterval {
        switch self {
        case .eco: 5 * 60
        case .balanced: 60
        case .precise: 45
        case .workout: 20
        }
    }

    var minimumTimedRecordingDistance: CLLocationDistance {
        switch self {
        case .eco: 10
        case .balanced: 12
        case .precise: 10
        case .workout: 5
        }
    }

    var minimumTurnDistance: CLLocationDistance {
        switch self {
        case .eco: 10
        case .balanced: 12
        case .precise: 10
        case .workout: 6
        }
    }

    var turnThresholdDegrees: CLLocationDirection {
        switch self {
        case .eco: 50
        case .balanced: 35
        case .precise: 30
        case .workout: 25
        }
    }
}
