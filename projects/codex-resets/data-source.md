# Codex Resets 数据来源与接入约定

本项目读取 [Codex Resets](https://codex-resets.com/zh-CN) 的公开重置公告数据。该站为社区项目，与 OpenAI 无隶属关系；这些数据不能代表当前用户的账户额度或实际可用量。无需登录、令牌或任何账号权限。

## 已核验的接口

2026-10-22 23:55（Asia/Shanghai）直接 HTTPS 请求核验成功：

| 用途 | URL | 核验 |
| --- | --- | --- |
| 当前状态、计划、统计 | `https://codex-resets.com/api/v1/status` | HTTP 200；同一 ETag 条件请求 HTTP 304 |
| 最近 5 次记录 | `https://codex-resets.com/api/v1/resets?limit=5&order=desc` | HTTP 200 |
| 官方 API 说明 | `https://codex-resets.com/api/docs` | HTTP 200 |
| OpenAPI 3.1 schema | `https://codex-resets.com/api/openapi.json` | HTTP 200，API 版本 1.0.0 |

官网 API 说明要求在展示数据的地方提供回链，例如「数据：Codex Resets」，链接到 `https://codex-resets.com/zh-CN`。组件本体点击打开来源网站符合这一用途，管理页也应保留明确来源链接。

无需解析网页 HTML，也无需接入站点的 MCP 服务。中文网页的 Python urllib 请求曾返回 403，但以上公开 API 均直接可读；应使用 API，不围绕网页限制制作抓取绕过逻辑。

## 状态模型

`GET /api/v1/status`：

```text
{
  data: {
    latest_reset: Reset | null,
    scheduled_reset: ScheduledReset | null,
    active_watch: Watch | null,
    stats: {
      total: Int,
      last_reset_at: Date | null,
      days_since_last: Double | null,
      avg_interval_days: Double | null
    }
  },
  meta: { api_version: "v1", generated_at: Date }
}
```

`Reset`：

```text
{
  id: String,
  reset_type: "regular" | "banked",
  announced_at: Date,
  text: String,
  source: { type: "x_post", author: String, url: URL }
        | { type: "observed", url?: URL }
}
```

`ScheduledReset` 包含同一组字段，并增加 `status: "scheduled"` 和 `scheduled_for: Date | null`。

`Watch`：

```text
{
  level: "elevated" | "strong",
  reset_chance_percent: Int | null,
  forecast_window: String,
  observed_at: Date,
  expires_at: Date,
  text: String,
  source: ResetSource
}
```

说明中的字段目前均为必需，只有明确标注 `null` / `?` 的值可空。Swift 解码可忽略未来新增字段；对未知 `reset_type` / `source.type` 推荐保留原值或友好降级，避免单个枚举扩展令整页失效。

## 历史模型

`GET /api/v1/resets` 返回：

```text
{
  data: [Reset],
  pagination: { has_more: Bool, next_cursor: String | null },
  meta: { api_version: "v1", generated_at: Date }
}
```

可用参数：`limit`（1–100，默认 20）、`order`（`asc` / `desc`，默认 `desc`）、`from` / `to`（ISO 日期时间，含边界）、`cursor`（原样使用接口返回的不透明游标）。组件只需 3–5 条，不必遍历全历史。接口未提供「最长等待」字段；除非完整计算并明确范围，否则不显示该统计。

## 关键语义

- `latest_reset` 是已记录的执行／观察结果；`announced_at` 是公告或首次观察时间，不能宣称为每个账号的精确到账时间。
- `scheduled_reset` 是等待执行证据的明确计划。**`scheduled_for` 已经过期也不代表已经执行。** 倒计时归零后显示「已到计划时间 · 待确认」，直到新的 API 数据确认。`scheduled_for` 为 `null` 时显示「已有计划 · 时间待定」。
- 计划重置不计入 `stats`。不要把计划当成最新完成记录，也不要给计划额外编造概率。
- `active_watch` 是站点 AI 分类的观察／预测，不是 OpenAI 的承诺；它与明确计划不同。显示时用「观察中」等明确措辞；超过 `expires_at` 后隐藏或标注已过期，不能继续当作有效预测。
- `regular` 与 `banked` 含义不同，后者为积存重置信用。可显示类型标签，不能自行改写成普通账户周期重置。
- 总次数和平均间隔直接使用 `stats`；`days_since_last` 是源站四舍五入的快照数据。组件需要运行中的相对时间时，从 `last_reset_at` 或 `announced_at` 计算，不持续冻结站点的一位小数。

## 时间与当前样例

时间字段使用带时区的 RFC3339／ISO 8601 字符串，实测包含毫秒和 `Z`。解码应同时兼容有／无小数秒；内部保存绝对时间，展示按系统当前时区转换，不固定加 8 小时。

核验时 API 的紧凑摘要（仅为测试快照，不是静态线上默认值）：

```json
{
  "latest_reset_at": "2026-10-20T06:33:48.000Z",
  "scheduled_for": "2026-10-22T17:00:00.000Z",
  "total": 64,
  "avg_interval_days": 6.3,
  "active_watch": null,
  "generated_at": "2026-10-22T15:55:00.905Z"
}
```

上海时区对应最近记录 10 月 20 日 14:33，计划时间 10 月 23 日 01:00。原公告文本中的自然语言时区不应用于再次推导时间，优先使用 API 结构化的 `scheduled_for`。

## 缓存、刷新与故障显示

实测 `/status` 响应为 `Cache-Control: public, max-age=14400, s-maxage=60, stale-while-revalidate=300`；历史接口为相同值但 `s-maxage=300`。两者提供 `ETag`，条件请求 `If-None-Match` 已核验返回 304。

推荐实现：

1. 本地保存最后一次成功解码快照及其 ETag、源站 `generated_at`、客户端成功检查时间 `checkedAt`。当前组件与管理 App 共用模型，各自沙盒独立缓存，不使用 App Group；两个界面的上次检查时间因此可能不同。
2. 刷新使用条件请求，避免默认 URLSession 本地缓存让用户手动刷新仍停留最长 4 小时。使用 `.reloadIgnoringLocalCacheData` 并携带已保存 ETag；不要添加随机查询参数。304 保留内容并更新 `checkedAt`，不要把 `generated_at` 伪造为当前时间。
3. 当前版本向 WidgetKit 申请每 5 分钟更新；实际由系统决定。倒计时应使用本地时间渲染，不按秒请求 API。手动刷新沿用同一条件请求。
4. 429 读取 `Retry-After` 秒数退避；503、超时和网络不可用保留最近有效快照。错误页显示「缓存数据」／「暂时无法更新」及上次成功时间，不用零值抹掉有效统计。没有缓存时显示占位和重试入口。
5. 解码失败不覆盖好缓存；状态成功、历史失败时仍显示状态并保留旧历史。来源在后台回源期间可能返回稍旧快照，展示时区分「已检查」与「源数据时间」。不要仅因 `generated_at` 较旧就断言用户离线。
6. 不把示例数据或测试 fixture 用作首次联网失败后的真实显示。预览可以显著标注示例。

OpenAPI 声明的错误 JSON 类型为 `application/problem+json`，包含 `type`、`title`、`status`、`code`、`detail`、`request_id`，可选 `parameter`。错误信息不需要完整展示给桌面用户。

## 本地验证材料

- `Tests/Fixtures/status-live.json`：2026-10-22 的公开状态原始响应。
- `Tests/Fixtures/resets-live.json`：同次抓取的最近 5 条公开记录。
- `Tests/Fixtures/openapi.json`：站点公开 OpenAPI schema。
- `Tests/Fixtures/status-null.json`：按 schema 构造的空状态与 nullable 字段测试（非实测数据）。
- `Tests/Fixtures/resets-empty.json`：按 schema 构造的空历史测试；历史 `data` 应为空数组，不是 `null`（非实测数据）。

这些文件仅用于离线解码和语义测试。未来需要更新时直接重新请求公开 API；不包含用户账户、凭据或私有家庭数据。
