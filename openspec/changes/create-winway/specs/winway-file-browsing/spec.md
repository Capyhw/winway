# Spec Delta

## Purpose

定义 Winway 对真实本地文件的呈现、筛选、选择、打开和详情行为，确保界面与当前磁盘状态对应，并在权限不足、文件消失及格式无法预览时提供清晰且可恢复的反馈。

## ADDED Requirements

### Requirement: Actual locations and directory entries
应用 SHALL 提供主目录、可用的桌面、文档、下载、图片、音乐、影片目录，以及已挂载卷入口，显示真实名称和路径；目录列表 SHALL 提供名称、修改时间、类型和大小，区分文件、文件夹和符号链接，不伪造 C:、D: 或云盘连接。

#### Scenario: Open a mounted volume
- **WHEN** 用户进入侧栏中的已挂载卷
- **THEN** 应用展示该卷真实目录内容，状态栏计数与当前列表一致

#### Scenario: Permission denied or disconnected volume
- **WHEN** 当前目录无法读取或所在卷已经卸载
- **THEN** 应用显示具体错误及重试、返回可用目录入口，不把错误呈现为空目录

### Requirement: Sorting filtering and hidden files
应用 SHALL 支持按名称、修改时间、类型、大小升降序排列，默认文件夹优先且按名称升序。搜索框 SHALL 明确表示当前目录名称过滤，不递归检索子目录。隐藏项默认不显示，并提供显示隐藏文件开关。

#### Scenario: Filter current directory
- **WHEN** 用户输入过滤词
- **THEN** 仅显示当前目录中名称包含该词的项目，显示可见项数量，清空后恢复列表

#### Scenario: No matching names
- **WHEN** 当前过滤词没有匹配项
- **THEN** 显示无匹配结果与清空过滤入口，不显示权限错误

### Requirement: Selection and system opening
应用 SHALL 支持单选、按当前键盘预设的修饰键增减选择、Shift 范围选择、框选、全选及取消选择。双击目录 SHALL 进入该目录，双击普通文件 SHALL 交由系统默认应用打开。

#### Scenario: Range selection
- **WHEN** 用户先选中一项，再按住 Shift 选择另一项
- **THEN** 应用选中当前排序和过滤下两项之间的可见范围，并同步状态栏数量

#### Scenario: Missing file on open
- **WHEN** 用户打开一个已经被外部删除的文件
- **THEN** 应用显示文件不存在，刷新目录并移除失效选择

### Requirement: Truthful details and bounded preview
应用 SHALL 为单个选中项显示名称、类型、大小、修改时间及真实路径；首版 SHALL 预览常见 PNG/JPEG 图片和小型 UTF-8 文本。多选时显示选择数量，不支持格式或超出文本预览限制时显示说明与系统打开入口，不使用模拟文档内容。

#### Scenario: Preview changes with selection
- **WHEN** 用户从图片切换选择到文本文件
- **THEN** 详情和预览对应新选择，旧请求的返回结果不会覆盖新内容

#### Scenario: Unsupported preview
- **WHEN** 用户选中 DOCX、不可解码的文本或超过 1 MiB 的文本
- **THEN** 应用仍显示真实属性，说明无法内嵌预览或超出限制，并允许系统打开

### Requirement: Responsive and refreshable listings
应用 SHALL 在读取目录期间保持窗口响应，显示加载状态并支持手动刷新及窗口重新激活时刷新；读取结果不得覆盖用户随后进入的其他目录。

#### Scenario: Rapid navigation
- **WHEN** 慢目录 A 尚未读取完毕时用户进入目录 B
- **THEN** 最终视图保持 B 的路径和内容，A 的迟到响应被忽略

#### Scenario: External modification
- **WHEN** 外部程序更改当前目录后用户刷新或重新激活窗口
- **THEN** 列表更新为真实内容，已不存在的选择被清除
