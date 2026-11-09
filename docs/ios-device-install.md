# iPhone 真机安装

KoreanMemo 的 iOS 工程在 `ios/`。在 Mac 上用 Xcode 签名后，可以装到自己的 iPhone。仓库里没有 Apple Team ID、证书或描述文件；签名使用你自己的 Apple 账号。

Linux 上的 CI 和云端环境不能为真机做代码签名，也不会生成可安装的设备 IPA。模拟器构建命令是 `flutter build ios --simulator --no-codesign`。

## 工程里已经定好的值

| 项 | 值 |
|---|---|
| Bundle ID | `com.abaddon145.koreanMemo` |
| 测试包 Bundle ID | `com.abaddon145.koreanMemo.RunnerTests` |
| 主屏幕名称 | 韩语记忆（与 PWA 的 `apple-mobile-web-app-title` 一致） |
| 最低系统 | iOS 15.0。这是当前 Flutter stable（生成时为 3.47.8）模板的要求。`file_picker` 需要 iOS 14+，`flutter_secure_storage` 需要 iOS 13+。 |
| 签名 | `CODE_SIGN_STYLE = Automatic`，不写入 `DEVELOPMENT_TEAM` |
| 版本 | 来自 `pubspec.yaml` 的 `version`（当前 `0.8.0+13`） |
| 出口合规 | `ITSAppUsesNonExemptEncryption` 为 false。应用只使用系统 HTTPS 和 Keychain，没有自行实现的加密算法。上传 TestFlight 时一般不必再回答出口合规问卷。 |

Android 工程在 `android/`，`applicationId` 为 `com.abaddon145.korean_memo`。`tool/configure_device_storage.dart` 会关闭系统自动备份，避免设备上的 API Key 被系统备份复制走。Release 清单声明了 `INTERNET`，以便正式包访问已配置的 HTTPS 接口。

### 隐私用途字符串

当前调用路径不需要额外的 `*UsageDescription`。缺了用途字符串时，iOS 会在真正访问该项数据时直接崩溃；反过来，写上用不到的字符串，上架审核会追问原因。因此这里按插件的实际入口处理：

- **文件**：导入 Excel 使用 `FileType.any`，备份和自定义背景（jpg / jpeg / png / webp）使用 `FileType.custom` 或 `saveFile`。iOS 上这些都走系统文件选择器（`UIDocumentPicker`），不读取相册。
- **照片**：应用没有使用 `FileType.image`、`FileType.video` 或 `FileType.media`，不会打开 `PHPicker`。不添加 `NSPhotoLibraryUsageDescription`。以后如果改成从相册选图，必须补上这句，否则一打开相册就会崩溃。
- **朗读**：`flutter_tts` 用 `AVSpeechSynthesizer` 朗读韩语或英语，代码没有把音频会话设成录音。不添加 `NSMicrophoneUsageDescription`。
- **密钥**：DeepSeek API Key 存在本机 Keychain（`flutter_secure_storage`）。这不使用用途说明字符串，而使用下面的 entitlement。

### Keychain

`dart run tool/configure_device_storage.dart` 写入 `ios/Runner/Runner.entitlements`：

```xml
<key>keychain-access-groups</key>
<array/>
```

并在 Runner 的 Debug / Release / Profile 里设置 `CODE_SIGN_ENTITLEMENTS`。这是 `flutter_secure_storage` 要求的 Keychain Sharing 能力，访问组留空，不表示某个 Team。不要删掉这个文件，否则设备上保存密钥会失败（常见错误 `-34018`）。

免费 Personal Team 有时会提示不支持 Keychain Sharing。出现这种情况时，付费 Apple Developer Program 可以签带该能力的描述文件。学习功能本身不依赖密钥；不签名时仍可使用下面的 PWA。

## Mac 与 Xcode

1. Mac 上从 App Store 安装 Xcode，打开一次并接受许可。需要命令行工具时执行 `xcode-select --install`。
2. 安装 Flutter stable（Dart 3.10+）。`flutter doctor` 里 Xcode 一项应为可用。
3. 用数据线连接 iPhone，在手机上点“信任此电脑”。
4. iOS 16 及以上：设置 → 隐私与安全性 → 开发者模式，打开后按提示重启。没开开发者模式时，开发签名的 App 无法启动。iOS 15 没有这一项。
5. 准备一个 Apple ID。装到自己的手机可以用免费 Personal Team。TestFlight 和 App Store 需要加入 [Apple Developer Program](https://developer.apple.com/programs/)。

## 打开工程并选择签名团队

在仓库根目录：

```bash
flutter pub get
dart run tool/configure_device_storage.dart
dart run build_runner build --delete-conflicting-outputs
flutter build ios --config-only
open ios/Runner.xcworkspace
```

打开的是 `ios/Runner.xcworkspace`，不是单独的 `Runner.xcodeproj`。`--config-only` 只生成 Flutter / 插件工程，不产出已签名的 IPA。

在 Xcode 中：

1. 选中 Runner target → Signing & Capabilities。
2. 勾选 Automatically manage signing。
3. Team 选择你的 Personal Team 或公司团队。Xcode 会把 Team ID 写进本机的 `project.pbxproj`。不要把这个改动提交到 git。
4. Bundle Identifier 保持 `com.abaddon145.koreanMemo`。如果提示该 ID 已被其他账号占用，改成你账号下唯一的 ID，并同时改 Runner 三个构建配置里的 `PRODUCT_BUNDLE_IDENTIFIER`。

第一次在这台 iPhone 上打开开发版时：设置 → 通用 → VPN 与设备管理 → 信任你的开发者证书。

## 真机运行

```bash
flutter devices
flutter run -d <device-id>
```

也可以用 `scripts/ios_device.sh run`，或在 Xcode 里把运行目标选成这台 iPhone 后按 Run。

## Archive、Ad Hoc、Personal Team 与 TestFlight

| 方式 | 账号 | 装到手机的方式 |
|---|---|---|
| `flutter run` 或 Xcode Run | 免费 Personal Team 或付费账号 | 手机连着 Mac，直接安装 |
| Personal Team 到期 | 免费账号 | 描述文件大约 7 天后失效，App 会打不开。用同一个 Apple ID 再 Run 一次即可换发。免费账号不能使用 TestFlight，可注册的设备数量也更少。 |
| Ad Hoc | Apple Developer Program | 在开发者网站登记这台 iPhone 的 UDID。Xcode：Product → Archive → Distribute App → Ad Hoc，导出 IPA，再用 Finder 或 Apple Configurator 安装。描述文件只覆盖已登记的设备，有效期通常随证书（大约一年），不是 7 天。 |
| TestFlight / App Store | Apple Developer Program | Archive → Distribute App → App Store Connect。TestFlight 发给自己或其他测试员，不需要逐台登记 UDID。 |

Team 已经在 Xcode 的 Signing 里选好、并且本机钥匙串里有对应证书之后，才可以在 Mac 上导出 IPA：

```bash
flutter build ipa --export-method development
flutter build ipa --export-method ad-hoc
flutter build ipa --export-method app-store
```

这三条都依赖你自己的签名身份。仓库和 `scripts/ios_device.sh` 都不会填 Team ID，也不会在签不上名时把未签名产物说成可安装的设备 IPA。

`flutter build ios --release --no-codesign` 得到的是不能装到真机的 `.app`。

## 不使用苹果签名时

用 Safari 打开 [https://abaddon145.github.io/-/](https://abaddon145.github.io/-/)，点分享 → 添加到主屏幕。词库和学习进度保存在这个浏览器的本地数据库里，和原生安装互不相通。换设备时用应用内的文件备份。

## 辅助脚本

`scripts/ios_device.sh` 只在 macOS 上执行依赖安装和构建命令：

- `run [device-id]`：`flutter run`
- `config`：`flutter build ios --config-only`，然后用 Xcode 选 Team
- `ipa`：打印上面的 Archive / `export-method` 说明，不执行签名导出

在 Linux 上脚本会直接退出并指向本页。
