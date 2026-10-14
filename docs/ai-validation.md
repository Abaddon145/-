# v0.6.1 验证记录

基线：main `6d3cb0594a3b8dba1b9281dd3c5e152b1be3e728`，v0.5.2。核对与验证日期：2026-10-14。
本机环境：Flutter 3.47.7 stable / Dart 3.13.5、Node 24.19.0；代理最低支持 Node 22，并提供 Node 22 CI。

## 已执行

| 验证 | 结果 |
| --- | --- |
| Drift build_runner 代码生成 | 成功，数据库 v4 增量迁移 |
| `flutter analyze` | No issues found |
| `flutter test --reporter expanded` | **96 项全部通过**，包含原 v0.6.0 的 78 项与直连新增 18 项 |
| `npm test`（ai-proxy） | **21 项全部通过**，仅 Mock SDK HTTP / 本机测试代理，无真实模型请求；新增 DeepSeek 地址、Chat / JSON object、输出上限和非思考参数的验证 |
| `npm run check` / `npm run build` | TypeScript 检查与编译通过 |
| `flutter build web --release --base-href '/-/' --pwa-strategy offline-first` | 发布构建成功，包含 Drift sqlite3.wasm 和 worker |
| `git diff --check` | 通过 |

Flutter CI 继续包含 macOS iOS simulator build、Web build 和两个非 UTC 时区统计回归；本地 Linux 不能执行 Xcode 构建。远端检查以 PR 的 Checks 页面为准。

## 覆盖的功能与边界

- 结构合法、缺字段、类型错误、数组/文本超限、非法 JSON、空响应、拒绝、截断、服务商限流。
- requestId / wordId / originalTerm / context 不一致时拒绝持久化。
- 仅保存用户选中字段；来源和备注保留，FSRS、复习日志、收藏、错词、统计、打卡逐表比较不变。
- 原词修改/删除、快照再次变化、重复保存、候选拼写的独立确认和重复词拒绝。
- SQLite v3 → v4 实际文件迁移、每日新词目标 250/400 仍可保存；旧备份、可选 AI 新备份、恢复快照和撤销恢复。
- AI 备份内容非法时，在删除当前数据之前拒绝恢复；会话凭证不进入导出/导入。
- 客户端两条并发、逐条落盘、部分失败、只重试未完成、取消实际请求、排队取消、同一任务拒绝重复启动、重开暂停并由用户手动继续。
- 服务端单进程并发 <=2、限流与排队上限、超时取消；AbortSignal 传到官方 SDK 的实际 fetch；取消后等待真实请求结束才释放并发槽。
- 代理鉴权、允许来源、请求大小、健康检查无模型调用、集中重试、错误日志不泄露密钥。
- PWA worker 跳过带 Authorization 的请求，包括同源代理，防止会话凭证落入 CacheStorage。
- 学习解释保持题目 ID、输入、揭示状态、本轮进度，关闭面板不评分；隐藏页面/后台应用不恢复计时。
- 320×568、1.5 倍字体、180/200 px 键盘 inset 的补全编辑与设置布局；词库选择可滚动；390×844 学习面板；AI 页面多次往返保留独立背景和零切换动画。

## 可重复的验收演示（Mock）

```sh
flutter test test/features/ai --reporter expanded
cd ai-proxy
npm test
```

1. `ai_data_test.dart` 的 acceptance 场景：为 `pressure / 압력` 的“原表未提供中文释义”生成测试建议，保持预览未保存状态，编辑中文后只确认中文，来源保留，无复习卡/日志/打卡变更。
2. `ai_tasks_test.dart`：包含部分失败、疑似 `clrculation`、取消/重试/恢复；疑似词拼写保持原样，成功结果待确认。
3. `ai_layout_test.dart`：在拼写练习中输入答案，打开并生成解释，关闭后继续原题；题目、输入和本轮进度一致，无自动评分。
4. `ai_client_test.dart`：Mock 断网返回错误，仍能从本机读取下一题。原记录/打卡保留由保存逐表比较及原有统计/恢复测试验证。

## 待配置及已知限制

真实个人 DeepSeek API Key 未提供，**尚未完成真实生成与语义质量验收**。默认直连只需用户填写个人 API Key；私有代理仍是可选方式。上述建议与响应均为测试数据，不构成工业术语质量或速度承诺。

已验证手机尺寸 widget 布局；未执行真实 iPhone/Android 硬件上的键盘、PWA 杀进程、弱网及长时间后台测试。iOS 签名与分发需要用户自己的配置。

现有 flutter_tts 4.2.5 在 Flutter 的 Dart Wasm dry-run 中发出 JS interop 类型警告；默认 JavaScript PWA 构建成功，本次未启用 Dart Wasm 目标。SQLite Wasm 运行文件沿用 Drift 官方版本，与这个 Dart Wasm 警告无关。

代理限额是单进程，不是多实例全局配额。用户关闭进程时服务器可能已产生模型费用；取消不保证撤回已完成的调用。任务以本机状态为准，重开后需要手动继续。

## v0.6.1 直连验证

基于已合并 v0.6.0 主分支 `d131101636140b69b72c360a9ac7258396fe28ba`，数据库仍为 v4；不改学习表，不添加数据库列或运行时依赖。

- 实际对 `https://api.deepseek.com/chat/completions` 执行浏览器 OPTIONS 预检（Origin `https://abaddon145.github.io`），HTTP 200，允许该 Origin、POST 和 Authorization / Content-Type。没有使用密钥，没有计费请求。
- 新增 16 项直连 Mock HTTP 测试：固定官方域名、Bearer 头且禁止跳转、JSON Schema 提示契约、选中词数据、解释风格、身份检查、各类结果/HTTP 错误、不泄露原始错误、无自动重试、只用 GET models 的连接检查，以及实际 AbortableRequest 取消/超时。
- 新增 2 项设置/Provider 测试：无需代理即可保存并使用直连；密钥默认隐藏，只在本次会话跨页面保留，数据库与含 AI 备份均无密钥，新运行会话不恢复密钥；原代理配置与访问凭证独立保留。
- 现有小屏、大字体、键盘、学习面板计时/题目保持、批量与备份迁移回归全部随 96 项完整测试通过。
- 服务商可能改变浏览器跨域策略；本项目不能保证未来 CORS 配置。真实手机和真实 API Key 生成尚未验收。代理的单进程并发/限流仅适用于代理模式，直连使用本机批量两条并发与 DeepSeek 自身限额。
