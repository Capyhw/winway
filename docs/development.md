# 开发 Winway

Winway 使用 Swift Package Manager，主界面基于 Swift + AppKit，快捷键设置使用 SwiftUI。目标系统为 macOS 13 及以上；最低版本是编译目标，并不代表所有系统版本均已完成实机验证。

## 本地构建

```sh
./scripts/build.sh
./scripts/test.sh
./scripts/build-app.sh
open dist/Winway.app
```

`./scripts/build-app.sh debug` 可生成调试包。普通构建不依赖 Node 或 Rust；应用包当前仅作 ad-hoc 签名，没有 Developer ID 签名或公证。

构建与打包统一通过 `scripts/build.sh`，默认使用 `swiftbuild` 后端与 `xcrun` 选中的 macOS SDK。使用较旧的 Xcode SwiftPM 时，可选择原生后端：

```sh
WINWAY_BUILD_SYSTEM=native ./scripts/build.sh
WINWAY_BUILD_SYSTEM=native ./scripts/build-app.sh
```

GitHub Actions 使用 Xcode 26.3 的原生后端。打包架构、产物和版本发布步骤见[发布说明](releasing.md)。

## 工具链说明

本地已验证过 Apple Silicon、Swift 6.4 与 Command Line Tools 环境。该 CLT 包含 Swift Testing framework 与宏插件，但不含 XCTest，因此测试统一使用 Swift Testing。

`scripts/test.sh` 执行 `swift test --disable-xctest`，并从当前工具链定位 `testing` 宏目录、添加 `-Xswiftc -plugin-path`，处理该 CLT 环境未自动发现宏插件的问题，不需要修改全局工具链。

Swift 6.4 / CLT 环境曾出现指定 SDK 27.0 后，链接结果仍记录 SDK 13.0、导致旧版控件外观的问题。构建脚本通过链接器 `-platform_version` 显式传入最低系统版本与实际 SDK 版本；打包前校验两项版本，不符时停止。工具链升级后应重新验证这一处理是否仍有必要。

## 测试与验收

```sh
./scripts/test.sh --filter KeyboardTests
```

常规测试覆盖文件服务、快捷键、导航及 10,000 项目录状态的排序、过滤和选择；这不等于原生窗口滚动性能验收。真实卷测试需要专用夹具，缺少夹具时明确跳过。

打包后运行 `./scripts/test-ui-components.sh` 可验证右键菜单分类、打开方式的多选应用交集与默认项、系统服务的文件 URL/旧格式路径传递及剪贴板隔离。应用和服务列表依赖本机安装情况，实际调用需另外用专用测试文件在原生窗口验收。

调试二进制支持以下参数，便于隔离测试目录和快捷键配置：

```sh
Winway --directory /绝对/测试目录 --settings-path /绝对/临时配置.json
```

写操作只使用专门创建的测试夹具，不使用用户文件。完整边界矩阵及待验收项见[验收记录](acceptance.md)，产品范围见 [OpenSpec](../openspec/changes/create-winway/)。

快捷键配置位置为 `~/Library/Application Support/Winway/keyboard.json`，预设和自定义行为见[快捷键说明](keyboard.md)。
