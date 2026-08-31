import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject private var reporter: CompanioBatteryReporter

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
        }
        .onAppear { reporter.startForegroundUpdates() }
        .onDisappear { reporter.stopForegroundUpdates() }
    }

    private var gaugeColor: Color {
        guard let level = reporter.snapshot?.level else { return .gray }
        if level < 20 { return .red }
        if level < 40 { return .orange }
        return .green
    }
}

#Preview {
    WatchContentView()
        .environmentObject(CompanioBatteryReporter.shared)
}
