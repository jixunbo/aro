import CoreLocation

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
        case .eco: "允许系统后台挂起，移动时稀疏保存"
        case .balanced: "允许系统后台挂起，自适应保留转弯与约 55 米级轨迹"
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

    var liveConfiguration: CLLocationUpdate.LiveConfiguration {
        switch self {
        case .eco, .balanced: .default
        case .precise: .otherNavigation
        case .workout: .fitness
        }
    }

    /// Balanced/Eco intentionally let iOS suspend the process and queue/relaunch delivery.
    /// Precise/Workout opt into timely background execution through CLBackgroundActivitySession.
    var requiresTimelyBackgroundDelivery: Bool {
        self == .precise || self == .workout
    }

    /// Accuracy is a storage-quality gate, not a request to turn GPS hardware on.
    var maximumAcceptedAccuracy: CLLocationAccuracy {
        switch self {
        case .eco: 120
        case .balanced: 80
        case .precise: 65
        case .workout: 50
        }
    }

    /// Normal movement distance that is sufficient to persist another point.
    var minimumRecordingDistance: CLLocationDistance {
        switch self {
        case .eco: 120
        case .balanced: 55
        case .precise: 20
        case .workout: 8
        }
    }

    /// Preserve a useful point even on slow movement if the previous saved point is old.
    var maximumRecordingInterval: TimeInterval {
        switch self {
        case .eco: 4 * 60
        case .balanced: 2 * 60
        case .precise: 45
        case .workout: 20
        }
    }

    var minimumTimedRecordingDistance: CLLocationDistance {
        switch self {
        case .eco: 40
        case .balanced: 20
        case .precise: 10
        case .workout: 5
        }
    }

    /// A turn can be worth keeping before the normal distance threshold is reached.
    var minimumTurnDistance: CLLocationDistance {
        switch self {
        case .eco: 45
        case .balanced: 18
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
