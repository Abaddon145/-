# 在 Windows 上把韩语记忆装到 iPhone

这份安装包给没有 Mac、也没有付费 Apple Developer 账号的人用。GitHub Actions 在 macOS 上打一个**未签名**的正式包，你在自己的 Windows 电脑上用 [Sideloadly](https://sideloadly.io) 和**免费 Apple ID** 重新签名，再装到 iPhone。

仓库是公开的。Apple ID、密码、验证码和 DeepSeek 密钥都只留在你自己的电脑和手机上，不要写进仓库、Issue、讨论或工作流日志。这个工作流不读取密钥，也不使用任何证书。

## Bundle ID 不能改

安装包的 Bundle ID 固定为：

`com.abaddon145.koreanMemo`

它和现有 iOS 构建用的组织名 `com.abaddon145` 一致。Sideloadly 重新签名时不要改这个 ID，也不要勾选会更换 App ID 的选项。

换一个 Bundle ID，手机会把它当成另一个新 App。原来的词库、学习记录和钥匙串里的密钥都留在旧 App 里，新 App 是空的。以后每次重新签名也必须继续用这个 ID。

主屏幕名称是「韩语记忆」。

## 先备份

网页版和这个 App 的数据**不互通**。装之前，先把现在要用的进度存成 JSON。

1. 打开正在用的网页版或已经装好的 App。
2. 进入「设置 → 文件备份与迁移」。
3. 点「备份学习进度」。网页版会下载 JSON，请确认文件已经落在电脑或「文件」里；iPhone 上会弹出系统保存面板，存到「文件」或 iCloud Drive。
4. 看到「备份文件已导出」再继续。文件上限 50 MB。开关「文件备份包含 AI 数据」只影响建议和任务，**不包含** API Key。

装好之后，在 App 里点「恢复学习进度」，选这个 JSON。恢复会替换这台手机上该 App 里的词库和学习进度。

## 打安装包

1. 打开 [构建 iOS 安装包](https://github.com/Abaddon145/-/actions/workflows/ios-build.yml)。
2. 点 **Run workflow**。工作流只在手动运行时执行。合并到 `main` 之后选 `main`；还在分支上验证时选含有该工作流的分支。
3. 等名为 iOS IPA 的运行结束，并且是绿色。
4. 打开该次运行页面，在 Artifacts 里下载 `KoreanMemo-` 加上 `pubspec.yaml` 里的版本号。当前版本是 `KoreanMemo-0.10.0+16`。
5. 解压下载到的压缩包，得到 `KoreanMemo-<版本>.ipa`。这个文件才是要拖进 Sideloadly 的安装包。不要把 ipa 提交回仓库。

安装包是真机 Release（arm64），不是模拟器包。里面没有描述文件，也没有推送、App Groups、iCloud、Associated Domains 或钥匙串共享这些免费账号签不了的授权。

## 在 Windows 上安装 Sideloadly

1. 从 https://sideloadly.io 下载 Windows 版并安装。
2. 按 Sideloadly 官网的 Windows 说明，从 Apple 网站安装 **iTunes（64 位）** 和 **iCloud**。不要用 Microsoft Store 里的 iTunes 或 iCloud，那两个版本不带 Sideloadly 需要的设备驱动。iTunes 可从 https://www.apple.com/itunes/download/win64 下载。装完后重启电脑。
3. 用数据线把 iPhone 接到电脑。手机上点「信任」。
4. 打开 Sideloadly，用你的免费 Apple ID 登录。双重认证的验证码只在 Sideloadly 的窗口里输入。

## 装到 iPhone

1. 把解压出来的 `.ipa` 拖进 Sideloadly。
2. 确认它显示的 Bundle ID 是 `com.abaddon145.koreanMemo`。不要改。
3. 点 Start，等它签名并安装。
4. 若手机还没有开发者模式：打开「设置 → 隐私与安全性 → 开发者模式」，按提示打开并重启。这个开关有时要等第一次安装尝试之后才会出现。重启后再在 Sideloadly 里装一次。
5. 打开「设置 → 通用 → VPN 与设备管理」（有的系统显示「描述文件与设备管理」），点你的 Apple ID，再点信任。
6. 回到主屏幕，打开「韩语记忆」。

## 每 7 天重新签名

免费 Apple ID 的描述文件大约 **7 天**后失效，App 会打不开。到期前用**同一台电脑、同一个 Apple ID、同一个 Bundle ID** 再装一次这份 ipa（或以后新建的、Bundle ID 仍是 `com.abaddon145.koreanMemo` 的包）。

直接覆盖安装，**不要先删掉手机上的 App**。Bundle ID 不变时，本机词库和学习记录会保留。先删除再安装，或中途改了 Bundle ID，数据就没了。重新签名前仍建议先导出一份备份。尽量一直用同一个 Apple ID；如果系统要求先删除才能换账号，先备份。

免费账号大致还有两个上限：一台设备上同时大约 **3 个**用免费证书签名的 App，同一个 Apple ID 每 7 天大约 **10 个** App ID。重复安装这一个 Bundle ID 一般不会再占一个新的 App ID。Sideloadly 如果提示 App ID 已满，等这一周的额度恢复，或删掉不再使用的描述文件。

## 离线时能用什么

普通背词不需要网络。

- 词库、FSRS、统计、收藏和设置写在本机 SQLite 文件里（Drift，文件在 App 自己的文档目录，名字是 `korean_memo.sqlite`）。iOS 构建使用 sqlite3 的本机库，打开应用时不会去下载数据库。
- 这个安装包带的是仓库里的 OpenType 字体 `KoreanMemoSans-Regular.otf`，iOS 能直接解析。网页版仍使用较小的 WOFF2，两边互不影响。
- 朗读使用 iPhone 自带的系统语音（韩语 `ko-KR`，没有韩文时用英语），不经过网络服务器。如果没有声音，到「设置 → 辅助功能 → 朗读内容 → 语音」里下载韩语语音；下好之后可以离线朗读。
- 没有配置 AI 时，学习、导入和备份都可用。AI 补全需要网络，以及你自己的 DeepSeek 密钥。

DeepSeek 密钥不会写进安装包，也不会写进上面的 JSON 备份。iPhone 版在你于 App 内保存后，用系统钥匙串存放（`flutter_secure_storage`，仅本机、不同步 iCloud、不和别的 App 共享）。请在「设置 → AI 学习助手设置」里自己粘贴。清除密钥只影响这台手机。
