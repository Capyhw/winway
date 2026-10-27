# FSearch 搜索

Winway 使用 [noahdunnagan/fsearch](https://github.com/noahdunnagan/fsearch) v0.2.1（提交 `88e63fdf850cf7749deae8198b187accd21f8ba5`，MIT）。这是面向 macOS 的 Rust 搜索引擎，与 cboxdoerfer 的 GTK 应用不同。

首次搜索会启动 FSearch 共享后台服务并建立磁盘索引。后续查询使用索引，由 FSEvents 更新文件变化；不再为每次输入重新递归遍历目录。Winway 保留 250ms 输入防抖，结果按文件列表选择的规则排序。首次索引耗时取决于磁盘和文件数，后台服务在窗口关闭后继续运行，不注册登录项。

## 查询

按 Ctrl+F 输入名称或筛选条件，范围始终限制为当前目录及子文件夹。即使输入其他 `in:` 条件，也不能扩大到当前目录以外。

| 输入 | 用途 |
| --- | --- |
| `mian.swift` | 模糊名称，允许一定程度的拼写错误 |
| `ext:pdf report` | PDF 文件中的模糊名称查询 |
| `type:image` | 图片文件 |
| `grep:invoice` | 搜索文本内容，列表显示命中的文件 |

最多读取前 10,000 个候选，再按隐藏文件设置、当前目录边界和现存文件过滤；超限会提示缩小范围。目录和符号链接本身可以出现在结果中，但不会通过符号链接祖先显示其他目录的内容。FSearch 语法中的特殊字符会按查询语法解释，详见上游 README。

## 索引与权限

索引保存在 `~/Library/Application Support/FSearch/`，与独立安装的同版本 FSearch 共享。没有完全磁盘访问权限时，上游主动跳过桌面、文档、下载、部分 Library/媒体目录及 `/Volumes`。Winway 对受保护目录显示权限提示，对包含这些目录的搜索显示覆盖不完整提示。普通目录也可能因权限或索引更新延迟缺少结果；刷新会重新查询当前索引。

需要搜索受保护目录时，在 macOS「系统设置 → 隐私与安全性 → 完全磁盘访问权限」中授权 Winway，以及实际提供索引的 FSearch 辅助程序。打包位置为 `Winway.app/Contents/Helpers/fsearch`；如果已运行独立安装的 FSearch，授权其对应程序。随后退出旧的 FSearch 后台进程，再重新搜索，使它重新检查权限。重建、重新签名或升级后可能需要重新授权。不要删除索引来代替授权。

上游全盘遍历不会跨越普通挂载点，外接卷的覆盖不能保证。内容索引也不是所有文件的全文数据库：默认文本上限为 1 MB，Git 仓库内为 10 MB，并排除部分忽略文件、锁文件、构建输出和大 JSON 等。内容搜索进行中或结果不完整时会提示刷新。没有授予权限和未覆盖的目录不能视为“磁盘上没有这个文件”。

## 构建和验证

`scripts/build-app.sh` 自动准备并打包辅助程序，无需最终用户安装 Rust。Apple Silicon 下载固定版本发布包并验证 SHA-256；Intel 从固定提交编译，构建机需要 Rust 1.92 或更新版本。许可证保留在 `ThirdParty/FSearch/LICENSE` 和应用资源中。

开发运行可设置 `WINWAY_FSEARCH_PATH`，否则依次查找应用内辅助程序、可执行文件旁的辅助程序和 `~/.local/bin/fsearch`。找不到程序或通信失败会显示错误，不会悄悄切回目录遍历。

```sh
./scripts/test.sh
./scripts/build-app.sh debug
./scripts/test-search.sh
./scripts/test-bundle.sh dist/Winway.app
```

核心测试用协议夹具验证取消、超时、错误、目录边界、隐藏目录、失效索引和展示逻辑；搜索集成测试调用真实 FSearch，使用临时文件验证索引查询、模糊匹配、筛选、内容搜索和文件变化。
