# KoreanMemo

本地优先的韩语背单词应用。用户从 Excel 导入自己的词库，应用通过韩语 TTS 和 FSRS 安排学习与复习。

## 当前里程碑

Milestone 1 基础版本包含：

- iPhone 与 Android 共用的 Flutter 工程
- `.xlsx` 文件选择、Sheet 读取、字段自动映射和导入预览
- Drift / SQLite 本地数据库
- 词条与学习状态分离
- FSRS-6 评分与 Review Log 事务写入
- 韩语 `ko-KR` 系统 TTS
- 首页、导入页和最小学习卡片闭环
- 亮色 / 暗色主题

手动字段映射、重复词交互策略和完整统计仍按 Issue #2–#4 继续实现。

## Excel 最低格式

| 韩语单词 | 中文释义 |
|---|---|
| 사랑 | 爱；爱情 |
| 학교 | 学校 |

也识别 `단어 / 뜻 / word / meaning` 等常见列名。

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

## 验证

```bash
flutter analyze
flutter test
flutter build ios --simulator --no-codesign
```
