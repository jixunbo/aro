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
        case .eco: "高质量定位约 100 米触发，静止后切换低功耗监控"
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

    /// Eco intentionally uses the Standard location service because distanceFilter controls
    /// location generation at the Core Location layer. Other modes use iOS 26 Live Updates.
    var usesDistanceFilteredStandardUpdates: Bool {
        self == .eco
    }

    var standardDesiredAccuracy: CLLocationAccuracy {
        kCLLocationAccuracyNearestTenMeters
    }

    var standardDistanceFilter: CLLocationDistance {
        self == .eco ? 100 : kCLDistanceFilterNone
    }

    var liveConfiguration: CLLocationUpdate.LiveConfiguration {
        switch self {
        case .eco, .balanced: .default
        case .precise: .otherNavigation
        case .workout: .fitness
        }
    }

    /// Balanced intentionally lets iOS suspend the process and queue/relaunch delivery.
    /// Precise/Workout opt into timely background execution through CLBackgroundActivitySession.
    /// Eco uses distance-filtered Standard location updates and does not retain a background session.
    var requiresTimelyBackgroundDelivery: Bool {
        self == .precise || self == .workout
    }

    /// Eco/Balanced transition to a persistent CLMonitor geofence while idle. Eco normally gets
    /// there through CLLocationManager automatic pause; Balanced proves spatial stability itself.
    var usesIdleMonitoring: Bool {
        self == .eco || self == .balanced
    }

    var usesSpatialIdleDetection: Bool {
        self == .balanced
    }

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

    /// A small minority of GPS outliers must not keep Balanced awake forever.
    var idleDetectionRequiredFraction: Double {
        self == .balanced ? 0.90 : 1
    }

    /// Prevent a slowly translating cluster from being mistaken for stationary GPS noise.
    var idleDetectionMaximumCenterDrift: CLLocationDistance {
        self == .balanced ? 20 : 0
    }

    var idleMonitorRadius: CLLocationDistance {
        switch self {
        case .eco: 100
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

    /// Accuracy is a storage-quality gate, not a request to turn GPS hardware on.
    var maximumAcceptedAccuracy: CLLocationAccuracy {
        switch self {
        case .eco: 50
        case .balanced: 80
        case .precise: 65
        case .workout: 50
        }
    }

    /// Normal movement distance sufficient to persist another delivered point. Eco's hardware
    /// cadence is already ~100 m, so its storage threshold stays lower to keep useful extra fixes.
    var minimumRecordingDistance: CLLocationDistance {
        switch self {
        case .eco: 25
        case .balanced: 35
        case .precise: 20
        case .workout: 8
        }
    }

    /// Preserve a useful point even on slow movement if the previous saved point is old.
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
        case .eco: 20
        case .balanced: 12
        case .precise: 10
        case .workout: 5
        }
    }

    /// A turn can be worth keeping before the normal distance threshold is reached.
    var minimumTurnDistance: CLLocationDistance {
        switch self {
        case .eco: 25
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
