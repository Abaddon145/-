# KoreanMemo

本地优先的韩语背单词应用。用户从 Excel 导入自己的词库，应用通过韩语 TTS 和 FSRS 安排学习与复习。

## 当前里程碑

Milestone 1 基础版本包含：

- iPhone 与 Android 共用的 Flutter 工程
- `.xlsx` 文件选择、Sheet 读取、字段自动映射和导入预览
- 首次启动自动导入 3 份内置词库
- Drift / SQLite 本地数据库
- 词条与学习状态分离
- FSRS-6 评分与 Review Log 事务写入
- 韩语 `ko-KR` 系统 TTS
- 首页、导入页和最小学习卡片闭环
- 每日新词目标、每日复习上限和当天学习进度
- 首页、词库、学习、统计、设置五个底部导航页
- 词库搜索、编辑、删除、收藏与错词本
- JSON 一键备份/恢复词库、FSRS 进度、复习记录与设置
- 云白、青森、暮霞、深夜四套风格，支持上传自定义背景
- 手动逐条录入单词，并为每个单词标记和编辑词性
- 可安装到 iPhone 主屏幕的离线 PWA

每日学习计划默认每天 20 个新词、最多 100 次复习，可在首页右上角调整。设置和当天完成进度会持久化保存。

可在「词库」中点击「录入单词」，填写韩语、中文释义和词性；已有词条可通过「编辑 / 标记词性」补齐。设置中的「外观风格」提供四套预设与自定义背景图片（最大 2 MB）。

备份文件由用户保存在自己的设备或文件服务中；备份包含外观设置和背景图片。恢复会替换本机数据，并在执行前要求确认。

## Excel 最低格式

| 韩语单词 | 中文释义 |
|---|---|
| 사랑 | 爱；爱情 |
| 학교 | 学校 |

也识别 `단어 / 뜻 / word / meaning` 等常见列名。

当前内置词库包含 3,103 条分组记录，跨词库去重后为 3,029 个韩语词条。只有同时包含韩语和中文释义的行才会生成学习卡片。

## 本地运行

需要 Flutter stable（Dart 3.10+）。首次克隆后生成平台工程与 Drift 代码：

```bash
flutter create --platforms=ios,android --org com.abaddon145 .
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

## iPhone 安装说明

iOS 构建必须在安装了 Xcode 的 Mac 上执行。连接 iPhone、启用 Developer Mode，并在 Xcode 中选择自己的 Signing Team 后即可运行。未付费的 Personal Team 可用于个人设备测试，但配置文件会定期到期；App Store / TestFlight 分发需要 Apple Developer Program。

不使用苹果签名时，可以打开 GitHub Pages 上的 PWA，在 Safari 分享菜单中选择“添加到主屏幕”。词库和学习进度保存在当前浏览器的本地数据库中。

## 验证

```bash
flutter analyze
flutter test
flutter build ios --simulator --no-codesign
```
