# 本机验收记录

日期：2026-10-21。当前状态：核心原生界面流程已完成实机验收，发现的问题已修复并重新打包；完整边界矩阵尚未全部验收。OpenSpec 27 项中 14 项完成，其余保留未勾选。

## 环境与产物

- 实际宿主：macOS 27.0 (26A428)、Apple Silicon arm64、Swift 6.4、Command Line Tools。
- `dist/Winway.app`：Swift + AppKit，SwiftUI 设置与详情元数据，内置 34 个 Figma 原始 SVG 和同图 @2x PNG。
- Release 构建、本机 ad-hoc 签名校验通过；未做 Developer ID、公证或发布。
- macOS 13 为最低编译目标，未实测旧系统与 Intel。
- 最终构建无 Swift 并发诊断；CLT 两个不存在的链接搜索路径仍有 warning，但不阻止构建。

## 此次界面验收与修复

用户退出 macOS 窗口总览、回到普通桌面并让 Winway 可见后，CUA 的初始窗口捕获恢复。此前的 ScreenCaptureKit `-3811` 在重置会话后仍复现，此次桌面状态改变后恢复；只能证明相关性，不能据此认定所有该错误都由窗口总览引起。没有修改系统权限。

使用 CUA 操作真实 `.app`，读写范围限于本次新建的临时目录。曾从独立临时位置启动 Release，实际展示内置图标、文件列表和预览；最终在项目 `dist/Winway.app` 复验修复。

| 实际发现 | 修复和复验 |
|---|---|
| 标签栏被裁成白色细条 | 禁用 ScrollView 自动标题栏 inset；重新启动后标签、关闭和新建标签按钮完整可见 |
| 恢复滚动时首行被表头遮挡 | 按 clip inset 归一化滚动位置；重新显示目录后首行正常 |
| 重命名字段无法保持编辑状态 | 展示标签与独立编辑框分离；去除重复启动编辑和递归焦点切换。组件测试复现根因，最终 CUA 提交成功 |
| `/var` 与 `/private/var` 路径别名造成新建后选择丢失 | 用物理父目录匹配刷新并映射实际目录条目；新建后自动选中已实测 |
| 缺少全屏退出快捷键菜单入口 | 增加原生进入/退出全屏菜单；实测进入全屏后 Ctrl+Cmd+F 返回普通窗口 |

## 实机通过的流程

| 流程 | 证据与范围 |
|---|---|
| 目录浏览 | 地址栏绝对路径、双击进入、跨标签切换；可见目录条目与磁盘一致 |
| 大目录 | 10,000 个真实文件加载，状态栏 10000；Shift 选中5项、滚动约100行、筛选09999剩1项并清空旧选择。未测持续帧率 |
| 新建 | 中文名称创建成功；同名失败保留原输入，换名重试成功且自动选中 |
| 重命名 | F2显示可编辑字段；点击字段后ASCII键入和提交成功；通过AX设置中文名称提交成功。同名错误保留输入，重试成功；Backspace只清文字，Esc取消且目录保留 |
| 跨标签复制 | Windows Ctrl+C、Ctrl+T、Ctrl+V；目标内容与源逐字节相等，源保留 |
| 同名复制 | 再粘贴出现冲突，选择保留两者生成“验收文本 (2).txt” |
| 移动 | macOS Cmd+C、Cmd+Option+V；图片从源移除、目标字节一致、粘贴按钮禁用，源标签刷新 |
| 废纸篓调用 | Windows Backspace删除测试副本，UI报告成功1、失败0，原目录副本消失。读取系统 `.Trash` 被权限拒绝，尚未确认在废纸篓内定位和恢复 |
| 预览 | 中文UTF-8真实内容、PNG图片、DOCX不支持格式提示；真实类型/大小/时间/路径展示 |
| 隐藏文件 | Cmd+Shift+.显示测试隐藏文件，原选择仍正确 |
| 键盘设置 | Windows/macOS预设切换；录入Cmd+Shift+R并保存，重启后保留且工具栏提示同步；Ctrl+C冲突阻止保存、Esc取消；单项恢复后切回Windows默认 |
| 全屏 | 原生全屏切换成功，最终版本Ctrl+Cmd+F退出成功 |

中文名称提交通过不等于中文输入法组合输入通过。CUA `typeText` 在程序选中文本但未显式点击字段时未可靠修改内容；本次用明确点击和AX设值复核提交，并保留真实IME与F2后直接物理键入的人工验证项。

测试结束后快捷键已恢复 Windows 默认，macOS 重命名覆盖也已恢复。未改用户文件，测试夹具与验收截图保留供复核。

## 自动化验证

| 入口 | 结果 |
|---|---|
| `scripts/test.sh` | 最终25项通过；3项真实卷夹具测试在无夹具运行时明确跳过 |
| `scripts/test-ui-components.sh` | 真实Explorer源码的6项未显示窗口AppKit回归通过：编辑、单次提交、失败保留、Esc取消、中文、失焦提交；不替代屏幕验收 |
| `scripts/test-preview.sh` | 9项通过，包含大小边界、非法UTF-8、图片缩略图、损坏图片、DOCX、HTML纯文本 |
| `scripts/test-filesystem.sh --volumes` | 独立128 MiB APFS镜像实测跨卷移动、只读失败保源、卸载路径报错通过，已卸载清理 |
| `scripts/test-bundle.sh dist/Winway.app` | 独立复制包的34张PNG和icns解码、透明、尺寸、路径通过 |
| `openspec validate create-winway --strict` | 通过 |

文件服务的数据保护边界和逐项场景见 [file-service.md](file-service.md)，键盘实现见 [keyboard.md](keyboard.md)，UI设计来源见 [ui.md](ui.md)。

## 尚未完成的边界验收

- 精确960×600窄窗、横向滚动、标签溢出、框选、Windows Control与macOS Command鼠标多选组合，以及最小化/拖动的完整矩阵。
- 中文IME组合输入、物理Fn/F2、F2后无需鼠标的直接输入、多个焦点上下文连续切换。
- 默认应用打开、外部删除/断卷后UI恢复、快速切换预览的完整竞态矩阵。
- 混合错误/取消/仅重试失败项的完整UI链路，废纸篓内定位与恢复。
- 原生红绿灯视觉位置：截图左上方被系统屏幕共享指示覆盖，不能据此确认其正常未共享时的外观。
- 全部Figma槽位逐像素比对与所有支持系统/架构。

## 截图

[主窗口和文本预览](screenshots/main-accepted.png) · [键盘设置及自定义绑定](screenshots/keyboard-settings.png)

## 复跑

```sh
./scripts/test.sh
./scripts/test-ui-components.sh
./scripts/test-preview.sh
./scripts/test-filesystem.sh --volumes
./scripts/build-app.sh release
./scripts/test-bundle.sh dist/Winway.app
open dist/Winway.app
```
