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
        case .eco: "事件唤醒后短暂精确定位，最低功耗"
        case .balanced: "约 75 米间隔，高质量定位，推荐日常使用"
        case .precise: "约 25 米间隔，轨迹更完整"
        case .workout: "高精度连续记录，耗电较高"
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

    var desiredAccuracy: CLLocationAccuracy {
        switch self {
        case .eco, .balanced, .precise: kCLLocationAccuracyNearestTenMeters
        case .workout: kCLLocationAccuracyBest
        }
    }

    var distanceFilter: CLLocationDistance {
        switch self {
        case .eco: 500
        case .balanced: 75
        case .precise: 25
        case .workout: 8
        }
    }

    var maximumAcceptedAccuracy: CLLocationAccuracy {
        switch self {
        case .eco: 150
        case .balanced: 100
        case .precise: 100
        case .workout: 65
        }
    }

    var usesContinuousUpdates: Bool { self != .eco }
    var allowsAutomaticPausing: Bool { self != .workout }
}
