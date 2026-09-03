import CoreLocation
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var repository: TrackRepository
#if ARO_CLOUDKIT_ENABLED
    @ObservedObject private var cloudSync = CloudSyncService.shared
#endif
    @State private var showDeleteConfirmation = false
    @State private var exportDocument: TrackDocument?
    @State private var exportType: UTType = .xml
    @State private var exportFilename = "aro.gpx"
    @State private var isExporting = false
    @State private var showImporter = false
    @State private var importMessage: String?
    @State private var deleteError: String?
    @AppStorage("onboarding.completed") private var hasCompletedOnboarding = true

    var body: some View {
        Form {
            automaticSection
            modesSection
            permissionsSection
            dataSection
#if ARO_CLOUDKIT_ENABLED
            iCloudSection
#else
            localICloudSection
#endif
            aboutSection
        }
        .navigationTitle("设置")
        .fileExporter(
            isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
            document: exportDocument,
            contentType: exportType,
            defaultFilename: exportFilename
        ) { _ in exportDocument = nil }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.xml, .json, .data],
            allowsMultipleSelection: false,
            onCompletion: handleImport
        )
        .alert("轨迹导入", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
            Button("好") { importMessage = nil }
        } message: {
            Text(importMessage ?? "")
        }
        .alert("删除失败", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("好") { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
        .confirmationDialog("永久删除全部轨迹？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("永久删除", role: .destructive) { deleteEverything() }
            Button("取消", role: .cancel) {}
        } message: {
            Text(deleteConfirmationMessage)
        }
    }

    private var automaticSection: some View {
        Section("自动记录") {
            Toggle("记录足迹", isOn: $locationService.isTrackingEnabled)
            Picker("定位模式", selection: $locationService.mode) {
                ForEach(TrackingMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
            LabeledContent("定位引擎", value: "iOS Live Updates")
            LabeledContent("运行状态", value: locationService.engineState)
            LabeledContent("当前活动", value: locationService.currentActivity)
            LabeledContent("最后记录", value: lastRecordedText)
            LabeledContent("记录通道", value: locationService.sourceLabel)
            if let accuracy = locationService.lastHorizontalAccuracy, accuracy >= 0 {
                LabeledContent("最近精度", value: "±\(Int(accuracy.rounded())) m")
            }
            LabeledContent(
                "本次启动",
                value: "接收 \(locationService.receivedUpdateCount) · 保存 \(locationService.recordedUpdateCount) · 丢弃 \(locationService.rejectedUpdateCount)"
            )
            if let error = locationService.lastError {
                LabeledContent("最近提示", value: error)
            }
        }
    }

    private var modesSection: some View {
        Section("定位精度") {
            ForEach(TrackingMode.allCases) { mode in
                modeRow(mode)
            }
        }
    }

    private func modeRow(_ mode: TrackingMode) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: mode.symbol)
                .foregroundStyle(mode == locationService.mode ? Color.cyan : Color.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(mode.title).font(.subheadline.weight(.semibold))
                Text(mode.subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var permissionsSection: some View {
        Section {
            LabeledContent("定位", value: locationService.authorizationLabel)
            LabeledContent("精确位置", value: locationService.accuracyAuthorization == .fullAccuracy ? "开启" : "关闭")
            LabeledContent("后台 App 刷新", value: backgroundRefreshLabel)
            permissionButton
            if locationService.accuracyAuthorization == .reducedAccuracy {
                Button("临时启用精确位置") { locationService.requestTemporaryFullAccuracy() }
            }
        } header: {
            Text("系统权限")
        } footer: {
            Text("全天自动记录要求“始终”定位权限。iOS Live Updates 会在设备静止后自动暂停位置更新，并在重新移动时恢复；显著位置变化和到访事件不再作为轨迹记录或恢复机制。")
        }
    }

    @ViewBuilder
    private var permissionButton: some View {
        switch locationService.authorizationStatus {
        case .notDetermined:
            Button("允许定位") { locationService.requestWhenInUseAuthorization() }
        case .authorizedWhenInUse:
            Button("请求“始终允许”") { locationService.requestAlwaysAuthorization() }
            Button("在系统设置中修改") { locationService.openSystemSettings() }
        case .denied, .restricted:
            Button("打开系统设置") { locationService.openSystemSettings() }
        default:
            EmptyView()
        }
    }

    private var dataSection: some View {
        Section {
            LabeledContent("本地占用", value: AppFormatters.bytes(repository.databaseBytes))
            LabeledContent("轨迹点", value: repository.lifetime.pointCount.formatted())
            Button("导出全部为 GPX") { prepareExport(asGPX: true) }
                .disabled(isExporting || repository.lifetime.pointCount == 0)
            Button("导出全部为 GeoJSON") { prepareExport(asGPX: false) }
                .disabled(isExporting || repository.lifetime.pointCount == 0)
            Button("导入 GPX 或 GeoJSON") { showImporter = true }
            Button("删除全部轨迹", role: .destructive) { beginDeleteEverything() }
#if ARO_CLOUDKIT_ENABLED
                .disabled((repository.lifetime.pointCount == 0 && !cloudSync.hasCloudData) || cloudSync.isSyncing)
#else
                .disabled(repository.lifetime.pointCount == 0)
#endif
        } header: {
            Text("数据")
        } footer: {
#if ARO_CLOUDKIT_ENABLED
            Text("SQLite 始终保留一份本地轨迹。关闭 iCloud 同步不会删除已有云端副本；“删除全部轨迹”会同时清理已存在的 iCloud 数据。")
#else
            Text("SQLite 始终保留一份本地轨迹。当前 Local / Personal Team 构建只管理本机数据。")
#endif
        }
    }

#if ARO_CLOUDKIT_ENABLED
    private var iCloudSection: some View {
        Section {
            Toggle(
                "iCloud 同步",
                isOn: Binding(
                    get: { cloudSync.isEnabled },
                    set: { cloudSync.setEnabled($0) }
                )
            )
            LabeledContent("状态", value: cloudSync.statusText)
            if let lastSyncAt = cloudSync.lastSyncAt {
                LabeledContent(
                    "最后同步",
                    value: lastSyncAt.formatted(.dateTime.month().day().hour().minute())
                )
            }
            Button("立即同步") {
                Task { await cloudSync.syncNow() }
            }
            .disabled(!cloudSync.isEnabled || cloudSync.isSyncing)
        } header: {
            Text("iCloud")
        } footer: {
            Text("同步默认关闭。开启后使用你的 CloudKit 私有数据库在同一 Apple 账户的设备间同步轨迹；aro 不使用自建服务器或分析服务。")
        }
    }
#endif

    private var localICloudSection: some View {
        Section {
            Label("iCloud 同步", systemImage: "icloud.slash")
            Text("当前 Local / Personal Team 构建未启用 iCloud 同步。轨迹仍会保存在本机 SQLite 中。")
                .font(.footnote)
                .foregroundStyle(.secondary)
#if !ARO_CLOUDKIT_ENABLED
            if localBuildMayHaveCloudData {
                Label("检测到此安装曾使用 iCloud 同步。Local 构建不会删除云端副本。", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
#endif
        } header: {
            Text("iCloud")
        } footer: {
            Text("如需使用 iCloud 私有数据库同步，请选择 CloudDebug 或 CloudRelease 构建，并使用支持 CloudKit 的开发团队签名。")
        }
    }

    private var aboutSection: some View {
        Section("关于") {
            LabeledContent("产品", value: "aro")
            LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.0")
            Button("重新查看隐私引导") { hasCompletedOnboarding = false }
        }
    }

    private var lastRecordedText: String {
        locationService.lastRecordedAt?.formatted(.dateTime.month().day().hour().minute()) ?? "暂无"
    }

    private var backgroundRefreshLabel: String {
        switch UIApplication.shared.backgroundRefreshStatus {
        case .available: "开启"
        case .denied: "关闭"
        case .restricted: "受限制"
        @unknown default: "未知"
        }
    }

#if !ARO_CLOUDKIT_ENABLED
    private var localBuildMayHaveCloudData: Bool {
        let defaults = UserDefaults.standard
        return defaults.bool(forKey: "icloudSync.hasCloudData")
            || defaults.double(forKey: "icloudSync.lastSyncAt") > 0
    }
#endif

    private func beginDeleteEverything() {
#if !ARO_CLOUDKIT_ENABLED
        guard !localBuildMayHaveCloudData else {
            deleteError = "此安装以前使用过 iCloud 同步，云端轨迹可能仍然存在。Local 构建无法安全完成“删除全部轨迹”；请改用 CloudDebug 或 CloudRelease 构建删除，避免以后重新启用 iCloud 时数据被同步回来。"
            return
        }
#endif
        showDeleteConfirmation = true
    }

    private var deleteConfirmationMessage: String {
#if ARO_CLOUDKIT_ENABLED
        if cloudSync.hasCloudData {
            return "这会从本机和你的 iCloud 私有数据库永久删除全部轨迹；其他已开启同步的设备收到云端删除后也会清空本地轨迹。此操作无法撤销，建议先导出备份。"
        }
#endif
        return "此操作无法撤销，建议先导出备份。"
    }

    private func deleteEverything() {
#if ARO_CLOUDKIT_ENABLED
        if cloudSync.hasCloudData {
            Task {
                do {
                    try await cloudSync.deleteCloudAndLocalData()
                } catch {
                    deleteError = error.localizedDescription
                }
            }
        } else {
            repository.deleteEverything()
        }
#else
        guard !localBuildMayHaveCloudData else {
            deleteError = "此安装以前使用过 iCloud 同步，云端轨迹可能仍然存在。请切换到 CloudDebug 或 CloudRelease 构建后再删除全部轨迹。"
            return
        }
        repository.deleteEverything()
#endif
    }

    private func prepareExport(asGPX: Bool) {
        isExporting = true
        Task.detached(priority: .userInitiated) {
            let points = TrackDatabase.shared.allPoints()
            let name = "aro \(Date.now.formatted(.iso8601.year().month().day()))"
            let data = asGPX ? TrackExport.gpx(points: points, name: name) : TrackExport.geoJSON(points: points, name: name)
            await MainActor.run {
                exportType = asGPX ? .xml : .json
                exportFilename = asGPX ? "aro.gpx" : "aro.geojson"
                exportDocument = TrackDocument(data: data)
                isExporting = false
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let hasAccess = url.startAccessingSecurityScopedResource()
            Task.detached(priority: .userInitiated) {
                defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    let points = try TrackImport.parse(data: data, fileExtension: url.pathExtension)
                    let count = TrackDatabase.shared.insertImported(points)
                    await MainActor.run {
                        repository.refresh(includeOverview: true)
#if ARO_CLOUDKIT_ENABLED
                        if cloudSync.isEnabled { cloudSync.appBecameActive() }
#endif
                        importMessage = "成功导入 \(count.formatted()) 个轨迹点。"
                    }
                } catch {
                    await MainActor.run { importMessage = error.localizedDescription }
                }
            }
        } catch {
            importMessage = error.localizedDescription
        }
    }
}
