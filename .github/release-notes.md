本次更新：

- 优化 Intel 版本的发布构建：复用已验证的固定版本 FSearch 二进制，省去每次发布时的 Rust 源码编译。
- 打包时校验 FSearch 的 SHA-256 和架构，并记录二进制来源与源码版本。
- 本次包含 v0.2.5 的权限引导、设置导航、重新索引、退出时关闭 FSearch 和更新检查功能。

支持 macOS 13 及以上。请按 Mac 芯片选择下载包：

- Apple Silicon（M 系列）：`macos-arm64`
- Intel：`macos-x86_64`
- DMG：打开后将 Winway 拖入 Applications。
- ZIP：解压后将 Winway.app 移入 Applications。
- `.sha256`：对应 ZIP 和 DMG 的 SHA-256 校验值。

当前应用仅使用 ad-hoc 签名，未使用 Apple Developer ID 签名，也未经过 Apple 公证。首次打开可能被 Gatekeeper 拦截；请先确认下载来源，再按 macOS“隐私与安全性”的提示处理。最低系统版本是编译目标，不代表已在所有 macOS 版本上完成实机验证。
