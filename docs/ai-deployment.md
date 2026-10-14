# v0.6.1 AI 配置、使用与可选代理部署

## 架构与数据边界

默认：Flutter / GitHub Pages PWA → DeepSeek 官方 API（用户输入个人 API Key）。

可选：Flutter / GitHub Pages PWA → 自建 HTTPS 私有代理 → 所选模型服务。

词库、FSRS、收藏、错词、统计、打卡和 AI 任务继续在本机 Drift 保存。这次没有新增账号或学习数据同步服务。已有云同步功能沿用现有实现，默认云快照不增加 AI 建议/任务表；文件备份可以主动包含 AI 数据。AI 不发送整个词库、学习历史、备份、来源文件或背景图片。模型输出按纯文本渲染。

DeepSeek 直连模式按用户要求直接填写个人 API Key，仅保存在 Riverpod 当前会话内存中，不写 Drift、日志、备份或 CacheStorage。刷新 PWA 或关闭进程后需要重新输入；只将密钥以 Authorization 请求头发送给固定的 `https://api.deepseek.com`，不允许更换直连地址。使用个人设备填写自己的密钥；浏览器运行期间可访问该密钥，因此这不是服务端密钥托管方式。

私有代理模式仍将模型密钥保留在服务器环境变量中；App 的代理访问凭证是独立的密码，亦仅存当前会话。代理地址请只填写你信任的服务。

## 最简单的方式：直接输入 DeepSeek API Key

1. 在 [DeepSeek 开放平台](https://platform.deepseek.com/api_keys)创建并复制完整 API Key（`sk-…`），不是 Tracking ID，也不是聊天账户登录凭证。
2. 应用 → 设置 → AI 学习助手设置，保留默认「DeepSeek 直连」。
3. 粘贴到「DeepSeek API Key」，点击「保存设置」。无需代理地址、代理访问凭证或服务器。
4. 可点「连接测试」：只请求官方 `GET /models`，检查鉴权和模型可用性，不生成计费内容。
5. 使用词条补全、批量补中文或学习解释；需要生成时再主动点击。

默认模型 `deepseek-flash`，可在「高级选项」修改账户支持的模型名。使用 Chat Completions、JSON object、4000 输出 token 上限和 `reasoning_effort=none`，不安装客户端模型 SDK。Dart 提示词/Schema 与 Provider 分离，字段、长度及请求身份仍严格验证；拒绝、截断、空结果、非法 JSON、401、余额不足、限流、断网和超时分别显示错误，无自动重试。批量仍最多两条同时请求，状态与结果在本机保存；直连的调用限额由 DeepSeek 执行，不经过 Node 单进程限流队列。取消信号传到实际 HTTP 请求。

2026-10-14 已对线上站点 Origin 执行官方接口 OPTIONS 预检，允许 POST 和 Authorization / Content-Type；未提供真实密钥，未执行计费生成。若未来服务商调整 CORS，浏览器会显示网络错误，可改用私有代理。浏览器 CORS 配置不是本项目控制的。

## 运行代理（可选）

需要 Node.js >=22。GitHub Pages 只能运行静态前端，需另外准备可运行 Node 的服务器；本项目不会开通付费服务。

```sh
cd ai-proxy
npm ci
cp .env.example .env
# 编辑 .env 后执行：
npm run check
npm test
npm run build
npm start
```

`npm run dev` 可以直接运行 TypeScript。`scripts/start.sh` 提供相同生产启动入口。

待填写的必需项：

| 配置 | 内容 |
| --- | --- |
| `MODEL_BASE_URL` | 模型 API 基地址，本次默认 `https://api.deepseek.com`；非本机必须 HTTPS |
| `MODEL_NAME` | 模板预填 `deepseek-flash`，可改为 DeepSeek 当前支持且你已开通的模型；程序不会猜测未填写的模型 |
| `MODEL_API_KEY` | 服务端 DeepSeek API 密钥 |
| `PROXY_ACCESS_TOKEN` | 单独随机生成至少 24 字符的访问凭证，可用 `openssl rand -hex 32`；不能直接复用模型密钥 |
| `PROVIDER_API` | `responses` 或 `chat`，以服务商实际支持为准 |
| `OUTPUT_MODE` | 支持严格结构化输出时选 `json_schema`；否则明确选 `json_object` 或 `text`，所有模式仍通过 Zod 严格校验 |
| `ALLOWED_ORIGINS` | 逗号分隔，PWA 为 `https://abaddon145.github.io`，不是带 `/-/` 的 URL |

### 本次使用 DeepSeek

`.env.example` 已按 DeepSeek 的 Chat Completions API 配置 `PROVIDER_API=chat` 和 `OUTPUT_MODE=json_object`。
`MODEL_BASE_URL=https://api.deepseek.com`，模型示例为 `deepseek-flash`。
`CHAT_MAX_TOKENS=4000` 限制输出；`CHAT_REASONING_EFFORT=none` 使用非思考模式，适合短词条补全和解释。
这些参数与模型名已核对 [DeepSeek 官方 API 文档](https://api-docs.deepseek.com/) 和 [Chat API 参数](https://api-docs.deepseek.com/api/create-chat-completion/)。
若使用其他兼容服务，可将 `CHAT_REASONING_EFFORT=omit`；不支持 `max_tokens` 的服务可设置 `CHAT_MAX_TOKENS=omit`，并显式调整 API / 输出能力配置。

DeepSeek 的 [JSON Output](https://api-docs.deepseek.com/guides/json_mode/) 使用 JSON object 模式；本项目仍在服务端和客户端验证字段、数量、长度及请求身份，不把 JSON 模式当成严格 Schema 保证。
代理使用官方 OpenAI SDK 的兼容协议调用 DeepSeek，实际请求发往 `MODEL_BASE_URL` 指定的 DeepSeek 服务，无需 OpenAI 模型账户或 OpenAI 模型密钥。

DeepSeek 网页聊天的登录不等于 API 访问。直连模式将个人 API 密钥填入 App 的「DeepSeek API Key」。如果选择私有代理模式，将模型密钥仅填写到服务器的 `.env` / 环境变量；不要填入 App 的代理凭证框。
完成服务器配置后，在 App 中填写 **私有代理的 HTTPS 地址及独立代理访问凭证**，而不是 DeepSeek 模型 API 地址与密钥。

代理默认监听 `127.0.0.1:8787`。通过已有 Nginx/Caddy 等反向代理提供 HTTPS，转发 `Authorization`，限制请求体至 16 KiB；读超时需超过 `REQUEST_TIMEOUT_MS`。关闭反向代理对请求头、正文、凭证与模型响应的记录。移动端在 HTTPS 网站上不能请求远端明文 HTTP。

默认请求超时 60 秒（包括等待队列）；App 90 秒。并发最多 2，每分钟模型调用默认 20，最大等待/运行总量 40。超时和取消均传递到实际 SDK HTTP 请求。代理断开也会取消上游请求。上游若已完成或不支持中断，取消不保证免除已产生费用。

**限流仅对一个 Node 进程有效**。本次建议单实例运行；多个进程或机器各自拥有自己的配额，不能把它当全局限额。本次不增加 Redis。任务持久化由本机 Drift 承担，服务器重启不恢复内存队列，用户在 App 中手动重试。

SDK 与 App 无自动重试，集中策略为 `MAX_RETRIES=0`；可设为 1，只对服务商错误/限流进行一次重试，每次重试仍进入限流队列。失败建议不会写词库。

## API 契约

所有接口都要求 `Authorization: Bearer <PROXY_ACCESS_TOKEN>`，含健康检查。CORS 单独检查允许来源，不代替鉴权。无 Origin 的原生客户端仍必须提供凭证。

- `GET /health`：服务状态、提示词版本、能力模式、单进程限制信息；健康检查不请求模型。
- `POST /v1/complete`：词条补全。
- `POST /v1/explain`：学习解释。

请求由 `ai-proxy/src/schema.ts` 和 `lib/features/ai/domain/ai_models.dart` 定义：UUID requestId、正整数 wordId、原词（200 字符）、语境（600）、当前中文（2000）、词性/原形（200）、当前例句（每项 1000）、style、exampleCount（1–3）。请求上限 16 KiB。

返回 `{result, model, generatedAt, promptVersion}`。result 包含需求中的全部字段，并增加工作场景例句、易混淆词、英韩术语说明。简明与工作例句可按数量以换行分段。释义/解释 2000 字符、例句 1000、短字段 200；列表最多 6 项，每项 500；拼写候选最多 5 项，每项 200。返回体最大 32 KiB。程序记录生成时间、模型及 `ko-zh-v1` 提示词版本。客户端和服务端均拒绝身份不一致、缺字段、错误类型及超长结果。

错误为 `{error: {code}}`，区分未配置、鉴权、非法请求、限流、取消、超时、拒绝、截断、空响应、非法 JSON、结构错误与服务商错误，不返回 SDK 原始诊断。没有检索词典，界面不会声称“官方词典已验证”。

## App 配置

设置 → AI 学习助手设置：默认 DeepSeek 直连，填写个人 API Key、选择默认语境并保存；连接测试查询模型列表。切换为私有代理后，填写 HTTPS 代理地址和独立访问凭证；连接测试检查代理健康。两种模式的密钥与凭证分开保存在当前会话。

清理缓存会删除未确认、且不属于批量任务的建议，保留任务和确认内容。有效缓存期限 30 天，键包括词条完整内容和规范化时间、语境、任务类型、风格、例句数量、提示词版本。编辑原内容后旧建议失效。

## 三个功能

1. **AI 补全词条**：词库 → 单词详情 → AI 补全 → 选择语境 → 生成。逐字段对比原内容和建议，可编辑、勾选后保存。已有字段默认不勾选；疑似拼写/需语境的中文不默认接受。重新生成保留候选供切换比较。拼写变更另选候选并单独确认，保存时检查重复词。
2. **AI 批量补中文**：词库 → 待补中文 → 勾选词 / 选择当前结果 → AI 批量补中文 → 语境 → 本机任务页 → 开始。每批最多 20，超过时取当前选中的前 20 并保留余下选择；此限制不影响每日新词或继续学习轮次。每条成功立即落盘；审核逐条编辑和保存中文，原词拼写保留。取消终止排队和支持取消的请求；重试只处理失败/未完成。已生成的成功结果不会重做，App 重开后在本机 AI 任务页手动继续。原词修改/删除会提示冲突；真实释义不会自动覆盖。
3. **AI 解释这个词**：学习题内 AI 解释 → 先显示有效缓存，或点击生成 → 更简单 / 工作场景 / 易混淆词 / 例句解析 → 可选保存例句与解释。打开面板暂停计时；关闭时仅在学习页可见且应用前台恢复。题目、输入、揭示状态和进度保留；关闭不评分，不完成学习。

AI 保存的用法、搭配、语法等在独立表中，不拼接进备注。确认内容显示“AI 生成·用户已确认”，不改变 FSRS、评分、学习计数或打卡。原表来源和生成时字段快照保留在本机。冲突必须先重新对比、再次勾选保存，保存事务还会重新核对快照。

## 迁移与备份

数据库从 v3 增量升级至 v4，仅新增 `ai_suggestions`、`ai_tasks`、`ai_task_items`、`ai_word_contents`，不清空旧表。没有运行时自动启动恢复任务。

设置 → 文件备份包含 AI 数据 为可选开关，默认关闭。旧 v1 备份没有 AI 表仍可恢复；新备份保留 v1 外层格式并附加四张 AI 表。恢复前始终保留含 AI 的本机快照；撤销恢复继续有效。正在运行的 AI 批量任务在文件恢复前先取消。恢复后的 running 项变为排队/待继续。凭证有导出与导入的双重过滤。

## 验收与限制

测试只用 Mock 模型、Mock HTTP 或本机测试代理，不使用真实模型密钥，不产生计费请求。验证记录见 [AI 验收记录](ai-validation.md)。

本次代码与 Mock 流程可以审查；没有提供真实个人 API Key，未进行真实生成与语义质量验收。前端发布后，个人使用默认只需输入自己的 DeepSeek API Key；选择私有代理模式时才需要独立部署代理。工业术语和疑似拼写结果始终需要人工核对。服务商 API 能力需要部署者验证并配置；选错能力会明确失败，不会自动降级发第二次计费请求。
