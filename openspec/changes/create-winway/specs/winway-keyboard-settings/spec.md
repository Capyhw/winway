# Spec Delta

## Purpose

让 Winway 用户在 Windows 与 macOS 键盘习惯之间自由切换，并对文件管理命令定制按键，同时确保输入文本、切换配置和重新启动应用时快捷键具有一致且可预测的行为。

## ADDED Requirements

### Requirement: Keyboard presets
设置 SHALL 提供 Windows 与 macOS 两套可切换预设，首次启动默认 Windows。Windows 默认使用 Ctrl+C/X/V/A、Enter 打开、F2 重命名、Delete 或 Mac 的 Backspace 移到废纸篓；macOS 默认使用 Cmd+C/V/A、Cmd+X 标记剪切、Cmd+Option+V 移动已复制项目、Cmd+Down 打开、Return 重命名、Cmd+Backspace 移到废纸篓。

#### Scenario: Switch keyboard habits
- **WHEN** 用户从 Windows 切换到 macOS 预设
- **THEN** 文件列表中的 Return 从打开改为重命名，命令菜单提示同步更新，不保留旧预设绑定同时触发

### Requirement: Command customization
设置 SHALL 列出文件操作、选择、导航、标签、刷新和设置命令，支持通过录入按键替换或清除单个绑定。每套预设 SHALL 独立保存用户覆盖，切换预设不丢失另一套的修改；一个命令在同一上下文可有一个用户自定义组合键。

#### Scenario: Record a replacement binding
- **WHEN** 用户为重命名录入有效且无冲突的组合键并保存
- **THEN** 新绑定立即生效，原默认绑定不再执行重命名，菜单显示新的组合键

#### Scenario: Switch back to customized preset
- **WHEN** 用户自定义 Windows 预设，切换到 macOS 后再切回 Windows
- **THEN** 先前的 Windows 自定义仍然生效

### Requirement: Conflict validation
设置 SHALL 在保存前检测同一可同时生效上下文内的重复绑定，显示冲突命令且阻止保存；仅修饰键、Escape 和已知由 macOS 保留的组合键 SHALL 不可作为自定义绑定。对于系统设置或其他软件额外占用而应用无法可靠检测的组合键，界面 SHALL 不保证可用性并提供实际按键试用说明。

#### Scenario: Duplicate assignment
- **WHEN** 用户将重命名绑定为已用于复制的组合键
- **THEN** 设置指出复制命令冲突，保存前原绑定保持有效

#### Scenario: Cancel key recording
- **WHEN** 用户录入按键期间按 Escape
- **THEN** 录入取消，原绑定不变，Escape 不会被保存为快捷键

### Requirement: Context-aware dispatch
快捷键 SHALL 仅在 Winway 前台窗口内生效。输入文件名、搜索词、路径或其他文本时，文本编辑和输入法组合输入 SHALL 优先；按键录入界面 SHALL 捕获按键而不执行命令。文件命令 SHALL 遵守选择与目录状态，不因自动重复产生多次写操作。

#### Scenario: Delete while renaming
- **WHEN** Windows 预设下用户正在编辑文件名并按 Backspace
- **THEN** 删除输入字符，不把选中文件移到废纸篓

#### Scenario: IME confirmation
- **WHEN** 用户在路径输入框使用中文输入法并按 Enter 确认候选词
- **THEN** 仅确认输入法内容，不同时导航、打开或重命名文件

### Requirement: Restore defaults
设置 SHALL 支持恢复单项默认绑定，以及经确认恢复当前预设的全部默认绑定；恢复当前预设 SHALL 不改变另一预设。

#### Scenario: Restore current profile
- **WHEN** 用户确认恢复 Windows 预设全部默认绑定
- **THEN** Windows 自定义覆盖被移除，macOS 自定义保持原样，提示文本同步刷新

### Requirement: Persistent settings with recovery
应用 SHALL 持久保存当前预设及两套自定义配置，重新启动后恢复。保存失败 SHALL 明确提示未保存；配置损坏 SHALL 使用可用默认值并提示恢复，不能阻止应用启动。

#### Scenario: Relaunch after customization
- **WHEN** 用户成功保存自定义绑定后退出并重新启动应用
- **THEN** 预设选择、自定义绑定和菜单快捷键提示一致恢复

#### Scenario: Unreadable configuration
- **WHEN** 启动时配置无法解析
- **THEN** 应用以 Windows 默认预设启动并提示配置恢复，不执行损坏配置中的绑定
