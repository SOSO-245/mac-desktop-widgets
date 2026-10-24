# Mac Desktop Widgets & Cards

五款中文原生 Mac 桌面工具：家庭概览、万年历、Codex 重置、VPN 实时卡片、Nikki 实时卡片。SwiftUI / AppKit / WidgetKit，macOS 14 及以上。

[下载安装包](https://github.com/SOSO-245/mac-desktop-widgets/releases) · [构建与使用](docs/BUILD.md) · [隐私与权限](docs/PRIVACY.md) · [第三方来源](THIRD-PARTY-NOTICES.md)

| 项目 | 版本 | 主要功能 | 形式 | 发布架构 |
| --- | --- | --- | --- | --- |
| [家庭概览](projects/home-overview) | 2.0.2 | Home Assistant 用电、功率、温湿度曲线、空气质量、NAS、车库/家充；状态栏功率 | 应用＋三尺寸小组件 | Apple Silicon |
| [万年历](projects/lunar-calendar) | 1.0.0 | 农历、彩色节气/节日、法定调休自动更新、生日、重复日程、自定义菜单栏 | 应用＋三尺寸小组件 | Apple Silicon / Intel |
| [Codex 重置](projects/codex-resets) | 1.0.5 | 公共重置公告、倒计时、上次重置经过天数、点击来源网站 | 应用＋三尺寸小组件 | Apple Silicon / Intel |
| [VPN 实时卡片](projects/vpn-card) | 1.1.2 | FlClash / Shadowrocket 节点、套餐、流量曲线、六站点延迟、状态栏 | 可拖动桌面卡片 | Apple Silicon / Intel |
| [Nikki 实时卡片](projects/nikki-card) | 1.0.2 | 旁路由实时流量、套餐、六站点延迟、策略组/节点切换、自选菜单栏项目 | 可拖动桌面卡片 | Apple Silicon / Intel |

## 安装

1. 在 Releases 下载所需 ZIP，解压后将应用移入 `~/Applications` 或“应用程序”。
2. 这些包采用本地临时签名，**未经过 Apple 公证**。首次打开可能被 Gatekeeper 阻止；确认来源后按 macOS 提示在“隐私与安全性”中允许，或自行从源码构建。不需要关闭全局安全保护。
3. 家庭概览和 Nikki 需填写自己的服务器地址与密钥；按提示允许本地网络。没有内置任何人的账户、订阅或密钥。
4. 前三款在桌面右键 → 编辑小组件中添加；两款实时卡片从应用打开，省略号切换小中大、锁定位置。

## 使用特点

- 蓝紫玻璃配色；实时卡片大号展示六站点，两行三列。
- 家庭概览的菜单栏功率为荧光绿，超过 1000 W 粉红，超过 3000 W 亮紫。
- Codex 重置有明确计划时显示粉红倒计时，无计划时显示荧光绿的上次重置经过天数。数据来自社区站点，**不是个人账号额度，也不是 OpenAI 官方工具**。
- 万年历桌面组件停止点选 30 秒后返回今日，主窗口/菜单栏为 60 秒；实际 WidgetKit 显示由系统调度。节假日每天北京时间零点尝试更新，启动/唤醒补查。
- Nikki 右上角 ⇄ 打开策略组与节点选择；“菜单栏显示”可自由组合图标、名称、延迟、套餐、剩余额度、节点、上传和下载。

## 范围与限制

家庭概览公开版已把设备唯一编号和车辆别名替换为示例实体。部分高级实体和电费模型仍需修改源码映射，详见子项目说明；不是安装后自动发现任意家庭设备的通用 HA 客户端。

VPN 卡片只监测已安装客户端；Shadowrocket 数据读取可能需要系统授权，接口兼容性随客户端版本变化。Nikki 是独立控制端，需要开启已有控制接口，程序不会修改路由器监听或防火墙。测速结果不代表流媒体/账号解锁状态。

WidgetKit 刷新频率由 macOS 决定；桌面实时卡片需要应用进程保持运行。登录启动为应用内可选功能，没有额外维护定时任务。发布包没有 Apple Developer ID / 公证；Intel 仅完成构建，未真机验收。真实通讯录/日历写入、登录重启和 Nikki 真实节点切换未作为自动测试执行。

## 开发

各项目独立，运行项目目录中的 `python3 build.py` 构建；默认不安装。测试使用本机模拟服务和合成数据，不需要生产账户。完整命令见 [BUILD.md](docs/BUILD.md)。

原创代码以 [MIT](LICENSE) 开源；第三方依赖与数据遵循各自声明。项目与 Apple、OpenAI、Home Assistant、FlClash、Shadowrocket、Nikki 及测速站点没有隶属关系。站点小图标采用项目自行绘制的文字标记，不分发第三方品牌 Logo。
