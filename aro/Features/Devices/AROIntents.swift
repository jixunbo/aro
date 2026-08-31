import AppIntents
import Foundation

struct BatteryDevice: AppEntity, Identifiable, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "设备")
    static let defaultQuery = BatteryDeviceQuery()

    static let appleWatch = BatteryDevice(id: "apple-watch", name: "Apple Watch")

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: "applewatch"))
    }
}

struct BatteryDeviceQuery: EntityQuery {
    func entities(for identifiers: [BatteryDevice.ID]) async throws -> [BatteryDevice] {
        identifiers.contains(BatteryDevice.appleWatch.id) ? [await currentDevice()] : []
    }

    func suggestedEntities() async throws -> [BatteryDevice] {
        [await currentDevice()]
    }

    func defaultResult() async -> BatteryDevice? {
        await currentDevice()
    }

    private func currentDevice() async -> BatteryDevice {
        let name = await MainActor.run {
            BatteryStore.shared.snapshot?.deviceName ?? "Apple Watch"
        }
        return BatteryDevice(id: BatteryDevice.appleWatch.id, name: name)
    }
}

struct GetDeviceBatteryLevelIntent: AppIntent {
    static let title: LocalizedStringResource = "获取设备的电量"
    static let description = IntentDescription(
        "获取 Apple Watch 最近同步的电量；手表在线时会先尝试刷新。",
        categoryName: "电池",
        searchKeywords: ["Apple Watch", "手表", "电量", "电池"],
        resultValueName: "电量"
    )
    static let openAppWhenRun = false

    @Parameter(title: "设备", description: "要查询电量的设备")
    var device: BatteryDevice

    static var parameterSummary: some ParameterSummary {
        Summary("获取 \(\.$device) 的电量")
    }

    init() {
        device = .appleWatch
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let snapshot = await PhoneConnectivity.shared.freshestSnapshot()
        guard let snapshot else { throw BatteryIntentError.noData }

        let age = max(0, Int(Date.now.timeIntervalSince(snapshot.updatedAt) / 60))
        let freshness = age < 1 ? "刚刚同步" : "\(age) 分钟前同步"
        return .result(
            value: snapshot.level,
            dialog: "\(snapshot.deviceName) 最近同步的电量为 \(snapshot.level)%，\(freshness)。"
        )
    }
}

enum BatteryIntentError: Error, CustomLocalizedStringResourceConvertible {
    case noData

    var localizedStringResource: LocalizedStringResource {
        "尚未收到 Apple Watch 电量。请先在手表上打开一次 ARO。"
    }
}

struct AROShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetDeviceBatteryLevelIntent(),
            phrases: [
                "用 \(.applicationName) 获取手表电量",
                "在 \(.applicationName) 查询 Apple Watch 电量",
                "获取 \(.applicationName) 的设备电量"
            ],
            shortTitle: "获取设备电量",
            systemImageName: "battery.75percent"
        )
    }
}
