import SwiftUI

struct WatchContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var reporter: WatchBatteryService

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: reporter.snapshot?.state.symbolName ?? "battery.0percent")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(gaugeColor)

            Text(reporter.snapshot.map { "\($0.level)%" } ?? "--")
                .font(.system(size: 38, weight: .bold, design: .rounded))

            Text(reporter.snapshot?.state.label ?? "正在读取")
                .font(.caption)
                .foregroundStyle(.secondary)

            Label(
                reporter.isReachable ? "iPhone 已连接" : "等待同步",
                systemImage: reporter.isReachable ? "iphone.radiowaves.left.and.right" : "iphone.slash"
            )
            .font(.caption2)
            .foregroundStyle(reporter.isReachable ? .green : .secondary)

            Text(versionLabel)
                .font(.system(size: 9, weight: .regular, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                reporter.startForegroundUpdates()
            } else {
                reporter.stopForegroundUpdates()
            }
        }
    }

    private var gaugeColor: Color {
        guard let level = reporter.snapshot?.level else { return .gray }
        if level < 20 { return .red }
        if level < 40 { return .orange }
        return .green
    }

    private var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "v\(version) (\(build))"
    }
}

#Preview {
    WatchContentView()
        .environmentObject(WatchBatteryService.shared)
}
