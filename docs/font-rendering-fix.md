# v0.7.1：韩文字形缺失修复

截图中的词为 `까딱하면`，其中缺失字是 `딱`（U+B531）。现有 JSON 词库的 UTF-8 字符正确，问题来自原先未指定随应用分发的韩文字体，Flutter Web 会依赖外部字体补字；网络或字体分片加载失败时可能显示缺字框。

## 修复

- 使用 `KoreanMemoSans` 应用字体，六套主题均应用到正文和标题，学习页及其他词条界面继承该字体。
- 字体包含全部 **11,172 个现代韩文预组音节**，不只包含内置词库已出现的字，因此新导入的正常现代韩文也能显示。另含原字体支持的 Jamo、GB2312 中文、当前词库和 UI 用字、常用拉丁及标点。未宣称覆盖 Unicode 的全部文字或表情。
- 字体 3,659,596 字节（约 3.5 MiB），随 PWA 资源和离线核心缓存分发，更新后无需再靠外部服务补齐韩文字形。
- 应用和缓存版本为 v0.7.1+12。无数据库、词条或学习状态变更，不重写用户原词。

## 字体来源与许可

原字体：Noto Sans CJK SC Regular 2.004，© 2014–2021 Adobe。来源项目 https://github.com/notofonts/noto-cjk ，采用版本 Sans2.004，对应 commit `523d033d6cb47f4a80c58a35753646f5c3608a78`，已查看该版本根目录 LICENSE。

输入为本环境 `fonts-noto-cjk` 包 `1:20240730+repack1-1` 的 `NotoSansCJK-Regular.ttc` 中 SC 字面；TTC SHA-256：`b76b0433203017ca80401b2ee0dd69350349871c4b19d504c34dbdd80541690a`。

对字形进行子集化，移除竖排和区域替代特性，保留横排韩文组合相关特性；字体家族改名 KoreanMemo Sans，保留原版权和许可证元信息。修改后资产 SHA-256：`6661071dad35facc809114b198e80eaf7b58289e385a30ad94d1484a6cb9b2a9`。

按 SIL OFL 1.1 分发，完整许可证和说明分别位于 `assets/fonts/OFL.txt`、`assets/fonts/NOTICE.txt`，均打包为应用资源。字体已生成并提交，运行、测试及部署不需要额外的 Python 或字体生成工具。

## 验证

- `flutter analyze --no-pub`：无问题。
- `flutter test --no-pub --reporter expanded`：103 项全部通过。
- `flutter build web --no-pub --release --base-href '/-/' --no-wasm-dry-run`：成功。
- 新增回归直接解析字体实际 cmap：覆盖全部现代韩文音节、`까딱하면` 和当前内置词库的中韩用字，并验证 Flutter 可加载资产及六套主题使用该字体。
- 浏览器验证使用隔离演示词库和手机尺寸，屏蔽外部字体服务；只检查显示和离线加载，不操作用户数据库，不请求 AI。
- 屏蔽外部字体后的在线显示和断网重开均通过，`까딱하면` 完整显示；本机字体缓存响应 200、大小 3,659,596 字节，页面错误为 0。

实际手机 Safari 的显示仍需用户更新后核对；浏览器模拟使用 Chromium 与 iPhone 尺寸/标识，不能称为 iPhone 真机测试。
