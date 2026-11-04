# MiniToggle 1.0

Swift / AppKit 菜单栏工具，用公开的 Quartz 鼠标事件监听和 Accessibility API，为前台应用 Dock 图标添加再次点击最小化。默认暂停，菜单栏一个开关启用或暂停；不跨重启自动启用。已知部分应用/快速操作仍可能无法最小化并触发保护暂停，详见验证记录。

## 安装

从 [GitHub Release](https://github.com/Royce-80457/MiniToggle/releases/tag/v1.0) 下载 `MiniToggle-1.0-universal.dmg`，打开后将 MiniToggle 拖入 Applications。退出旧实例，再从“应用程序”启动，打开设置授予辅助功能权限，最后打开菜单“启用”开关。

本次安装包使用 Apple Development 开发签名，尚无 Developer ID 分发签名及 Apple 公证，Gatekeeper 可能阻止启动。仅信任来源时按 [Apple 官方说明](https://support.apple.com/102445)在隐私与安全性中手动允许；不要关闭系统安全机制。也可自行从源码构建。详见 [安装说明](docs/INSTALL.zh-CN.md)。

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

`build.sh` 使用标准工程的 Release 配置构建并导出 app，`test.sh` 使用同一工程执行 Debug XCTest。脚本导出 app 前请退出正在使用的旧实例。图标为一枚向下箭头与 Dock 形长条圆角矩形：应用图标固定采用 A 版实心长条和蓝色圆角底；菜单栏启用时实心，未启用、手动暂停或异常停止时空心，支持系统深浅色模板。自身默认不显示 Dock 图标。

图标资源位于 `Resources/Assets.xcassets/AppIcon.appiconset`，菜单栏与应用图标共用 `IconArtwork.swift` 的矢量路径。修改后可在项目根目录运行 `swiftc Sources/MiniToggle/IconArtwork.swift scripts/render-icons.swift -o build/render-icons`，再执行 `./build/render-icons`，重新生成全部 macOS 图标尺寸。

脚本优先使用显式 `SIGNING_IDENTITY`；未指定时，自动使用本机唯一可用的 Apple Development 证书，没有唯一匹配时退回 ad-hoc 并打印警告。ad-hoc 重编译可能使 TCC 授权失效，不能稳定保留跨版本授权。开发阶段应一直使用同一签名证书、bundle ID 和 app 路径，重编译前退出旧进程；不要同时运行多份。正式分发应使用 Developer ID 签名和公证，但脚本本身不提交公证。

若系统设置显示已开启而 app 显示未授权，先退出 MiniToggle，在辅助功能列表选中旧 MiniToggle 按 `−` 移除，再用 `+` 添加当前的 `build/MiniToggle.app` 并开启，重新启动。只关开旧记录可能无法替换过期的签名身份。更换签名证书（包括从 ad-hoc 切到 Apple Development）后也需重新授权一次；无需修改整个系统的 TCC 数据库。

## 权限和第一次测试

1. 启动 app，打开菜单 → 设置 → 通用，在“辅助功能”区域选择“申请权限…”或“打开系统设置…”。
2. 在系统设置 → 隐私与安全性 → 辅助功能（系统版本可能使用不同名称）中开启 MiniToggle；必要时用 `+` 添加 `build/MiniToggle.app`。用途：识别 Dock 图标、读取活动窗口、设置其最小化状态。
3. 在设置窗口确认辅助功能“已授权”，回到菜单打开“启用”滑动开关。此开关同时开启监听和实验性最小化，无需第二个开关；授权本身不会自动开启增强。
4. 启动 TextEdit 后若出现文件选择界面，先点“新建文稿”，进入可输入文字、带黄色最小化按钮的文稿编辑窗口。把文稿窗口缩小并放在屏幕中间，点击文稿使其成为前台，再短按其 Dock 图标，确认仅活动窗口最小化；再次点击应由系统恢复。
5. 换另一应用为前台，再点击 TextEdit 图标。应只激活 TextEdit，诊断可能出现 `pass background-click`；不应有此点击的最小化请求。
6. 关闭菜单中的滑动开关会停止增强；关闭设置窗口不会退出工具。设置窗口“排除应用”页用“＋”选择不兼容应用，选中行后用“−”移除排除项。
7. 如果菜单显示失败/暂停，停止测试并复制日志。不要反复重试来掩盖错误。

只在鼠标 tap 创建失败且系统要求时使用设置窗口“通用”页的“申请输入监控…”。原型实测：监听预检为 false 时，被动鼠标 tap 仍能创建，因此不以此预检强制阻止运行，也不在启动时申请输入监控。无需屏幕录制、自动化 Apple Events、管理员、网络权限。设置深链接只是便利入口，失效时请手动导航系统设置。

## 操作和隐私

0.1.12 起，菜单仅保留状态、合并的启用/暂停、设置入口、复制日志和退出；清空日志放在设置窗口的通用页。原生设置窗口分为“通用、排除应用”：通用页集中提供运行状态、登录启动、权限及清空日志。排除页只列出已排除的应用，以图标、名称、类型展示，支持“＋”选择多个 app 和“−”移除选中的多行；移除排除项不会删除应用文件。列表按 bundle ID 保存，保留未运行或无法定位的旧项，应用启动/退出或窗口重新获得焦点时刷新。登录项使用 SMAppService，实际审批状态以系统设置为准；登录后仍默认暂停。

无网络代码、无遥测、无第三方 SDK。诊断仅保留本次进程最近 200 条在内存中，含单调时钟、PID、判断结果、错误码、窗口资格属性和窗口/显示器可用区域的坐标尺寸，不记录窗口标题、文本或按键内容。只有点击“复制”才写入剪贴板；退出清除内存记录。排除的应用 ID 存在本机 UserDefaults。辅助功能读取过程中会用到 app URL，但不写入诊断。

另有显式的只读诊断参数 `--audit-windows`：查询已运行的 Safari、ChatGPT、QQ 和 TextEdit 最多三个窗口的公开 AX 资格属性并打印到标准输出，不激活应用、不改变窗口、不读标题/内容。可通过 LaunchServices 运行以使用 app 自身授权身份（`--stdout` 的文件是显式导出的诊断）：

```sh
open -n -g -W --stdout "$PWD/build/window-audit.txt" --stderr "$PWD/build/window-audit-errors.txt" build/MiniToggle.app --args --audit-windows
```

## 有意保守的行为和限制

- 仅在按下时命中前台 app 图标并保存活动普通窗口、抬起后仍可确认同一图标/应用/窗口时尝试操作。后台点击、未运行 app、窗口缩略图、文件夹和废纸篓原样放行。
- 所有原始事件始终放行，不注入、不吞事件、不修改 Dock。0.1.8 已实际出现请求成功、窗口仍显示且 AXMinimized=false，快速模式尚未达到可靠性目标。用户选择继续公开 API 实验。0.1.9 曾在抬起回调后等待 50ms，实测快速点击仍不跟手；0.1.10 改为当前回调返回后下一轮主队列执行，不设固定等待，再验证同一图标/前台/窗口和资格。有新输入、状态变化或调度超过 200ms 即取消，写入前再次检查。此调度不保证 Dock 已完成处理，仍须实际验证。约 250ms 后在独立队列回读，单次超时 100ms；对 false 或 cannotComplete 在同一三次总预算内额外确认，间隔 250ms，从不重发最小化。预算耗尽仍未确认 true、未知属性或对象失效会暂停。后续输入会取消旧回读，以免将用户主动恢复误判为竞争；取消意味着该次最终状态未知。回读只是该时刻的证据，不能证明之后永远不恢复。
- 短按上限 250ms、位移上限 4 点；任何拖动事件、右键、其他按钮、修饰键变化均取消。0.1.7 起每次短按独立判断，接受系统标记的二次及以上点击，取消最小化后的 500ms 固定冷却。每次仍要求可靠的前台/窗口状态；动画期间属性不可读或没有焦点窗口时保留原生行为。新输入取消尚未执行的旧操作，不为失败的点击重发最小化。因此不能保证快于系统窗口动画的每次点击都完成一次切换。
- app 激活会取消正在进行的候选，但不再额外等待 400ms；后台首次点击仍由 down 时前台 PID 检查放行。Space 切换、显示器变更、睡眠唤醒后仍取消候选并等待 400ms；激活通知不会缩短已有的过渡等待。没有使用私有 Space API，不尝试切换或枚举全部桌面。跨桌面、多屏、Stage Manager、Dock 自动隐藏/放大均未完成实测。
- 只使用 `AXFocusedWindow`，不回退到窗口列表第一个，不激活 app，不批量最小化。窗口没有焦点、已最小化、模态/Sheet、按钮不可用、属性缺失/不支持均跳过。
- down 时保存的 NSWorkspace 前台 PID 必须与 Dock 目标一致，抬起后的执行阶段再确认。0.1.10 在两个阶段都批量读取目标 app 的 AXFrontmost 和 AXFocusedWindow，必须前台 PID 一致且 AXFrontmost=true；false、缺失或查询错误不作为可操作证据。窗口须通过 AXUIElementGetPid 验证所属 PID，且始终为 down 保存的同一窗口。不再在交互路径查询系统级 AXFocusedApplication，以减少部分应用中该属性缺失/超时的额外开销；只读 audit 仍保留旧查询用于对照。批量读取不是原子事务，不使用旧窗口缓存跳过实时焦点检查。
- 没有使用未在公共 SDK 定义的 `AXFullScreen` 字符串。检查最小化按钮启用状态，且要求窗口完整位于单一显示器的可用区域内，并拒绝覆盖整块显示器（含菜单栏/Dock 区域、边界误差 2 点）的窗口。0.1.4 允许普通贴顶和占满工作区的最大化窗口；超出工作区、跨屏窗口仍保守跳过。此几何检查不能声称覆盖第三方所有非标准全屏实现。
- Dock 的辅助功能 subrole 和 URL 有公开常量，但 **Dock 是否始终提供这些数据，以及其与输入事件的时序，没有兼容性承诺**。缺失或歧义均不操作。应用未正确暴露窗口属性时需要排除该应用。
- 全局命中测试会接触普通应用界面。若该界面返回 AX notImplemented（不支持命中测试）或 noValue，按未确认 Dock 图标跳过当前点击，不全局暂停；其他错误仍按相应策略处理。
- 点击判断的 AX 单次消息超时 50ms，窗口的八项属性采用一次批量查询（不支持批量的 app 回退逐项查询），每阶段写入前检查累计耗时 120ms；回读单独使用 100ms 超时。这些是尽力限制，不是硬实时保证，耗时超预算会写入诊断。先保存 down 时前台 PID，命中该 app 的 Dock 图标后才读取其焦点窗口，避免查询普通点击涉及的其他窗口。点击判断遇到已失效的 AX 元素或偶发 cannotComplete 时取消本次操作，不重试该点击或改操作其他窗口；0.1.8 起，连续通信失败须累计至少三次、首末跨度至少两秒且相邻间隔不超过五秒才暂停，避免连点在一个动画周期内误触发；两秒不是点击冷却或重试等待。成功完成 down 窗口检查（包括无焦点窗口等正常跳过）或完整 up 检查会清零。down 时先检查目标焦点窗口，无窗口就直接保留原生恢复，不再为此查询全局 AX 焦点。权限失效、tap 被禁用、其他异常或最小化写入失败立即暂停，不自动恢复。回读错误仍按上述有限重试策略处理。每次鼠标处理/实际写入前检查辅助功能权限；运行时另有每三秒一次的权限/tap 健康检查，没有窗口高频轮询。诊断包含应用 bundle ID、点击计数、手势/冷却/激活等待的取消原因、AX 错误名/数值/属性和处理阶段；每次暂停的原因也会写入诊断。
- 延后操作和回读还使用 CGEventSource 的公开事件计数检测尚未送达 tap 的新输入；仅比较计数，不读取键码/文本、不申请额外权限，不高频轮询。计数读取也不是跨进程原子事务。
- 公共 API 并不提供跨进程原子化的“读取点击前状态 + 阻止 Dock + 最小化”事务。尤其第一次激活和快速交互不能只依靠事后 frontmost 判断。0.1.10 在 down 时保存 NSWorkspace 与目标 app 前台/窗口证据，up 回调后下一轮主队列再验证；这降低风险，无法证明绝无时序竞争。若目标 app 在动画期间不响应 AX，无法通过减少本工具的等待来保证每次快速点击都有效。

技术论证、路线对比与 Apple 来源：[docs/feasibility.md](docs/feasibility.md)。实际证据和待测场景：[docs/validation-summary.md](docs/validation-summary.md)。

## GitHub 与持续集成

仓库包含源码、标准 Xcode 工程、共享 Scheme、构建/测试脚本及 GitHub Actions 工作流。每次 push / PR 会在 macOS runner 上执行不签名构建和核心规则测试；CI 不会执行全局 Dock 交互或申请辅助功能权限。

`build/`、DerivedData、Xcode 个人状态、本地签名配置和完整本机排障日志已忽略。证书与私钥由开发者自己的钥匙串管理，仓库不包含它们。完整本机验证历史保留在开发目录；上传版本使用不含本地进程记录的验证摘要。

设置说明集中在每项旁的圆形问号中，悬停立即显示浮层、移开关闭，也可点击查看；窗口按内容与列表行数自适应高度。菜单开关开启时使用固定蓝色轨道、白色圆钮，关闭时为灰色；颜色不修改系统强调色，键盘及辅助功能继续由原生按钮处理。

0.1.18 菜单收窄为约 140pt 的内容宽度，采用统一菜单字号与紧凑行距；“设置”不带省略号，与“复制日志”之间没有分割线。界面状态仅显示“运行中”或“已暂停”，异常细节仍完整记录在日志中。

## 制作安装镜像

Release 构建后执行 `./scripts/package.sh`，输出 DMG 和 `SHA256SUMS.txt` 到 `build/release/`。镜像包含签名 app、Applications 快捷入口及安装说明；脚本不会替你生成 Developer ID 证书、公证或上传。已有同名产物时停止，避免覆盖发布文件。
