# Winway 原生 Explorer 界面

## 设计来源与资源

本地 Figma MCP 文件 `wGLenm7aPmWyd9rDVtjfkm`、节点 `2:38`，本轮重新读取完整设计上下文及截图。应用不包含设计稿外部蓝色桌面。

- 初始内容区 1376 × 820；最小 960 × 600。
- 顶部标签、导航、命令栏各 44pt；底部 32pt。
- 侧栏 224pt，详情 300pt；文件区自适应，列总宽不足时水平滚动。
- 行高 32pt；正文 SF 13pt。颜色来自该节点。
- `Resources/Figma` 保留 34 个未经修改的原始 SVG 与源 asset hash 清单。已通过 `NSImage` 验证全部 SVG 解码，并按原始比例导出透明 @2x PNG 用于运行时加载，避免不同 macOS 版本的 SVG 支持差异。不引入远程图片请求，也不替换成相近符号。
- 表头排序使用 `Resources/Lucide` 的原始 `chevron-up.svg` / `chevron-down.svg`，通过 `NSImage` 本地加载并按强调色绘制，居中显示在列名上方；同目录附带上游许可证。表头只绘制实际列之间的分隔线，不绘制末列和滚动条角落的额外分隔线。
- 侧栏取消平铺位置列表的层级缩进，图钉随单元格右边缘布局。筛选框使用与地址栏一致的 4pt 圆角，图标、文本编辑区和清空按钮各自占位，支持按名称搜索多层子文件夹、搜索中状态、点击清空和 Escape 清空。
- 文档列表 Word 使用 24pt 原图缩放到设计槽位 20pt，详情标题使用专用 40pt Word 原图。红绿灯使用真实 macOS 窗口控件。
- 动态符号链接图标使用系统实际图标。原设计的 OneDrive、网络发现和 Windows 盘符不显示；侧栏由真实目录及卷提供。
- 设计中的假 DOCX 纸张预览未实现，按规格显示类型图标、无法预览原因及系统打开入口。

## 集成接口

`ExplorerWindowController(onAction:)` 仅依赖 `WinwayCore` 的条目和命令类型，不依赖 AppModel。`render(_:)` 接收 `ExplorerSnapshot`；用户意图通过 `ExplorerAction` 输出。`focusAddress`、`focusSearch`、`focusFiles`、`beginRename` 供统一命令路由调用。

`sort` key 使用 `name`、`modified`、`kind`、`size`。侧栏图标名使用 `home`、`pc`、`document`、`download`、`gallery`、`music`、`video`、`drive`、`folder`。所有菜单与命令按钮从 `enabledCommands` 读取有效性；提示标签来自 `shortcutLabels`，菜单不另注册一套快捷键。

窗口与根分区由 Auto Layout/NSStackView 约束；分区内部按明确设计尺寸布局。文件表格采用 NSTableView 复用行，选择以全部 row index 计算，不依赖当前可见 cell。

## 交互

- 多标签新增、切换和独立关闭；标签可横向滚动，切换时使当前标签进入视区。
- 悬停反馈覆盖整个标签，标题区域不单独着色；关闭按钮保留独立悬停反馈。标签任意区域可右键关闭当前、其余、左侧或右侧标签，没有目标的菜单项置灰。批量关闭保留未被关闭的当前标签；若当前标签被关闭，则选中右键目标。关闭最后一个标签仍新建主目录标签。
- 路径面包屑单击导航；双击路径或调用地址命令进入文本编辑，支持 Escape 放弃。
- 当前目录及子文件夹名称搜索、四种排序、隐藏项与详情开关；搜索时额外显示“所在位置”列。
- Windows Ctrl / macOS Cmd 增减选择，Shift 范围选择、空白区域开始框选、Escape 清空选择、双击打开。
- 右键先同步目标选择；工具栏、空白/文件菜单都输出统一命令。
- 内联重命名保留扩展名选择范围，Escape 放弃；提交失败重新显示已输入名称。
- 详情文本只读、可选取；真实属性通过 `NSHostingView` 嵌入 `ExplorerMetadataView`（SwiftUI），图片保持比例。预览内容及有界读取由应用服务提供。
- 加载、空目录、筛选无匹配、读取错误、文件任务状态和取消入口均由真实状态驱动。

## 验证边界

本轮 `swift build` 通过。34 个 SVG 已下载，全部 `NSImage` 解码及透明 @2x PNG 导出验证通过。真实运行、1376/960 窗口截图、点击和快捷键验收由总控代理执行；未进行的实机项目不在这里声明通过。
