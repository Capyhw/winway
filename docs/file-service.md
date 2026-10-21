# 文件服务实现与验收

`LocalFileService` 实现 `FileServing`。目录读取、递归搜索和文件写入分别在独立串行 DispatchQueue 上执行；读写不会占用 MainActor。主界面负责导航版本、过滤排序、预览、默认应用打开和系统废纸篓。

## 集成接口

- `listDirectory(_:includeHidden:) async throws -> [FileEntry]`：默认隐藏项不显示，使用 lstat 保留符号链接本身的属性，失效链接仍可见；读取错误绝不转换为空列表。
- `searchDirectory(_:query:includeHidden:cancellation:)`：按名称不区分大小写搜索当前目录及所有层级子目录，返回匹配项和无法读取的项目数。隐藏目录关闭时整棵跳过；符号链接本身可匹配，但不跟随链接。根目录读取失败抛错，子目录错误跳过并计数。每个项目之间检查取消，不承诺中断正在执行的系统读取。搜索不读取文件正文、不依赖 Spotlight 索引。
- `createDirectory(in:name:)`、`rename(_:to:)`：拒绝空白、`.`、`..`、斜线、空字符和已有名称。不会覆盖已有项目。大小写遵循目标卷能力，同时检查 Unicode 规范等价名称。
- `transfer(_:cancellation:onProgress:resolveConflict:) async -> FileOperationReport`：`.copy` / `.move`；冲突回调异步返回 `.skip`、`.keepBoth` 或 `.cancel`。回调可进入 MainActor 显示对话框，文件队列在后台等待。
- 进度包含 `jobID / total / processed / succeeded / failed / currentSource / state`；是项目数，不是伪造的字节百分比。UI 应在 MainActor 上接收事件。
- 报告的每项包含 `source / destination / outcome / error / residualURLs`。只能将 `.succeeded` 的移动从剪切状态删除；跳过/失败/取消应继续保留。重试创建新请求且仅包含用户选择的未完成项。
- `FileTransferRequest.id` 在同一服务实例中只接受一次，包含已结束的任务。调用方重复点击粘贴仍应复用当前任务或禁用重复提交。服务不持久化任务历史。

## 数据保护边界

复制先写目标同目录下 `.winway-copy-UUID`，递归 SHA-256 校验内容、权限位、mtime 和扩展属性；目录、应用包和符号链接分别处理。复制前后的源设备/inode/ctime/size 及内容快照需要一致。目标最终使用 macOS `renamex_np(RENAME_EXCL)` 提交；目标被外部并发创建时重新询问冲突，不能覆盖或合并。

同卷移动使用无覆盖原子 rename。跨卷移动先复制、验证、提交目标，再把源原子移到同目录的 `.winway-move-UUID` 并重新核对文件身份和内容，然后删除。失败时尝试恢复源，不能恢复的位置和已提交副本通过 `residualURLs` 返回。删除阶段失败时副本已完整验证，报告仍为失败，并说明现存路径，不假装回滚。符号链接复制、移动只作用于链接本身。

取消从安全边界停止：尚未开始项目取消；已开始的复制在复制和校验结束、提交之前检查取消。不会强行中断系统 `copyItem`，不会撤销已经完成的项目。正在等待冲突时也支持取消。

此保护不能锁住不配合的外部写入进程；快照核验与实际系统删除之间仍存在极短的外部并发修改窗口。应用不承诺数据库级事务、通用撤销、跨进程独占访问或断电恢复。源被其他进程持续修改时应先停止该写入再重试。特殊设备、socket、FIFO 不作为普通文件复制。

## 可复跑测试

标准测试源：`Tests/WinwayCoreTests/FileSystemTests.swift`，使用 Swift Testing。宿主 CLT 所需测试框架参数由项目测试入口配置。

无测试框架的独立入口（从相同测试源生成简单断言运行器，不是另写一套模拟测试）：

```sh
scripts/test-filesystem.sh
scripts/test-filesystem.sh --volumes
scripts/test-search.sh # 搜索与原生列表集成：多层结果、取消、切换、重命名刷新
```

`--volumes` 只创建临时 128 MiB APFS 镜像，先读写挂载验证跨卷移动，再只读挂载验证失败保源，最后卸载验证失效路径。脚本退出时卸载并清理自己创建的镜像。不会修改用户磁盘设置或既有卷。

2026-10-21，macOS 27.0 (26A428)、arm64、Apple Swift 6.4，本机实测通过：

| 场景 | 结果 |
|---|---|
| 中文、隐藏项、真实大小、失效链接、缺失目录 | 通过 |
| 新建/重命名与非法名称、已有名称拒绝 | 通过 |
| 应用包目录复制，SHA-256、链接、权限、mtime、xattr | 通过 |
| skip / keepBoth / cancel，部分成功、重复任务 | 通过 |
| 自身、子目录、链接解析后的子目录拒绝 | 通过 |
| 同卷移动、失效符号链接复制 | 通过 |
| 后台进度与取消剩余项目 | 通过 |
| chmod 000 目录权限错误 | 通过 |
| 复制中并发创建目标，再询问并保留两者 | 通过 |
| Unicode 规范等价、当前卷大小写冲突 | 通过 |
| 持续外部写入源，检测变更、保源、清理临时副本 | 通过 |
| 独立 APFS 卷跨卷移动，st_dev 不同，成功后移除源 | 通过 |
| 只读 APFS 卷失败，源内容完整且无临时残留 | 通过 |
| 卷卸载后目录读取返回 notFound | 通过 |

普通测试未提供卷环境变量时会跳过三个可选卷场景；不能把该次跳过计作实测。真实卷验收由 `--volumes` 执行。Finder/TCC 系统授权对话框、系统废纸篓及原生 UI 属于应用集成验收，不由本文件服务测试证明。
