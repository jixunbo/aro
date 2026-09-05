# aro

aro（Everything Around You）是一款隐私优先的 iOS + watchOS App：在 iPhone 上低功耗记录全天足迹，并同步显示 Apple Watch 最近一次有效电量快照。轨迹始终保存在本地 SQLite；用户也可以选择开启 iCloud 私有数据库同步，不需要 aro 账号、自建服务器或分析服务。

## 系统要求

- iPhone / iPad：iOS / iPadOS 26.0 或更高版本。aro 2.0 不提供 iOS 17–25 的兼容定位实现。
- Apple Watch：watchOS 10.0 或更高版本。
- 开发环境：Xcode 26 或更高版本。

## 功能

- 四档定位模式：极省电、均衡、精确、运动。
- 极省电模式使用 Motion & Fitness 活动识别 + 高质量 Standard Core Location + 约 100 m `distanceFilter`，把主要省电放在系统产生定位更新这一层；移动里程点若精度暂时不够，会做一次短时有界的精度恢复，而不是直接丢掉后继续等下一个 100 m。
- 均衡/精确/运动使用 iOS 26 `CLLocationUpdate.liveUpdates`；全天记录统一使用显式 `CLServiceSession(.always)`。
- 极省电在系统自动暂停或 Motion 持续静止后，先取得新鲜高质量静止点，再建立约 50 m persistent `CLMonitor` 并停止 Standard updates；离开静止范围后由 Core Location 唤醒并重新开始距离驱动定位。
- 均衡通过约 5 分钟的 robust 空间稳定窗口主动进入 60 m `CLMonitor`。少量 GPS outlier 不再阻止休眠，同时用前后稳定中心漂移限制避免把缓慢真实移动误判为静止。
- 精确/运动模式使用 `CLBackgroundActivitySession` 保持及时后台交付，因此更适合需要更完整实时轨迹的场景，也会比均衡/极省电更耗电。
- 自适应轨迹保存结合距离、时间、定位精度噪声和转弯变化决定是否保存点。均衡模式正常直线约 35 米级保存，同时允许较短距离的真实转弯提前落点。
- 后台恢复后允许处理当前记录会话内排队的历史定位，不再使用会误删合法后台点的 180 秒墙钟 freshness 限制。
- 设置页区分“更新 / 定位 / 保存 / 过滤”，并显示真实运行状态；Core Location 没有报告 stationary 不再被错误显示成“正在移动”。
- 今日轨迹、历史日历、足迹总览和距离统计。
- GPX 与 GeoJSON 导入/导出。
- 本地 SQLite/WAL 存储，适合长期积累大量坐标。
- 可选 CloudKit 私有数据库轨迹同步，SQLite 仍是本地 source of truth。
- 分阶段定位授权、数据保留与一键删除。
- Apple Watch 电量、充电状态、设备名与最后同步时间。
- “获取设备电量”快捷指令；手表可达时主动刷新，不可达时明确使用缓存。
- watchOS 系统调度的后台电量刷新。
- Apple Watch WidgetKit 电量复杂功能：圆形样式采用 Ultra 风格刻度环，>50% 绿色、21–50% 橙色、≤20% 红色，充电/已充满始终绿色。
- Apple Watch WidgetKit 圆形“aro 轨迹”复杂功能：显示当天路线缩略图和累计距离。

## 定位模式

- **极省电**：Motion 活动识别 + Standard Core Location，高质量定位，`distanceFilter ≈ 100 m`，允许系统自动暂停；Motion-only 静止需持续约 2 分钟，随后用新鲜静止点切换到约 50 m persistent `CLMonitor`。移动中的 100 m 回调若只差定位质量，会短暂尝试恢复一个 ≤30 m 的更好 fix 后立即回到 100 m cadence，并限制为约每分钟最多启动一次，避免弱信号时退化成持续高频定位。目标行为贴近实测的一生足迹省电模式：移动时约百米级高质量点，静止时真正停止持续定位。
- **均衡**：`.default` Live Updates。正常移动约 35 米级保存，最长约 60 秒且确有移动时补点，明显转弯可更早保存；约 5 分钟稳定静止后切到 60 m `CLMonitor`。推荐日常足迹。
- **精确**：`.otherNavigation` + 及时后台活动，约 20 米级保存。
- **运动**：`.fitness` + 及时后台活动，约 8 米级保存。

极省电的约 100 m 是 Core Location 的 `distanceFilter`，系统仍可因启动或精度改善额外交付位置；均衡/精确/运动的“约 N 米级”主要描述 aro 的数据保存策略。Core Location 的实际后台交付时机仍由系统决定。

## 构建配置与运行

1. 使用 Xcode 26 或更新版本打开 `aro.xcodeproj`。共享的 `aro` scheme 保留为唯一 scheme，`Debug`/`Release` 是 Local 版，`CloudDebug`/`CloudRelease` 是 Cloud 版。
2. Local 版（`Debug` 或 `Release`）使用 `aro/aro.local.entitlements`，不携带 CloudKit、iCloud container 或 APNs entitlement，也不编译 CloudKit 同步代码，适合 Apple Personal Team 的免费 7 天签名。定位记录、SQLite、GPX/GeoJSON、Watch App、Watch battery 和 Widget 不依赖 iCloud；设置页会显示“当前构建未启用 iCloud 同步”。
3. Cloud 版（`CloudDebug` 或 `CloudRelease`）使用 `aro/aro.entitlements`，编译并启用 `CKSyncEngine`，使用 `iCloud.com.xunbo.aro`、Push Notifications 和 `Background Modes → Remote notifications`。它需要加入 Apple Developer Program 的团队，以及已在 Developer Account 中启用对应能力并匹配的 provisioning profile。
4. CI 会编译 Local `Debug`、Cloud `CloudDebug`、运行单元测试和静态分析，并执行 generic device build。CloudKit silent push、多设备同步、Core Location 后台调度和真实耗电仍只能在签名真机验证。
5. 在 `aro`、`ARO Watch App` 和 `ARO Watch Widget Extension` 三个 target 的 Signing & Capabilities 中选择同一个开发团队；Watch App 与 Widget Extension 都需要 `group.com.xunbo.traceon.watch` App Group。Watch bundle identifier 为 `com.xunbo.aro.watchkitapp`，Widget Extension 为 `com.xunbo.aro.watchkitapp.widget`，Watch 的 `WKCompanionAppBundleIdentifier` 为 `com.xunbo.aro`。
6. 选择已配对 Apple Watch 的 iPhone 作为运行设备，并运行共享的 `aro` scheme。首次启动依次授予“使用 App 时”和“始终”定位权限；aro 2.0 的全天自动记录不会以“使用 App 时”权限启动一个降级 fallback。

## 后台生命周期

`NSLocationRequireExplicitServiceSession` 已启用。开启自动记录后，aro 保持一个明确要求 `.always` 的 `CLServiceSession`。均衡/精确/运动迭代 `CLLocationUpdate.liveUpdates`；极省电使用同一个授权生命周期下的 Standard location service，并设置约 100 m `distanceFilter`。

极省电和均衡最终都把静止状态交给 persistent `CLMonitor`：极省电结合 Standard location automatic pause 与 Motion 活动分类，但 Motion 仅作提示而不是后台唤醒源；均衡把 Motion stationary 与 robust GPS 空间稳定检测融合。只有在 monitor 建立成功后才停止当前移动定位引擎。离开 geofence 后恢复该模式自己的主定位引擎，不使用 significant-change、Visits 或 Core Motion wake fallback。

定位启动路径刻意不初始化 WatchConnectivity 或 CloudKit。普通前台进入由 `RootView` 激活 WatchConnectivity，并在 Cloud 构建中恢复 CloudKit；CloudKit remote notification 有独立入口。这样，后台足迹唤醒不会顺便产生手表请求或云网络工作。

极省电/均衡不持有 `CLBackgroundActivitySession`；精确/运动才持有该 session 来换取及时后台位置交付。

## iCloud 与数据边界

`CKSyncEngine` 的自动同步依赖 CloudKit silent push，因此模拟器只能验证编译和本地数据库逻辑，不能证明多设备远端更新。只有 Cloud 版真机在开启“设置 → iCloud 同步”后才会创建/使用 CloudKit 私有数据库；Local 版不会初始化 CloudKit。

“关闭 iCloud 同步”只停止后续同步，不删除已经存在的 iCloud 副本。Cloud 版的“删除全部轨迹”会在检测到曾使用 iCloud 时先删除 CloudKit `AROTracks` zone，再删除本地 SQLite；其他已开启同步的设备收到 zone 删除后也会清空对应本地轨迹，防止旧数据重新上传。Local 版如果检测到当前安装曾经使用过 iCloud 同步，会拒绝执行仅本地的“删除全部轨迹”，并要求切换到 Cloud 构建完成删除。

aro 使用新的 Bundle ID 身份，不能覆盖升级现有的 Traceon/Companio 安装；旧 App 的容器、权限、UserDefaults 和轨迹数据库不会自动出现在 aro 中。需要保留历史时，请先在旧 App 导出 GPX/GeoJSON，再在 aro 中导入。新 App 内部仍使用 `Application Support/traceon/tracks.sqlite3`，这是数据库文件名兼容性约定，不代表跨 Bundle ID 自动迁移。

## Apple Watch

Watch App 主界面底部显示实际安装包的营销版本与构建号；当前未发布测试线为 `v2.1.2 (1)`，用于真机安装和功耗对照时确认版本。

如果表盘编辑器中没有 `aro 电量` 或 `aro 轨迹`：确认手表系统为 watchOS 10 或更新版本，并且是从配对 iPhone 的 `aro` scheme 安装了完整的 Watch App（其中包含 `ARO Watch Widget Extension`）。先在手表上打开一次 aro，再重新进入表盘编辑器。`aro 轨迹` 当前只支持圆形位置。

`aro 轨迹` 不会在 Apple Watch 上再次开启定位。iPhone 把当天轨迹压缩成少量归一化路线点和累计距离，通过 WatchConnectivity 的 application context 保留最新状态，并在 complication 已启用且系统预算允许时额外使用 complication transfer。Watch 端收到两种数据都会更新共享快照并请求 WidgetKit timeline reload。

Apple Watch 电量必须使用配对真机测试。公开 WatchKit 仍只提供 `WKInterfaceDevice.batteryLevel`；如果 watchOS 本身只给第三方 App 5%/10% 粒度，aro 不使用 private API 猜测中间值。WidgetKit 和 Watch App 后台刷新时间由 watchOS 决定，不能保证固定间隔。

## 真机验证

后台轨迹与功耗不能由模拟器证明。发布 aro 2.1.2 前至少验证：

- **极省电竞品对照**：与一生足迹省电模式同时跑相同路线，重点比较稳态点间距离是否接近约 100 m、有效点数量、定位精度、过滤原因、稳态/过渡回调比例、静止后是否停止持续回调，以及离开约 50 m 静止范围后的恢复延迟。
- **均衡静止**：完全静止约 5–7 分钟，应从“监测中”进入“静止省电监控”；少量 30–40 m GPS 漂移不应再让 Live Updates 永远保持运行。
- 锁屏和普通后台下，同一路线与目标足迹 App 对照总距离、转弯保留、轨迹点数量和最近精度。
- 在 Live Updates 和 CLMonitor 状态分别制造系统内存压力，确认当前 tracking session 可正确恢复，且定位恢复不能顺带初始化 WatchConnectivity 或 CloudKit。
- 至少两个路线相近的完整工作日比较极省电/均衡模式功耗与竞品省电模式。
- 单独测试精确/运动模式的及时后台行为和更高功耗预期。
- 验证 Watch 轨迹 complication 不需要手动打开 Watch App 才能收到新的 iPhone 当日路线，以及电量 complication 的新颜色阈值。

详细步骤见 [TESTING.md](TESTING.md)。
