# MiniDock 1.1.5

- 应用、Xcode 工程、Swift Package、源码目录、菜单和设置文案统一更名为 MiniDock。
- GitHub 仓库、介绍、README、安装文档及构建、测试、打包流程同步更新。
- 版本为 1.1.5（build 26），包含 Apple silicon / Intel 通用应用。

## 安装与升级

下载 `MiniDock-1.1.5-universal.dmg`，将 MiniDock.app 拖入 Applications。`SHA256SUMS.txt` 用于验证下载完整性。

从更名前的版本升级时，先退出并移除旧应用。Bundle ID 已改为 `local.royce.MiniDock`，需重新授予辅助功能和屏幕录制权限，并重新设置偏好、排除列表和登录启动项。

使用 Apple Development 开发证书签名，尚无 Developer ID 分发签名及 Apple 公证。首次打开及已知限制详见仓库安装说明。
