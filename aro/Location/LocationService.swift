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
    @Published private(set) var isTrackingActive = false
    @Published private(set) var receivedUpdateCount = 0
    @Published private(set) var locationUpdateCount = 0
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
            resetIdleDetection()
            guard liveUpdatesTask != nil || ecoStandardUpdatesRunning || idleMonitorTask != nil || isIdleMonitorPersisted else { return }
            Task { @MainActor [weak self] in
                await self?.reconfigureActiveTrackingForModeChange()
            }
        }
    }

    private let authorizationManager = CLLocationManager()
    private var serviceSession: CLServiceSession?
    private var backgroundActivitySession: CLBackgroundActivitySession?
    private var liveUpdatesTask: Task<Void, Never>?
    private var liveUpdatesGeneration = UUID()
    private var ecoStandardUpdatesRunning = false
    private var idleMonitor: CLMonitor?
    private var idleMonitorTask: Task<Void, Never>?
    private var idleMonitorGeneration = UUID()
    private var latestAcceptedPoint: TrackPoint?
    private var trackingStartedAt: Date
    private var lastMovementLocation: CLLocation?
    private var lastMovementBearing: CLLocationDirection?
    private var lastReliableLocation: CLLocation?
    private var idleDetectionStartedAt = Date.now
    private var idleLocationWindow: [CLLocation] = []
    private var lastBackgroundRepositoryRefreshAt: Date?

    private static let backgroundRepositoryRefreshInterval: TimeInterval = 5 * 60
    private static let idleMonitorName = "aro.idle-monitor"
    private static let idleConditionIdentifier = "stationary-area"

    private enum Keys {
        static let enabled = "tracking.enabled"
        static let mode = "tracking.mode"
        static let startedAt = "tracking.startedAt"
        static let lastAcceptedSyncID = "tracking.lastAcceptedSyncID"
        static let idleMonitorActive = "tracking.idleMonitorActive"
    }

    private struct MovementObservation {
        let turnDegrees: CLLocationDirection?
        let hasMeaningfulMovement: Bool

        static let none = MovementObservation(turnDegrees: nil, hasMeaningfulMovement: false)
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

        super.init()

        authorizationManager.delegate = self
        if savedEnabled, savedStartedAt <= 0 {
            defaults.set(trackingStartedAt.timeIntervalSince1970, forKey: Keys.startedAt)
            defaults.removeObject(forKey: Keys.lastAcceptedSyncID)
            latestAcceptedPoint = nil
        }
        if !savedEnabled || !savedMode.usesIdleMonitoring {
            defaults.removeObject(forKey: Keys.idleMonitorActive)
        }
    }

    /// Called from UIApplicationDelegate on every process launch. Location is intentionally the
    /// only launch-time subsystem so a CLMonitor, Live Updates, or Eco Standard relaunch stays isolated.
    func handleApplicationLaunch() {
        authorizationStatus = authorizationManager.authorizationStatus
        accuracyAuthorization = authorizationManager.accuracyAuthorization
        startTrackingIfAuthorized()
    }

    func handleTrackDataDeleted() {
        lastRecordedAt = nil
        lastSource = nil
        lastHorizontalAccuracy = nil
        lastBackgroundRepositoryRefreshAt = nil
        if isTrackingEnabled {
            beginNewTrackingSession()
        } else {
            clearTrackingAnchor()
            resetMovementGeometry()
            resetIdleDetection()
        }
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
        switch mode {
        case .eco: "约 100 米触发 + 静止监控"
        case .balanced: "静止低功耗监控"
        case .precise, .workout: "及时后台"
        }
    }

    private var isIdleMonitorPersisted: Bool {
        UserDefaults.standard.bool(forKey: Keys.idleMonitorActive)
    }

    private var isPrimaryUpdatesRunning: Bool {
        liveUpdatesTask != nil || ecoStandardUpdatesRunning
    }

    private func beginNewTrackingSession() {
        trackingStartedAt = .now
        clearTrackingAnchor()
        resetMovementGeometry()
        resetIdleDetection()
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
        guard !isPrimaryUpdatesRunning, idleMonitorTask == nil else { return }

        if serviceSession == nil {
            serviceSession = CLServiceSession(authorization: .always)
        }
        configureBackgroundDelivery()

        if mode.usesIdleMonitoring, isIdleMonitorPersisted {
            restoreIdleMonitoring()
        } else {
            UserDefaults.standard.removeObject(forKey: Keys.idleMonitorActive)
            startPrimaryUpdates()
        }
    }

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

    private func startPrimaryUpdates() {
        if mode.usesDistanceFilteredStandardUpdates {
            startEcoStandardUpdates()
        } else {
            startLiveUpdates()
        }
    }

    private func startEcoStandardUpdates() {
        guard mode == .eco,
              isTrackingEnabled,
              authorizationStatus == .authorizedAlways,
              !ecoStandardUpdatesRunning,
              liveUpdatesTask == nil,
              idleMonitorTask == nil else { return }

        resetMovementGeometry()
        resetIdleDetection()
        authorizationManager.desiredAccuracy = mode.standardDesiredAccuracy
        authorizationManager.distanceFilter = mode.standardDistanceFilter
        authorizationManager.activityType = .other
        authorizationManager.pausesLocationUpdatesAutomatically = true
        authorizationManager.allowsBackgroundLocationUpdates = true
        authorizationManager.showsBackgroundLocationIndicator = false
        ecoStandardUpdatesRunning = true
        isTrackingActive = true
        engineState = "等待距离定位"
        currentActivity = "监测中"
        authorizationManager.startUpdatingLocation()
    }

    private func stopEcoStandardUpdates() {
        guard ecoStandardUpdatesRunning else { return }
        authorizationManager.stopUpdatingLocation()
        ecoStandardUpdatesRunning = false
    }

    private func startLiveUpdates() {
        guard mode != .eco,
              isTrackingEnabled,
              authorizationStatus == .authorizedAlways,
              liveUpdatesTask == nil,
              !ecoStandardUpdatesRunning,
              idleMonitorTask == nil else { return }

        let generation = UUID()
        liveUpdatesGeneration = generation
        let configuration = mode.liveConfiguration
        resetIdleDetection()
        engineState = "等待定位"
        currentActivity = "监测中"
        isTrackingActive = true

        liveUpdatesTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                for try await update in CLLocationUpdate.liveUpdates(configuration) {
                    guard !Task.isCancelled else { break }
                    self.consume(update)
                }
            } catch is CancellationError {
                // Expected when tracking is disabled, mode changes, or idle monitoring takes over.
            } catch {
                guard !Task.isCancelled else { return }
                self.lastError = error.localizedDescription
                self.engineState = "定位流已停止"
            }

            if self.liveUpdatesGeneration == generation {
                self.liveUpdatesTask = nil
                self.isTrackingActive = false
            }
        }
    }

    private func stopLiveUpdates() {
        liveUpdatesGeneration = UUID()
        liveUpdatesTask?.cancel()
        liveUpdatesTask = nil
    }

    private func restartPrimaryUpdates() {
        stopEcoStandardUpdates()
        stopLiveUpdates()
        startPrimaryUpdates()
    }

    private func stopPrimaryUpdatesForIdle() {
        stopEcoStandardUpdates()
        stopLiveUpdates()
        resetMovementGeometry()
        resetIdleDetection()
    }

    private func reconfigureActiveTrackingForModeChange() async {
        configureBackgroundDelivery()
        if idleMonitorTask != nil || isIdleMonitorPersisted {
            await leaveIdleMonitoringAndResumePrimaryUpdates()
        } else if isPrimaryUpdatesRunning {
            restartPrimaryUpdates()
        }
    }

    private func enterIdleMonitoring(center: CLLocationCoordinate2D) {
        guard mode.usesIdleMonitoring,
              isTrackingEnabled,
              authorizationStatus == .authorizedAlways,
              idleMonitorTask == nil else { return }

        let generation = UUID()
        idleMonitorGeneration = generation
        engineState = "准备静止省电"
        currentActivity = "静止"

        idleMonitorTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let monitor = await self.getIdleMonitor()
            guard self.idleMonitorGeneration == generation, !Task.isCancelled else { return }

            await monitor.remove(Self.idleConditionIdentifier)
            let condition = CLMonitor.CircularGeographicCondition(
                center: center,
                radius: self.mode.idleMonitorRadius
            )
            await monitor.add(condition, identifier: Self.idleConditionIdentifier, assuming: .satisfied)

            guard self.idleMonitorGeneration == generation, !Task.isCancelled else {
                await monitor.remove(Self.idleConditionIdentifier)
                return
            }

            UserDefaults.standard.set(true, forKey: Keys.idleMonitorActive)
            self.stopPrimaryUpdatesForIdle()
            self.isTrackingActive = true
            self.engineState = "静止省电监控"
            self.currentActivity = "静止"

            await self.listenForIdleMonitorEvents(monitor, generation: generation)
        }
    }

    private func restoreIdleMonitoring() {
        guard mode.usesIdleMonitoring, idleMonitorTask == nil else { return }
        let generation = UUID()
        idleMonitorGeneration = generation
        engineState = "恢复静止监控"
        currentActivity = "静止"
        isTrackingActive = true

        idleMonitorTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let monitor = await self.getIdleMonitor()
            guard self.idleMonitorGeneration == generation, !Task.isCancelled else { return }

            let identifiers = await monitor.identifiers
            guard identifiers.contains(Self.idleConditionIdentifier) else {
                UserDefaults.standard.removeObject(forKey: Keys.idleMonitorActive)
                self.idleMonitorTask = nil
                self.isTrackingActive = false
                self.startPrimaryUpdates()
                return
            }

            self.engineState = "静止省电监控"
            self.currentActivity = "静止"
            await self.listenForIdleMonitorEvents(monitor, generation: generation)
        }
    }

    private func getIdleMonitor() async -> CLMonitor {
        if let idleMonitor { return idleMonitor }
        let monitor = await CLMonitor(Self.idleMonitorName)
        idleMonitor = monitor
        return monitor
    }

    private func listenForIdleMonitorEvents(_ monitor: CLMonitor, generation: UUID) async {
        do {
            for try await event in await monitor.events {
                guard idleMonitorGeneration == generation, !Task.isCancelled else { return }
                guard event.identifier == Self.idleConditionIdentifier else { continue }

                if event.authorizationDenied || event.authorizationDeniedGlobally || event.authorizationRestricted {
                    await recoverFromIdleMonitor(monitor, generation: generation, message: "低功耗位置监控失去定位权限")
                    return
                }
                if event.conditionLimitExceeded || event.conditionUnsupported || event.persistenceUnavailable
                    || event.serviceSessionRequired || event.insufficientlyInUse {
                    await recoverFromIdleMonitor(monitor, generation: generation, message: "低功耗位置监控不可用，已恢复定位")
                    return
                }

                switch event.state {
                case .unsatisfied:
                    await wakeFromIdleMonitor(monitor, generation: generation)
                    return
                case .unmonitored:
                    await recoverFromIdleMonitor(monitor, generation: generation, message: "低功耗位置监控已停止，已恢复定位")
                    return
                case .satisfied:
                    engineState = "静止省电监控"
                case .unknown:
                    engineState = "确认静止范围"
                @unknown default:
                    break
                }
            }
        } catch is CancellationError {
            return
        } catch {
            await recoverFromIdleMonitor(monitor, generation: generation, message: error.localizedDescription)
        }
    }

    private func wakeFromIdleMonitor(_ monitor: CLMonitor, generation: UUID) async {
        guard idleMonitorGeneration == generation else { return }
        await monitor.remove(Self.idleConditionIdentifier)
        guard idleMonitorGeneration == generation else { return }
        UserDefaults.standard.removeObject(forKey: Keys.idleMonitorActive)
        idleMonitorTask = nil
        resetMovementGeometry()
        resetIdleDetection()
        currentActivity = "监测中"
        engineState = "检测到移动"
        configureBackgroundDelivery()
        startPrimaryUpdates()
    }

    private func recoverFromIdleMonitor(_ monitor: CLMonitor, generation: UUID, message: String) async {
        guard idleMonitorGeneration == generation else { return }
        await monitor.remove(Self.idleConditionIdentifier)
        guard idleMonitorGeneration == generation else { return }
        UserDefaults.standard.removeObject(forKey: Keys.idleMonitorActive)
        idleMonitorTask = nil
        lastError = message
        resetIdleDetection()
        configureBackgroundDelivery()
        startPrimaryUpdates()
    }

    private func leaveIdleMonitoringAndResumePrimaryUpdates() async {
        idleMonitorGeneration = UUID()
        idleMonitorTask?.cancel()
        idleMonitorTask = nil
        UserDefaults.standard.removeObject(forKey: Keys.idleMonitorActive)
        if let idleMonitor {
            await idleMonitor.remove(Self.idleConditionIdentifier)
        }
        isTrackingActive = false
        resetIdleDetection()
        configureBackgroundDelivery()
        startPrimaryUpdates()
    }

    private func stopTracking() {
        stopEcoStandardUpdates()
        stopLiveUpdates()
        idleMonitorGeneration = UUID()
        idleMonitorTask?.cancel()
        idleMonitorTask = nil
        UserDefaults.standard.removeObject(forKey: Keys.idleMonitorActive)
        if let idleMonitor {
            Task { await idleMonitor.remove(Self.idleConditionIdentifier) }
        }
        isTrackingActive = false
        backgroundActivitySession?.invalidate()
        backgroundActivitySession = nil
        serviceSession?.invalidate()
        serviceSession = nil
        resetMovementGeometry()
        resetIdleDetection()
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
            resetMovementGeometry()
        } else if update.locationUnavailable {
            engineState = "暂时无法定位"
        }

        guard let location = update.location else { return }
        locationUpdateCount += 1
        lastHorizontalAccuracy = location.horizontalAccuracy
        rememberReliableLocation(location)

        let idleCenter: CLLocationCoordinate2D?
        if update.stationary,
           mode.usesIdleMonitoring,
           location.horizontalAccuracy >= 0,
           location.horizontalAccuracy <= max(mode.maximumAcceptedAccuracy, mode.idleDetectionMaximumAccuracy),
           CLLocationCoordinate2DIsValid(location.coordinate) {
            idleCenter = location.coordinate
        } else {
            idleCenter = updateIdleDetection(with: location)
        }

        let previousForFilter = previousPointForCurrentSession()
        let movement = update.stationary ? .none : advanceMovementGeometry(with: location)
        if !update.stationary {
            updateMovementUI(using: movement)
        }

        let shouldRecord = TrackMath.shouldRecordLiveLocation(
            location,
            after: previousForFilter,
            mode: mode,
            trackingStartedAt: trackingStartedAt,
            observedTurnDegrees: movement.turnDegrees
        )

        if update.stationary {
            resetMovementGeometry(anchoredAt: location)
        }

        if shouldRecord {
            record(location, source: "live")
        } else {
            rejectedUpdateCount += 1
        }

        if let idleCenter {
            enterIdleMonitoring(center: idleCenter)
        }
    }

    private func consumeEcoStandardLocations(_ locations: [CLLocation]) {
        receivedUpdateCount += 1

        for location in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
            locationUpdateCount += 1
            lastHorizontalAccuracy = location.horizontalAccuracy
            rememberReliableLocation(location)

            let movement = advanceMovementGeometry(with: location)
            updateMovementUI(using: movement)

            let shouldRecord = TrackMath.shouldRecordLiveLocation(
                location,
                after: previousPointForCurrentSession(),
                mode: .eco,
                trackingStartedAt: trackingStartedAt,
                observedTurnDegrees: movement.turnDegrees
            )

            if shouldRecord {
                record(location, source: "standard")
            } else {
                rejectedUpdateCount += 1
            }
        }
    }

    private func previousPointForCurrentSession() -> TrackPoint? {
        if let latestAcceptedPoint, latestAcceptedPoint.timestamp >= trackingStartedAt.addingTimeInterval(-1) {
            return latestAcceptedPoint
        }
        return nil
    }

    private func rememberReliableLocation(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= mode.maximumAcceptedAccuracy,
              location.timestamp >= trackingStartedAt.addingTimeInterval(-1),
              CLLocationCoordinate2DIsValid(location.coordinate) else { return }
        lastReliableLocation = location
    }

    private func idleAnchorCoordinate() -> CLLocationCoordinate2D? {
        if let lastReliableLocation {
            return lastReliableLocation.coordinate
        }
        return latestAcceptedPoint?.location.coordinate
    }

    private func record(_ location: CLLocation, source: String) {
        let point = TrackPoint(
            syncID: UUID().uuidString.lowercased(),
            timestamp: location.timestamp,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.altitude,
            horizontalAccuracy: location.horizontalAccuracy,
            speed: location.speed,
            course: location.course,
            source: source,
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
        notifyRepositoryOfRecordedPoint()
    }

    private func updateIdleDetection(with location: CLLocation) -> CLLocationCoordinate2D? {
        guard mode.usesSpatialIdleDetection,
              location.timestamp >= idleDetectionStartedAt.addingTimeInterval(-1),
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= mode.idleDetectionMaximumAccuracy,
              CLLocationCoordinate2DIsValid(location.coordinate) else { return nil }

        idleLocationWindow.append(location)
        let cutoff = location.timestamp.addingTimeInterval(-(mode.idleDetectionInterval + 60))
        idleLocationWindow.removeAll { $0.timestamp < cutoff }
        if idleLocationWindow.count > 256 {
            idleLocationWindow.removeFirst(idleLocationWindow.count - 256)
        }
        return TrackMath.idleMonitorCenter(for: idleLocationWindow, mode: mode)
    }

    private func resetIdleDetection() {
        idleDetectionStartedAt = .now
        idleLocationWindow.removeAll(keepingCapacity: true)
    }

    private func notifyRepositoryOfRecordedPoint() {
        let now = Date.now
        if UIApplication.shared.applicationState == .active {
            lastBackgroundRepositoryRefreshAt = now
            TrackRepository.shared.didInsertPoint()
            return
        }

        if let lastBackgroundRepositoryRefreshAt,
           now.timeIntervalSince(lastBackgroundRepositoryRefreshAt) < Self.backgroundRepositoryRefreshInterval {
            return
        }
        lastBackgroundRepositoryRefreshAt = now
        TrackRepository.shared.didInsertPoint()
    }

    private func advanceMovementGeometry(with location: CLLocation) -> MovementObservation {
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= mode.maximumAcceptedAccuracy,
              location.timestamp >= trackingStartedAt.addingTimeInterval(-1),
              CLLocationCoordinate2DIsValid(location.coordinate)
        else { return .none }

        guard let previous = lastMovementLocation else {
            lastMovementLocation = location
            return .none
        }
        guard location.timestamp > previous.timestamp else { return .none }

        let distance = previous.distance(from: location)
        let previousAccuracy = previous.horizontalAccuracy >= 0 ? previous.horizontalAccuracy : 0
        let movementFloor = max(8, max(previousAccuracy, location.horizontalAccuracy) * 0.5)
        guard distance >= movementFloor else { return .none }

        let interval = location.timestamp.timeIntervalSince(previous.timestamp)
        if interval < 10 * 60, distance / interval > 100 {
            return .none
        }

        let bearing = TrackMath.bearing(from: previous.coordinate, to: location.coordinate)
        let turn = lastMovementBearing.map { TrackMath.headingDifference($0, bearing) }
        lastMovementLocation = location
        lastMovementBearing = bearing
        return MovementObservation(turnDegrees: turn, hasMeaningfulMovement: true)
    }

    private func updateMovementUI(using observation: MovementObservation) {
        if observation.hasMeaningfulMovement {
            currentActivity = "移动"
            engineState = "移动中"
        } else if idleMonitorTask == nil {
            currentActivity = "监测中"
            if engineState != "准备静止省电" {
                engineState = mode == .eco ? "等待距离移动" : "监测中"
            }
        }
    }

    private func resetMovementGeometry(anchoredAt location: CLLocation? = nil) {
        lastMovementLocation = location
        lastMovementBearing = nil
        if location == nil {
            lastReliableLocation = nil
        }
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
                beginNewTrackingSession()
            }
            lastError = nil
            startTrackingIfAuthorized()
        } else if isPrimaryUpdatesRunning || idleMonitorTask != nil || isIdleMonitorPersisted {
            stopTracking()
            if isTrackingEnabled {
                engineState = authorizationStatus == .authorizedWhenInUse ? "等待始终定位权限" : "等待定位权限"
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard manager === authorizationManager,
              mode == .eco,
              ecoStandardUpdatesRunning else { return }
        consumeEcoStandardLocations(locations)
    }

    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        guard manager === authorizationManager,
              mode == .eco,
              ecoStandardUpdatesRunning else { return }

        currentActivity = "静止"
        engineState = "系统确认静止"
        guard let center = idleAnchorCoordinate() else { return }
        enterIdleMonitoring(center: center)
    }

    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        guard manager === authorizationManager,
              mode == .eco,
              ecoStandardUpdatesRunning,
              idleMonitorTask == nil else { return }
        currentActivity = "监测中"
        engineState = "检测到移动"
    }
}
