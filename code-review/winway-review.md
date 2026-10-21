# Winway Swift 写法与界面交互审查

初次审查日期：2026-10-21。范围：当前项目全部 Swift 源码、主窗口交互、快捷键设置及布局。按照 write-swift、ainvest-fe-code-review、ui-ux-pro-max 审查。后续按用户要求修复第 1、2、3、4、6 项，第 5 项快捷键录制交互保留现状。

## 修复与复验结果

2026-10-21：五项修复已完成，并更新本地 `dist/Winway.app`。以下初次审查条目及原始探针日志保留作为修复前证据。

| 原问题 | 已完成修改 | 验证 |
|---|---|---|
| 1 选择时重复排序 | BrowserTabState 保存派生的 visibleEntries；仅 entries/filter/sort/ascending 变化时重算。AppModel 复用选择结果并去掉重复 render。 | 同一源码优化构建探针：14.59、8.06、7.33 ms；修复前 331.74、315.37、318.59 ms。新增派生状态更新和副本隔离测试通过。 |
| 2 导航不回顶部 | 同标签 directory 变化时应用 scrollOffset；保留刷新位置和切换标签恢复行为。 | 组件 offset 从原先残留 1536 pt 修复为 0；刷新、标签恢复回归通过。新版真实窗口从 A-079 切换到 B-000。 |
| 3 名称列移动后编辑框错位 | 按列 identifier 定位名称列；编辑前使列和行可见；随列宽和列位置变化更新布局。 | 960×600 组件验证列移动、列宽变化后编辑框仍对齐名称单元格。 |
| 4 编辑框越出文件区域 | 编辑框移入透明、裁剪到文件可见区域的容器；排除表头；空白容器不截获鼠标事件。 | 960×600 组件验证横向/纵向部分裁剪、编辑焦点保留、Escape 清理，以及空白区域鼠标穿透。 |
| 6 大小写重命名误报冲突 | 大小写不敏感卷上，验证目标确实为源目录项后，继续使用 RENAME_EXCL；保留内核对其他目标的不覆盖保证。 | 普通文件、目录、失效符号链接的大小写修改通过；真实文件冲突和不同名称硬链接仍拒绝。新版真实窗口 B-000.txt → b-000.txt 提交成功，预览内容正常。 |

验证入口：`swift build` 和 Release 打包通过；`scripts/test.sh` 共 31 项，28 项执行通过、3 项真实卷夹具测试跳过；`scripts/test-ui-components.sh` 通过；`scripts/test-preview.sh` 9 项通过。CLT 链接路径和测试 framework 的系统版本警告仍在。

真实界面验证使用从新包复制并独立签名的 Winway Check，不重启或改变用户正在使用的原 Winway 窗口。原进程需要关闭后重新打开本地 `.app` 才会加载修复。列移动与窄窗裁剪以组件测试为验收依据，未将其写成完整人工视觉验收。性能数字为 MainActor 同步选择路径的组件耗时，不是整应用帧率。

## 📊 Overall Assessment

> Approved with Changes ⚠️
> 确认 6 个问题：1 个 P1 性能问题、5 个 P2 交互或布局问题。基础结构可以保留，建议优先修复选择热路径和重命名布局。

项目已启用 Swift 6 语言模式，使用值类型保存目录和标签状态；UI 放在 MainActor，阻塞文件操作使用专用队列；导航和预览使用 generation 防止旧结果覆盖新状态。现有 @unchecked Sendable 有串行队列或锁作为依据，不应只为追随新语法而改成 actor 或 @concurrent。最低系统目标为 macOS 13，不能机械采用 skill 中要求更高系统版本的 API。

## 🚨 Must Fix (Critical)

本次未确认 P0 问题。

## ⚠️ Should Fix (Warning)

| # | 优先级 | File | Line | Issue | Recommendation |
|---|---|---|---|---|---|
| 1 | P1 | Sources/WinwayCore/Models/BrowserTabState.swift | 15–25 | visibleEntries 每次读取都会重新过滤和排序。AppModel.selected、enabledCommands、render、updatePreview 在一次选择中反复读取，造成主线程同步卡顿。 | 仅在 entries/filter/sort/ascending 变化时计算排序结果；同一次状态更新复用 visibleEntries 和 selected，合并重复 render。 |
| 2 | P2 | Sources/WinwayApp/Explorer/ExplorerWindowController.swift | 229–233 | 同标签导航不应用新的 scrollOffset，进入其他目录仍停留在原目录的中部。 | 在目录导航成功并重置滚动状态时同步 clip view；与刷新保留位置、标签切换恢复位置分开处理。 |
| 3 | P2 | Sources/WinwayApp/Explorer/ExplorerWindowController.swift | 276–282 | 重命名框使用固定列下标 0。原生表格允许移动列，名称列移动后，编辑框覆盖修改日期等其他列。 | 按名称列 identifier 查询当前列下标，定位前使目标单元格可见。 |
| 4 | P2 | Sources/WinwayApp/Explorer/ExplorerWindowController.swift | 262–263、282–283 | 重命名框挂在整个 content 上；仅以 intersects 判断显隐，不能裁剪越界部分。横向滚动会把编辑框绘制到侧栏上。 | 将编辑器放在受文件列表 viewport 裁剪的容器中，或显式约束可见范围；处理纵向滚动时同类问题。 |
| 5 | P2 | Sources/WinwayApp/Settings/SettingsWindowController.swift | 125–133 | 录制 monitor 吞掉整个 sheet 的 keyDown；Tab 和 Return 继续覆盖候选，无法使用普通键盘导航到保存按钮。 | 增加明确的录制结束状态及可用的键盘确认路径；仅在录制控件处于录制状态时捕获按键，仍保留绑定 Tab/Return 的能力。 |
| 6 | P2 | Sources/WinwayCore/FileSystem/LocalFileService.swift | 48–51 | 大小写不敏感卷上，仅修改名称大小写也被 nameOccupied 当作冲突。 | 区分真正已占用目标与仅改变同一目录项大小写，设计保留不覆盖保证的重命名路径。 |

### 1 万项目录选择的同步耗时

从本次源码以 swiftc -O 编译 AppModel、Explorer 和 WinwayCore，使用 10,000 个确定性乱序目录条目，直接计时 MainActor 上的 handle(.select)。三次耗时分别为 **331.74 ms、315.37 ms、318.59 ms**。测试条目均为目录，避免异步文件预览干扰；这是当前源码的未显示窗口组件测量，不是整应用帧率测试。

调用链包括 AppModel.swift:140 的 reconcileSelection → render → updatePreview；selected 在 36 行再次读取 visibleEntries；enabledCommands 的 85–86 行又重复计算选择；render 的 104 行再次排序。单次事件中没有 await 来释放 UI 执行，因此这段耗时直接占用主线程。

### 2 目录导航滚动位置

真实 Winway 窗口：临时 A、B 目录各有 200 个文件。A 滚动到 A-077.txt 后，地址栏进入 B，首个可见条目仍是 B-077.txt。

当前源码组件复核：同一 activeTabID，切换 directory 与 entries，并传入 scrollOffset=0，实际 clip offset 仍为 **1536 pt**。AppModel.swift:165 已重置模型位置，视图却只在 tabChanged 时应用它。

### 3 列重排后的编辑框位置

当前源码组件在 960×600 内容区将名称列从第 1 列移至第 4 列。列顺序变成 modified、kind、size、name 后：名称单元格 x=688、宽=356；重命名框 x=272、宽=144，仍按第一列的宽度和位置布局。

该操作只移动列和打开编辑器，不提交文件重命名。

### 4 横向滚动后的编辑框越界

当前源码组件在 960×600 内容区开始重命名，然后横向滚动 300 pt：文件列表 viewport 为 x=240、宽=404；重命名框变成 x=-28、宽=320，isHidden=false。框与列表尚有少量相交，导致剩余部分仍显示在整个 content 上，覆盖侧栏区域。

### 5 快捷键录制无法用普通键盘完成

真实窗口：打开“修改重命名快捷键”，录入 Ctrl+Shift+R；按 Tab 后候选变为 Tab，而不是聚焦保存；按 Return 后候选再次变为 Return，并提示与“打开”冲突。Escape 成功取消，未保存任何配置。

这不是要求禁用 Tab/Return 绑定，而是录制和确认缺少独立的交互状态。

### 6 仅修改名称大小写失败

使用当前 WinwayCore 和独立临时文件实测：卷 volumeSupportsCaseSensitiveNames=false；report.txt → Report.txt 返回“目标名称已被占用：Report.txt”。测试目录已清理。目标实际对应源目录项，不是另一个待保护文件。

## 💡 Suggestions (Info)

- KeyboardSettingsView 自行创建的 KeyboardEditorState 建议由 @StateObject 持有；@ObservedObject 更适合接收外部对象。当前未复现状态丢失，因此不计入上述 6 项缺陷。
- AppModel 的 private settingsURL 只赋值未读取，可删除该存储，保留传给 KeyboardSettingsStore 的初始化参数。无需为此扩展重构范围。
- AppModel 同时负责命令路由、操作状态、弹窗和视图快照，后续可先提取纯快照派生与文件操作状态；优先减少重复计算，再考虑其他结构调整。

## 验证结果

| 验证入口 | 本次结果 |
|---|---|
| swift build | 通过；CLT 的两处链接搜索路径不存在警告仍在 |
| scripts/test.sh | 28 项中实际执行 25 项通过，3 项真实卷测试因无夹具跳过 |
| scripts/test-ui-components.sh | 6 个内联重命名组件场景通过 |
| scripts/test-preview.sh | 9 项通过 |
| 当前源码独立优化构建探针 | 选择耗时、960×600 组件布局、列重排、横向滚动和同标签导航问题已复核 |
| 当前源码大小写重命名探针 | 复现误报冲突 |
| CUA 真实窗口 | 查看主窗口布局，复现跨目录滚动残留和快捷键录制问题；恢复原目录及筛选，关闭本次打开的设置窗口 |

真实窗口验证使用当时运行的 Winway 实例；源码探针直接编译本次文件，不把已运行二进制等同于本次重新打包版本。960×600 是组件几何验证，未宣称完成该尺寸下的整窗口视觉验收。未测其他 macOS 版本、Intel、持续滚动帧率或完整 VoiceOver 流程。测试链接的 Swift Testing framework 最低版本为 macOS 14，不能用本机测试通过证明 macOS 13 兼容。

## 复核材料

- [源码组件探针](evidence/ReviewProbe.swift)
- [组件探针编译运行脚本](evidence/run-probe.sh)
- [原始探针结果](evidence/probe.log)
- [大小写重命名探针](evidence/CaseRenameProbe.swift)

脚本使用当前机器的项目与资源路径。组件探针不修改应用源码或用户文件；大小写探针只创建并清理自己的临时夹具。
