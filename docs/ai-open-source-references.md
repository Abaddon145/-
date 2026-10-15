# AI 开源参考与依赖

本次基于主分支 `6d3cb0594a3b8dba1b9281dd3c5e152b1be3e728`（v0.5.2，数据库 v3），交付目标 v0.6.0 / 数据库 v4。
仓库没有 AGENTS.md；已读取数据库、文件恢复、学习控制器、现有测试和 CI。以下记录为实际读取源码的版本，核对日期 2026-10-14。

| 项目 / 查看 SHA | 实际参考文件 | 采用方式与本项目位置 | 许可 |
| --- | --- | --- | --- |
| [raine/anki-llm](https://github.com/raine/anki-llm) / `2a0abab3c089361f3967e785f0499837eb481c5f` | `LICENSE`, `Cargo.toml`, `src/batch/preview.rs`, `engine.rs`, `file_mode.rs`, `process_file/command.rs`, `src/llm/provider.rs`, `src/generate/pipeline/regenerate.rs`, `src/generate/tui/screens/review.rs` | 借鉴逐字段差异预览、逐条接受/拒绝、重新生成、保留候选、增量保存与恢复、配置/Provider 分离。以 Dart 重写到 `lib/features/ai/presentation/ai_assistant_sheet.dart`、`ai_tasks_page.dart`、`data/ai_repository.dart`、`ai_task_runner.dart`；TypeScript 重写 Provider 和提示词分离。无 Rust/Anki 运行依赖，无源码复制。 | MIT，Copyright (c) 2025 Raine Virta；原文见 `docs/licenses/anki-llm-MIT.txt` |
| [brylee10/anki-language-gpt](https://github.com/brylee10/anki-language-gpt) / `788168f8adfa221cf28cd52865b3430747b0057b` | `LICENSE`, `pyproject.toml`, `python/openai_generator.py`, `translation_utils.py`, `anki_language_gpt.py` | 借鉴翻译/例句/解释分字段、语言/例句数量配置、目标词强调和异步批量思路。韩中及工业提示词独立重写至 `ai-proxy/src/prompts.ts`；纯文本强调、数量选择至 `ai_assistant_sheet.dart`；取消、校验、冲突和限流由本项目实现。无 Python 运行依赖，无源码复制。 | MIT，Copyright (c) 2024 Bryan Lee；原文见 `docs/licenses/anki-language-gpt-MIT.txt` |
| [sindresorhus/p-queue](https://github.com/sindresorhus/p-queue) / `7f272ab5ff2254c0dc2537b7977e88ede1cd55e8`（10.0.0） | `license`, `package.json`, `source/index.ts`, `source/priority-queue.ts`；实际安装包的 `license`, `dist/index.js` | **直接依赖 10.0.0**，Node >=22，ESM。在 `ai-proxy/src/scheduler.ts` 采用并发 2、每分钟调用限额、排队上限；独立 AbortController 区分等待和运行中的取消，实际请求结束才释放并发槽。内存队列不持久化；Flutter/Drift 保存任务。限制仅对单进程有效，多实例并非全局限额。 | MIT，Copyright (c) Sindre Sorhus；原文见 `docs/licenses/p-queue-MIT.txt` |
| [openai/openai-node](https://github.com/openai/openai-node) / `dd51b11156f920c57dc2e4ad4162cf28a42fe8a1`（初始主分支 7.33.0）；采用版本 SHA `2b12eabd29733c8de495bb183b41632e091b4994`（v7.32.0） | 两个版本的 `LICENSE`, `package.json`, `docs/structured-outputs.md`；采用版本 `src/client.ts`, `src/resources/responses/responses.ts` | **直接依赖 7.32.0**（实施时 npm 稳定发布版本），Node >=22。`ai-proxy/src/provider.ts` 使用官方 SDK Responses 或 Chat；能力通过环境变量选择 JSON Schema / JSON object / text；Zod 本地验证并区分拒绝、截断、空响应、非法 JSON、服务商错误；SDK `maxRetries=0`，集中调度重试。客户端不依赖 SDK。 | Apache-2.0；采用版本完整 LICENSE 见 `docs/licenses/openai-node-Apache-2.0.txt`。该版本根目录无 NOTICE 文件；SDK 包内自带的第三方许可随 npm 包保留。 |

Zod 4.3.6 用于服务端验证及 JSON Schema 生成（MIT）；TypeScript、tsx 和 Node 类型包仅用于开发/构建，锁定的实际版本见 `ai-proxy/package-lock.json`。新增 Flutter HTTP 直接依赖沿用现有锁文件中的 http 1.6.0（BSD-3-Clause），未增加终端语言依赖。

四个参考项目的词库、生成内容、图片、品牌素材与界面均未复制。测试例子由本项目自建，仅存在测试代码。流程借鉴不构成对参考项目速度或模型效果的性能承诺。

本项目的 schema、提示词、Flutter UI 和 TypeScript 适配代码独立编写。附上参考项目许可用于审查；直接依赖的版权及第三方许可文件仍保留在 npm 包中，打包服务端时必须随依赖一同分发。

## v0.6.1 个人 DeepSeek API Key 直连

按用户后续要求增加 `lib/features/ai/data/ai_deepseek_client.dart`；不新增 SDK 或依赖，使用已有 Dart HTTP。`domain/ai_prompts.dart` 独立重写并沿用本项目 ko-zh-v1 字段契约，按 [DeepSeek 官方 Chat API](https://api-docs.deepseek.com/api/create-chat-completion/) 和 [JSON Output](https://api-docs.deepseek.com/guides/json_mode/) 配置。官方 API 文档和跨域预检核对日期 2026-10-14。代理端 SDK/队列与原许可记录不变；密钥不写入源码、数据库、日志或备份。

## v0.7.0 设备密钥持久化

直接依赖 pub.dev 的 `flutter_secure_storage` **11.2.0**（BSD-3-Clause，Copyright 2017 German Saprykin），以 `pubspec.lock` 中制品校验值锁定。本次查看该发行包的 LICENSE、README、iOS/Web 选项与 Web 存储实现，不复制其源代码。实现位置：`lib/features/ai/data/ai_key_store.dart`、`tool/configure_device_storage.dart`。原生密钥使用设备安全存储；Web 使用其 WebCrypto 实验实现，同源脚本仍可能访问，不描述为服务器密钥托管。遵循用户后续要求从“仅会话保存”改为“此设备自动保存”，备份仍排除密钥。

Drift Web 运行文件同步到已锁定的 **2.35.2**，包含上游 2.35.1 的 IndexedDB 事务持久化修复及 2.35.2 的 OPFS 嵌套事务修复；数据库 schema 仍为 v4。
