# aro 真机验收清单

安装或分发改动后的构建前，确认 iOS App、Watch App、Widget Extension 以及全部 Local/Cloud 配置使用同一个预期版本。aro 2.0.2 的 iOS/iPadOS 最低版本是 26.0；不要在 iOS 17–25 上做兼容性验收。

## 测试前提

每次测试前确认：自动记录已开启、定位权限为“始终”、精确位置已开启。设置页诊断项区分“更新 / 定位 / 保存 / 过滤”：`更新` 是 Core Location 回调或 Live Update 事件，`定位` 是其中实际包含 `CLLocation` 的数量。

四种模式当前应表现为：

- **极省电**：Standard Core Location，高质量定位，约 100 m `distanceFilter`，允许 automatic pause；静止后切到约 100 m persistent `CLMonitor`。记录通道显示“标准定位”。
- **均衡**：`.default` Live Updates；约 35 m 自适应保存；robust 空间静止判定后切到约 60 m persistent `CLMonitor`。记录通道显示“Live Updates”。
- **精确**：`.otherNavigation` Live Updates + `CLBackgroundActivitySession`，约 20 m 保存，不进入 idle monitor。
- **运动**：`.fitness` Live Updates + `CLBackgroundActivitySession`，约 8 m 保存，不进入 idle monitor。

## 极省电：与目标 App 省电模式同类行为

1. **移动点间距基线**：在开阔区域连续步行/驾车至少 2–3 km。导出当天点并计算相邻有效点距离。多数移动点应围绕约 100 m 量级分布；允许启动、定位精度改善或系统调度产生更短/更长间隔，不能要求固定 100.0 m。
2. **单点质量**：重点看 horizontal accuracy，而不是只看点数。目标是多数正常环境下保持高质量定位，不通过接受数百米粗点换省电。明显劣于约 50 m 的点应被保存层拒绝。
3. **静止自动休眠**：在信号良好处保持不动。观察 Standard location 是否触发 automatic pause。触发后设置页应进入“静止省电监控”，Standard updates 应停止，后续静止期间 `定位` 不应继续高频增长。
4. **静止范围唤醒**：进入“静止省电监控”后，不打开 aro，直接离开当前位置并持续移动至少 500 m。约 100 m monitored circle 被系统判定离开后，应恢复 Standard updates。记录从真实开始移动到首个新保存点的时间与距离。
5. **系统回收后唤醒**：先进入 Eco idle monitor，再让系统在内存压力下回收 aro（不要手动上划），保持静止一段时间后离开 monitored circle。确认 persistent CLMonitor 能恢复进程和 Eco Standard recorder。
6. **对照一生足迹省电模式**：同一台手机、相近时间和路线同时运行。比较：总距离、点数、相邻点距离中位数/分布、定位精度、长时间静止 gap、重新移动后的首点延迟、系统“电池”页占比与后台活动。目标是行为和功耗尽量接近，不要求逐点完全一致。

## 均衡：Live Updates + robust idle

1. **前台基线**：步行 1 km。确认更新/定位/保存/过滤持续变化，路线不出现 1.5 那种大量超长直线，城市转弯能够保留。
2. **普通后台**：切到其他 App 后步行或驾车 2–3 km，回来确认当前 session 的 Live Updates 已写入 SQLite，总距离与路线连续性合理。
3. **锁屏**：锁屏后移动至少 10 分钟。解锁后确认路线没有完全中断；允许 `.default` Live Updates 被 iOS 排队/合并，不要求 UI 实时刷新。
4. **robust idle**：在信号良好位置完全静止。正常情况下约 5–7 分钟内应从“监测中”进入“静止省电监控”。少量约 30–40 m 的 GPS outlier 不应再让 idle 判定永远失败。
5. **慢速移动不得误睡**：以缓慢但持续的方向移动至少 5–10 分钟。即使每个短时间窗口看起来局部聚集，early/late robust center 应持续漂移，不应进入 idle monitor。
6. **idle 后回调停止**：进入“静止省电监控”后继续静止 10–30 分钟，`定位`计数不应像 2.0.1 早期测试那样持续快速增加。少量 monitor/诊断事件可以出现。
7. **60 m 范围唤醒**：进入 idle 后不打开 aro 直接离开并移动至少 500 m。确认离开约 60 m monitored circle 后 Live Updates 自动恢复，不能重现 1.5 数百米起步缺失。
8. **系统 stationary**：如果 iOS 在 robust detector 之前直接报告 `stationary`，应进入同一个 idle monitor 状态，不维护第二套休眠架构。
9. **同路线质量对照**：与一生足迹省电模式同时跑 2–3 km。均衡允许比竞品保存更多点；重点比较总距离误差、主要转弯、最长切角和实际耗电，而不是追求点数相同。

## 生命周期、权限与模式切换

1. **Live Updates 状态系统回收**：Balanced/Precise/Workout 移动中制造内存压力，确认系统恢复后当前 tracking session 的合法排队点最终可写入，且旧的 180 秒墙钟 freshness 不会删除它们。
2. **Eco Standard 状态系统回收**：Eco 移动状态下制造系统回收后继续移动，确认 Always/background Standard recording 能恢复到可继续记录的状态；记录真实恢复行为。
3. **CLMonitor 状态系统回收**：Eco/Balanced 分别进入 idle monitor 后测试系统回收和退出 geofence。若 `tracking.idleMonitorActive` 存在但 Core Location 实际已没有该 condition，aro 应清标记并恢复对应模式的主 recorder，而不是卡死。
4. **手动强制结束**：从多任务界面手动上划后记录系统实际行为，但不把“系统必须重新拉起被用户强制结束的 App”作为要求。重新手动打开后应恢复用户的记录意图和可恢复的 monitor 状态。
5. **手机重启**：分别在移动 recorder 状态和 idle monitor 状态测试重启/首次解锁后的恢复。
6. **权限降级**：把“始终”改成“使用 App 时”。引擎必须停止、清理 idle condition，并显示等待 Always。恢复“始终”后建立新的 tracking session boundary。
7. **精确位置关闭**：确认设置页显示受限提示；低质量点应被保存层拒绝，也不能被用来证明 Balanced 静止。
8. **系统定位关闭**：确认停止写入伪造/缓存点；恢复定位后重新验证 selected mode 的 primary recorder/monitor 状态。
9. **模式切换**：依次测试 Eco → Balanced → Precise → Workout → Eco，并覆盖从 idle monitor 状态切换。切换必须移除旧 monitor、停止旧 recorder，再启动新模式：Eco=Standard distance-filtered，Balanced/Precise/Workout=相应 Live Updates。
10. **删除数据时处于 idle**：删除全部轨迹后 recorder anchor、last-record UI 和 session boundary 必须正确重置；idle condition 不能让已删除点继续成为过滤基准。

## 弱信号与数据正确性

- 地下停车场、高楼密集区、地铁进出站测试。精度差的漂移不能被“转弯”误保存，也不能让 Balanced 错误建立 geofence。
- 同路线分别步行、骑车、驾车，比较轨迹与实际道路。
- 验证跨午夜、夏令时和时区切换后的每日分组。
- 导出 GPX，删除本地数据并重新导入，核对点数、日期和总距离。
- 制造/模拟乱序记录点后确认 `daily_summary` 与 raw points 重算距离一致。
- 关闭记录再开启，确认新的 tracking-session boundary 生效，旧缓存点不能混入新 session。

## 功耗基线

不要用一次短测试判断耗电。至少做路线和手机使用方式相近的完整工作日比较：

- **Day 0 / baseline**：暂停 aro，记录“设置 → 电池”的总耗电、后台活动和屏幕时间。
- **Day 1 / Eco**：极省电全天记录；重点验证移动时不是高频回调再过滤，而是 Standard location 的约 100 m 距离驱动生成，静止后进入 CLMonitor。
- **Day 2 / competitor**：一生足迹省电模式，尽量保持相近日程，与 Day 1 比较点间距、路线和耗电。
- **Day 3 / Balanced**：均衡全天记录；重点验证 robust idle 后 Live Updates 真正停止，观察轨迹质量相对 Eco 提升带来的实际耗电差。
- **Day 4 / Precise（可选）**：验证 `CLBackgroundActivitySession` 的及时交付和预期更高功耗。

至少一次使用 Instruments / Energy Log 做“静止 30–60 分钟 → 移动 30–60 分钟”。Eco/Balanced 进入 idle monitor 后，持续位置生成应真正停止或显著下降，而不是仅由 aro 丢弃大量位置。

## Watch 真机验证

- 安装 aro 2.0.2 的 iPhone App、Watch App 和 Widget Extension，确认 Watch App 底部显示 `v2.0.2 (1)`。
- `aro 轨迹` complication：iPhone 当日路线变化后，不手动打开 Watch App，确认 complication 最终能通过 application context / complication transfer 更新。
- `aro 电量` complication：>50% 为绿色，21–50% 为橙色，≤20% 为红色；充电/已充满始终绿色。
- 电量百分比以公共 `WKInterfaceDevice.batteryLevel` 为准；如果 watchOS 只提供 5%/10% 粒度，不把它当 aro rounding bug。

## Local / Cloud 构建配置

1. Local `Debug`/`Release` 使用 `aro/aro.local.entitlements`，不携带 CloudKit container、iCloud services 或 APNs entitlement。
2. CI 的 `CloudDebug` simulator build 必须通过，确保可选 CloudKit 代码仍可编译；CloudKit 当前不是 2.0.2 的真机发布重点。
3. Personal Team 真机安装使用 Debug Local，验证 Core Location、SQLite、导入导出、Watch App 与 complications。
4. 仅 Core Location 导致的后台进程恢复不能顺带初始化 WatchConnectivity 或 CloudKit。

## 自动检查

在提交前至少运行/等待 CI 完成：

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
