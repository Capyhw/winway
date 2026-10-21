# Winway

运行在 macOS 上、采用 Windows 11 交互风格的原生文件管理器。Swift + AppKit 构建主界面，SwiftUI 提供快捷键设置。

## 开发

项目使用 Swift Package Manager，目标为 macOS 13 及以上。当前实际构建环境为 Apple Silicon、Swift 6.4、Command Line Tools；最低系统版本仅为编译目标，尚未在所有版本上验证。

```sh
./scripts/build.sh
./scripts/test.sh
./scripts/build-app.sh
open dist/Winway.app
```

本机 Command Line Tools 包含 Swift Testing framework 与宏插件，但不含 XCTest。测试统一使用 Swift Testing；`scripts/test.sh` 执行标准 `swift test --disable-xctest`，并从当前工具链定位 `testing` 宏目录、添加 `-Xswiftc -plugin-path`，修正此 CLT 安装中宏插件未被自动发现的问题。不需要下载测试依赖、安装完整 Xcode 或修改全局工具链。

可用 `./scripts/test.sh --filter KeyboardTests` 运行单套测试。常规测试包含文件服务、快捷键、导航与 10,000 项目录状态的排序/过滤和选择；这不代表已完成原生窗口滚动性能验收。真实卷测试需单独提供专用测试夹具，缺少夹具时明确跳过。独立备用测试脚本及实际验收范围见 `docs/` 和 `artifacts/`。普通构建不依赖 Node、Rust 或完整 Xcode。

`./scripts/build-app.sh debug` 可打包调试版本。脚本只作本机 ad-hoc 签名；没有 Developer ID 签名或公证。

GitHub Release 自动打包已配置：推送 `v0.1.0` 这类版本标签后，分别构建 Apple Silicon 和 Intel 的 ZIP、DMG 与 SHA-256 校验文件，通过检查后发布 Release。也可在 Actions 中手动运行 **Release macOS**，仅生成测试包。详细步骤和签名限制见 [发布说明](docs/releasing.md)。

开发及打包统一通过 `scripts/build.sh`，使用当前推荐的 `swiftbuild` 后端和 `xcrun` 选中的 macOS SDK，最低支持版本仍为 macOS 13。当前 Swift 6.4 / CLT 即使指定 SDK 27.0，也会在默认链接步骤中记录 SDK 13.0，触发旧版控件外观；脚本通过链接器的 `-platform_version` 参数，分别传入最低系统版本和实际 SDK 版本。打包前会校验二进制的两项版本，不符时停止打包。后续升级工具链时可重新验证是否还需要显式链接参数。

## 首版行为

- 多标签分别保存目录、历史、过滤、排序、选择和滚动位置。
- 鼠标标准后退/前进侧键可切换当前标签页的目录历史；没有对应历史时不执行操作。
- 按名称搜索当前目录及所有子文件夹；后台遍历支持取消，搜索结果显示所在位置。可切换隐藏文件，手动刷新或重新激活窗口时更新。
- 图片预览支持 PNG/JPEG；UTF-8 文本限制 1 MiB，图片限制 32 MiB、8000 万像素并生成缩略图。不支持的格式可用系统默认应用打开。
- 复制/剪切只在 Winway 内共享，支持跨标签粘贴。同名选择跳过、保留两者或取消剩余任务，不覆盖或合并已有内容。
- 删除使用系统废纸篓，不提供永久删除或自动永久删除兜底；可在系统废纸篓恢复。
- 操作可能部分完成，结果列出成功、失败、跳过/取消和残留目标。重试仅针对失败项，不回滚已完成项目。
- 权限不足、只读卷和断开卷会显示错误；可重试或进入可用目录。应用不会自动提升权限或修改隐私设置。

## 键盘设置

从更多菜单或应用菜单打开设置。默认 Windows 预设，支持 macOS 预设及逐项自定义，两套覆盖独立保存。预设切换、菜单提示和绑定立即同步，配置保存到 `~/Library/Application Support/Winway/keyboard.json`。

Windows 默认 Ctrl+C/X/V/A、Enter 打开、F2 重命名、Backspace/Delete 移到废纸篓。macOS 默认 Cmd+C/V/A、Cmd+Down 打开、Return 重命名、Cmd+Backspace 移到废纸篓；Cmd+X 是 Winway 的剪切扩展，Cmd+Option+V 移动已复制项。

文本编辑与输入法优先。F2 是否需要 Fn 取决于系统设置；自定义快捷键可能受系统或其他应用占用。可恢复单项或当前预设默认值，保存失败会显示“未保存”。

## 开发验收启动

调试二进制支持 `--directory /绝对/测试目录 --settings-path /绝对/临时配置.json`，用于隔离测试文件和快捷键配置。仅操作专门建立的测试夹具，不用用户文件验证写操作。

产品范围及验收标准见 `openspec/changes/create-winway/`。当前实现进度以任务复选框和[本机验收记录](docs/acceptance.md)为准；核心原生界面流程已实机验收；完整边界矩阵仍有待验收项，详见记录。
