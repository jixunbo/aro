# aro 真机验收清单

安装或分发改动后的构建前，确认 iOS App、Watch App、Widget Extension 以及全部 Local/Cloud 配置使用同一个预期版本。aro 2.0.0 的 iOS/iPadOS 最低版本是 26.0；不要在 iOS 17–25 上做兼容性验收。

## iOS 26 Live Updates + CLMonitor 后台记录

每次测试前在“设置”页确认：自动记录已开启、定位权限为“始终”、精确位置已开启。均衡模式应显示“定位引擎：iOS Live Updates”“后台策略：静止低功耗监控”。新增轨迹点的记录通道应为 `Live Updates`。诊断项区分“更新 / 定位 / 保存 / 过滤”：`更新` 包含无坐标的 Core Location 诊断事件，`定位` 才是实际带 `CLLocation` 的事件。

1. **前台基线**：清空或记下现有点数，使用“均衡”步行 1 km。确认“更新/定位/保存/过滤”持续变化，最近精度合理，路线不会只有少数超长直线。
2. **普通后台**：打开 aro 后切换到其他 App，步行或驾车 2–3 km。回来确认当前会话中的后台 Live Updates 已写入 SQLite，总距离和路线连续性合理。
3. **锁屏**：锁屏后步行或驾车至少 10 分钟。解锁后确认路线没有完全中断；允许 iOS 对移动状态的 `.default` Live Updates 做排队/合并，不要求实时刷新 UI。
4. **主动 idle → movement**：均衡模式在信号良好的位置完全静止至少 10 分钟。正常情况下约 5 分钟稳定窗口后应从“移动中/等待定位”进入“静止省电监控”；进入后继续静止 10–30 分钟，`定位`计数不应像旧实现一样持续快速增加。随后不打开 aro 直接离开静止地点并移动至少 500 m，确认离开约 60 m 监控范围后 Live Updates 自动恢复，路线开头不应再出现旧 1.5 那种数百米缺失。记录从开始移动到首个新保存点的实际距离和时间。
5. **系统 stationary 信号**：如果 iOS 在 aro 主动 idle 判定前先报告 `stationary`，应直接进入同一个“静止省电监控”状态，而不是维持另一套休眠架构。重新移动后的行为与第 4 项相同。
6. **同路线竞品对照**：在相近时间、信号环境和手机使用方式下，让 aro“均衡”和目标足迹 App 的省电模式同时记录同一条约 2–3 km 路线。至少记录：实际/参考距离、两边报告距离、点数、主要转弯是否保留、最长明显切角、aro 最近精度，以及 aro 的更新/定位/保存/过滤数量。不要只比较点数；目标是移动时保留真实几何、静止时真正停止高频 Live Updates。
7. **转弯保留**：选择含多个 90 度路口的城市步行路线。均衡模式约 35 m 普通保存，但明显转弯约 12 m 后即可提前保存；重点测试低速步行，因为 `CLLocation.course` 可能不可用，几何转弯检测仍应工作。
8. **后台排队 freshness**：让 aro 长时间处于后台/挂起状态后继续移动，再回到 App。确认当前 `tracking.startedAt` 之后的合法排队点即使交付时已经超过 180 秒也不会因墙钟年龄被丢弃；同时确认重新启动 Live Updates 后的 idle 窗口只使用新鲜定位，旧排队点不能立即把设备重新判为静止。
9. **Live Updates 状态下系统回收**：制造内存压力，让系统有机会终止 aro（不要手动上划），随后继续移动。确认 Core Location 可以重新启动进程，`LocationService` 立即重建 service/live-update session，排队点最终写入。位置恢复不能顺带初始化 WatchConnectivity 或 CloudKit。
10. **CLMonitor 状态下系统回收**：先让设置页明确进入“静止省电监控”，再让进程被系统回收。保持静止一段时间后离开监控范围，确认同名 persistent `CLMonitor` 能让 aro 恢复并重新开始 Live Updates。若持久化标记存在但 Core Location 中已没有该 condition，aro 应清标记并恢复 Live Updates，而不是卡死。
11. **手动强制结束**：从多任务界面手动上划结束 aro 后记录系统行为，但不要把“系统必须重新拉起被用户强制结束的 App”作为验收要求。重新手动打开后应恢复用户的记录意图；如果 persistent idle condition 仍存在，应恢复对应监控状态。
12. **手机重启**：在 Live Updates 状态和“静止省电监控”状态分别测试重启/首次解锁后的恢复。确认数据库可继续写入，并记录 Core Location 实际恢复时机。
13. **权限降级**：把“始终”改成“使用 App 时”。即使“记录足迹”开关仍表示用户意图，实际引擎必须停止，清理 idle condition，并显示“等待始终定位权限”。恢复“始终”后建立新的 tracking session boundary 并重新开始 Live Updates。
14. **精确位置关闭**：关闭 Precise Location，确认设置页明确显示受限提示；低质量点应被保存层拒绝，也不能凭低质量漂移错误进入 idle 监控。重新开启后提示/精度应恢复正常。
15. **系统定位关闭**：关闭 Location Services，确认状态明确且不写伪造/缓存点；若当时处于 idle monitor，恢复系统定位后重新验证监控/Live Updates 状态。
16. **弱信号**：地下停车场、高楼密集区、地铁进出站测试。确认精度差的短距离漂移不会被“转弯”逻辑误保存，也不会用来证明稳定静止、错误建立过小 geofence。
17. **模式切换**：在前台从均衡切换到精确/运动，再切回均衡，并分别在 Live Updates 与“静止省电监控”状态切换。切换应先移除 idle condition，再按新模式启动正确的 Live Updates/后台策略；均衡/极省电显示“静止低功耗监控”，精确/运动显示“及时后台”。
18. **删除数据时处于 idle**：进入“静止省电监控”后删除全部轨迹。确认 recorder anchor/last-record UI 被清空且 tracking session boundary 重建；idle monitor 不应让已删除点继续成为新轨迹过滤基准。

## 功耗基线

不要用一次短测试判断耗电。至少做路线和手机使用方式接近的完整工作日比较。

- **Day 0 / baseline**：暂停 aro，记录“设置 → 电池”中的总耗电、后台活动和屏幕时间。
- **Day 1 / Balanced**：使用“均衡”全天记录。它不持有 `CLBackgroundActivitySession`；移动时使用 `.default` Live Updates，连续稳定静止约 5 分钟后应取消 Live Updates 并只保留 persistent `CLMonitor`，离开约 60 m 圈后恢复 Live Updates。
- **Day 2 / competitor**：同类日程开启目标足迹 App 的省电模式，与 Day 1 比较总路线质量、aro/竞品电池占比和后台活动。
- **Day 3 / Precise（可选）**：使用“精确”验证 `CLBackgroundActivitySession` 的及时交付和预期更高功耗；精确模式不进入 idle CLMonitor 路径。
- 用 Instruments / Energy Log 做至少一次“静止 30–60 分钟 → 步行或驾车 30–60 分钟”。进入“静止省电监控”后 Live Updates 的位置生成应真正停止/显著下降，而不是仅由 aro 丢弃大量位置；重新移动后 Live Updates 应及时恢复。
- 静止测试至少记录进入 idle 前后的 `定位`计数。例如进入 idle 后 20 分钟仍每秒/每几秒增长，视为失败；少量 CLMonitor/系统诊断事件不等于高频 GPS 回调。
- 检查后台位置指示行为。均衡/极省电没有 `CLBackgroundActivitySession`；精确/运动可以出现与及时后台会话一致的系统可见行为。
- 测试低电量模式、Wi‑Fi 开/关和蜂窝弱信号；记录条件，因为无线/定位环境会显著影响功耗和 geofence exit 延迟。
- 不在产品文案承诺固定耗电百分比、固定回调周期或每 N 米必有一个系统定位。TrackingMode 的距离是保存策略；60 m idle monitor 半径也是当前工程参数，不是系统保证的精确触发距离。

## 路线质量建议目标

aro 2.0 当前均衡策略：水平精度上限约 80 m，正常移动约 35 m 级保存；超过约 60 秒且至少移动约 12 m 可补点；明显转弯约 12 m 后可提前保存；水平精度噪声会提高短距离保存门槛。连续约 5 分钟的优质定位若始终集中在约 30 m 范围内，则转入 60 m idle monitor。

真机对照重点是：

- 总距离不再像 1.5 对照那样明显大幅低估。
- 主要城市路口不被长直线切掉。
- aro 不要求比竞品点更少；已经生成的高质量移动点可以更积极保存。
- 静止后应从“不断收到再过滤”变成 CLMonitor 低功耗守候。
- idle monitor 的离开检测不能换来明显的起步缺失；如稳定出现几十米以上过大缺口，优先调整 monitor 半径/恢复路径，而不是重新加入 significant-change、visit 或 Core Motion fallback。

## 数据正确性

- 同一路线分别测试步行、骑车和驾车，比较轨迹与实际道路。
- 验证跨午夜、夏令时切换和时区切换后的每日分组。
- 导出 GPX，再删除本地数据并重新导入，核对点数、日期和总距离。
- 导入大文件前保留原始文件；批量导入会重建每日统计。
- 关闭记录后再重新开启，确认新 tracking-session boundary 生效；旧缓存定位不能作为新会话首批后台数据混入。
- 制造/模拟乱序记录点后确认 `daily_summary` 与 raw points 重算距离一致，历史页与 lifetime 不应少算。

## Local / Cloud 构建配置

1. **Local 编译检查**：共享 `aro` scheme 的 `Debug`/`Release` 使用 `aro/aro.local.entitlements`，签名 App 不包含 CloudKit container、iCloud services 或 `aps-environment`。
2. **Cloud 编译检查**：CI 的 `CloudDebug` simulator build 必须通过；真机 `CloudDebug`/`CloudRelease` 使用 `aro/aro.entitlements`，保留 `iCloud.com.xunbo.aro`、Push Notifications、Remote notifications。
3. **Personal Team 真机安装**：使用 Debug Local 安装 iOS 26+ iPhone，并确认嵌入 Watch App/Widget 可安装。验证 Live Updates、CLMonitor、SQLite、导入导出、Watch battery 和 complications。
4. **Local iCloud UI**：明确显示当前构建未启用 iCloud 同步；普通启动、前台进入、Live Updates/CLMonitor 后台恢复都不能初始化 CloudKit。
5. **Cloud 生命周期隔离**：Cloud 构建普通前台可以启动同步；silent push 通过独立 remote-notification callback 触发同步。仅 Core Location 导致的后台进程恢复不能顺带启动 CloudKit。

## iCloud / CloudKit 同步

CloudKit 当前不是 aro 2.0 定位验收的发布重点；代码仍作为可选编译能力保留。若未来重新启用，以下检查必须在加入 Apple Developer Program 的真实设备上完成，unsigned CI/模拟器不能验证 silent push。

1. Capability / provisioning：确认 `iCloud.com.xunbo.aro`、Push Notifications、Remote notifications 和签名 entitlement 正确。
2. 默认关闭：新安装默认不上传轨迹。
3. 首次开启：已有本地点先本地可用，再最终上传；离线记录仍必须成功。
4. 双设备拉取：同 Apple 账户两台设备最终一致，允许系统合并 push。
5. 相同历史去重：两端已有相同 timestamp/lat/lon 时，不得因不同 `sync_id` 让本地点数/summary 翻倍。
6. 关闭/重开：关闭停止未来同步但不删云数据；重开后最终合并。
7. 删除全部：有 cloud footprint 时先删 `AROTracks` zone，再清 SQLite；另一设备接到 zone 删除后也应清本地，旧数据不得复活。
8. iCloud 不可用时的删除：不能只删本地留下可恢复的云副本。
9. 账户变化：暂停同步、保留本地，不把旧账户数据上传到新账户。
10. **位置恢复隔离**：让系统因 Live Updates 或 CLMonitor 恢复 aro，确认 CloudKit 未启动；再单独触发/等待 Cloud remote notification，确认同步入口正常。
11. iCloud 开/关分别做完整工作日功耗对照，区分定位成本与网络同步成本。

## Bundle ID 与数据边界

- iOS Bundle ID：`com.xunbo.aro`；Watch App：`com.xunbo.aro.watchkitapp`；Widget：`com.xunbo.aro.watchkitapp.widget`；Watch companion identifier：`com.xunbo.aro`。
- aro 不自动读取旧 `com.xunbo.traceon` 容器。旧 Traceon/Companio 历史需要导出/导入。
- `Application Support/traceon/tracks.sqlite3` 只是 aro 当前容器内的稳定相对路径，不代表跨 Bundle ID 迁移。

## Apple Watch 与快捷指令

1. 使用同一开发团队签名 iOS/Watch/Widget，安装到已配对设备；Watch App 中应显示 aro。
2. Watch App 底部的 bundle-derived 版本号在 aro 2.0 初始构建应为 `v2.0.0 (1)`。
3. Watch 可达时在 iPhone“设备”页刷新，最近同步时间应推进；不要仅看电量数值是否变化。
4. Watch 不可达时，iPhone 必须明确使用缓存并保留较新的时间戳，旧快照不能覆盖新快照。
5. 快捷指令“获取设备电量”：可达先尝试实时；不可达返回最近缓存和同步时间；从未收到快照时给可操作错误。
6. Battery complication：在 Watch App 不打开 2–3 小时的情况下观察系统分配的 Widget/Watch background refresh，记录真实间隔但不要求固定 30/60 分钟。
7. Track complication：确认圆形 `aro 轨迹` 显示当天路线和距离；iPhone 前台时可立即更新，后台只做已有 WatchConnectivity session 下的机会式发布。
8. **定位隔离**：分别制造一次 Live Updates 背景恢复和一次 CLMonitor exit 背景恢复，确认没有因为位置恢复而主动请求 Watch battery 或激活新的 WatchConnectivity session。
9. 使用 Instruments/系统电池页对比无 Watch 功能、普通 Watch 功能和 complication 场景，确认 Watch 逻辑没有把 iPhone 全天定位功耗明显放大。

## 发布前最低通过条件

- Local Debug simulator build、CloudDebug simulator build、XCTest、static analyzer、generic device build全部通过。
- iOS 26 真机均衡模式完成“进入 idle CLMonitor → 静止期间定位回调显著停止 → 离开范围恢复 Live Updates”、后台/锁屏、Live/Monitor 两种系统回收、弱信号和竞品同路线对照。
- idle monitor 不得重新造成 1.5 式数百米起步缺失；若失败，不允许用旧 significant-change / visit / Core Motion wake 作为无依据 fallback。
- 至少两个完整工作日的均衡功耗数据足以说明没有明显持续后台回归，并与目标足迹 App 的省电模式做可比对照。
- Cloud/Watch 若本次发布包含对应功能改动，则完成各自签名真机检查。
- 不以模拟器或一次短途测试替代 Core Location 后台/功耗结论。
