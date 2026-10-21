# Design

## Context

动机和功能边界见 `proposal.md`。本项目是新建的 `winway/`，当前只有迁入的 OpenSpec，没有现成业务代码、组件库或构建配置。现有能力清单为空，不涉及旧实现迁移。

本地 Figma MCP 已在本次会话读取指定节点的完整设计上下文与截图。画板为 1440×900，窗口内容为 1376×820；顶部分为三个 44px 高区域，列表行高 32px，正文主要为 13px，详情面板宽 300px。设计中已有 macOS 红绿灯、SF Pro 字体和顶部多标签，但磁盘盘符、OneDrive 入口及 DOCX 预览仍为示意，需要按规格适配真实环境。

用户确认：产品名 Winway、新项目、macOS、Win11 交互、指定 Figma 设计、可切换和自定义快捷键。用户另已确认采用 Swift + AppKit、辅以 SwiftUI 的原生技术方案；首版功能边界和其他默认值仍按本提案执行，切换技术栈不自动扩大功能范围。

## Goals / Non-Goals

**Goals:**
- 原生视图层负责交互状态，文件服务负责真实磁盘结果，使所有入口共享命令及操作语义。
- 将导航读取、文件写入、预览和设置保存分别建模，避免慢任务阻塞窗口或迟到数据污染当前视图。
- 在当前 Mac 完成真实读写、废纸篓和快捷键验收，视觉预览不能替代原生能力验证。

**Non-Goals:**
- 不通过任意 shell 命令实现文件服务，不使用 WebView 承载主界面。
- 不将 Figma 生成代码中的固定宽度直接用作整个应用布局，也不把截图作为界面实现。
- 首版不提供跨应用文件剪贴板、拖放文件搬移、全局快捷键、会话标签恢复或全目录实时监听。框选仍在范围内。

## Decisions

### 1. Swift 原生应用：AppKit 主界面、SwiftUI 设置、Swift 文件服务

采用 Swift 编写整个应用。AppKit 管理生命周期、NSWindow、文件列表、导航侧栏、菜单和响应链；SwiftUI 编写设置、快捷键编辑器及部分详情区域，通过 NSHostingView 嵌入 AppKit。业务状态和文件服务独立于视图，支持测试与后台执行。

选择 AppKit 主体是为了直接控制桌面文件列表、焦点与系统交互，SwiftUI 则减少设置表单的维护成本。相比 Web 界面与原生服务桥接，本方案在一个 Swift 工程中维护事件和文件模型；相比完全使用 SwiftUI，AppKit 提供明确的行复用与复杂选择控制点。Win11 样式和键盘行为仍需主动定制，原生控件默认值不是验收标准。

参考官方文档：[NSHostingView](https://developer.apple.com/documentation/swiftui/nshostingview)、[NSTableView](https://developer.apple.com/documentation/appkit/nstableview)、[NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace)、[Swift Package Manager](https://docs.swift.org/main/documentation/packagemanagerdocs/)。

使用 Swift Package Manager 定义应用 executable target、独立 WinwayCore target 和测试 target，通过 `swift build`、`swift test` 构建和测试。打包脚本生成 `.app` 的可执行文件、Info.plist、图标和资源布局。SwiftPM 不自动产出完整 `.app`；脚本必须复制资源 bundle，并验证脱离源码和构建目录后仍能启动及加载素材。若本地运行需要临时签名，使用 ad-hoc 签名，不代表 Developer ID 分发签名或公证。

代码直接创建在当前项目根，保留 `openspec/`，拟用目录：

```text
Package.swift
Sources/
  WinwayApp/
    Application/    lifecycle, windows, composition
    Explorer/       AppKit views and controllers
    Settings/       hosted SwiftUI views
    Platform/       macOS open, trash, icons, volumes
    Resources/      Figma assets and application resources
  WinwayCore/
    Models/         tabs, entries, selection
    Commands/       command definitions and key bindings
    FileSystem/     listing and operation jobs
    Settings/       versioned configuration storage
Tests/WinwayCoreTests/
Packaging/Info.plist
scripts/build-app.sh
```

首版本地开发包采用非 App Sandbox 模式，文件访问仍受系统权限和 TCC 限制，不要求提权或自动修改系统隐私设置。未来 Mac App Store 沙盒授权及安全作用域书签需独立设计。测试可注入模拟文件服务，发布包使用真实服务。

### 2. Figma 作为视觉基准，采用可伸缩布局

实施时重新通过本地 MCP 读取节点并获取原始 SVG；本次返回的是临时 `localhost:3845/assets` URL，不能留在发布代码里。原始设计素材随项目保留，原生打包验证格式兼容性；需要兼容导出时使用相同图形的 PDF 或 @2x PNG，保留比例和颜色，不以近似 SF Symbols 替换。通过共享 Swift 设计令牌管理 NSColor/SwiftUI Color、字号和间距。优先系统 SF 字体，不另外分发字体文件。

使用真实窗口红绿灯，标题栏其余区域容纳标签并提供拖动区域；按钮和标签不属于窗口拖动命中区。主体使用 Auto Layout 和分栏容器形成侧栏、弹性文件列表和可收起详情三列，详情展开时保留其基准宽度，列表列不足时滚动而非挤压文字。画板外桌面背景不进入应用。Figma 自定义颜色与间距优先保留，不套用 iOS 导航布局或自动换成默认 macOS 材质。

Figma 没有设置、右键菜单、冲突对话框和错误状态的完整设计，这些使用相同令牌补齐，并单独验收；不声称已获得这些页面的 Figma 高保真节点。

### 3. 每个标签独立的状态与带版本的读取

`TabState` 保存 id、directory、history/index、sort、filter、selection、anchor 和 scroll。UI 状态在 MainActor 更新，目录及预览请求带 requestId/导航版本，仅当标签和版本仍匹配才提交结果。文件服务按批返回条目，文件列表采用复用行视图的 NSTableView，侧栏采用 AppKit 导航视图，层级数据使用 NSOutlineView；选择逻辑基于完整可见项目集合而非已创建的行视图；用 10,000 项测试目录检查滚动和范围选择。

首版使用显式刷新、窗口重新激活刷新和文件操作完成后的相关目录刷新，避免先引入递归 watcher。`~` 在文件服务中解析；路径与展示名称分离，读取和写入时重新检查存在性。符号链接以链接元数据展示，浏览跟随到目标时遵循权限，写操作默认只作用于链接本身。

### 4. 后台操作任务，显式维护部分完成状态

统一 Swift 命令服务接收工具栏、右键菜单和快捷键意图；专用后台串行队列执行写任务，独立有界队列负责读取。任务状态可用 actor 隔离，但阻塞文件 I/O 不在 MainActor 或共享协作线程上长时间执行；仅把同步 I/O 放进 Task 不算线程隔离。任务包含 jobId、操作类型、源项目、目标目录和逐项结果，状态为 queued/running/awaiting-conflict/completed/partial/failed/cancelled。以项目数报告进度，不伪造字节百分比。

应用内文件剪贴状态保存 copy/cut 模式及源路径，不改变系统文本剪贴板。macOS 的 Cmd+Option+V 可将应用内 copy 项作为移动执行。读写开始前重新验证源、目标、文件标识和路径关系；禁止自身与后代目标，并防止大小写或 Unicode 规范化导致错误覆盖。

复制使用目标同目录下的临时名称，成功后以不覆盖已存在项目的方式提交；冲突提供跳过、保留两者、取消剩余。目录递归复制保留符号链接，并验证权限、时间及 macOS 扩展属性等元数据保留；不能把会丢弃元数据的朴素字节复制当成完整实现。

同卷移动优先原生 rename；跨卷采用复制完成、验证结果、再删除源的顺序。源在任务中发生变化时停止并报告，避免把更新后的源误删。中断时保留源；对于未能清理的临时目标，结果中返回实际位置与原因。取消从安全边界停止，不宣称回滚已完成项。

文件读写以 Foundation FileManager/URL 为基础，无覆盖提交和元数据操作封装在平台服务中。废纸篓与默认应用打开通过 NSWorkspace 适配，不使用永久删除兜底，不拼接 shell 命令。普通文件夹和应用包均需用测试夹具验证元数据及边界。

### 5. 命令注册表 + 两套预设覆盖

注册表定义稳定 commandId、中文名称、可用条件、上下文、默认绑定和执行入口。工具栏、右键菜单及键盘都引用注册表，菜单提示从当前有效绑定生成。

设置保存 schemaVersion、activePreset、windowsOverrides、macOverrides。有效绑定由预设叠加对应覆盖，显式空值表示禁用；恢复单项删除该项覆盖，恢复整套只清除当前套覆盖。原子写入应用配置目录，保存失败保留最近可用状态并显示未保存，不显示“已保存”。

按键以归一化修饰键 + 逻辑键保存，区分 Control、Meta、Alt、Shift 和 Backspace/Delete；默认绑定可含平台等价别名，用户自定义替换整组。录入时忽略纯修饰键与自动重复；已知保留组合键采用清单拒绝，不能承诺检测用户所有系统自定义热键。

分发顺序：按键录入 > 输入法组合输入/文本编辑 > 模态界面 > 当前文件列表 > 窗口导航。文本区复制、粘贴、删除不得调用文件命令；上下文有重叠的绑定才判冲突。文件写命令忽略 key repeat 并通过任务去重。

AppKit 的 first responder、字段编辑器和菜单 key equivalent 接入同一命令路由，SwiftUI 设置共享配置状态。录入器只在应用前台捕获事件，组合输入期间不抢先消费按键；Windows Ctrl 组合键在文本区保持文本语义，文件列表才按文件预设处理。防止系统菜单默认 Cmd 绑定在 Windows 模式重复触发，以及 SwiftUI 和 AppKit 对一次事件重复执行。

预设补充表（文件操作核心绑定见快捷键规格）：

| 命令 | Windows | macOS |
|---|---|---|
| 新建/关闭标签 | Ctrl+T / Ctrl+W | Cmd+T / Cmd+W |
| 地址栏 | Ctrl+L | Cmd+L |
| 当前目录过滤 | Ctrl+F | Cmd+F |
| 后退/前进 | Alt+Left / Alt+Right | Cmd+[ / Cmd+] |
| 上级目录 | Alt+Up | Cmd+Up |
| 新建文件夹 | Ctrl+Shift+N | Cmd+Shift+N |
| 刷新 | F5 | Cmd+R |
| 设置 | Ctrl+, | Cmd+, |
| 增减选择 | Ctrl+单击 | Cmd+单击 |

鼠标选择修饰键跟随预设，但首版自定义编辑器只配置键盘命令。macOS 预设中的 Cmd+X 是 Winway 明示的剪切便利扩展，并非声称 Finder 原生支持该组合。

### 6. 预览受限读取，DOCX 明确降级

详情始终来自真实 metadata。首版内嵌 PNG/JPEG 和不超过 1 MiB 的 UTF-8 文本，图片设置解码像素及读取大小上限；超限说明不能预览并保留系统打开入口。内容只读，不运行文件中的 HTML/脚本。DOCX、PDF 等先显示系统类型图标、真实属性和打开入口；Quick Look 可后续通过原生适配接入，本次不因技术栈变化扩大既定预览范围。

## Risks / Trade-offs

- [本机工具链尚未完成应用构建验证] → 已确认 Swift 6.4 可运行，当前 developer directory 指向 Command Line Tools，xcodebuild 报需要完整 Xcode；按 SwiftPM + 本地打包路径验证实际编译、资源加载和启动，不自动切换全局工具链或安装 Xcode。
- [原生默认按键和外观不等于 Win11 行为] → AppKit 控件样式和选择规则按设计定制，实际窗口验证键盘、标题拖动、权限和文件操作；SwiftUI 预览不替代实机验收。
- [文件复制和跨卷移动可能部分完成或丢失元数据] → 分项结果、临时目标、源变更检查和元数据测试；未完成真实跨卷测试时必须标为未验收。
- [macOS TCC 权限、只读卷、失效链接和大目录] → 显示错误类别和可恢复入口，不把不可读当空目录；有界读取和虚拟化。
- [系统保留按键、Fn 功能键和中文输入法] → 在实际键盘实测，允许自定义替代，不注册全局键盘钩子。
- [Figma 示例包含不属于 Mac 的入口] → 使用真实主目录及挂载卷替代，隐藏未实现的 OneDrive/网络发现；不留下可点击但无行为的入口。

## Migration Plan

1. OpenSpec 已迁入新项目，后续所有命令从 `winway/` 执行；不需要迁移旧应用数据。
2. 按任务创建脚手架、原生窗口和受控文件服务，再接入界面、文件任务与快捷键设置。
3. 在专用临时目录进行功能验收，使用与 Figma 相近的文件夹/文件结构进行视觉验收。
4. 构建当前宿主架构 `.app` 并启动验证，记录实际 macOS 版本、架构及已测范围，不据此宣称其他版本兼容。
5. 本阶段不自动发布、使用 Developer ID 分发签名或公证。若需回退，停止使用新应用；配置可单独重置，但真实文件操作不能通过代码回滚自动撤销。
