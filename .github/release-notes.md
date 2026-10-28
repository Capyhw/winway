本次更新：

- 首次启动提供完全磁盘访问权限引导，授权后返回 Winway 自动检查，再启动搜索索引。
- 设置新增左侧导航，提供快捷键、权限和关于页面；可以查看权限状态并打开 macOS 对应设置。
- 支持手动重新建立 FSearch 索引，补齐此前因权限不足跳过的目录。
- 退出 Winway 时同时停止内置 FSearch，关于页面支持查看版本和检测更新。

支持 macOS 13 及以上。请按 Mac 芯片选择下载包：

- Apple Silicon（M 系列）：`macos-arm64`
- Intel：`macos-x86_64`
- DMG：打开后将 Winway 拖入 Applications。
- ZIP：解压后将 Winway.app 移入 Applications。
- `.sha256`：对应 ZIP 和 DMG 的 SHA-256 校验值。

当前应用仅使用 ad-hoc 签名，未使用 Apple Developer ID 签名，也未经过 Apple 公证。首次打开可能被 Gatekeeper 拦截；请先确认下载来源，再按 macOS“隐私与安全性”的提示处理。最低系统版本是编译目标，不代表已在所有 macOS 版本上完成实机验证。
