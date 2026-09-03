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
        case .eco: "静止后切换低功耗监控，移动时稀疏保存"
        case .balanced: "静止后切换低功耗监控，自适应保留约 35 米级轨迹"
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

    /// Eco/Balanced can transition from Live Updates to a persistent CLMonitor geofence after
    /// several minutes of high-quality, spatially stable fixes. Precise/Workout stay live.
    var usesIdleMonitoring: Bool {
        self == .eco || self == .balanced
    }

    var idleDetectionInterval: TimeInterval {
        switch self {
        case .eco: 3 * 60
        case .balanced: 5 * 60
        case .precise, .workout: .infinity
        }
    }

    var idleDetectionRadius: CLLocationDistance {
        switch self {
        case .eco: 45
        case .balanced: 30
        case .precise, .workout: 0
        }
    }

    var idleDetectionMaximumAccuracy: CLLocationAccuracy {
        switch self {
        case .eco: 60
        case .balanced: 40
        case .precise, .workout: 0
        }
    }

    var idleMonitorRadius: CLLocationDistance {
        switch self {
        case .eco: 120
        case .balanced: 60
        case .precise, .workout: 0
        }
    }

    var minimumIdleSamples: Int {
        switch self {
        case .eco, .balanced: 8
        case .precise, .workout: .max
        }
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
        case .balanced: 35
        case .precise: 20
        case .workout: 8
        }
    }

    /// Preserve a useful point even on slow movement if the previous saved point is old.
    var maximumRecordingInterval: TimeInterval {
        switch self {
        case .eco: 4 * 60
        case .balanced: 60
        case .precise: 45
        case .workout: 20
        }
    }

    var minimumTimedRecordingDistance: CLLocationDistance {
        switch self {
        case .eco: 40
        case .balanced: 12
        case .precise: 10
        case .workout: 5
        }
    }

    /// A turn can be worth keeping before the normal distance threshold is reached.
    var minimumTurnDistance: CLLocationDistance {
        switch self {
        case .eco: 45
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
