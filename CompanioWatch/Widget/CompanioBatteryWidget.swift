import SwiftUI
import WidgetKit

struct CompanioBatteryWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: BatterySnapshot?
}

struct CompanioBatteryWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CompanioBatteryWidgetEntry {
        CompanioBatteryWidgetEntry(date: .now, snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (CompanioBatteryWidgetEntry) -> Void) {
        completion(CompanioBatteryWidgetEntry(date: .now, snapshot: WatchSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CompanioBatteryWidgetEntry>) -> Void) {
        let entry = CompanioBatteryWidgetEntry(date: .now, snapshot: WatchSnapshotStore.load())
        let nextRefresh = Date(timeIntervalSinceNow: 30 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct CompanioBatteryWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family

    let entry: CompanioBatteryWidgetEntry

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
            VStack(spacing: -2) {
                Image(systemName: symbolName)
                    .font(.caption)
                Text(levelText)
                    .font(.caption2.weight(.semibold))
            }
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

struct CompanioBatteryWidget: Widget {
    static let kind = WatchSnapshotStore.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: CompanioBatteryWidgetProvider()) { entry in
            CompanioBatteryWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Companio 电量")
        .description("显示 Apple Watch 最近同步的电量。")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline,
            .accessoryRectangular
        ])
    }
}

@main
struct CompanioBatteryWidgetBundle: WidgetBundle {
    var body: some Widget {
        CompanioBatteryWidget()
    }
}
