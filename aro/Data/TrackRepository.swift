import CloudKit
import Combine
import Foundation

@MainActor
final class TrackRepository: ObservableObject {
    static let shared = TrackRepository()

    @Published private(set) var todayPoints: [TrackPoint] = []
    @Published private(set) var days: [TrackDay] = []
    @Published private(set) var lifetime: LifetimeStats = .empty
    @Published private(set) var overviewPoints: [TrackPoint] = []
    @Published private(set) var databaseBytes: Int64 = 0
    @Published private(set) var isLoading = false

    private let database = TrackDatabase.shared

    private init() {}

    func refresh(includeOverview: Bool = false) {
        guard !isLoading else { return }
        isLoading = true
        let database = self.database
        Task.detached(priority: .utility) {
            let today = database.points(on: Date())
            let days = database.trackDays()
            let lifetime = database.lifetimeStats()
            let overview = includeOverview ? database.overviewPoints() : []
            let bytes = database.fileSize()
            await MainActor.run {
                self.todayPoints = today
                self.days = days
                self.lifetime = lifetime
                if includeOverview { self.overviewPoints = overview }
                self.databaseBytes = bytes
                self.isLoading = false
            }
        }
    }

    func loadPoints(on date: Date) async -> [TrackPoint] {
        let database = self.database
        return await Task.detached(priority: .userInitiated) {
            database.points(on: date)
        }.value
    }

    func didInsertPoint() {
        refresh()
    }

    func deleteEverything() {
        database.deleteAll()
        todayPoints = []
        days = []
        lifetime = .empty
        overviewPoints = []
        databaseBytes = 0
    }
}

@MainActor
final class CloudSyncService: ObservableObject {
    static let shared = CloudSyncService()

    @Published private(set) var statusText = "未开启"
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncAt: Date?

    static let enabledKey = "icloudSync.enabled"
    private static let lastSyncKey = "icloudSync.lastSyncAt"

    private let manager = CloudTrackSyncEngine.shared
    private var activationTask: Task<Void, Never>?

    private init() {
        let timestamp = UserDefaults.standard.double(forKey: Self.lastSyncKey)
        if timestamp > 0 { lastSyncAt = Date(timeIntervalSince1970: timestamp) }
        if UserDefaults.standard.bool(forKey: Self.enabledKey) { statusText = "等待同步" }
    }

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    func appBecameActive() {
        guard isEnabled else {
            statusText = "未开启"
            return
        }
        activationTask?.cancel()
        activationTask = Task {
            do {
                try await manager.startIfNeeded()
                guard !Task.isCancelled else { return }
                statusText = "等待系统同步"
            } catch {
                guard !Task.isCancelled else { return }
                statusText = Self.message(for: error)
            }
        }
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        if enabled {
            Task { await syncNow() }
        } else {
            activationTask?.cancel()
            activationTask = nil
            statusText = "未开启"
            isSyncing = false
            Task { await manager.stop() }
        }
    }

    func syncNow() async {
        guard isEnabled else {
            statusText = "未开启"
            return
        }
        isSyncing = true
        statusText = "正在同步…"
        defer { isSyncing = false }
        do {
            try await manager.syncNow()
            noteSyncCompleted()
        } catch {
            statusText = Self.message(for: error)
        }
    }

    func deleteCloudAndLocalData() async throws {
        guard isEnabled else {
            TrackRepository.shared.deleteEverything()
            return
        }
        isSyncing = true
        statusText = "正在删除 iCloud 数据…"
        defer { isSyncing = false }
        do {
            try await manager.deleteCloudZone()
            TrackRepository.shared.deleteEverything()
            statusText = "已删除"
            lastSyncAt = nil
            UserDefaults.standard.removeObject(forKey: Self.lastSyncKey)
        } catch {
            statusText = Self.message(for: error)
            throw error
        }
    }

    func noteAutomaticSync() {
        guard isEnabled else { return }
        let now = Date()
        lastSyncAt = now
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Self.lastSyncKey)
        if !isSyncing { statusText = "已同步" }
    }

    func disableAfterAccountChange() {
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        statusText = "iCloud 账户已变化，已暂停同步"
        isSyncing = false
    }

    func disableAfterRemoteZoneDeletion() {
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        statusText = "iCloud 数据已被移除，已暂停同步"
        isSyncing = false
    }

    private func noteSyncCompleted() {
        let now = Date()
        lastSyncAt = now
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Self.lastSyncKey)
        statusText = "已同步"
    }

    private static func message(for error: Error) -> String {
        if let error = error as? CloudSyncError { return error.localizedDescription }
        if let ckError = error as? CKError {
            switch ckError.code {
            case .notAuthenticated: return "未登录 iCloud"
            case .networkUnavailable, .networkFailure: return "网络不可用"
            default: return "同步失败：\(ckError.localizedDescription)"
            }
        }
        return "同步失败：\(error.localizedDescription)"
    }
}

private enum CloudSyncError: LocalizedError {
    case accountUnavailable(CKAccountStatus)

    var errorDescription: String? {
        switch self {
        case .accountUnavailable(.noAccount): "未登录 iCloud"
        case .accountUnavailable(.restricted): "iCloud 访问受限制"
        case .accountUnavailable(.couldNotDetermine): "无法确定 iCloud 状态"
        case .accountUnavailable(.temporarilyUnavailable): "iCloud 暂时不可用"
        case .accountUnavailable(.available): "iCloud 状态异常"
        @unknown default: "iCloud 暂时不可用"
        }
    }
}

private actor CloudTrackSyncEngine: CKSyncEngineDelegate {
    static let shared = CloudTrackSyncEngine()

    private static let containerIdentifier = "iCloud.com.xunbo.aro"
    private static let zoneName = "AROTracks"
    private static let recordType: CKRecord.RecordType = "TrackPoint"
    private static let zone = CKRecordZone(zoneName: zoneName)
    private static let zoneID = zone.zoneID

    private let container = CKContainer(identifier: containerIdentifier)
    private let database = TrackDatabase.shared
    private let stateStore = CloudSyncStateStore()
    private var syncEngine: CKSyncEngine?

    func startIfNeeded() async throws {
        if let syncEngine {
            queueLocalChanges(on: syncEngine)
            return
        }

        let accountStatus = try await container.accountStatus()
        guard accountStatus == .available else { throw CloudSyncError.accountUnavailable(accountStatus) }

        var configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: stateStore.load(),
            delegate: self
        )
        configuration.automaticallySync = true
        let syncEngine = CKSyncEngine(configuration)
        self.syncEngine = syncEngine
        syncEngine.state.add(pendingDatabaseChanges: [.saveZone(Self.zone)])
        queueLocalChanges(on: syncEngine)
    }

    func stop() {
        syncEngine = nil
    }

    func syncNow() async throws {
        try await startIfNeeded()
        guard let syncEngine else { return }
        queueLocalChanges(on: syncEngine)
        try await syncEngine.fetchChanges()
        queueLocalChanges(on: syncEngine)
        try await syncEngine.sendChanges()
    }

    func deleteCloudZone() async throws {
        let accountStatus = try await container.accountStatus()
        guard accountStatus == .available else { throw CloudSyncError.accountUnavailable(accountStatus) }

        do {
            _ = try await container.privateCloudDatabase.deleteRecordZone(withID: Self.zoneID)
        } catch let error as CKError where error.code == .zoneNotFound {
            // The intended end state is already true.
        }
        syncEngine = nil
        stateStore.clear()
        database.resetCloudSyncState()
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let event):
            stateStore.save(event.stateSerialization)

        case .accountChange:
            stateStore.clear()
            database.resetCloudSyncState()
            self.syncEngine = nil
            await MainActor.run { CloudSyncService.shared.disableAfterAccountChange() }

        case .fetchedDatabaseChanges(let event):
            if event.deletions.contains(where: { $0.zoneID == Self.zoneID }) {
                stateStore.clear()
                database.resetCloudSyncState()
                self.syncEngine = nil
                await MainActor.run { CloudSyncService.shared.disableAfterRemoteZoneDeletion() }
            }

        case .fetchedRecordZoneChanges(let event):
            let fetchedPoints = event.modifications.compactMap { Self.trackPoint(from: $0.record) }
            let deletedIDs = event.deletions
                .filter { $0.recordID.zoneID == Self.zoneID && $0.recordType == Self.recordType }
                .map { $0.recordID.recordName }

            if !fetchedPoints.isEmpty { _ = database.applyCloudPoints(fetchedPoints) }
            if !deletedIDs.isEmpty { _ = database.deleteCloudPoints(syncIDs: deletedIDs) }
            if !fetchedPoints.isEmpty || !deletedIDs.isEmpty {
                await MainActor.run {
                    TrackRepository.shared.refresh(includeOverview: true)
                    CloudSyncService.shared.noteAutomaticSync()
                }
            }

        case .sentRecordZoneChanges(let event):
            let savedIDs = event.savedRecords
                .filter { $0.recordID.zoneID == Self.zoneID && $0.recordType == Self.recordType }
                .map { $0.recordID.recordName }
            if !savedIDs.isEmpty { database.markCloudSynced(syncIDs: savedIDs) }

            var needsZone = false
            for failure in event.failedRecordSaves {
                switch failure.error.code {
                case .serverRecordChanged:
                    if let serverRecord = failure.error.serverRecord,
                       let point = Self.trackPoint(from: serverRecord) {
                        _ = database.applyCloudPoints([point])
                        database.markCloudSynced(syncIDs: [serverRecord.recordID.recordName])
                    }
                case .zoneNotFound:
                    needsZone = true
                case .unknownItem:
                    break
                case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable,
                     .notAuthenticated, .operationCancelled, .requestRateLimited,
                     .accountTemporarilyUnavailable:
                    break
                default:
                    break
                }
            }
            if needsZone { syncEngine.state.add(pendingDatabaseChanges: [.saveZone(Self.zone)]) }
            queueLocalChanges(on: syncEngine)
            if !savedIDs.isEmpty {
                await MainActor.run { CloudSyncService.shared.noteAutomaticSync() }
            }

        case .sentDatabaseChanges:
            break

        case .willFetchChanges, .willFetchRecordZoneChanges, .didFetchRecordZoneChanges,
             .didFetchChanges, .willSendChanges, .didSendChanges:
            break

        @unknown default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let points = database.unsyncedPoints(limit: 250)
        guard !points.isEmpty else {
            syncEngine.state.hasPendingUntrackedChanges = false
            return nil
        }

        let records = points.compactMap { point -> CKRecord? in
            guard let record = Self.record(from: point),
                  context.options.scope.contains(CKSyncEngine.PendingRecordZoneChange.saveRecord(record.recordID)) else {
                return nil
            }
            return record
        }
        guard !records.isEmpty else { return nil }
        return CKSyncEngine.RecordZoneChangeBatch(
            recordsToSave: records,
            recordIDsToDelete: [],
            atomicByZone: false
        )
    }

    private func queueLocalChanges(on syncEngine: CKSyncEngine) {
        if !database.unsyncedPoints(limit: 1).isEmpty {
            syncEngine.state.hasPendingUntrackedChanges = true
        }
    }

    private static func record(from point: TrackPoint) -> CKRecord? {
        guard let syncID = point.syncID, !syncID.isEmpty else { return nil }
        let recordID = CKRecord.ID(recordName: syncID, zoneID: zoneID)
        let record = CKRecord(recordType: recordType, recordID: recordID)
        record["timestamp"] = point.timestamp as CKRecordValue
        record["latitude"] = NSNumber(value: point.latitude)
        record["longitude"] = NSNumber(value: point.longitude)
        record["altitude"] = NSNumber(value: point.altitude)
        record["horizontalAccuracy"] = NSNumber(value: point.horizontalAccuracy)
        record["speed"] = NSNumber(value: point.speed)
        record["course"] = NSNumber(value: point.course)
        record["source"] = point.source as CKRecordValue
        if let activity = point.activity { record["activity"] = activity as CKRecordValue }
        return record
    }

    private static func trackPoint(from record: CKRecord) -> TrackPoint? {
        guard record.recordType == recordType,
              record.recordID.zoneID == zoneID,
              let timestamp = record["timestamp"] as? Date,
              let latitude = record["latitude"] as? NSNumber,
              let longitude = record["longitude"] as? NSNumber else {
            return nil
        }

        return TrackPoint(
            syncID: record.recordID.recordName,
            timestamp: timestamp,
            latitude: latitude.doubleValue,
            longitude: longitude.doubleValue,
            altitude: (record["altitude"] as? NSNumber)?.doubleValue ?? 0,
            horizontalAccuracy: (record["horizontalAccuracy"] as? NSNumber)?.doubleValue ?? -1,
            speed: (record["speed"] as? NSNumber)?.doubleValue ?? -1,
            course: (record["course"] as? NSNumber)?.doubleValue ?? -1,
            source: record["source"] as? String ?? "cloud",
            activity: record["activity"] as? String
        )
    }
}

private struct CloudSyncStateStore: Sendable {
    private let url: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = support.appendingPathComponent("traceon", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appendingPathComponent("cloudkit-sync-state.json")
    }

    func load() -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    func save(_ serialization: CKSyncEngine.State.Serialization) {
        guard let data = try? JSONEncoder().encode(serialization) else { return }
        do {
            try data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
        } catch {
            // A future state update will retry; the local track database remains authoritative.
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
