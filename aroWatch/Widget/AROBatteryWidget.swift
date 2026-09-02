import Foundation
import SwiftUI
import WatchKit
import WidgetKit

struct AROBatteryWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: BatterySnapshot?
}

struct AROBatteryWidgetProvider: TimelineProvider {
    private static let batterySamplingDelay: TimeInterval = 1

    func placeholder(in context: Context) -> AROBatteryWidgetEntry {
        AROBatteryWidgetEntry(date: .now, snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (AROBatteryWidgetEntry) -> Void) {
        completion(AROBatteryWidgetEntry(date: .now, snapshot: WatchSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AROBatteryWidgetEntry>) -> Void) {
        if !WatchSnapshotStore.shouldSampleBattery() {
            let entry = AROBatteryWidgetEntry(date: .now, snapshot: WatchSnapshotStore.load())
            completion(Timeline(entries: [entry], policy: .after(Date(timeIntervalSinceNow: 30 * 60))))
            return
        }

        loadFreshSnapshot { freshSnapshot in
            if let freshSnapshot {
                WatchSnapshotStore.save(freshSnapshot)
            }

            let entry = AROBatteryWidgetEntry(
                date: .now,
                snapshot: freshSnapshot ?? WatchSnapshotStore.load()
            )
            let nextRefresh = Date(timeIntervalSinceNow: 30 * 60)
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }

    private func loadFreshSnapshot(completion: @escaping (BatterySnapshot?) -> Void) {
        DispatchQueue.main.async {
            let device = WKInterfaceDevice.current()
            device.isBatteryMonitoringEnabled = true

            DispatchQueue.main.asyncAfter(deadline: .now() + Self.batterySamplingDelay) {
                let rawLevel = device.batteryLevel
                defer { device.isBatteryMonitoringEnabled = false }

                guard rawLevel >= 0 else {
                    completion(nil)
                    return
                }

                completion(
                    BatterySnapshot(
                        level: Int((rawLevel * 100).rounded()),
                        state: BatteryChargeState(widgetState: device.batteryState),
                        deviceName: device.name
                    )
                )
            }
        }
    }
}

private extension BatteryChargeState {
    init(widgetState state: WKInterfaceDeviceBatteryState) {
        switch state {
        case .unknown: self = .unknown
        case .unplugged: self = .unplugged
        case .charging: self = .charging
        case .full: self = .full
        @unknown default: self = .unknown
        }
    }
}

struct AROBatteryWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family

    let entry: AROBatteryWidgetEntry

    private var levelText: String {
        entry.snapshot.map { "\($0.level)%" } ?? "--%"
    }

    private var shortLevelText: String {
        entry.snapshot.map { "\($0.level)" } ?? "--"
    }

    private var symbolName: String {
        entry.snapshot?.state.symbolName ?? "battery.0percent"
    }

    private var stateLabel: String {
        entry.snapshot?.state.label ?? "等待同步"
    }

    var body: some View {
        content
            .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            UltraBatteryCircularView(snapshot: entry.snapshot)
        case .accessoryCorner:
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: symbolName)
                    .font(.caption2)
                Text(shortLevelText)
                    .font(.caption2.weight(.semibold))
            }
        case .accessoryInline:
            Label("Watch \(levelText)", systemImage: symbolName)
                .font(.caption)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("Apple Watch")
                    .font(.headline)
                Text("\(levelText) · \(stateLabel)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        default:
            Label("Watch \(levelText)", systemImage: symbolName)
                .font(.caption)
        }
    }
}

private struct UltraBatteryCircularView: View {
    let snapshot: BatterySnapshot?

    private var level: Int { snapshot?.level ?? 0 }
    private var progress: Double { Double(level) / 100 }

    private var accent: Color {
        if snapshot?.state == .charging || snapshot?.state == .full { return .green }
        if level <= 20, snapshot != nil { return .red }
        return .orange
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.22), lineWidth: 3.5)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(accent, style: StrokeStyle(lineWidth: 3.5, lineCap: .butt))
                .rotationEffect(.degrees(-90))

            ForEach(0..<24, id: \.self) { index in
                Capsule()
                    .fill(tickColor(at: index))
                    .frame(width: 1.2, height: index.isMultiple(of: 6) ? 4.5 : 3)
                    .offset(y: -25)
                    .rotationEffect(.degrees(Double(index) * 15))
            }

            VStack(spacing: -2) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(accent)
                Text(snapshot.map { "\($0.level)" } ?? "--")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.75)
                Text("%")
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.65))
            }
        }
    }

    private func tickColor(at index: Int) -> Color {
        let tickProgress = Double(index + 1) / 24
        return tickProgress <= progress ? accent.opacity(0.9) : Color.white.opacity(0.18)
    }
}

struct AROBatteryWidget: Widget {
    static let kind = WatchSnapshotStore.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: AROBatteryWidgetProvider()) { entry in
            AROBatteryWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("aro 电量")
        .description("显示 Apple Watch 最近同步的电量。")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline,
            .accessoryRectangular
        ])
    }
}

struct AROTrackWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: TrackComplicationSnapshot?
}

struct AROTrackWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> AROTrackWidgetEntry {
        AROTrackWidgetEntry(date: .now, snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (AROTrackWidgetEntry) -> Void) {
        completion(AROTrackWidgetEntry(date: .now, snapshot: WatchSnapshotStore.loadTrack()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AROTrackWidgetEntry>) -> Void) {
        let entry = AROTrackWidgetEntry(date: .now, snapshot: WatchSnapshotStore.loadTrack())
        let calendar = Calendar.autoupdatingCurrent
        let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now))
            ?? Date(timeIntervalSinceNow: 12 * 60 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextDay)))
    }
}

struct AROTrackWidgetEntryView: View {
    let entry: AROTrackWidgetEntry

    private var distance: (value: String, unit: String) {
        guard let snapshot = entry.snapshot else { return ("--", "km") }
        let meters = snapshot.distanceMeters
        if meters < 1_000 {
            return (String(Int(meters.rounded())), "m")
        }

        let kilometers = meters / 1_000
        if kilometers < 10 {
            return (String(format: "%.2f", kilometers), "km")
        }
        if kilometers < 100 {
            return (String(format: "%.1f", kilometers), "km")
        }
        return (String(Int(kilometers.rounded())), "km")
    }

    var body: some View {
        VStack(spacing: 0) {
            TrackRouteMiniature(segments: entry.snapshot?.segments ?? [])
                .frame(height: 23)

            Text(distance.value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.65)
                .lineLimit(1)

            Text(distance.unit)
                .font(.system(size: 6.5, weight: .bold, design: .rounded))
                .foregroundStyle(.blue)
        }
        .padding(.horizontal, 3)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

private struct TrackRouteMiniature: View {
    let segments: [TrackComplicationSegment]

    var body: some View {
        Canvas { context, size in
            guard !segments.isEmpty else {
                let symbol = context.resolve(Image(systemName: "point.topleft.down.to.point.bottomright.curvepath"))
                context.draw(symbol, at: CGPoint(x: size.width / 2, y: size.height / 2))
                return
            }

            for segment in segments where segment.points.count > 1 {
                var path = Path()
                for (index, point) in segment.points.enumerated() {
                    let position = CGPoint(x: point.x * size.width, y: point.y * size.height)
                    if index == 0 {
                        path.move(to: position)
                    } else {
                        path.addLine(to: position)
                    }
                }
                context.stroke(
                    path,
                    with: .color(.blue),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
            }

            if let endpoint = segments.last?.points.last {
                let center = CGPoint(x: endpoint.x * size.width, y: endpoint.y * size.height)
                let marker = Path(ellipseIn: CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4))
                context.fill(marker, with: .color(.blue))
            }
        }
    }
}

struct AROTrackWidget: Widget {
    static let kind = WatchSnapshotStore.trackWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: AROTrackWidgetProvider()) { entry in
            AROTrackWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("aro 轨迹")
        .description("显示今天的路线形状和累计距离。")
        .supportedFamilies([.accessoryCircular])
    }
}

@main
struct AROBatteryWidgetBundle: WidgetBundle {
    var body: some Widget {
        AROBatteryWidget()
        AROTrackWidget()
    }
}
