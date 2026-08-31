import SwiftUI

struct DevicesView: View {
    let isSelected: Bool

    @StateObject private var store = BatteryStore.shared
    @StateObject private var connectivity = PhoneConnectivity.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var isRefreshing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if !connectivity.isWatchAppInstalled || store.snapshot == nil {
                    setupCard
                }
                batteryCard
                connectionCard
                shortcutCard
            }
            .padding(20)
        }
        .background(background)
        .navigationTitle("设备")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    refresh()
                } label: {
                    if isRefreshing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshing)
                .accessibilityLabel("刷新手表电量")
            }
        }
        .task(id: isSelected) {
            guard isSelected else { return }
            refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, isSelected {
                refresh()
            }
        }
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                connectivity.isWatchAppInstalled ? "正在同步 Apple Watch" : "自动准备 Apple Watch",
                systemImage: connectivity.isWatchAppInstalled ? "arrow.triangle.2.circlepath" : "applewatch"
            )
            .font(.headline)

            if connectivity.isWatchAppInstalled {
                Text("手表组件已安装，正在等待第一条电量数据。通常不需要额外设置；如果几分钟后仍无数据，请在手表上打开一次 ARO。")
            } else {
                Text("ARO 已包含 Apple Watch 组件。若系统没有自动安装，请在 iPhone 的 Watch App → 我的手表 → 可用 App 中安装 ARO；开启自动安装后无需手动配对。")
            }

            Text("安装状态会在 App 回到前台时自动检查。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if !connectivity.isWatchAppInstalled {
                Button("重新检查") {
                    connectivity.appBecameActive()
                }
                .buttonStyle(.bordered)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(18)
        .deviceCardStyle()
    }

    private var batteryCard: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.10), lineWidth: 16)

                Circle()
                    .trim(from: 0, to: CGFloat(store.snapshot?.level ?? 0) / 100)
                    .stroke(
                        gaugeColor,
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.6), value: store.snapshot?.level)

                VStack(spacing: 4) {
                    Image(systemName: "applewatch")
                        .font(.title2)
                    Text(store.snapshot.map { "\($0.level)%" } ?? "--")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                    Text(store.snapshot?.state.label ?? "等待同步")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 210, height: 210)

            VStack(spacing: 5) {
                Text(store.snapshot?.deviceName ?? "Apple Watch")
                    .font(.headline)
                if let date = store.snapshot?.updatedAt {
                    Text("最近同步于 \(date.formatted(date: .omitted, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if !connectivity.isReachable {
                        Text("当前显示缓存，不代表实时电量")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                } else {
                    Text("请在 Apple Watch 上打开一次 ARO")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .deviceCardStyle()
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("连接状态", systemImage: "antenna.radiowaves.left.and.right")
                .font(.headline)

            statusRow(
                title: "手表 App",
                value: connectivity.isWatchAppInstalled ? "已安装" : "未安装",
                good: connectivity.isWatchAppInstalled
            )
            statusRow(
                title: "实时连接",
                value: connectivity.isReachable ? "可用" : "使用缓存",
                good: connectivity.isReachable
            )

            if let error = connectivity.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .padding(18)
        .deviceCardStyle()
    }

    private var shortcutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("快捷指令", systemImage: "square.stack.3d.up.fill")
                .font(.headline)

            Text("在快捷指令中搜索“获取设备电量”，选择 Apple Watch。动作会返回 0–100 的整数，可直接接在“如果电量小于 35”后面。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            Label("建议每天先打开一次手表端 App，让后台刷新更稳定。", systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .deviceCardStyle()
    }

    private func statusRow(title: String, value: String, good: Bool) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(good ? .green : .orange)
                    .frame(width: 8, height: 8)
                Text(value)
                    .fontWeight(.medium)
            }
        }
    }

    private var gaugeColor: Color {
        guard let level = store.snapshot?.level else { return .gray }
        if level < 20 { return .red }
        if level < 40 { return .orange }
        return .green
    }

    private var background: some View {
        LinearGradient(
            colors: [Color.green.opacity(0.12), Color(.systemBackground)],
            startPoint: .topLeading,
            endPoint: .center
        )
        .ignoresSafeArea()
    }

    private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            _ = await connectivity.freshestSnapshot()
            isRefreshing = false
        }
    }
}

private extension View {
    func deviceCardStyle() -> some View {
        background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.10))
            }
    }
}

#Preview {
    NavigationStack {
        DevicesView(isSelected: true)
    }
}
