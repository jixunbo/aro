import Combine
import CoreLocation
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
    @Published private(set) var engineState = "未开启"
    @Published private(set) var receivedUpdateCount = 0
    @Published private(set) var recordedUpdateCount = 0
    @Published private(set) var rejectedUpdateCount = 0
    @Published private(set) var lastHorizontalAccuracy: CLLocationAccuracy?

    @Published var isTrackingEnabled: Bool {
        didSet {
            guard isTrackingEnabled != oldValue else { return }
            UserDefaults.standard.set(isTrackingEnabled, forKey: Keys.enabled)
            if isTrackingEnabled {
                beginNewTrackingSession()
                lastError = nil
                startTrackingIfAuthorized()
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.startedAt)
                clearTrackingAnchor()
                stopTracking()
            }
        }
    }

    @Published var mode: TrackingMode {
        didSet {
            guard mode != oldValue else { return }
            UserDefaults.standard.set(mode.rawValue, forKey: Keys.mode)
            resetMovementGeometry()
            guard liveUpdatesTask != nil else { return }
            configureBackgroundDelivery()
            restartLiveUpdates()
        }
    }

    private let authorizationManager = CLLocationManager()
    private var serviceSession: CLServiceSession?
    private var backgroundActivitySession: CLBackgroundActivitySession?
    private var liveUpdatesTask: Task<Void, Never>?
    private var liveUpdatesGeneration = UUID()
    private var latestAcceptedPoint: TrackPoint?
    private var trackingStartedAt: Date
    private var lastMovementLocation: CLLocation?
    private var lastMovementBearing: CLLocationDirection?

    private enum Keys {
        static let enabled = "tracking.enabled"
        static let mode = "tracking.mode"
        static let startedAt = "tracking.startedAt"
        static let lastAcceptedSyncID = "tracking.lastAcceptedSyncID"
    }

    private override init() {
        let defaults = UserDefaults.standard
        let savedMode = defaults.string(forKey: Keys.mode).flatMap(TrackingMode.init(rawValue:)) ?? .balanced
        let savedEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? false
        let latestPoint = TrackDatabase.shared.latestPoint()
        let savedStartedAt = defaults.double(forKey: Keys.startedAt)
        let sessionStart = savedStartedAt > 0 ? Date(timeIntervalSince1970: savedStartedAt) : .now
        let savedAnchor = defaults.string(forKey: Keys.lastAcceptedSyncID)
            .flatMap { TrackDatabase.shared.point(syncID: $0) }

        mode = savedMode
        isTrackingEnabled = savedEnabled
        authorizationStatus = authorizationManager.authorizationStatus
        accuracyAuthorization = authorizationManager.accuracyAuthorization
        trackingStartedAt = sessionStart
        if let savedAnchor,
           savedAnchor.timestamp >= sessionStart.addingTimeInterval(-1),
           savedAnchor.timestamp <= Date.now.addingTimeInterval(60) {
            latestAcceptedPoint = savedAnchor
        } else {
            latestAcceptedPoint = nil
        }
        lastRecordedAt = latestPoint?.timestamp
        lastSource = latestPoint?.source

        // 1.x did not persist a modern live-update session boundary. On first 2.0 launch,
        // start a new boundary instead of treating arbitrary cached legacy fixes as queued work.
        super.init()

        authorizationManager.delegate = self
        if savedEnabled, savedStartedAt <= 0 {
            defaults.set(trackingStartedAt.timeIntervalSince1970, forKey: Keys.startedAt)
            defaults.removeObject(forKey: Keys.lastAcceptedSyncID)
            latestAcceptedPoint = nil
        }
    }

    /// Called from UIApplicationDelegate on every process launch. This is intentionally the only
    /// launch-time service bootstrap: a Core Location background relaunch can immediately rejoin
    /// the outstanding live/service sessions without also starting WatchConnectivity or CloudKit.
    func handleApplicationLaunch() {
        authorizationStatus = authorizationManager.authorizationStatus
        accuracyAuthorization = authorizationManager.accuracyAuthorization
        startTrackingIfAuthorized()
    }

    func requestWhenInUseAuthorization() {
        authorizationManager.requestWhenInUseAuthorization()
    }

    func requestAlwaysAuthorization() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .notDetermined else { return }
        authorizationManager.requestAlwaysAuthorization()
    }

    func requestTemporaryFullAccuracy() {
        guard accuracyAuthorization == .reducedAccuracy else { return }
        authorizationManager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "TrackRecording")
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

    var backgroundDeliveryLabel: String {
        mode.requiresTimelyBackgroundDelivery ? "及时后台" : "系统节能调度"
    }

    private func beginNewTrackingSession() {
        trackingStartedAt = .now
        clearTrackingAnchor()
        resetMovementGeometry()
        UserDefaults.standard.set(trackingStartedAt.timeIntervalSince1970, forKey: Keys.startedAt)
    }

    private func clearTrackingAnchor() {
        latestAcceptedPoint = nil
        UserDefaults.standard.removeObject(forKey: Keys.lastAcceptedSyncID)
    }

    private func persistTrackingAnchor(_ point: TrackPoint) {
        latestAcceptedPoint = point
        if let syncID = point.syncID {
            UserDefaults.standard.set(syncID, forKey: Keys.lastAcceptedSyncID)
        } else {
            UserDefaults.standard.removeObject(forKey: Keys.lastAcceptedSyncID)
        }
    }

    private func startTrackingIfAuthorized() {
        guard isTrackingEnabled else {
            engineState = "未开启"
            return
        }
        guard CLLocationManager.locationServicesEnabled() else {
            engineState = "系统定位已关闭"
            lastError = "系统定位服务已关闭"
            return
        }
        guard authorizationStatus == .authorizedAlways else {
            engineState = authorizationStatus == .authorizedWhenInUse ? "等待始终定位权限" : "等待定位权限"
            return
        }
        guard liveUpdatesTask == nil else { return }

        // The explicit Always session is the durable authorization intent for the feature.
        // Core Location remembers the outstanding live/service sessions across suspension and
        // system termination; recreating them immediately on launch rejoins queued delivery.
        serviceSession = CLServiceSession(authorization: .always)
        configureBackgroundDelivery()
        startLiveUpdates()
    }

    /// Balanced and Eco intentionally do not hold CLBackgroundActivitySession. With Always
    /// authorization, iOS may suspend aro, queue locations, and resume/relaunch it when delivery
    /// is appropriate. Precise and Workout explicitly opt into timely background execution.
    private func configureBackgroundDelivery() {
        if mode.requiresTimelyBackgroundDelivery {
            if backgroundActivitySession == nil {
                backgroundActivitySession = CLBackgroundActivitySession()
            }
        } else if let backgroundActivitySession {
            backgroundActivitySession.invalidate()
            self.backgroundActivitySession = nil
        }
    }

    private func startLiveUpdates() {
        guard isTrackingEnabled,
              authorizationStatus == .authorizedAlways,
              liveUpdatesTask == nil else { return }

        let generation = UUID()
        liveUpdatesGeneration = generation
        let configuration = mode.liveConfiguration
        engineState = "等待定位"

        liveUpdatesTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                for try await update in CLLocationUpdate.liveUpdates(configuration) {
                    guard !Task.isCancelled else { break }
                    self.consume(update)
                }
            } catch is CancellationError {
                // Expected when tracking is disabled or the user changes mode.
            } catch {
                guard !Task.isCancelled else { return }
                self.lastError = error.localizedDescription
                self.engineState = "定位流已停止"
            }

            if self.liveUpdatesGeneration == generation {
                self.liveUpdatesTask = nil
            }
        }
    }

    private func restartLiveUpdates() {
        liveUpdatesGeneration = UUID()
        liveUpdatesTask?.cancel()
        liveUpdatesTask = nil
        startLiveUpdates()
    }

    private func stopTracking() {
        liveUpdatesGeneration = UUID()
        liveUpdatesTask?.cancel()
        liveUpdatesTask = nil
        backgroundActivitySession?.invalidate()
        backgroundActivitySession = nil
        serviceSession?.invalidate()
        serviceSession = nil
        resetMovementGeometry()
        currentActivity = "未知"
        engineState = "未开启"
    }

    private func consume(_ update: CLLocationUpdate) {
        receivedUpdateCount += 1

        if update.authorizationDenied || update.authorizationDeniedGlobally {
            engineState = "定位权限不足"
            lastError = "定位权限已被拒绝"
            return
        }
        if update.authorizationRestricted {
            engineState = "定位受系统限制"
            lastError = "定位服务受到系统限制"
            return
        }
        if update.serviceSessionRequired {
            engineState = "定位会话异常"
            lastError = "Core Location 要求有效的服务会话"
            return
        }
        if update.insufficientlyInUse {
            engineState = "后台定位不可用"
            lastError = "当前定位模式没有足够的后台使用条件"
            return
        }
        if update.accuracyLimited {
            lastError = "精确位置已关闭，轨迹质量可能受影响"
        }
        if update.authorizationRequestInProgress {
            engineState = "等待权限确认"
        }

        if update.stationary {
            currentActivity = "静止"
            engineState = "系统静止休眠"
            // Stationary diagnostics can arrive without a location. Always clear the prior
            // movement bearing so motion after the sleep interval cannot inherit a stale turn.
            resetMovementGeometry()
        } else if update.locationUnavailable {
            engineState = "暂时无法定位"
        }

        guard let location = update.location else { return }
        lastHorizontalAccuracy = location.horizontalAccuracy
        if !update.stationary {
            currentActivity = "移动"
            engineState = "移动中"
        }

        let previousForFilter: TrackPoint?
        if let latestAcceptedPoint, latestAcceptedPoint.timestamp >= trackingStartedAt.addingTimeInterval(-1) {
            previousForFilter = latestAcceptedPoint
        } else {
            previousForFilter = nil
        }

        let observedTurnDegrees = update.stationary ? nil : advanceMovementGeometry(with: location)
        let shouldRecord = TrackMath.shouldRecordLiveLocation(
            location,
            after: previousForFilter,
            mode: mode,
            trackingStartedAt: trackingStartedAt,
            observedTurnDegrees: observedTurnDegrees
        )

        if update.stationary {
            resetMovementGeometry(anchoredAt: location)
        }

        guard shouldRecord else {
            rejectedUpdateCount += 1
            return
        }

        // Generate the sync ID before inserting so the local recorder can persist a stable
        // cross-process anchor without consulting arbitrary imported or remotely synced rows.
        let point = TrackPoint(
            syncID: UUID().uuidString.lowercased(),
            timestamp: location.timestamp,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.altitude,
            horizontalAccuracy: location.horizontalAccuracy,
            speed: location.speed,
            course: location.course,
            source: "live",
            activity: currentActivity
        )
        let rowID = TrackDatabase.shared.insert(point)
        guard rowID > 0 else {
            rejectedUpdateCount += 1
            return
        }

        let recordedPoint = TrackPoint(
            id: rowID,
            syncID: point.syncID,
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
        persistTrackingAnchor(recordedPoint)
        lastRecordedAt = recordedPoint.timestamp
        lastSource = recordedPoint.source
        recordedUpdateCount += 1
        TrackRepository.shared.didInsertPoint()
    }

    /// Builds a coarse direction history from good live fixes so pedestrian turns can be retained
    /// even when CLLocation.course is unavailable. Short/noisy movements don't advance the bearing.
    private func advanceMovementGeometry(with location: CLLocation) -> CLLocationDirection? {
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= mode.maximumAcceptedAccuracy,
              location.timestamp >= trackingStartedAt.addingTimeInterval(-1),
              CLLocationCoordinate2DIsValid(location.coordinate)
        else { return nil }

        guard let previous = lastMovementLocation else {
            lastMovementLocation = location
            return nil
        }
        guard location.timestamp > previous.timestamp else { return nil }

        let distance = previous.distance(from: location)
        let previousAccuracy = previous.horizontalAccuracy >= 0 ? previous.horizontalAccuracy : 0
        let movementFloor = max(8, max(previousAccuracy, location.horizontalAccuracy) * 0.5)
        guard distance >= movementFloor else { return nil }

        let interval = location.timestamp.timeIntervalSince(previous.timestamp)
        if interval < 10 * 60, distance / interval > 100 {
            return nil
        }

        let bearing = TrackMath.bearing(from: previous.coordinate, to: location.coordinate)
        let turn = lastMovementBearing.map { TrackMath.headingDifference($0, bearing) }
        lastMovementLocation = location
        lastMovementBearing = bearing
        return turn
    }

    private func resetMovementGeometry(anchoredAt location: CLLocation? = nil) {
        lastMovementLocation = location
        lastMovementBearing = nil
    }

    var sourceLabel: String {
        switch lastSource {
        case "live": "Live Updates"
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
        guard manager === authorizationManager else { return }
        let previousAuthorizationStatus = authorizationStatus
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization

        if authorizationStatus == .authorizedAlways {
            if isTrackingEnabled, previousAuthorizationStatus != .authorizedAlways {
                // A period without Always authorization cannot produce valid all-day recording.
                // Start a fresh boundary so cached fixes from that permission gap are never imported.
                beginNewTrackingSession()
            }
            lastError = nil
            startTrackingIfAuthorized()
        } else if liveUpdatesTask != nil {
            stopTracking()
            if isTrackingEnabled {
                engineState = authorizationStatus == .authorizedWhenInUse ? "等待始终定位权限" : "等待定位权限"
            }
        }
    }
}
