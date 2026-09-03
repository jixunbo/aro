# TODO

- [ ] iOS 26 真机验证 Balanced robust idle：稳定静止约 5–7 分钟后停止高频 Live Updates，少量 GPS outlier 不阻止进入约 60 m CLMonitor；离开范围后及时恢复且不出现 1.5 式数百米起步缺失。
- [ ] iOS 26 真机验证极省电：移动时 Standard Core Location 的点间距离分布接近约 100 m、定位精度保持高质量，系统自动 pause 后进入约 100 m CLMonitor，离开静止范围后恢复 Standard updates。
- [ ] iOS 26 真机验证 Live Updates、Eco Standard updates 与 CLMonitor 状态下的后台、锁屏、系统回收、重启和权限降级/恢复。
- [ ] 与一生足迹省电模式做同路线 2–3 km 对照，比较距离、点间距分布、转弯、精度、更新/定位/保存/过滤诊断，以及静止后的回调数量。
- [ ] 完整工作日分别做 Eco / Balanced 与一生足迹省电模式功耗对照，并至少一次使用 Instruments / Energy Log 验证 idle 后位置生成显著停止。
- [ ] aro 2.0.2 真机验证 Watch App/Widget 安装、Battery complication 三段颜色，以及 iPhone 当日轨迹无需手动打开 Watch App 即可刷新 Track complication。
- [ ] 如重新启用 CloudKit，再做签名真机 silent push、多设备同步、账户变化与删除语义验证。
- [ ] GeoJSON 导出保留时间戳（当前仍不保留）。
