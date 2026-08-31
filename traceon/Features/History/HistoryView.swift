import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var repository: TrackRepository

    var body: some View {
        Group {
            if repository.days.isEmpty {
                ContentUnavailableView("还没有历史轨迹", systemImage: "calendar.badge.clock", description: Text("开始记录后，每一天会自动整理到这里。"))
            } else {
                List(repository.days) { day in
                    NavigationLink(value: day) {
                        dayRow(day)
                    }
                }
                .listStyle(.insetGrouped)
                .navigationDestination(for: TrackDay.self) { day in
                    DayDetailView(day: day)
                }
            }
        }
        .navigationTitle("历史")
        .refreshable { repository.refresh() }
    }

    private func dayRow(_ day: TrackDay) -> some View {
        HStack(spacing: 14) {
            VStack(spacing: 0) {
                Text(day.date.formatted(.dateTime.day()))
                    .font(.title2.bold())
                Text(day.date.formatted(.dateTime.month(.abbreviated)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 48, height: 52)
            .background(Color.cyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 5) {
                Text(day.date.formatted(.dateTime.year().month(.wide).day().weekday(.wide)))
                    .font(.headline)
                Text("\(AppFormatters.distance(day.distance)) · \(day.pointCount) 个轨迹点")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct DayDetailView: View {
    let day: TrackDay
    @EnvironmentObject private var repository: TrackRepository
    @State private var points: [TrackPoint] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if points.isEmpty, isLoading {
                    ProgressView().frame(maxWidth: .infinity).frame(height: 380)
                } else {
                    TrackMapView(points: points)
                        .frame(height: 430)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }

                HStack(spacing: 12) {
                    MetricCard(title: "当日距离", value: AppFormatters.distance(day.distance), symbol: "arrow.triangle.swap")
                    MetricCard(title: "记录点", value: day.pointCount.formatted(), symbol: "mappin")
                }
                HStack(spacing: 12) {
                    MetricCard(title: "开始", value: day.firstPointAt.formatted(.dateTime.hour().minute()), symbol: "sunrise.fill")
                    MetricCard(title: "结束", value: day.lastPointAt.formatted(.dateTime.hour().minute()), symbol: "sunset.fill")
                }
            }
            .padding()
        }
        .navigationTitle(day.date.formatted(.dateTime.month().day()))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            points = await repository.loadPoints(on: day.date)
            isLoading = false
        }
    }
}

