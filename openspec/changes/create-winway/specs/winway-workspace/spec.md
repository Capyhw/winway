# Spec Delta

## Purpose

定义 Winway 在 macOS 上的窗口、界面分区和多标签导航体验，让用户能够沿用 Windows 文件管理习惯，同时保持真实的 macOS 窗口操作与互不干扰的目录上下文。

## ADDED Requirements

### Requirement: Desktop explorer shell
应用 SHALL 提供可拖动、缩放、最小化、全屏和关闭的真实 macOS 窗口，并以 Figma 文件 `wGLenm7aPmWyd9rDVtjfkm` 节点 `2:38` 为浅色界面基准，包含顶部标签、导航与搜索、命令栏、侧栏、文件区、可收起详情面板及状态栏。

#### Scenario: Window visual baseline
- **WHEN** 在 1376×820 的窗口内容区域展示具有相同结构的测试文件列表
- **THEN** 界面的分区、层级、图标、颜色、间距和选中状态与设计基准一致；实际文件名称及系统窗口控件允许平台适配
- **THEN** 设计稿窗口外的蓝色桌面背景不成为应用内留白

#### Scenario: Compact window
- **WHEN** 用户将窗口缩小到支持的最小内容尺寸 960×600
- **THEN** 标签、导航和文件操作仍可访问，详情面板可以收起，文件表格可横向滚动，长名称不覆盖相邻列

### Requirement: Independent tabs
应用 SHALL 支持新增、切换和关闭标签，每个标签独立保持目录、导航历史、排序、过滤词、选择和滚动位置；新标签默认打开用户主目录，关闭最后一个标签后保留一个主目录标签。

#### Scenario: Switching between directories
- **WHEN** 用户在文档标签选中文件并滚动，切换到下载标签后返回
- **THEN** 文档标签恢复其原有目录和界面状态，下载标签不被改变

#### Scenario: Closing the final tab
- **WHEN** 用户关闭唯一剩余标签
- **THEN** 应用显示一个主目录标签，窗口继续可用

### Requirement: Directory navigation
应用 SHALL 提供前进、后退、上级目录、面包屑和可编辑路径栏；路径栏接受绝对路径与 `~` 开头的主目录路径。仅成功进入目录后提交历史，新分支导航清除前进历史。

#### Scenario: Failed path navigation
- **WHEN** 用户输入不存在或不可读的目录
- **THEN** 应用显示原因并保留此前可用目录及历史，不显示成功进入的状态

#### Scenario: History branching
- **WHEN** 用户依次进入 A、B、C，后退到 B 后进入 D
- **THEN** 后退可返回 B，前进历史不再包含 C；其他标签历史不受影响

### Requirement: Coherent command entry points
应用 SHALL 通过命令栏、文件或空白处右键菜单、快捷键提供一致的相关操作，并根据选择、剪贴状态和目录能力同步启用状态；更多菜单 SHALL 提供设置入口。

#### Scenario: No file selection
- **WHEN** 当前没有选中文件
- **THEN** 重命名、剪切、复制和移到废纸篓入口不可执行，新建文件夹和设置仍可访问

#### Scenario: Settings entry
- **WHEN** 用户从更多菜单选择设置
- **THEN** 应用显示包含键盘习惯与快捷键配置的设置界面，关闭后返回原标签
