import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var repository: TrackRepository
    @EnvironmentObject private var locationService: LocationService

    private var distance: Double { TrackMath.distance(of: repository.todayPoints) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                statusCard

                if repository.todayPoints.isEmpty {
                    emptyMap
                } else {
                    TrackMapView(points: repository.todayPoints, showsUserLocation: true)
                        .frame(height: 390)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(alignment: .topLeading) {
                            Text("今日轨迹")
                                .font(.headline)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(14)
                        }
                }

                HStack(spacing: 12) {
                    MetricCard(title: "距离", value: AppFormatters.distance(distance), symbol: "point.topleft.down.to.point.bottomright.curvepath")
                    MetricCard(title: "轨迹点", value: repository.todayPoints.count.formatted(), symbol: "mappin.and.ellipse")
                }

                HStack(spacing: 12) {
                    MetricCard(title: "活动", value: locationService.currentActivity, symbol: "figure.walk.motion")
                    MetricCard(title: "最后记录", value: lastRecordedText, symbol: "clock.fill")
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(Date.now.formatted(.dateTime.month(.wide).day().weekday(.wide)))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { repository.refresh() } label: {
                    Image(systemName: repository.isLoading ? "hourglass" : "arrow.clockwise")
                }
                .disabled(repository.isLoading)
            }
        }
    }

    private var statusCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(locationService.isTrackingEnabled ? Color.green.opacity(0.16) : Color.orange.opacity(0.16))
                Image(systemName: locationService.isTrackingEnabled ? "location.fill" : "pause.fill")
                    .foregroundStyle(locationService.isTrackingEnabled ? .green : .orange)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(locationService.isTrackingEnabled ? "正在自动记录" : "记录已暂停")
                    .font(.headline)
                Text("\(locationService.mode.title) · 定位权限：\(locationService.authorizationLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("记录", isOn: $locationService.isTrackingEnabled).labelsHidden()
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var emptyMap: some View {
        ContentUnavailableView {
            Label("等待第一段足迹", systemImage: "map")
        } description: {
            Text(locationService.isTrackingEnabled ? "带着手机移动一段距离，轨迹会自动出现在这里。" : "开启自动记录后，traceon 才会保存位置。")
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var lastRecordedText: String {
        guard let date = locationService.lastRecordedAt else { return "暂无" }
        return date.formatted(.dateTime.hour().minute())
    }
}
