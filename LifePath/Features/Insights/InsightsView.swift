import SwiftUI

struct InsightsView: View {
    @EnvironmentObject private var repository: TrackRepository

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ZStack(alignment: .topLeading) {
                    if repository.overviewPoints.isEmpty {
                        ContentUnavailableView("足迹正在积累", systemImage: "globe.asia.australia", description: Text("有了轨迹后，这里会显示你走过的所有地方。"))
                    } else {
                        TrackMapView(points: repository.overviewPoints, overview: true)
                    }

                    Text("一生足迹")
                        .font(.title2.bold())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(14)
                }
                .frame(height: 420)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

                HStack(spacing: 12) {
                    MetricCard(title: "累计距离", value: AppFormatters.distance(repository.lifetime.distance), symbol: "road.lanes")
                    MetricCard(title: "记录天数", value: repository.lifetime.dayCount.formatted(), symbol: "calendar")
                }
                HStack(spacing: 12) {
                    MetricCard(title: "坐标数量", value: repository.lifetime.pointCount.formatted(), symbol: "circle.grid.cross")
                    MetricCard(title: "开始于", value: firstDateText, symbol: "flag.checkered")
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("足迹总览")
        .task {
            repository.refresh(includeOverview: true)
            repository.loadOverview()
        }
    }

    private var firstDateText: String {
        repository.lifetime.firstDate?.formatted(.dateTime.year().month().day()) ?? "暂无"
    }
}

