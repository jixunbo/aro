# aro

aro（Everything Around You）是一款隐私优先的 iOS + watchOS App：在 iPhone 上低功耗记录全天足迹，并同步显示 Apple Watch 最近一次有效电量快照。轨迹始终保存在本地 SQLite；用户也可以选择开启 iCloud 私有数据库同步，不需要 aro 账号、自建服务器或分析服务。

## 功能

- 四档定位模式：极省电、均衡、精确、运动
- App 休眠或被系统回收后，通过显著位置变化与到访事件继续记录
- 今日轨迹、历史日历、足迹总览和距离统计
- GPX 与 GeoJSON 导入/导出
- 本地 SQLite/WAL 存储，适合长期积累大量坐标
- 可选 CloudKit 私有数据库轨迹同步，SQLite 仍是本地 source of truth
- 分阶段定位授权、数据保留与一键删除
- Apple Watch 电量、充电状态、设备名与最后同步时间
- “获取设备电量”快捷指令；手表可达时主动刷新，不可达时明确使用缓存
- watchOS 系统调度的后台电量刷新
- Apple Watch WidgetKit 电量复杂功能：圆形样式采用 Ultra 风格刻度环，角落、行内和矩形样式继续可用
- Apple Watch WidgetKit 圆形“aro 轨迹”复杂功能：显示当天路线缩略图和累计距离

## 构建配置与运行

1. 使用 Xcode 26 或更新版本打开 `aro.xcodeproj`。共享的 `aro` scheme 保留为唯一 scheme，`Debug`/`Release` 是 Local 版，`CloudDebug`/`CloudRelease` 是 Cloud 版。
2. Local 版（`Debug` 或 `Release`）使用 `aro/aro.local.entitlements`，不携带 CloudKit、iCloud container 或 APNs entitlement，也不编译 CloudKit 同步代码，适合 Apple Personal Team 的免费 7 天签名。定位记录、SQLite、GPX/GeoJSON、Watch App、Watch battery 和 Widget 不依赖 iCloud；设置页会显示“当前构建未启用 iCloud 同步”。
3. Cloud 版（`CloudDebug` 或 `CloudRelease`）使用 `aro/aro.entitlements`，编译并启用 `CKSyncEngine`，使用 `iCloud.com.xunbo.aro`、Push Notifications 和 `Background Modes → Remote notifications`。它需要加入 Apple Developer Program 的团队，以及已在 Developer Account 中启用对应能力并匹配的 provisioning profile。
4. 在 Xcode 的 scheme action 中选择所需 configuration；命令行可使用 `-configuration Debug`（Local）或 `-configuration CloudDebug`（Cloud）。CI 明确使用 `Debug`，因此默认验证的是无 Cloud entitlement 的 Local 版。
5. 在 `aro`、`ARO Watch App` 和 `ARO Watch Widget Extension` 三个 target 的 Signing & Capabilities 中选择同一个开发团队；Watch App 与 Widget Extension 都需要 `group.com.xunbo.traceon.watch` App Group。Watch bundle identifier 为 `com.xunbo.aro.watchkitapp`，Widget Extension 为 `com.xunbo.aro.watchkitapp.widget`，Watch 的 `WKCompanionAppBundleIdentifier` 为 `com.xunbo.aro`。
6. 选择已配对 Apple Watch 的 iPhone 作为运行设备，并运行共享的 `aro` scheme。watchOS App 会作为 Watch Content 嵌入 iOS App，Widget Extension 会嵌入 Watch App。首次启动依次授予“使用 App 时”和“始终”定位权限；若设备页迟迟没有首条电量，请在 Apple Watch 上打开一次 aro，随后在表盘编辑器中选择 `aro 电量`。圆形复杂功能位置还可以选择 `aro 轨迹`。

`CKSyncEngine` 的自动同步依赖 CloudKit silent push，因此模拟器只能验证编译和本地数据库逻辑，不能证明多设备远端更新。只有 Cloud 版真机在开启“设置 → iCloud 同步”后才会创建/使用 CloudKit 私有数据库；Local 版不会初始化 CloudKit。Core Location 触发的后台冷启动会刻意跳过 CloudKit 初始化，避免把定位唤醒变成额外网络工作；Cloud 版普通启动和 CloudKit 远端通知启动则可以恢复同步引擎。

“关闭 iCloud 同步”只停止后续同步，不删除已经存在的 iCloud 副本。Cloud 版的“删除全部轨迹”会在检测到曾使用 iCloud 时先删除 CloudKit `AROTracks` zone，再删除本地 SQLite；其他已开启同步的设备收到 zone 删除后也会清空对应本地轨迹，防止旧数据重新上传。Local 版如果检测到当前安装曾经使用过 iCloud 同步，会拒绝执行仅本地的“删除全部轨迹”，并要求切换到 Cloud 构建完成删除，避免以后重新启用 iCloud 时旧轨迹被同步回来。

如果表盘编辑器中没有 `aro 电量` 或 `aro 轨迹`：确认手表系统为 watchOS 10 或更新版本，并且是从配对 iPhone 的 `aro` scheme 安装了完整的 Watch App（其中包含 `ARO Watch Widget Extension`），而不是只安装 iOS App。先在手表上打开一次 aro，再退出表盘编辑器并重新进入；复杂功能只会出现在支持相应 accessory family 的表盘位置。`aro 轨迹` 当前只支持圆形位置。仍未出现时，重新从 Xcode 安装 Watch App 与 Widget Extension，检查两个 watch target 都使用同一个 App Group，并确认 Widget Extension 的 bundle identifier 为 `com.xunbo.aro.watchkitapp.widget`。模拟器只能验证编译，不能验证复杂功能是否出现在已配对手表的表盘编辑器中。

`aro 轨迹` 不会在 Apple Watch 上再次开启定位。iPhone 把当天轨迹压缩成少量归一化路线点和累计距离，通过已有的 WatchConnectivity application context 机会同步到手表，再写入 Watch App Group 给 WidgetKit 使用。普通前台启动会立即尝试同步；如果 WatchConnectivity 会话此前已经激活，后台继续记录时会节流更新。Core Location 单独触发的冷启动不会因此额外激活 WatchConnectivity，因此轨迹复杂功能不是逐点实时流，系统也可能合并或延迟跨设备传输。

aro 使用新的 Bundle ID 身份，不能覆盖升级现有的 Traceon/Companio 安装；旧 App 的容器、权限、UserDefaults 和轨迹数据库不会自动出现在 aro 中。需要保留历史时，请先在旧 App 导出 GPX/GeoJSON，再在 aro 中导入。新 App 内部仍使用 `Application Support/traceon/tracks.sqlite3`，这是数据库文件名兼容性约定，不代表跨 Bundle ID 自动迁移。

后台轨迹必须在真机、锁屏、步行/驾车等不同场景下持续测试。iOS 会根据系统压力、定位设置和信号环境调度事件，因此任何后台方案都不保证逐点连续。

Apple Watch 电量也必须使用配对真机测试。iPhone 无法通过公开 API 直接读取手表电量；手表不可达时，设备页和快捷指令只能使用带时间戳的最近缓存。watchOS 后台刷新时间由系统决定，不能保证固定间隔。

复杂功能平时显示 App Group 中的最近快照；当 WidgetKit 授予新的 Timeline 刷新机会时，电量 Widget Extension 会在手表本地读取一次电量并更新快照。它没有计时器、持续轮询或网络请求。添加到活动表盘可带来更多系统刷新机会，但不能承诺精确的刷新周期。

Watch App 仅在界面处于可交互前台时每五分钟采样，单次读取结束后立即关闭电量监控；后台 App 刷新的 preferred interval 为一小时。aro 的 Watch App 明确关闭 Always On display，放下手腕后不会为了显示电量页而继续保持常亮。

详细的真机验收与耗电测量步骤见 [TESTING.md](TESTING.md)。
