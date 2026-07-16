# CC Switch Widgets

> 常驻 macOS 桌面与菜单栏的 AI 用量 / 花费监控组件。直接读取 [CC Switch](https://github.com/farion1231/cc-switch) 的数据，装上就能看——不用自己逐个配置 provider。

[CC Switch](https://github.com/farion1231/cc-switch) 是目前很火的 AI provider 管理工具，我本人也高度依赖使用它。本组件**不替代它管理 provider**，只是给 CC Switch 配了一个能随时瞄一眼用量和花费的桌面组件/菜单展示栏。

## 截图

<p align="center">
  <img src="assets/深色主题桌面组件.png" width="45%" alt="深色主题桌面组件" />
  <img src="assets/浅色主题桌面组件.png" width="45%" alt="浅色主题桌面组件" />
</p>
<p align="center">
  <img src="assets/app 界面.png" width="45%" alt="App 界面（用量分析 + 设置）" />
  <img src="assets/菜单栏浮窗.png" width="45%" alt="菜单栏浮窗" />
</p>

## 它解决什么

用 Claude Code / Codex / Gemini 写代码，烧了多少 token、花了多少钱，平时基本没数——想看还得一个个去翻设置、对账对到头秃。CC Switch Widgets 把每天的用量和花费算出来摆到桌面上，干活时余光扫一眼心里就有数。

## 特性

- **直接接 CC Switch**：读它的请求日志（**只读、不碰配置、不上传**），不用再每个 provider 自己配一遍监控。只要在 CC Switch 里能配余额查询的（含各种**中转站**），这边就能一起查到。
- **桌面组件 + 菜单栏**：macOS 上最适合「瞄一眼」的两种形态。
  - 桌面组件：今日总览、今日 vs 7 日均值、应用卡、Top 模型、模型排行、用量趋势、费用概览。
  - 菜单栏：常驻硬币图标，实时显示 token / 请求数 / 花费，点开 popover 看趋势明细。
- **用量 + 花费可视化**：当天 / 7 日 / 30 日趋势、模型排行、应用分项、费用（今日 / 昨日 / 本月）。
- **可定制**：深色 / 浅色 / 自定义主题色、涨跌色、刷新频率、图表区间。
- **开源可扩展**：框架搭得干净，想加 provider、改配色、加图表，fork 接着改就行（这组件本身就是 vibe coding 出来的 🤣）。

## 支持的 provider

当前接的是 **Claude Code、Codex、Gemini**（通过 CC Switch 的 provider 配置）。要支持别的工具，自己加即可。

## 工作原理

宿主 App 会以只读模式读取 CC Switch 的
`~/.cc-switch/cc-switch.db`，查询 `proxy_request_logs`，
不会修改 CC Switch 的数据库、配置或应用文件。

macOS Widget 扩展运行在独立沙盒中，不能可靠继承宿主 App
对该数据库目录的访问授权。因此数据流为：

1. 宿主 App 只读查询 CC Switch 数据库并聚合统计；
2. 将聚合后的结果保存到 App Group 的本地 JSON 快照；
3. 桌面组件、菜单栏界面从该快照读取并渲染。

不会向开发者服务器上传用量数据或账号数据。
如启用了余额查询，App 会按你的 CC Switch 配置，
直接请求对应 Provider 的官方/兼容额度接口；OAuth 凭据仅用于该请求，
不会发送给本项目的任何服务器。

## 安装

目前推荐从源码自行编译。仓库暂不提供 Developer ID 签名并经 Apple 公证的 DMG，
也不建议通过关闭 Gatekeeper 或清除 quarantine 属性来安装来源不明的构建产物。

### 准备环境

- macOS 14 或更高版本；
- Xcode 15 或更高版本，并在 `Xcode → Settings → Accounts` 登录 Apple ID；
- 可用于本机签名的 Apple Development 团队（个人免费团队也可以）；
- [xcodegen](https://github.com/yonaskolb/XcodeGen)：`brew install xcodegen`。

App、Widget Extension 与 App Group 必须由同一个开发团队签名。
由于仓库中的默认 Bundle ID 和 App Group 属于项目作者，其他开发者自行编译时需要换成自己的唯一标识；
否则 App 可能可以启动，但桌面组件无法读取共享快照，只会显示占位内容。

### 推荐：让 AI 编码助手协助编译

如果你不熟悉 Xcode 签名，可以克隆仓库后，让 Codex、Claude Code 等能操作本地项目的 AI 编码助手执行下面的任务：

```text
请帮我在本机编译并安装这个 macOS SwiftUI 项目。

要求：
1. 检查 Xcode、xcodegen 和 Apple Development 签名是否可用。
2. 使用我已经登录 Xcode 的 Apple 开发者团队。
3. 为宿主 App、Widget Extension 和 App Group 设置属于该团队的唯一标识。
4. 同步修改 project.yml、两个 entitlements 文件，以及 SharedConstants 中对应的标识，保证 App 与 Widget 使用同一个 App Group。
5. 运行测试，然后通过 script/build_and_run.sh 构建并安装到 ~/Applications。
6. 验证 App 和 Widget Extension 的签名、provisioning profile 与 App Group entitlement。
7. 不修改业务逻辑，不上传任何账号、OAuth 凭据或用量数据。
```

### 手动编译

1. 克隆仓库并安装 `xcodegen`。
2. 在 `project.yml` 中设置自己的 `DEVELOPMENT_TEAM`，并为 App 和 Widget 设置唯一的 `PRODUCT_BUNDLE_IDENTIFIER`。
3. 将 `Config/CCSwitchWidgetsApp.entitlements` 和 `Config/CCSwitchWidgetsWidget.entitlements` 中的 App Group 改为属于自己团队的唯一标识。
4. 同步修改 `Sources/CCSwitchCore/SharedUsageStore.swift` 中 `SharedConstants` 的 App、Widget 与 App Group 标识。
5. 构建并安装：

```bash
DEVELOPMENT_TEAM=你的TeamID bash script/build_and_run.sh
```

安装后启动 App，连接 CC Switch 数据目录；再在 macOS 桌面进入“编辑小组件”，搜索“CC Switch”添加组件。

## 使用

打开 App 后可设置：

- 连接 CC Switch 数据目录（默认 `~/.cc-switch`）。
- 主题色 / 涨跌色 / 刷新频率 / 图表区间。
- 立即刷新。

桌面组件在「编辑组件」里选择类型、大小、范围；点击桌面组件可通过 `ccswitchwidgets://chart` 打开 App 的交互式图表。

## 限制

- **需要 macOS 14 及以上**（14 / 15 / 26 都可以；依赖 WidgetKit / Swift Charts），暂无 Windows / Linux 版。
- 需要先安装并配置好 [CC Switch](https://github.com/farion1231/cc-switch)。
- 用量 / 花费依赖 CC Switch 记录的请求日志；未经过 CC Switch 的请求不计入。

## 开发

技术栈：Swift 6 · SwiftUI · WidgetKit · AppIntents · Swift Charts · SQLite3。

```bash
swift test                       # 跑核心逻辑测试
bash script/build_and_run.sh     # 构建并安装到 ~/Applications
```

欢迎 PR：加 provider 支持、新组件类型、配色、图表……
