# 技术可行性与最小原型计划

审阅日期：2026-10-30。空目录起步；先做只读环境探针，再实现交互原型。没有已获批准的私有 API 路线。

## 结论

公开 API 足以构造受约束的最小实验，但目前证据不足以承诺完整满足目标交互。没有在审阅的公开文档/SDK 中找到专用 Dock 图标点击回调。这是检索结论，不是虚构一个不存在的事件接口。

| 问题 | 公开方案 | 限制 / 验证点 |
| --- | --- | --- |
| 用户点了哪个 Dock app | CGEvent 被动监听 down/up；AXUIElementCopyElementAtPosition 命中，要求所属进程为 com.apple.dock、subrole 为 kAXApplicationDockItemSubrole；以 kAXURLAttribute 对应唯一正在运行的 app bundle URL | 本机已授权并多次命中 TextEdit 等目标；公开常量不保证 Dock 各版本均返回这些属性 |
| 点击前前台 app / 活动窗口 | down 回调先保存 NSWorkspace.frontmostApplication，命中对应 Dock 图标后读取系统 AXFocusedApplication，返回 PID 时要求一致；系统级焦点缺失时须目标 app 的 AXFrontmost=true；读取 AXFocusedWindow 并验证所属 PID 后保存 | 不覆盖已知的焦点冲突，也不将读取异常当作缺失。回调并不是 OS 保证的“点击前原子快照”；应用/焦点可以并发变化 |
| 区分后台激活 / 前台再次点击 | 只允许 down 时命中目标已等于保存的前台 PID；up 再验证相同窗口/目标和状态，激活/Space 通知使候选失效 | 通知本身也异步；不能用激活后查询代替 down 快照；必须实测时序 |
| 最小化 | 普通窗口，AXModal=false、AXMinimized=false、按钮 enabled、AXMinimized 可写后 SetAttributeValue(true) | 依赖目标 app 的 AX 实现；只处理保存的一个窗口；不使用 hide/AppleScript |
| 是否需要拦截 | 首先用 listenOnly tap 原样放行，在 up 时发 AX 请求，约 250ms 后启动有限回读；0.1.2 将回读放在独立队列，仅对通信错误有限重试 | 若实际回读为 false 且无后续用户点击，仍暂停；重试只读、不重发最小化，不能靠任意延时宣称修复 Dock 竞争 |

## 路线比较与推荐

1. **推荐当前原型：被动 CGEvent + 公共 AX。** 不吞任何点击，失败保留原生输入。先观察，再受控启用最小化，用真实窗口检验 Dock 时序。没有通过前不继续包装成稳定成品。
2. NSEvent 全局监听 + AX：更高层，但 Apple 明确说明异步、只观察，点击前状态更难保证。适合诊断；不优先用于严格交互。
3. 公开的主动 CGEvent tap：可返回 nil 丢弃事件，但必须处理完整 down/up、长按、拖动、取消等生命周期。只吞 up 可能留下 Dock 按下状态；吞 down 后重放会改变原生时序和语义，影响拖拽。不能从“可拦截”推出“能完整满足全部要求”。仅作为被动方案失败后需要重新设计与实验的备选；本次未实现。
4. 用户主动快捷键/菜单最小化前台窗口：减少 Dock 时序依赖、公开 API 更直接，但不满足点击 Dock 的产品目标，不能冒充已完成。
5. Dock 注入、私有窗口/Space API、修改 Dock、关闭 SIP：本次未执行。此类路线会扩大兼容性、安全及分发风险；若未来考虑，必须先说明具体方案并等待用户决定。

## 权限、兼容性和分发

AXIsProcessTrusted / WithOptions 检查和由用户主动触发授权提示。辅助功能用于读取 Dock/窗口并控制最小化，是必需权限。CGRequestListenEventAccess 仅在 tap 无法建立时作为用户主动排障入口；不申请屏幕录制或 Apple Events 自动化权限。不需 root。

最低部署 macOS 13，主要由 SMAppService 登录项 API 决定。当前构建仅为本机 arm64，不是 universal；macOS 13–26 / Intel 均需另行构建及验证。避免使用 HID tap，采用用户 session 的 listenOnly tap。API 本身公开，不表示 Dock 辅助功能树稳定。

Apple 文档列出 assistive app 的 Accessibility 使用与 App Sandbox 不兼容，Mac App Store 要求沙盒。因此本方案以站外 Developer ID 签名、公证分发为目标，不承诺上架 Mac App Store。本机现已改用 Apple Development 签名以稳定开发授权身份，这不等于已签 Developer ID、已公证或通过 Gatekeeper 分发验证。

## 验证顺序 / 停止条件

1. 只读探针：前台 PID、AX 授权、tap 是否创建、Dock AX 属性是否能读。
2. 观察模式：验证 URL 命中和 down/up 前台判定。先记录前台/后台场景，不能执行窗口操作。
3. 实验模式：单一普通窗口最小化、保持状态、原生恢复，再多窗口。
4. 异常与边界：见 validation.md。出现后台首次点击被最小化、错误窗口、退出全屏、长按/拖动破坏或恢复竞争，即暂停该路线并保留证据。
5. 全部核心场景实测通过后才推进常驻启用、登录恢复策略和成品细化；当前仅附有必要操作菜单。

## Apple 官方资料

- [AXUIElementCopyElementAtPosition](https://developer.apple.com/documentation/applicationservices/1462077-axuielementcopyelementatposition)：全局左上角坐标的辅助功能命中测试。
- [NSWorkspace.frontmostApplication](https://developer.apple.com/documentation/appkit/nsworkspace/frontmostapplication)：前台应用；[NSRunningApplication](https://developer.apple.com/documentation/appkit/nsrunningapplication)：文档明确指出状态存在竞争、受主 run loop 更新影响。
- [AXUIElementIsAttributeSettable](https://developer.apple.com/documentation/applicationservices/1459972-axuielementisattributesettable) 与 [AXUIElementSetAttributeValue](https://developer.apple.com/documentation/applicationservices/1460434-axuielementsetattributevalue)：查询可写性并修改属性。
- [CGEvent.tapCreate](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)) 与 [CGEventTapCallBack](https://developer.apple.com/documentation/coregraphics/cgeventtapcallback)：区分 passive listener 和 active filter；被动返回值不影响输入流。
- [NSEvent.addGlobalMonitorForEvents](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:))：异步观察、不能修改或阻止原始事件。
- [AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions)、[AXUIElementSetMessagingTimeout](https://developer.apple.com/documentation/applicationservices/1459345-axuielementsetmessagingtimeout)、[CGPreflightListenEventAccess](https://developer.apple.com/documentation/coregraphics/cgpreflightlisteneventaccess())。
- [Protecting user data with App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)：沙盒限制和分发条件。
- [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice) 与 [register](https://developer.apple.com/documentation/servicemanagement/smappservice/register())：macOS 13+ 登录时启动，由用户批准。
- [AXUIElementCopyMultipleAttributeValues](https://developer.apple.com/documentation/applicationservices/1462051-axuielementcopymultipleattribute)：批量读取窗口资格属性，逐项处理 CFNull 和 AXValue AXError，减少跨进程消息。
- [kAXFrontmostAttribute](https://developer.apple.com/documentation/applicationservices/kaxfrontmostattribute) 表示该应用是否 active；[AXUIElementGetPid](https://developer.apple.com/documentation/applicationservices/1460337-axuielementgetpid) 可验证焦点窗口所属进程。0.1.5 用前者处理系统级 AX 焦点缺失，用后者避免操作其他进程窗口。
- [NSScreen.visibleFrame](https://developer.apple.com/documentation/appkit/nsscreen/visibleframe) 与 [frame](https://developer.apple.com/documentation/appkit/nsscreen/frame)：可用工作区与包含菜单栏/Dock 的完整屏幕不同；普通占满工作区不应仅因贴顶就判为全屏。

另核对本机 macOS 27 SDK 的 HIServices/Headers/AXAttributeConstants.h、AXRoleConstants.h 和 CoreGraphics/Headers/CGEvent.h、CGEventTypes.h：Dock subrole、URL、FocusedWindow、Modal、Minimized、MinimizeButton 均有公共常量；未找到通用 AXFullScreen 属性常量，所以未使用该字符串。
