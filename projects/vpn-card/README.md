# VPN 实时卡片

可拖动 AppKit 桌面面板，监测本机 FlClash 或 Shadowrocket。三种尺寸、位置锁定、套餐用量与到期、实时流量曲线，大号六站点两行三列；菜单栏延迟与剩余额度圆环。

不是 VPN 客户端，不附带节点/订阅。FlClash 兼容 0.9.1 的本机配置与 SQLite profiles，使用其已经启用的 loopback 控制接口和认证。Shadowrocket 只读共享数据，系统可能要求单独授权，数据格式兼容性随版本变化。

流量来自所选客户端，不用整机流量代替。站点测速只走对应本机代理或已验证 VPN 隧道，无法确定路径则不测试。切换显示来源仅打开客户端，不启停 VPN 或切换节点。

构建 `python3 build.py`，模型测试 `bash Tests/run-tests.sh`、`bash Tests/run-shadowrocket-tests.sh`、`bash Tests/run-site-tests.sh`。登录启动在菜单选择，维护在进程内。

## 注意要点

macOS 14+；当前发布为临时签名，未公证。运行时的私人配置不在仓库中；来源许可见根 THIRD-PARTY-NOTICES.md。默认构建不会安装应用。

菜单栏显示设置支持九项独立开关和七项自定义颜色；全部关闭仍保留入口图标，同一线路常规测速保留旧值直到新结果返回。默认常规延迟荧光绿、超过 2000 ms 粉红色。
