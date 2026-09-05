# TODO

- [ ] iOS 26 真机验证 Balanced robust idle：稳定静止约 5–7 分钟后停止高频 Live Updates，少量 GPS outlier 不阻止进入约 60 m CLMonitor；离开范围后及时恢复且不出现 1.5 式数百米起步缺失。
- [ ] iOS 26 真机验证极省电 2.1.2：同路线确认 steady-state 约 100 m cadence 不再被软件过滤大量吞掉；记录稳态/过渡定位与过滤原因、精度恢复次数，并验证保存点数量明显靠近一生足迹省电模式。
- [ ] iOS 26 真机验证 Live Updates、Eco Standard updates 与 CLMonitor 状态下的后台、锁屏、系统回收、重启和权限降级/恢复；Eco Motion-only 静止短于约 2 分钟不得误睡，idle capture 失败不得用旧点建立 geofence。
- [ ] 与一生足迹省电模式继续做同路线 2–3 km 对照：2026-09-05 基线为竞品约 2.5 km / 25 点，aro 约 2.0 km / 9 点且 23 定位 / 10 保存 / 13 过滤；2.1.2 重点比较 steady filter、精度恢复后有效点数、总距离与切弯。
- [ ] 完整工作日分别做 Eco / Balanced 与一生足迹省电模式功耗对照，并至少一次使用 Instruments / Energy Log 验证 idle 后位置生成显著停止。
- [ ] aro 2.1.2 真机验证 Watch App/Widget 安装、Battery complication 三段颜色，以及 iPhone 当日轨迹无需手动打开 Watch App 即可刷新 Track complication。
- [ ] 如重新启用 CloudKit，再做签名真机 silent push、多设备同步、账户变化与删除语义验证。
- [ ] GeoJSON 导出保留时间戳（当前仍不保留）。
