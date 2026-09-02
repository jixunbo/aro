# aro 真机验收清单

安装或分发改动后的构建前，确认 iOS App、Watch App、Widget Extension 以及全部 Local/Cloud 配置使用同一个预期版本。Bug 修复通常递增 patch 版本；向后兼容的新功能通常递增 minor 版本。

## 后台记录

每次测试前在“设置”页确认：自动记录已开启、定位权限为“始终”、精确位置已开启。

1. **普通后台**：打开 aro 后切换到其他 App，步行 500 米；回到 aro，确认轨迹点、距离和时间更新。
2. **锁屏**：锁屏后步行或驾车 10 分钟；解锁后确认路线没有完全中断。
3. **静止后恢复**：使用“均衡”模式静止至少 15–30 分钟，让系统有机会自动暂停标准定位，然后不打开 aro 直接步行或驾车至少 2–3 km。回到 App 后确认低功耗的显著位置变化/到访离开事件能重新拉起标准定位，路线在第一段低功耗唤醒之后继续出现较密的标准定位点，而不是全程只剩几条数百米级直线。
4. **同路线对照**：在相近时间和信号环境下重复同一条约 2–3 km 路线，记录 aro 的轨迹点数、拐弯保留情况和总距离，并与修复前版本或另一款足迹 App 对照。均衡模式不要求逐米导航，但不应长期退化成只有 significant-change 级别的稀疏点。
5. **系统回收**：开启多个大型 App 造成内存压力，随后移动；aro 应能通过显著位置变化或到访通道恢复。
6. **手动划掉**：从多任务界面结束 aro，再移动至少 500 米；不同 iOS 版本的调度可能有延迟，检查“记录通道”是否显示“显著位置变化”。
7. **重启手机**：重启并首次解锁后移动；确认数据库仍可写入。
8. **权限降级**：分别测试“使用 App 时”、关闭精确位置、关闭系统定位和关闭后台 App 刷新，确认界面能明确显示状态。
9. **弱信号**：测试地铁、地下停车场、高楼密集区；确认漂移点不会造成异常长距离。

## 功耗基线

不要用一次短测试判断耗电。至少比较两个完整工作日，并保持路线和手机使用方式接近。

- 第一天：暂停 aro，记录“设置 → 电池”中的总耗电与屏幕时间。
- 第二天：使用“均衡”模式，记录相同数据以及 aro 的后台活动占比。
- 第三天：如需更低耗电，改用“极省电”；如需路线细节，改用“精确”。
- 对“均衡”模式额外做一次静止 30 分钟 → 移动 30–60 分钟的 Energy Log，确认标准定位自动暂停后 Core Motion 活动更新也停止，并在低功耗移动事件出现后恢复标准定位。
- 使用 Xcode Instruments 的 Energy Log 做 30–60 分钟步行和驾车样本。
- 测试低电量模式、Wi‑Fi 开/关和蜂窝弱信号；无线信号差通常会放大定位耗电。

建议初始目标：均衡模式在典型工作日的额外耗电保持在可感知但较低的范围，同时接受道路拐角会比精确模式稀疏。不要在产品文案中承诺固定百分比。

## 数据正确性

- 用同一条路线分别测试步行、骑车和驾车，比较轨迹与实际道路。
- 验证跨午夜、夏令时切换和时区切换后的每日分组。
- 导出 GPX，再删除本地数据并重新导入，核对点数、日期和总距离。
- 导入大文件前保留原始文件；批量导入会重建每日统计。

## Local / Cloud 构建配置

1. **Local 编译检查**：使用共享 `aro` scheme 的 `Debug` 或 `Release` configuration。确认构建使用 `aro/aro.local.entitlements`，签名后的 app 不包含 `com.apple.developer.icloud-container-identifiers`、`com.apple.developer.icloud-services` 或 `aps-environment`。
2. **Personal Team 真机安装**：使用 Apple Personal Team 的 `Debug` configuration 安装到 iPhone，再确认嵌入的 Watch App 和 Widget Extension 也能安装到已配对 Apple Watch。验证定位记录、后台定位授权、SQLite、GPX/GeoJSON、Watch battery 和 Widget/复杂功能均可使用。
3. **Local iCloud UI**：在 Local 版设置页确认 iCloud 区块明确显示“当前构建未启用 iCloud 同步”，没有可操作的开关、立即同步按钮或 CloudKit 错误；普通启动、回前台和 Core Location 冷启动都不初始化 CloudKit。
4. **Cloud 编译检查**：使用 `CloudDebug` 或 `CloudRelease` configuration。确认构建使用 `aro/aro.entitlements`，保留 `iCloud.com.xunbo.aro`、CloudKit、`aps-environment` 和 `remote-notification`；Watch App 与 Widget 仍只使用现有 App Group。
5. **Cloud 真机安装与同步**：使用加入 Apple Developer Program 的团队和匹配 profile 安装 Cloud 版，按下面的 iCloud / CloudKit 清单验证首次开启、silent push、离线本地优先、重复合并、删除传播、账户变化和后台冷启动隔离。Local 版不执行这些 CloudKit 行为测试。

## iCloud / CloudKit 同步

这些检查必须在加入 Apple Developer Program 的真实设备上完成。GitHub Actions 使用 `CODE_SIGNING_ALLOWED=NO`，模拟器也不能验证 CKSyncEngine 的 silent push。

1. **Capability / provisioning**：在 iOS `aro` target 中确认 iCloud → CloudKit 选中 `iCloud.com.xunbo.aro`，Push Notifications 已启用，Background Modes 中 Remote notifications 已选中；安装到真机后用签名后的 app entitlement 检查 `aps-environment` 与 CloudKit container 都存在。
2. **默认关闭**：全新安装时确认 iCloud 同步默认关闭；仅记录轨迹不会创建可见的同步状态，也不会影响本地 SQLite 写入。
3. **首次开启**：记录若干本地轨迹后开启同步，等待“已同步”；关闭网络再记录新点时本地记录必须继续成功，恢复网络/手动“立即同步”后再上传。
4. **双设备拉取**：两台设备登录同一 Apple 账户并开启同步。A 新增轨迹后，确认 B 在系统允许的 silent push/同步时机收到；若推送被系统合并，B 前台进入或手动同步后必须最终一致。
5. **已有相同历史**：在 A、B 分别导入包含相同 timestamp/latitude/longitude 的 GPX 后，先让 A 上传，再让 B 同步。B 的本地重复点应采用云端 `sync_id` 而不是再次上传一条不同 record ID；最终本地点数和每日统计不能翻倍。
6. **关闭再开启**：同步成功后关闭 iCloud，同步状态应停止但云端副本保留；本地继续新增点。重新开启后应先拉取远端变化，再最终上传本地未同步点。
7. **删除全部（同步开启）**：两台设备均已同步时，在 A 执行“删除全部轨迹”。A 应先删除 CloudKit `AROTracks` zone 再清本地；B 收到 zone 删除后也必须清空本地，而不是把旧轨迹重新上传。之后 B/A 再次进入前台，旧数据不能复活。
8. **删除全部（同步已关闭）**：设备曾经成功使用过 iCloud 后关闭开关，再执行“删除全部轨迹”。确认删除动作仍要求访问并清理 CloudKit；若 iCloud/网络不可用，应显示失败且保留本地数据，避免只删本地后未来被云端恢复。
9. **远端 zone 删除**：在另一台设备或 CloudKit 管理环境删除 `AROTracks` zone，接收设备应把它视为全局删除并清空本地轨迹；这是有意的数据语义，不要把 zone 删除当作无害的同步重置。
10. **账户变化**：登出 iCloud 或切换 Apple 账户时，aro 应暂停同步并保留当前本地数据，不能自动把旧账户的数据上传到新账户。旧账户中的 CloudKit 数据仍属于旧账户；需要删除时必须切回对应账户。
11. **位置后台隔离**：开启 iCloud 后，通过显著位置变化触发一次 Core Location 冷启动。日志/Instruments 应显示 LocationService 恢复，但该 location-triggered launch 不初始化 CloudKit；普通启动或 CloudKit 远端通知启动可以初始化同步引擎。
12. **功耗**：分别在 iCloud 关闭与开启的情况下做至少两个路线相近的完整工作日对比；记录无线活动、后台启动和电量。不要把一次 silent push 或用户主动“立即同步”的网络活动算成持续定位回归。

## Bundle ID 变更与数据边界

- 在仍有历史轨迹的 Traceon/Companio 真机上先导出 GPX/GeoJSON，再安装使用新身份的 aro；确认 aro 可以独立启动、定位授权和设置初始化正常，并将导出文件重新导入后核对点数、日期和总距离。
- 确认 iOS Bundle ID 为 `com.xunbo.aro`，Watch App 为 `com.xunbo.aro.watchkitapp`，Widget Extension 为 `com.xunbo.aro.watchkitapp.widget`，Watch 的 `WKCompanionAppBundleIdentifier` 为 `com.xunbo.aro`。
- 明确验证 aro 不会读取旧 `com.xunbo.traceon` 容器中的 SQLite/UserDefaults；旧 App 与 aro 可以作为两个独立身份存在。不要把新 App 的数据库路径仍叫 `Application Support/traceon/tracks.sqlite3` 解读为跨 Bundle ID 的自动迁移。

## Apple Watch 与快捷指令

1. 使用同一开发团队签名 `aro` 与 `ARO Watch App`，在已配对的 iPhone/Apple Watch 上从 `aro` scheme 安装；确认 Watch App 中显示 aro。
2. 在手表上打开 aro，确认电量、充电状态、iPhone 连接状态和底部的 bundle-derived 版本号出现；`1.4.0` 的初始构建应显示 `v1.4.0 (1)`。回到 iPhone“设备”页，确认设备名、电量和同步时间一致。
3. 手表可达时进入“设备”页并点刷新，确认产生新的同步时间；不要只依据数值相同判断是否刷新。
4. 关闭蓝牙、让手表离线或拉开距离后再次查看，确认 iPhone 明确标注“使用缓存/不代表实时电量”，并保留较新的快照而不被旧时间戳覆盖。
5. 在快捷指令中运行“获取设备电量”：可达时确认先尝试实时请求；不可达时确认返回最近缓存及同步时间；从未收到快照时确认给出可操作的错误提示。
6. 在活动表盘上保留 aro 复杂功能，打开 Watch App 一次后退出，随后至少 2–3 小时不要再次打开 Watch App。每隔约 30–60 分钟查看 iPhone 端最近同步时间；当 watchOS 分配后台预算时，时间戳应能在不打开 Watch App 的情况下推进。记录真实间隔，但不要把一小时的 preferred date 当作保证。
7. 重复上一步但移除活动复杂功能，比较后台更新时间戳的变化；这用于确认复杂功能带来的 watchOS 预算差异，不要求固定次数。
8. 确认 iPhone 普通启动或回前台后可以被动吸收 Watch 的较新 application context，即使用户没有先打开“设备”页；同时通过 Core Location 冷启动时仍不得因此主动初始化 WatchConnectivity 或发送实时请求。

## WidgetKit 电量复杂功能

1. 在同一开发团队下安装 `ARO Watch App` 与 `ARO Watch Widget Extension`，并确认两者都使用 `group.com.xunbo.traceon.watch` App Group。
2. 在活动 Apple Watch 表盘上添加 aro 复杂功能，分别检查圆形、角落、行内和矩形样式；首次没有快照时应显示 `--%`，不能出现伪造电量。
3. 打开一次 Watch App，确认表盘复杂功能与 Watch App 显示同一电量和状态；在 iPhone“设备”页记录收到的时间戳。
4. 关闭 Watch App 并保持手表闲置数小时，周期性记录 Watch 复杂功能和 iPhone 快照时间戳；Watch App 会以一小时为 preferred date 请求下一次 app refresh，Widget 会请求约 30 分钟后的新 Timeline，但 watchOS 可以分别延后或节流。重点验证复杂功能无需重新打开 Watch App 仍能显示新的电量；Widget 自己采样不会同步推进 iPhone 时间戳，只有 Watch App 获得执行机会且显示值发生变化时才会发布新的 WatchConnectivity context。
5. 移除活动复杂功能后重复相同观察，作为对照；至少观察完整一天再判断 watchOS 调度差异。
6. 确认 Widget Extension 只在 WidgetKit 请求新 Timeline 时读取一次 `WKInterfaceDevice` 并写入 App Group，没有前台计时器、持续轮询或 iPhone 网络请求；若暂时读不到有效电量，应回退到最新有效快照而不是显示伪造值。Watch App 的自主刷新只更新 application context，不应产生无请求对应的 `sendMessage`。模拟器只能验证编译和静态布局，不能验证复杂功能刷新频率。
7. 打开 Watch App 后确认交互前台每五分钟才允许一次周期采样；放下手腕或按下数码表冠后，场景离开 `.active`、计时器停止，电量监控回到关闭状态。确认 aro 页面不会在 Always On 状态持续显示。

如果表盘编辑器中找不到 `aro 电量`，记录手表型号和 watchOS 版本，确认已安装完整的 `ARO Watch App`（不是只有 iOS App），并核对 Widget Extension 已随 Watch App 嵌入、bundle identifier 为 `com.xunbo.aro.watchkitapp.widget`、App Group 为 `group.com.xunbo.traceon.watch`。在手表上打开一次 aro 后退出并重新打开表盘编辑器；确认当前表盘位置支持所选 accessory family，再重新安装一次 Watch App 做对照。不要把模拟器中能编译或能预览 Widget 当作真机表盘可发现性的证明。

## 设备功能的后台能耗隔离

- 在未打开“设备”页的情况下，通过显著位置变化触发一次 iOS 后台定位唤醒；用 Instruments/日志确认这次启动没有向 Apple Watch 发送实时电量请求，也没有因为 iCloud 功能初始化 CloudKit；该冷启动也不应仅为了接收 Watch 快照而初始化 PhoneConnectivity。
- 确认 iPhone 端没有电量轮询计时器、仅为电池监控注册的 `BGTaskScheduler` 任务或其他周期后台任务。Watch 的 app-refresh 调度发生在 watchOS 本身。
- 分别对合并前基线与合并版本做至少两个路线和使用方式接近的完整工作日对比，并用 Instruments Energy Log 做 30–60 分钟步行/驾车样本。比较定位唤醒、CPU、无线活动和“设置 → 电池”后台活动；模拟器结果不能替代此项。
- 在“设备”页前台停留、频繁手动刷新、运行快捷指令和手动 iCloud 同步时单独测量，避免把用户主动设备/云端请求的无线活动误算成后台定位回归。
