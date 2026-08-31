# Companio

一款隐私优先的 iOS + watchOS 伴侣 App：在 iPhone 上低功耗记录全天足迹，并同步显示 Apple Watch 最近一次有效电量快照。轨迹默认只存储在设备本地，不需要账号或服务器。

## 功能

- 四档定位模式：极省电、均衡、精确、运动
- App 休眠或被系统回收后，通过显著位置变化与到访事件继续记录
- 今日轨迹、历史日历、足迹总览和距离统计
- GPX 与 GeoJSON 导入/导出
- 本地 SQLite/WAL 存储，适合长期积累大量坐标
- 分阶段定位授权、数据保留与一键删除
- Apple Watch 电量、充电状态、设备名与最后同步时间
- “获取设备电量”快捷指令；手表可达时主动刷新，不可达时明确使用缓存
- watchOS 系统调度的后台电量刷新
- Apple Watch WidgetKit 电量复杂功能（圆形、角落、行内和矩形样式）

## 运行

1. 使用 Xcode 26 或更新版本打开 `traceon.xcodeproj`。
2. 在 `traceon`、`Companio Watch App` 和 `Companio Watch Widget Extension` 三个 target 的 Signing & Capabilities 中选择同一个开发团队；Watch App 与 Widget Extension 都需要 `group.com.xunbo.traceon.watch` App Group。
3. 保持 iOS bundle identifier 为 `com.xunbo.traceon`，watchOS bundle identifier 为 `com.xunbo.traceon.watchkitapp`，Widget Extension bundle identifier 为 `com.xunbo.traceon.watchkitapp.widget`，并确认 watch target 的 `WKCompanionAppBundleIdentifier` 为 `com.xunbo.traceon`。
4. 选择已配对 Apple Watch 的 iPhone 作为运行设备，并运行共享的 `traceon` scheme。watchOS App 会作为 Watch Content 嵌入 iOS App，Widget Extension 会嵌入 Watch App。
5. 首次启动依次授予“使用 App 时”和“始终”定位权限。若设备页迟迟没有首条电量，请在 Apple Watch 上打开一次 Companio；随后在表盘编辑器的复杂功能列表中选择 `Companio 电量`。如果 Xcode 报告 provisioning profile 缺少 App Groups，请在两个 watch target 的 Signing & Capabilities 中添加 App Groups，并注册/勾选 `group.com.xunbo.traceon.watch` 后重新运行。

现有 Traceon 安装升级后仍使用 `com.xunbo.traceon` 和原来的 `Application Support/traceon/tracks.sqlite3`，不会因为显示名称变为 Companio 而迁移或清空已有轨迹。

后台轨迹必须在真机、锁屏、步行/驾车等不同场景下持续测试。iOS 会根据系统压力、定位设置和信号环境调度事件，因此任何后台方案都不保证逐点连续。

Apple Watch 电量也必须使用配对真机测试。iPhone 无法通过公开 API 直接读取手表电量；手表不可达时，设备页和快捷指令只能使用带时间戳的最近缓存。watchOS 后台刷新时间由系统决定，不能保证固定间隔。

复杂功能只显示 Watch App 写入 App Group 的最近快照，不会自行读取或轮询电池。添加到活动表盘可带来额外的 watchOS 刷新机会，但不能承诺精确的刷新周期。

详细的真机验收与耗电测量步骤见 [TESTING.md](TESTING.md)。
