import Combine
import CoreLocation
import CoreMotion
import Foundation
import UIKit

@MainActor
final class LocationService: NSObject, ObservableObject {
    static let shared = LocationService()

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var accuracyAuthorization: CLAccuracyAuthorization
    @Published private(set) var lastRecordedAt: Date?
    @Published private(set) var lastSource: String?
    @Published private(set) var currentActivity = "未知"
    @Published private(set) var lastError: String?
    @Published var isTrackingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isTrackingEnabled, forKey: Keys.enabled)
            isTrackingEnabled ? startServices() : stopServices()
        }
    }
    @Published var mode: TrackingMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Keys.mode)
            configureDetailManager()
            if isTrackingEnabled {
                restartDetailUpdates()
                stopMotionUpdates()
                if mode != .eco { startMotionUpdates() }
            }
        }
    }

    private let wakeManager = CLLocationManager()
    private let detailManager = CLLocationManager()
    private let motionManager = CMMotionActivityManager()
    private var latestAcceptedPoint: TrackPoint?
    private var isStarted = false
    private var detailUpdatesPaused = false
    private var isMotionUpdating = false

    private enum Keys {
        static let enabled = "tracking.enabled"
        static let mode = "tracking.mode"
    }

    private override init() {
        let savedMode = UserDefaults.standard.string(forKey: Keys.mode).flatMap(TrackingMode.init(rawValue:)) ?? .balanced
        mode = savedMode
        isTrackingEnabled = UserDefaults.standard.object(forKey: Keys.enabled) as? Bool ?? false
        authorizationStatus = wakeManager.authorizationStatus
        accuracyAuthorization = wakeManager.accuracyAuthorization
        latestAcceptedPoint = TrackDatabase.shared.latestPoint()
        lastRecordedAt = latestAcceptedPoint?.timestamp
        lastSource = latestAcceptedPoint?.source
        super.init()

        wakeManager.delegate = self
        detailManager.delegate = self
        configureDetailManager()
    }

    func handleApplicationLaunch(locationTriggered: Bool) {
        authorizationStatus = wakeManager.authorizationStatus
        accuracyAuthorization = wakeManager.accuracyAuthorization
        if isTrackingEnabled, authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            startServices()
        }
        if locationTriggered, isTrackingEnabled {
            startLowPowerMonitoring()
        }
    }

    func requestWhenInUseAuthorization() {
        wakeManager.requestWhenInUseAuthorization()
    }

    func requestAlwaysAuthorization() {
        guard authorizationStatus == .authorizedWhenInUse else { return }
        wakeManager.requestAlwaysAuthorization()
    }

    func requestTemporaryFullAccuracy() {
        guard accuracyAuthorization == .reducedAccuracy else { return }
        wakeManager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "TrackRecording")
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    var hasAlwaysAuthorization: Bool { authorizationStatus == .authorizedAlways }

    var authorizationLabel: String {
        switch authorizationStatus {
        case .notDetermined: "尚未授权"
        case .restricted: "受系统限制"
        case .denied: "已拒绝"
        case .authorizedWhenInUse: "使用 App 时"
        case .authorizedAlways: "始终"
        @unknown default: "未知"
        }
    }

    private func startServices() {
        guard CLLocationManager.locationServicesEnabled(),
              authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else { return }
        guard !isStarted else { return }
        isStarted = true
        startLowPowerMonitoring()
        restartDetailUpdates()
        if mode != .eco { startMotionUpdates() }
    }

    private func startLowPowerMonitoring() {
        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            wakeManager.startMonitoringSignificantLocationChanges()
        }
        wakeManager.startMonitoringVisits()
    }

    private func stopServices() {
        isStarted = false
        detailUpdatesPaused = false
        wakeManager.stopMonitoringSignificantLocationChanges()
        wakeManager.stopMonitoringVisits()
        detailManager.stopUpdatingLocation()
        stopMotionUpdates()
    }

    private func configureDetailManager() {
        detailManager.desiredAccuracy = mode.desiredAccuracy
        detailManager.distanceFilter = mode.distanceFilter
        detailManager.pausesLocationUpdatesAutomatically = mode.allowsAutomaticPausing
        detailManager.activityType = mode == .workout ? .fitness : .other
        detailManager.showsBackgroundLocationIndicator = false
        detailManager.allowsBackgroundLocationUpdates = true
    }

    private func restartDetailUpdates() {
        detailManager.stopUpdatingLocation()
        detailUpdatesPaused = false
        configureDetailManager()
        if mode.usesContinuousUpdates,
           authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            detailManager.startUpdatingLocation()
        }
    }

    private func resumeDetailUpdatesAfterLowPowerWake() {
        guard detailUpdatesPaused,
              isTrackingEnabled,
              mode.usesContinuousUpdates,
              authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse
        else { return }

        detailManager.stopUpdatingLocation()
        detailUpdatesPaused = false
        configureDetailManager()
        detailManager.startUpdatingLocation()
        if mode != .eco { startMotionUpdates() }
    }

    private func startMotionUpdates() {
        guard !isMotionUpdating, CMMotionActivityManager.isActivityAvailable() else { return }
        isMotionUpdating = true
        motionManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self, let activity, self.isTrackingEnabled, self.mode != .eco else { return }
            self.currentActivity = Self.label(for: activity)
            if activity.automotive {
                self.detailManager.activityType = .automotiveNavigation
            } else if activity.walking || activity.running || activity.cycling {
                self.detailManager.activityType = .fitness
            } else {
                self.detailManager.activityType = .other
            }
        }
    }

    private func stopMotionUpdates() {
        guard isMotionUpdating else { return }
        motionManager.stopActivityUpdates()
        isMotionUpdating = false
    }

    private func consume(_ locations: [CLLocation], source: String) {
        var insertedAny = false
        for location in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
            let ageLimit: TimeInterval = source == "visit" ? 7 * 24 * 60 * 60 : (source == "significant" ? 6 * 60 * 60 : 180)
            let acceptanceMode: TrackingMode = source == "visit" ? .eco : mode
            let previousForFilter = source == "visit" ? nil : latestAcceptedPoint
            guard TrackMath.shouldAccept(location, after: previousForFilter, mode: acceptanceMode, maximumAge: ageLimit) else { continue }
            let point = TrackPoint(location: location, source: source, activity: currentActivity)
            let rowID = TrackDatabase.shared.insert(point)
            guard rowID > 0 else { continue }
            let recordedPoint = TrackPoint(
                id: rowID,
                timestamp: point.timestamp,
                latitude: point.latitude,
                longitude: point.longitude,
                altitude: point.altitude,
                horizontalAccuracy: point.horizontalAccuracy,
                speed: point.speed,
                course: point.course,
                source: point.source,
                activity: point.activity
            )
            if latestAcceptedPoint == nil || recordedPoint.timestamp >= latestAcceptedPoint!.timestamp {
                latestAcceptedPoint = recordedPoint
                lastRecordedAt = point.timestamp
                lastSource = source
            }
            insertedAny = true
        }
        if insertedAny {
            TrackRepository.shared.didInsertPoint()
        }
    }

    private static func label(for activity: CMMotionActivity) -> String {
        if activity.automotive { return "驾车" }
        if activity.cycling { return "骑行" }
        if activity.running { return "跑步" }
        if activity.walking { return "步行" }
        if activity.stationary { return "静止" }
        return "未知"
    }

    var sourceLabel: String {
        switch lastSource {
        case "standard": "标准定位"
        case "significant": "显著位置变化"
        case "visit": "到访地点"
        case "import": "文件导入"
        case .some(let value): value
        case nil: "暂无"
        }
    }
}

extension LocationService: @preconcurrency CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
        guard manager === wakeManager else { return }
        if isTrackingEnabled,
           authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            isStarted = false
            startServices()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        consume(locations, source: manager === wakeManager ? "significant" : "standard")
        if manager === wakeManager {
            resumeDetailUpdatesAfterLowPowerWake()
        }
    }

    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        let isDeparture = visit.departureDate != .distantFuture
        let timestamp = isDeparture ? visit.departureDate : visit.arrivalDate
        let location = CLLocation(
            coordinate: visit.coordinate,
            altitude: 0,
            horizontalAccuracy: visit.horizontalAccuracy,
            verticalAccuracy: -1,
            timestamp: timestamp
        )
        consume([location], source: "visit")
        if isDeparture {
            resumeDetailUpdatesAfterLowPowerWake()
        }
    }

    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        guard manager === detailManager else { return }
        detailUpdatesPaused = true
        stopMotionUpdates()
    }

    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        guard manager === detailManager else { return }
        detailUpdatesPaused = false
        if mode != .eco { startMotionUpdates() }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let code = (error as? CLError)?.code
        if code != .locationUnknown { lastError = error.localizedDescription }
    }
}
