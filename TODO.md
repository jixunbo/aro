# TODO

- [ ] iOS 26 真机验证 Balanced 的 idle CLMonitor：稳定静止后停止高频 Live Updates，离开约 60 m 范围后及时恢复，且不出现 1.5 式数百米起步缺失。
- [ ] iOS 26 真机验证 Live Updates 与 CLMonitor 两种状态下的后台、锁屏、系统回收、重启和权限降级/恢复。
- [ ] 与目标足迹 App 省电模式做同路线 2–3 km 对照，比较距离、转弯、点数、更新/定位/保存/过滤诊断。
- [ ] 完整工作日 Balanced 功耗对照，并至少一次使用 Instruments / Energy Log 验证 idle 后位置生成显著停止。
- [ ] aro 2.0.1 真机验证 Watch App/Widget 安装、Battery complication 三段颜色，以及 iPhone 当日轨迹无需手动打开 Watch App 即可刷新 Track complication。
- [ ] 如重新启用 CloudKit，再做签名真机 silent push、多设备同步、账户变化与删除语义验证。
- [ ] GeoJSON 导出保留时间戳（当前仍不保留）。
