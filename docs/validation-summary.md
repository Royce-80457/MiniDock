# 验证状态

当前功能版本：0.1.6。验证环境：Apple silicon、macOS 27.0.1、Xcode 27.1。

## 已有实际证据

- 用户实际使用并确认 Safari、TextEdit、系统设置、iPhone 镜像的前台重复点击最小化行为。
- QQ、WeChat、用户测试的 ChatGPT 路径进程（bundle ID 为 com.openai.codex）、DeepSeek 有多次最小化请求成功及后续 AXMinimized=true 回读；用户反馈功能测试成功。
- 后台首次点击有放行日志，部分应用最小化后没有焦点窗口时也按原生路径放行；完整的多窗口/Space 切换体验尚未全部验收。
- TextEdit 启动文件选择界面缺少可用的最小化能力，实际被跳过；普通文稿窗口可进入增强路径。
- 辅助功能身份已由临时签名改为稳定的本机开发证书；用户重新授权后恢复。

## 修订与边界

- 窗口动画期间可能出现 AX 通信失败；回读只做最多三次读取，从不重发最小化。
- 不将系统级 AX 焦点缺失直接当作不同前台应用，须由目标 app 的 AXFrontmost=true 进一步确认；真实 PID 冲突仍拒绝。
- 偶发窗口失效/通信失败取消当前点击；持续故障、权限撤销、写入失败仍暂停。
- 0.1.6 修正全局命中测试返回 notImplemented 时错误暂停整个工具的问题；后续长期运行仍在验证。
- Xcode/单元测试通过只证明工程和规则检查可运行，不能证明所有系统交互已通过。

## 尚未完整实际验证

多窗口、全屏与动画过渡、模态/Sheet、长按菜单及拖放、跨 Space、多显示器与负坐标、Dock 各方向/自动隐藏、快速连击、Stage Manager、运行中撤权、登录启动及审批、Intel、macOS 13–26。

完整的本机排障历史保留在开发目录中，不随 GitHub 仓库上传。

## 标准 Xcode 工程验证

- 原生 App、静态核心模块、无宿主 XCTest 三个 target；MiniToggle 共享 Scheme 支持 Run / Test / Archive。
- Xcode 工程 Debug 构建及使用本机开发证书的 Release 构建成功，Release 签名验证通过；arm64 + x86_64 通用二进制生成成功。Intel 真机运行仍未验证。
- 通过 xcodebuild test 实际运行 12 项核心规则测试，全部通过。App 部署目标仍为 macOS 13，测试 target 单独使用 macOS 14+ 以兼容当前 XCTest。
- 工程迁移仅调整构建、签名配置和文档，没有修改增强行为，也未替换当前试用的旧产物。
