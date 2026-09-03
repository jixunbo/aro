import SwiftUI

struct OnboardingView: View {
    @Binding var isComplete: Bool
    @EnvironmentObject private var locationService: LocationService
    @State private var page = 0

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, Color(red: 0.02, green: 0.13, blue: 0.19)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                TabView(selection: $page) {
                    pageView(
                        symbol: "point.topleft.down.to.point.bottomright.curvepath",
                        title: "把走过的路留下来",
                        detail: "aro 使用 iOS Live Updates 在后台记录路线；静止时系统会自动暂停定位更新，移动后自动恢复。"
                    ).tag(0)
                    pageView(
                        symbol: "lock.shield.fill",
                        title: "位置只属于你",
                        detail: "不需要账号，轨迹默认只保存在这台设备上。你可以随时导出或彻底删除。"
                    ).tag(1)
                    permissionPage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                Button(action: advance) {
                    Text(buttonTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.cyan, in: Capsule())
                        .foregroundStyle(.black)
                }
                .padding(.horizontal, 28)

                Spacer().frame(height: 12)
            }
        }
    }

    private func pageView(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: symbol)
                .font(.system(size: 72, weight: .thin))
                .foregroundStyle(.cyan)
            Text(title).font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text(detail)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
        }
    }

    private var permissionPage: some View {
        VStack(spacing: 22) {
            Image(systemName: locationService.hasAlwaysAuthorization ? "checkmark.circle.fill" : "location.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(locationService.hasAlwaysAuthorization ? .green : .cyan)
            Text("允许后台记录").font(.largeTitle.bold())
            Text(permissionDetail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
            Text("当前权限：\(locationService.authorizationLabel)")
                .font(.callout.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.thinMaterial, in: Capsule())
        }
    }

    private var permissionDetail: String {
        locationService.authorizationStatus == .authorizedWhenInUse
            ? "下一步请选择“始终允许”。aro 的全天自动记录只在获得“始终”定位权限后启动。"
            : "iOS 会分阶段询问定位权限。aro 只在你开启记录后保持后台定位会话。"
    }

    private var buttonTitle: String {
        guard page == 2 else { return "继续" }
        switch locationService.authorizationStatus {
        case .notDetermined: return "允许使用定位"
        case .authorizedWhenInUse: return "允许始终定位"
        case .authorizedAlways: return "开始记录"
        case .denied, .restricted: return "打开系统设置"
        @unknown default: return "继续"
        }
    }

    private func advance() {
        guard page == 2 else {
            withAnimation { page += 1 }
            return
        }
        switch locationService.authorizationStatus {
        case .notDetermined:
            locationService.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            locationService.requestAlwaysAuthorization()
        case .authorizedAlways:
            locationService.isTrackingEnabled = true
            isComplete = true
        case .denied, .restricted:
            locationService.openSystemSettings()
        @unknown default:
            break
        }
    }
}
