# MiniToggle（交互验证原型）

Swift / AppKit 菜单栏工具，用公开的 Quartz 鼠标事件监听和 Accessibility API，实验性地为前台应用 Dock 图标添加再次点击最小化。**目前不是通过交互验收的成品。默认暂停，启用后默认只观察；实验开关不跨重启保存。**

## 构建与运行

需要 macOS 13+ 和完整 Xcode（命令行构建也使用 xcodebuild）。当前验证环境为 macOS 27.0.1 / Xcode 27.1 / Swift 6.4。无第三方依赖。工程支持 arm64 和 x86_64 构建；Intel 的真实交互尚未测试。

### 在 Xcode 中打开

1. 双击 `MiniToggle.xcodeproj`，选择 **MiniToggle** Scheme 和 **My Mac**。
2. 本机调试可直接按 `⌘R`；按 `⌘U` 运行核心规则测试；归档使用 **Product → Archive**。
3. 为避免每次重新构建丢失辅助功能授权，复制 `Configs/Signing.example.xcconfig` 为 `Configs/Signing.local.xcconfig`，填入自己的 Team ID，使用稳定的 Apple Development 证书。本地签名文件不会提交 Git；没有本地配置时工程使用 ad-hoc 签名。
4. Xcode Run 产物位于 DerivedData，命令行脚本导出位于 `build/MiniToggle.app`。测试时固定使用一处 app，关闭旧实例，再为实际运行的 app 授权。已在试用的旧 app 不会因仅打开或构建工程被自动替换。

工程包括三个 target：`MiniToggle` 原生 macOS 菜单栏 App、`ToggleCore` 静态 Swift 模块、`ToggleCoreTests` 无宿主单元测试。App 最低 macOS 13；测试 target 为 macOS 14+，适配当前 Xcode 的 XCTest 框架。共享 Scheme 随仓库提交。`Package.swift` 仍可用于单独的 SwiftPM 编译/测试，但原生 app 打包以 `.xcodeproj` 为准。新增或删除 Swift 文件时，在 Xcode 中保持相应 target membership 与 Package 源码目录一致。

### 命令行构建

```sh
cd MiniToggle
./scripts/build.sh
./scripts/test.sh
open build/MiniToggle.app
```

`build.sh` 使用标准工程的 Release 配置构建并导出 app，`test.sh` 使用同一工程执行 Debug XCTest。脚本导出 app 前请退出正在使用的旧实例。菜单栏图标为两个矩形压缩符号；自身不显示 Dock 图标。

脚本优先使用显式 `SIGNING_IDENTITY`；未指定时，自动使用本机唯一可用的 Apple Development 证书，没有唯一匹配时退回 ad-hoc 并打印警告。ad-hoc 重编译可能使 TCC 授权失效，不能稳定保留跨版本授权。开发阶段应一直使用同一签名证书、bundle ID 和 app 路径，重编译前退出旧进程；不要同时运行多份。正式分发应使用 Developer ID 签名和公证，但脚本本身不提交公证。

若系统设置显示已开启而 app 显示未授权，先退出 MiniToggle，在辅助功能列表选中旧 MiniToggle 按 `−` 移除，再用 `+` 添加当前的 `build/MiniToggle.app` 并开启，重新启动。只关开旧记录可能无法替换过期的签名身份。更换签名证书（包括从 ad-hoc 切到 Apple Development）后也需重新授权一次；无需修改整个系统的 TCC 数据库。

## 权限和第一次测试

1. 启动 app，打开菜单，选择“申请辅助功能权限…”，再打开“辅助功能设置…”。
2. 在系统设置 → 隐私与安全性 → 辅助功能（系统版本可能使用不同名称）中开启 MiniToggle；必要时用 `+` 添加 `build/MiniToggle.app`。用途：识别 Dock 图标、读取活动窗口、设置其最小化状态。
3. 回到菜单，确认“辅助功能：已授权”，点击“启用观察 / 重试”。授权本身不会自动开启增强。
4. 启动 TextEdit 后若出现文件选择界面，先点“新建文稿”，进入可输入文字、带黄色最小化按钮的文稿编辑窗口。启动时的文件选择界面不作为最小化测试对象。把文稿窗口缩小并放在屏幕中间。点击文稿使其成为前台，等待一秒，短按它的 Dock 应用图标。复制诊断应有 `candidate` 和 `would-minimize`，窗口应不变。
5. 换另一应用为前台，再点击 TextEdit 图标。应只激活 TextEdit，诊断可能出现 `pass background-click`；不应出现此点击的 `would-minimize`。
6. 上两步确认后，在菜单开启“实验：再次点击最小化”，保持观察已启用。重复前台短按，观察窗口是否最小化并保持；再次点击应由系统恢复。复制本次诊断回报。
7. 如果菜单显示失败/暂停，停止测试并复制诊断。不要反复重试来掩盖错误。

只在鼠标 tap 创建失败且系统要求时使用菜单“申请输入监控…”。原型实测：监听预检为 false 时，被动鼠标 tap 仍能创建，因此不以此预检强制阻止运行，也不在启动时申请输入监控。无需屏幕录制、自动化 Apple Events、管理员、网络权限。设置深链接只是便利入口，失效时请手动导航系统设置。

## 操作和隐私

菜单提供启用/暂停、实验开关、权限状态/入口、登录时启动、按应用排除、复制/清空诊断、退出。排除列表列出正在运行的普通应用，并保留已选的未运行应用；按 bundle ID 保存。登录项使用 SMAppService，实际审批状态以系统设置为准；本阶段登录后仍默认暂停，待原型验收后再确定自动启用策略。

无网络代码、无遥测、无第三方 SDK。诊断仅保留本次进程最近 200 条在内存中，含单调时钟、PID、判断结果、错误码、窗口资格属性和窗口/显示器可用区域的坐标尺寸，不记录窗口标题、文本或按键内容。只有点击“复制”才写入剪贴板；退出清除内存记录。排除的应用 ID 存在本机 UserDefaults。辅助功能读取过程中会用到 app URL，但不写入诊断。

另有显式的只读诊断参数 `--audit-windows`：查询已运行的 Safari、ChatGPT、QQ 和 TextEdit 最多三个窗口的公开 AX 资格属性并打印到标准输出，不激活应用、不改变窗口、不读标题/内容。可通过 LaunchServices 运行以使用 app 自身授权身份（`--stdout` 的文件是显式导出的诊断）：

```sh
open -n -g -W --stdout "$PWD/build/window-audit.txt" --stderr "$PWD/build/window-audit-errors.txt" build/MiniToggle.app --args --audit-windows
```

## 有意保守的行为和限制

- 仅在按下和抬起都命中同一个已运行的前台 app 图标、同一活动普通窗口时尝试操作。后台点击、未运行 app、窗口缩略图、文件夹和废纸篓原样放行。
- 所有原始事件始终放行，不注入、不吞事件、不修改 Dock。无法保证 Dock 不会在稍后恢复刚最小化的窗口。约 250ms 后在独立串行队列回读，单次超时 100ms；只对 AX cannotComplete 通信错误额外重试最多两次，间隔 250ms，从不重发最小化。回读非 true、对象失效或重试耗尽会暂停，并记录具体错误。后续点击会取消旧回读，以免将用户主动恢复误判为竞争。回读只是该时刻的证据，不能证明之后永远不恢复。
- 短按上限 250ms、位移上限 4 点；任何拖动事件、右键、其他按钮、修饰键变化均取消。二次及以上 clickCount 跳过；最小化后 500ms 内跳过。快速连续点击的增强会故意退化为原生行为，仍须实测是否发生窗口闪动。
- app 激活、Space 切换、显示器变更、睡眠唤醒后取消候选，并等待 400ms。没有使用私有 Space API，不尝试切换或枚举全部桌面。跨桌面、多屏、Stage Manager、Dock 自动隐藏/放大均未完成实测。
- 只使用 `AXFocusedWindow`，不回退到窗口列表第一个，不激活 app，不批量最小化。窗口没有焦点、已最小化、模态/Sheet、按钮不可用、属性缺失/不支持均跳过。
- down 时保存的 NSWorkspace 前台 PID 必须与 Dock 目标一致，up 再确认；系统级 AXFocusedApplication 返回 PID 时必须一致，若缺失，改用目标 app 公开的 AXFrontmost=true 确认，false/缺失仍跳过。读取出错不伪装成缺失，仍按错误策略处理。焦点窗口还必须通过 AXUIElementGetPid 验证所属进程。系统级焦点缺失在部分应用点击 Dock 时会发生，不能直接当作前台 PID 冲突。
- 没有使用未在公共 SDK 定义的 `AXFullScreen` 字符串。检查最小化按钮启用状态，且要求窗口完整位于单一显示器的可用区域内，并拒绝覆盖整块显示器（含菜单栏/Dock 区域、边界误差 2 点）的窗口。0.1.4 允许普通贴顶和占满工作区的最大化窗口；超出工作区、跨屏窗口仍保守跳过。此几何检查不能声称覆盖第三方所有非标准全屏实现。
- Dock 的辅助功能 subrole 和 URL 有公开常量，但 **Dock 是否始终提供这些数据，以及其与输入事件的时序，没有兼容性承诺**。缺失或歧义均不操作。应用未正确暴露窗口属性时需要排除该应用。
- 全局命中测试会接触普通应用界面。若该界面返回 AX notImplemented（不支持命中测试）或 noValue，按未确认 Dock 图标跳过当前点击，不全局暂停；其他错误仍按相应策略处理。
- 点击判断的 AX 单次消息超时 50ms，窗口的八项属性采用一次批量查询（不支持批量的 app 回退逐项查询），每阶段写入前检查累计耗时 120ms；回读单独使用 100ms 超时。这些是尽力限制，不是硬实时保证，耗时超预算会写入诊断。先保存 down 时前台 PID，命中该 app 的 Dock 图标后才读取其焦点窗口，避免查询普通点击涉及的其他窗口。点击判断遇到已失效的 AX 元素或偶发 cannotComplete 时取消本次操作，不重试该点击或改操作其他窗口；连续通信失败累计三次且相邻间隔不超过五秒时暂停，完整点击检查成功会清零。权限失效、tap 被禁用、其他异常或最小化写入失败立即暂停，不自动恢复。回读错误仍按上述有限重试策略处理。每次鼠标处理/实际写入前检查辅助功能权限；运行时另有每三秒一次的权限/tap 健康检查，没有窗口高频轮询。诊断包含应用 bundle ID、点击计数、手势/冷却/激活等待的取消原因、AX 错误名/数值/属性和处理阶段；每次暂停的原因也会写入诊断。
- 公共 API 并不提供跨进程原子化的“读取点击前状态 + 阻止 Dock + 最小化”事务。尤其第一次激活和快速交互不能只依靠事后 frontmost 判断。本原型读取 down 时 NSWorkspace 与系统 AX 焦点、保存窗口，到 up 再验证；这降低风险，无法证明绝无时序竞争。

技术论证、路线对比与 Apple 来源：[docs/feasibility.md](docs/feasibility.md)。实际证据和待测场景：[docs/validation-summary.md](docs/validation-summary.md)。

## GitHub 与持续集成

仓库包含源码、标准 Xcode 工程、共享 Scheme、构建/测试脚本及 GitHub Actions 工作流。每次 push / PR 会在 macOS runner 上执行不签名构建和核心规则测试；CI 不会执行全局 Dock 交互或申请辅助功能权限。

`build/`、DerivedData、Xcode 个人状态、本地签名配置和完整本机排障日志已忽略。证书与私钥由开发者自己的钥匙串管理，仓库不包含它们。完整本机验证历史保留在开发目录；上传版本使用不含本地进程记录的验证摘要。
