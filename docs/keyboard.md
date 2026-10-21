# 键盘与设置

设置窗口提供 Windows / macOS 预设，首次使用 Windows。每个预设有独立的自定义覆盖；切换预设不会清除另一套修改。每个命令可录入一个组合键、清除绑定或恢复默认。整套恢复需要确认，仅影响当前预设。设置即时应用并保存，菜单提示引用同一份配置。

Windows：Return/Enter 打开、F2 重命名、Control+C/X/V/A、Backspace（⌫）移到废纸篓。macOS：Command+Down 打开、Return 重命名、Command+C/X/V/A、Command+Option+V 移动已复制项目、Command+Backspace 移到废纸篓。Command+X 是 Winway 的便利扩展，不能据此认为 Finder 支持剪切。

点击“修改”后录入一次组合键，查看组合键和冲突提示，再点击“保存”或按 Return 保存。需要更换组合键时选择“重新录入”或按 ⌘R。录入后 Tab 交回系统，按钮间的 Tab 导航遵循 macOS 键盘导航设置。冲突或保留组合键不能保存，但仍可通过键盘重新录入或取消。Escape 取消；仅修饰键与自动重复不会被录入。长按录入的 Return 或 Space 不会自动确认保存。恢复单项默认键时，如果默认键已经被另一个自定义命令占用，也会提示冲突。用户自行配置的 macOS 或其他软件热键无法完整检测，保存后应在文件列表实测；部分键盘需用 Fn+F2。

配置在 `~/Library/Application Support/Winway/keyboard.json`，包含版本号及两套覆盖，使用原子写入。保存失败保留当前窗口可用配置并明确提示“未保存”，支持重试；重启不会承诺恢复未保存内容。损坏、未来版本或含冲突的配置会恢复 Windows 默认值并提示，原文件在用户再次保存前不会覆盖。需要完全重置时，退出应用并移走此文件。

AppKit 接入要求：只在主文件窗口前台且没有模态/文本编辑时分发。主路由必须检查 `store.isRecording`；菜单使用当前第一有效绑定设置真实 `keyEquivalent` 和修饰键，统一事件路由在文件域消费已处理事件，避免重复触发。输入法组合输入优先；文本区 Windows Control+C/X/V/A 桥接到字段编辑器，保留 macOS 的 Command 文本快捷键。菜单动作和验证也须优先保护文本编辑并隔离设置窗口与 sheet。写命令重复按键由注册表拒绝，文件任务层仍需去重。

自动化测试覆盖预设切换、独立覆盖、冲突/保留键、恢复冲突、写重复、录入屏蔽、配置重载、损坏和版本恢复、保存失败重试。Fn/F2、中文输入法候选确认、SwiftUI/AppKit 焦点、菜单和真实文件操作需要实机验收，不以纯配置测试替代。

当前机器的 Command Line Tools 已包含 Swift Testing framework 和宏插件，缺少 XCTest；因此标准测试统一使用 Swift Testing。Swift 6.4 的 swiftbuild 引擎在此 CLT 安装中没有自动加入 testing 宏子目录，需要显式传入：

```bash
swift test --disable-xctest \
  -Xswiftc -plugin-path \
  -Xswiftc "$(xcode-select -p)/usr/lib/swift/host/plugins/testing" \
  --filter KeyboardTests
```

独立备用入口 `scripts/test-keyboard.sh` 直接读取同一测试文件，将 `#expect` 转为 Swift `precondition`，编译相同核心源文件并逐项执行，不需要安装包或修改全局工具链。该备用入口只验证快捷键核心，不替代完整应用测试。

`scripts/test-key-recorder.sh` 验证原生录入器的事件处理：捕获后放行确认按键、Return/Space 长按保护、重新录入与冲突后的导航。它不替代真实窗口中的 SwiftUI 焦点和 VoiceOver 验收。

2026-10-21 使用独立测试应用与临时配置实测：冲突候选按 Return 不会保存，⌘R 可重新录入，随后可录入 ⌘R 并按 Return 保存；长按 Return 作为候选不会立即提交；Tab 可作为候选录入，Escape 取消后保留原绑定。本次未启用 VoiceOver，也未更改系统键盘导航设置。
