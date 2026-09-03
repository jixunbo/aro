# aro

aro（Everything Around You）是一款隐私优先的 iOS + watchOS App：在 iPhone 上低功耗记录全天足迹，并同步显示 Apple Watch 最近一次有效电量快照。轨迹始终保存在本地 SQLite；用户也可以选择开启 iCloud 私有数据库同步，不需要 aro 账号、自建服务器或分析服务。

## 系统要求

- iPhone / iPad：iOS / iPadOS 26.0 或更高版本。aro 2.0 不提供 iOS 17–25 的兼容定位实现。
- Apple Watch：watchOS 10.0 或更高版本。
- 开发环境：Xcode 26 或更高版本。

## 功能

- 四档定位模式：极省电、均衡、精确、运动。
- iOS 26 原生 `CLLocationUpdate.liveUpdates` 定位引擎；全天记录使用显式 `CLServiceSession(.always)`。
- Core Location 判断设备静止后自动暂停位置更新，重新移动后自动恢复；不再依赖显著位置变化、到访事件或 Core Motion 来“救醒”标准定位。
- 极省电/均衡允许 iOS 挂起 aro，并通过 Always 授权和未结束的 Live Updates / service session 在系统合适的时机排队、恢复或重新启动交付，避免为了实时性长期保持 App 在后台运行。
- 精确/运动模式使用 `CLBackgroundActivitySession` 保持及时后台交付，因此更适合需要更完整实时轨迹的场景，也会比均衡模式更耗电。
- 自适应轨迹保存：结合距离、时间、定位精度噪声和转弯变化决定是否保存点。均衡模式正常直线约 55 米级保存，同时允许较短距离的真实转弯提前落点。
- 后台恢复后允许处理当前记录会话内排队的历史定位，不再使用会误删合法后台点的 180 秒墙钟 freshness 限制。
- 设置页显示 Live Updates 运行状态、后台策略、最近精度以及本次进程接收/保存/丢弃数量，方便真机与其他足迹 App 做同路线对照。
- 今日轨迹、历史日历、足迹总览和距离统计。
- GPX 与 GeoJSON 导入/导出。
- 本地 SQLite/WAL 存储，适合长期积累大量坐标。
- 可选 CloudKit 私有数据库轨迹同步，SQLite 仍是本地 source of truth。
- 分阶段定位授权、数据保留与一键删除。
- Apple Watch 电量、充电状态、设备名与最后同步时间。
- “获取设备电量”快捷指令；手表可达时主动刷新，不可达时明确使用缓存。
- watchOS 系统调度的后台电量刷新。
- Apple Watch WidgetKit 电量复杂功能：圆形样式采用 Ultra 风格刻度环，角落、行内和矩形样式继续可用。
- Apple Watch WidgetKit 圆形“aro 轨迹”复杂功能：显示当天路线缩略图和累计距离。

## 定位模式

- **极省电**：`.default` Live Updates + 系统节能后台调度，保存点最稀疏。适合更看重全天功耗、可以接受更少轨迹细节的场景。
- **均衡**：`.default` Live Updates + 系统节能后台调度。正常移动约 55 米级保存，最长约 2 分钟且确有移动时补点，明显转弯可更早保存。推荐日常足迹。
- **精确**：`.otherNavigation` + 及时后台活动，约 20 米级保存。
- **运动**：`.fitness` + 及时后台活动，约 8 米级保存。

“约 N 米级”描述的是 aro 的**数据保存策略**，不是承诺 Core Location 固定每 N 米产生一次定位。系统什么时候产生、排队和交付更新仍由 iOS 决定。

## 构建配置与运行

1. 使用 Xcode 26 或更新版本打开 `aro.xcodeproj`。共享的 `aro` scheme 保留为唯一 scheme，`Debug`/`Release` 是 Local 版，`CloudDebug`/`CloudRelease` 是 Cloud 版。
2. Local 版（`Debug` 或 `Release`）使用 `aro/aro.local.entitlements`，不携带 CloudKit、iCloud container 或 APNs entitlement，也不编译 CloudKit 同步代码，适合 Apple Personal Team 的免费 7 天签名。定位记录、SQLite、GPX/GeoJSON、Watch App、Watch battery 和 Widget 不依赖 iCloud；设置页会显示“当前构建未启用 iCloud 同步”。
3. Cloud 版（`CloudDebug` 或 `CloudRelease`）使用 `aro/aro.entitlements`，编译并启用 `CKSyncEngine`，使用 `iCloud.com.xunbo.aro`、Push Notifications 和 `Background Modes → Remote notifications`。它需要加入 Apple Developer Program 的团队，以及已在 Developer Account 中启用对应能力并匹配的 provisioning profile。
4. CI 会编译 Local `Debug`、Cloud `CloudDebug`、运行单元测试和静态分析，并执行 generic device build。CloudKit silent push、多设备同步、Core Location 后台调度和真实耗电仍只能在签名真机验证。
5. 在 `aro`、`ARO Watch App` 和 `ARO Watch Widget Extension` 三个 target 的 Signing & Capabilities 中选择同一个开发团队；Watch App 与 Widget Extension 都需要 `group.com.xunbo.traceon.watch` App Group。Watch bundle identifier 为 `com.xunbo.aro.watchkitapp`，Widget Extension 为 `com.xunbo.aro.watchkitapp.widget`，Watch 的 `WKCompanionAppBundleIdentifier` 为 `com.xunbo.aro`。
6. 选择已配对 Apple Watch 的 iPhone 作为运行设备，并运行共享的 `aro` scheme。首次启动依次授予“使用 App 时”和“始终”定位权限；aro 2.0 的全天自动记录不会以“使用 App 时”权限启动一个降级 fallback。

## 后台生命周期

`NSLocationRequireExplicitServiceSession` 已启用。开启自动记录后，aro 保持一个明确要求 `.always` 的 `CLServiceSession` 并迭代 `CLLocationUpdate.liveUpdates`。当 iOS 挂起或因系统资源原因终止 aro 时，Core Location 可以记住仍未结束的定位需求；进程再次由系统启动后，`AppDelegate` 会立即只恢复定位/service session，再处理排队更新。

定位启动路径刻意不初始化 WatchConnectivity 或 CloudKit。普通前台进入由 `RootView` 激活 WatchConnectivity，并在 Cloud 构建中恢复 CloudKit；CloudKit remote notification 有独立入口。这样，后台足迹唤醒不会顺便产生手表请求或云网络工作。

极省电/均衡不持有 `CLBackgroundActivitySession`，允许系统为了功耗挂起进程；精确/运动才持有该 session 来换取及时后台位置交付。所有模式仍会利用 Live Updates 的 stationary 状态：设备静止时系统可以停止位置流，重新移动时再恢复。

## iCloud 与数据边界

`CKSyncEngine` 的自动同步依赖 CloudKit silent push，因此模拟器只能验证编译和本地数据库逻辑，不能证明多设备远端更新。只有 Cloud 版真机在开启“设置 → iCloud 同步”后才会创建/使用 CloudKit 私有数据库；Local 版不会初始化 CloudKit。

“关闭 iCloud 同步”只停止后续同步，不删除已经存在的 iCloud 副本。Cloud 版的“删除全部轨迹”会在检测到曾使用 iCloud 时先删除 CloudKit `AROTracks` zone，再删除本地 SQLite；其他已开启同步的设备收到 zone 删除后也会清空对应本地轨迹，防止旧数据重新上传。Local 版如果检测到当前安装曾经使用过 iCloud 同步，会拒绝执行仅本地的“删除全部轨迹”，并要求切换到 Cloud 构建完成删除。

aro 使用新的 Bundle ID 身份，不能覆盖升级现有的 Traceon/Companio 安装；旧 App 的容器、权限、UserDefaults 和轨迹数据库不会自动出现在 aro 中。需要保留历史时，请先在旧 App 导出 GPX/GeoJSON，再在 aro 中导入。新 App 内部仍使用 `Application Support/traceon/tracks.sqlite3`，这是数据库文件名兼容性约定，不代表跨 Bundle ID 自动迁移。

## Apple Watch

Watch App 主界面底部显示实际安装包的营销版本与构建号；aro 2.0 初始构建显示 `v2.0.0 (1)`，用于真机安装和功耗对照时确认版本。

如果表盘编辑器中没有 `aro 电量` 或 `aro 轨迹`：确认手表系统为 watchOS 10 或更新版本，并且是从配对 iPhone 的 `aro` scheme 安装了完整的 Watch App（其中包含 `ARO Watch Widget Extension`）。先在手表上打开一次 aro，再重新进入表盘编辑器。`aro 轨迹` 当前只支持圆形位置。

`aro 轨迹` 不会在 Apple Watch 上再次开启定位。iPhone 把当天轨迹压缩成少量归一化路线点和累计距离，通过已有的 WatchConnectivity application context 机会同步到手表。普通前台启动会立即尝试同步；已激活的 WatchConnectivity session 在后台存在时才会机会式节流更新。Core Location 单独触发的后台恢复不会额外激活 WatchConnectivity。

Apple Watch 电量必须使用配对真机测试。iPhone 无法通过公开 API 直接读取手表电量；手表不可达时，设备页和快捷指令只能使用带时间戳的最近缓存。WidgetKit 和 Watch App 后台刷新时间由 watchOS 决定，不能保证固定间隔。

## 真机验证

后台轨迹与功耗不能由模拟器证明。发布 aro 2.0 前至少验证：

- 均衡模式静止 30 分钟后，不打开 aro 直接步行/驾车，确认 Live Updates 能从 stationary 状态恢复，而不是等待数百米级旧 wake 机制。
- 锁屏和普通后台下，同一路线与目标足迹 App 对照总距离、转弯保留、轨迹点数量和最近精度。
- 制造系统内存压力让 aro 被系统回收，确认重新启动后当前 tracking session 的排队定位仍可写入，不因墙钟年龄被删除。
- 至少两个路线相近的完整工作日比较均衡模式功耗；重点确认静止期间没有 `CLBackgroundActivitySession` 的持续后台执行。
- 单独测试精确/运动模式的及时后台行为和更高功耗预期。

详细步骤见 [TESTING.md](TESTING.md)。
