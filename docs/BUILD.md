# 构建与测试

需要 macOS 14+、完整 Xcode（包含 macOS SDK）、Python 3。仅 VPN 卡片可仅用 Command Line Tools 构建；含 WidgetKit 的项目需要完整 Xcode。节气生成工具需 Node.js，但常规构建直接使用已生成数据。

在任意子项目目录运行：

```sh
python3 build.py
```

安装包输出到该目录 `交付/`。默认只构建，不修改已安装的应用。`--install` 才安装；家庭概览安装器带备份与回滚，VPN/Nikki 已存在同名应用时会停止，需先妥善备份。普通用户可手动拖入应用程序。

构建脚本会生成 Xcode 工程和 plist。首次使用 `python3 build.py --generate-only` 可只生成家庭概览、万年历或 Codex 重置的工程。所有包仅临时签名；正式发行请自行配置合法 Developer ID、签名授权与公证。

## 测试

在仓库根运行 `python3 scripts/test_all.py`。测试包括：

- 万年历：日期、农历、节气、调休、生日提醒、重复规则与返回今日计时；另含合成天气、同步冲突合并和隔离文件读写，含天文台数据对照。
- 家庭概览：模型、模拟 HTTP、详情单位与时效、曲线、安装回滚的隔离测试。
- Codex 重置：缓存、网络模拟、倒计时、导航语义、互动计数和模拟请求；不发送真实感谢。
- VPN 卡片：FlClash / Shadowrocket 模型、权限失败、站点探测与剩余额度；节点身份/订阅匹配、占位与重名拒绝、选择前复核、取消请求及左右键隔离，均使用合成数据或注入的模拟传输，不打开真实客户端 URL。
- Nikki：只向本机模拟接口测试认证、请求编码、选择校验、回读、菜单栏配置；不切换真实路由器节点。

六款菜单栏自定义测试同时编译 `AppSettings.swift`，与统一设置路由使用同一依赖。测试不启动六款正式应用、不修改用户真实连接设置，也不执行天气测试的可选联网参数。

公开版与本机定制版使用相同应用标识，便于正常升级，但不适合同时安装两个副本。发布构建不执行安装或启动应用，避免读入开发者的个人数据。通用安装包的 Intel 兼容性需实际硬件进一步验证。

Mac 实时监测：18 项采集解析、时效与网卡计数差值检查，以及 9 项菜单栏检查。Vendor 中提供已核对上游发行包的 Apple Silicon 采集器，构建无需 Rust。

网速范围回归：VPN 与 Nikki 各自运行 `bash Tests/run-traffic-tests.sh`，验证实际出站分类、连接新增/消失、计数重置、时间回退、无效包及缓存兼容；已纳入 `scripts/test_all.py`。

## 更新组件

首次构建会下载固定 Sparkle 2.10.0，核对 SHA256 后缓存；需要连接 GitHub。每款 Updater/config.json 只包含公开地址与公钥。发布过程见 [UPDATES](UPDATES.md)。

手机测试：在 projects/codex-resets/scriptable 运行 `node Tests/run-tests.js` 和 `node Tests/update-tests.js`。

真实更新隔离测试：`python3 shared/updater/Tests/run-integration.py`。创建独立测试钥匙串账号和临时应用，仅监听回环地址；分别验证成功替换、坏包拒绝、坏清单拒绝。不会给真实六款应用安装测试版本。
