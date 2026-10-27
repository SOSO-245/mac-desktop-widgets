# 来源与许可

- 农历基础：Apple Foundation 中国历；系统框架不作为第三方二进制打包。
- 法定节假日：[NateScarlet/holiday-cn](https://github.com/NateScarlet/holiday-cn)，MIT；完整许可保留在万年历 `THIRD-PARTY-NOTICES.txt`。
- 二十四节气：[6tail/lunar-javascript](https://github.com/6tail/lunar-javascript)，MIT，固定提交 `4c45a59f79b856125516f31aefa8295035c16afd`。构建期源代码及许可在万年历 `Tools/vendor/`。
- 测试对照：[香港天文台公历农历对照](https://data.weather.gov.hk/weatherAPI/hko_data/calendar/nongli_calendar_2026.csv) 与 [2026 年节气表](https://www.hko.gov.hk/tc/gts/time/calendar/text/files/T2026c.txt)。只用于核对日期事实，不表示天文台认可本项目，不随应用安装包提供测试夹具。
- Codex 重置：[Codex Resets](https://codex-resets.com/zh-CN) 公共 API，应用内保留数据来源与回链；第三方公告不代表 OpenAI 或个人额度。接口说明见子项目 `data-source.md`。
- Nikki 接口：[Mihomo API](https://wiki.metacubex.one/api/)。应用仅调用控制 API，没有打包其代理核心。
- FlClash / Shadowrocket：应用仅兼容用户另行安装的软件，不包含其程序、订阅或品牌图标文件。
- 六站点图标：本项目绘制的圆角字母缩写（G、GH、YT、GPT、CL、B），不使用第三方 Logo；服务名称仍属于各自权利人。
- 应用图标与玻璃纹理：项目原创绘制或 AI 辅助生成，不使用 Home Assistant 或其他官方应用图标。原生 SF Symbols 由 macOS 在运行时提供，不单独打包字体。

根 MIT 许可适用于原创代码；上列第三方文件按各自许可和来源使用，不改变第三方商标或数据权利。

## macmon

Mac 实时监测分发并调用未修改的 macmon v0.10.0 官方 Apple Silicon 二进制。项目：https://github.com/vladkens/macmon ，MIT 许可证保存在 projects/mac-vitals/Vendor/LICENSE；固定源提交 5df67a54e082e0b30a0aa2b48b7c7f78a36f1795。官方原始发行 tar.gz SHA256：0ccff60b7bf67bcb9e09cc8f804656a1cafa7eeae7297ee83d10e460ead7d43d。应用打包时仅重新本地签名。

## Sparkle

六款使用 [Sparkle 2.10.0](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0)，保留官方框架签名。许可及其第三方依赖声明在各项目 Updater/Sparkle-LICENSE，发布 ZIP 根目录也包含 Sparkle-LICENSE.txt。归档 SHA256 固定于 updater_build.py。

## Electric Border CSS (visual reference for Codex Resets)

https://github.com/hammadxcm/electric-border-css — MIT, Copyright (c) 2025 Fyniti. The moving turbulence/displacement and layered glow are adapted to native SwiftUI Canvas; no webpage is embedded or downloaded at runtime. License: projects/codex-resets/Assets/ElectricBorder-MIT.txt (also included in the app Resources).

## Power water duck

`projects/home-overview/Resources/duck-*.png` are original AI-generated transparent illustrations commissioned for this project (base duck, seasonal accessories, snow and cartoon shock skeleton). Prompt is included alongside the asset. The SwiftUI water renderer is original project code; it does not embed a third-party runtime.
