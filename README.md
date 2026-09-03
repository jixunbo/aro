# aro

aro（Everything Around You）是一个本地优先的 iPhone/iPad + Apple Watch 应用：iOS 端记录全天足迹，Watch 端提供电量/设备状态与表盘 complication。当前未发布版本为 **2.0.1**。

> iOS/iPadOS 26.0+；Watch App 保持 watchOS 10.0+。aro 不再维护 iOS 17–25 的定位兼容层。

## 功能

- 全天后台足迹记录，支持极省电 / 均衡 / 精确 / 锻炼四种模式。
- iOS 26 Core Location 原生定位引擎：`CLLocationUpdate.liveUpdates` + `CLServiceSession(.always)`；Eco/Balanced 在稳定静止后切到持久 `CLMonitor` 圆形条件，离开区域后恢复 Live Updates。
- 今日、历史与总览地图，距离与轨迹点统计。
- GPX / GeoJSON 导入导出。
- Apple Watch 电量、充电状态、设备名展示与手动刷新；Shortcuts 提供“获取设备电量”。
- Watch 表盘电量 complication 与今日轨迹 / 距离 complication。电量圆形 complication：>50% 绿色、21–50% 橙色、≤20% 红色，充电/满电始终绿色。
- 今日轨迹通过 WatchConnectivity 最新状态和 complication 专用传输同步到 Watch；实际刷新时机仍由 watchOS/WidgetKit 调度。
- 可选 CloudKit 私有数据库同步；本地 Debug/Release 不依赖 CloudKit，SQLite 始终是本地事实来源。

## 本地数据

- SQLite: `Application Support/traceon/tracks.sqlite3`
- WAL + `synchronous=NORMAL`
- 原始点保存在 `track_points`，每日统计保存在 `daily_summary`
- Watch App 与 Watch Widget 通过 App Group `group.com.xunbo.traceon.watch` 共享电量与轨迹 complication 快照

## 定位策略

aro 2.0 系列不再用旧的 significant-change / visit / dual-`CLLocationManager` 作为正常记录或唤醒路径。移动时，Live Updates 是唯一的路线来源；Eco/Balanced 连续确认位置稳定后注册 `CLMonitor.CircularGeographicCondition` 并停止 Live Updates，从而把主要省电发生在静止阶段，而不是移动时大量丢弃已经生成的 GPS 点。

均衡模式当前目标是移动时保留较完整的城市路线、静止后真正降功耗。当前保存策略约 35 m 普通距离、60 秒且有实际位移时补点，并允许真实转弯更早落点。实际 Core Location 生成频率、CLMonitor 离开半径与系统唤醒延迟必须通过 iOS 26 真机验证。

## Apple Watch 电量

Watch 电量来源是公开 API `WKInterfaceDevice.batteryLevel`。aro 不把值主动量化到 5% 或 10%；如果 watchOS 本身只暴露粗粒度数值，公开 API 无法恢复隐藏的中间百分比。项目不会使用私有 IOKit / 私有符号来伪造更高精度。

## 构建

```bash
xcodebuild -project aro.xcodeproj -scheme aro -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project aro.xcodeproj -scheme aro \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO test

xcodebuild -project aro.xcodeproj -scheme aro -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO analyze

xcodebuild -project aro.xcodeproj -scheme aro \
  -destination 'generic/platform=iOS' -derivedDataPath DerivedData-device \
  CODE_SIGNING_ALLOWED=NO build
```

CI 还会额外构建 `CloudDebug`，确保 CloudKit 条件编译代码仍可编译。

## 真机验证

定位后台恢复、CLMonitor 静止/离开行为、系统回收后的恢复、WatchConnectivity、WidgetKit complication 刷新以及电量影响都无法由 simulator CI 证明。发布前按 `TESTING.md` 执行真机测试，重点包括：

- Balanced 静止约五分钟后进入低功耗监控，随后 Live Updates 高频定位显著停止；
- 离开约 60 m 监控范围后及时恢复轨迹，不重现 1.5 版本数百米起步缺失；
- 与目标足迹 App 同路线比较距离、转弯、点数和全天耗电；
- iPhone 当日轨迹能在无需手动打开 Watch App 的情况下更新 Watch 轨迹 complication；
- 电量 complication 三段颜色正确，并确认真机实际 `batteryLevel` 粒度。

更多架构、决策和未完成验证见 `PROJECT_CONTEXT.md`、`DECISIONS.md`、`TESTING.md`、`TODO.md`。
