# Spec Delta

## Purpose

定义 Winway 对本地文件和文件夹执行新建、复制、移动、重命名及移到废纸篓的可观察结果，使用户能够掌握每项操作的完成状态，在冲突或失败后仍保有明确的文件归属。

## ADDED Requirements

### Requirement: Create and rename
应用 SHALL 在当前可写目录新建文件夹，并对单个选中项执行内联重命名；空名称、路径分隔符、保留的相对目录名以及同目录已占用名称 SHALL 被拒绝并保留输入供修正。

#### Scenario: Name conflict
- **WHEN** 用户将文件重命名为已存在项目的名称
- **THEN** 应用提示冲突且不覆盖任何项目，允许修改名称或取消

#### Scenario: Successful creation
- **WHEN** 用户输入合法且未占用的文件夹名称并确认
- **THEN** 文件夹在磁盘创建，列表刷新并选中新项目

### Requirement: Copy and cut paste within Winway
应用 SHALL 支持在 Winway 标签和目录间复制、剪切与粘贴多个文件或目录。剪切仅标记待移动项；只有目标完成后才移除源项。复制完成后保留源项，成功移动的项目从待剪切列表移除，失败或跳过项仍可重试。首版不承诺与 Finder 共享文件剪贴板。

#### Scenario: Paste cut items in another tab
- **WHEN** 用户剪切 A 目录的项目并在 B 标签粘贴
- **THEN** 成功项目移动到 B，A 和 B 的视图更新，成功项目的剪切标记消失

#### Scenario: Failed cross-volume move
- **WHEN** 跨卷移动在目标复制阶段失败
- **THEN** 源项目保持存在，应用报告失败和残留目标的状态，不将该项标为移动完成

### Requirement: Explicit conflict choices
应用 SHALL 在目标同名时暂停相关项目并提供跳过、保留两者或取消剩余任务；首版不执行覆盖或目录合并，保留两者 SHALL 使用未占用名称且不因并发创建覆盖其他项目。

#### Scenario: Keep both
- **WHEN** 目标已有同名文件且用户选择保留两者
- **THEN** 原目标内容保持不变，新文件以可区分名称创建并在结果中显示实际名称

#### Scenario: Cancel at a conflict
- **WHEN** 批量操作发生冲突后用户取消剩余任务
- **THEN** 尚未开始的项目不再处理，已完成项目保持完成状态，界面分别显示已完成和已取消项

### Requirement: Reject invalid destinations and preserve links
应用 SHALL 拒绝将目录复制或移动到自身或后代、将项目移动到自身、以及使用失效源或不可写目标执行操作；对符号链接执行复制、移动和移到废纸篓时 SHALL 操作链接本身而非递归操作其目标。

#### Scenario: Descendant destination
- **WHEN** 用户把目录复制到该目录的子目录，包含通过符号链接解析得到的子目录
- **THEN** 应用拒绝操作并解释原因，不产生递归副本

#### Scenario: Copy a symbolic link
- **WHEN** 用户复制符号链接
- **THEN** 目标为保留链接指向的符号链接，链接目标内容不被复制或修改

### Requirement: System trash
删除操作 SHALL 使用 macOS 系统废纸篓，操作入口标明“移到废纸篓”。如果系统不能完成，应用 SHALL 报错且不得退化为永久删除。

#### Scenario: Trash and recover through system
- **WHEN** 用户将临时测试文件移到废纸篓
- **THEN** 原目录不再包含该项，系统废纸篓中可以找到对应项

### Requirement: Per-item progress and outcome
耗时操作 SHALL 异步执行，展示操作类型、已处理项目数、成功数、失败原因和剩余状态；可取消尚未开始的项目。同一任务 SHALL 防止重复提交，重试 SHALL 仅处理明确选定的未完成项。

#### Scenario: Partial batch failure
- **WHEN** 三个项目中两个成功而第三个因权限失败
- **THEN** 应用显示两个成功和一个失败及具体原因，不声称全部完成；重试失败项不会重复复制成功项
