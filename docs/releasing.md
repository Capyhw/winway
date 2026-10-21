# GitHub Release 打包

工作流为 `.github/workflows/release.yml`，名称 **Release macOS**。

## 手动检查打包

在 GitHub Actions 选择 **Release macOS → Run workflow**。手动运行只构建和上传 Actions artifacts，不创建标签或发布 Release；产物保留 14 天。

```sh
gh workflow run release.yml --ref main
```

## 发布版本

确认待发布代码已经推送，再为该提交创建版本标签：

```sh
git tag -a v0.1.0 -m 'Winway v0.1.0'
git push origin v0.1.0
```

每次发布使用新版本号，不移动或覆盖已经发布的标签。支持 `v0.1.0-rc.1` 这类预发布标签，自动标记为 Pre-release。版本标签覆盖打包副本的 `CFBundleShortVersionString`（只写入数字部分），构建编号来自 Actions 的 `GITHUB_RUN_NUMBER`，不会自动改写仓库中的 `Packaging/Info.plist`。手动构建则使用该文件中的版本号。

工作流分别在 `macos-15`（Apple Silicon）和 `macos-15-intel`（Intel）上使用 Xcode 26.3 原生构建，执行核心测试、打包资源校验、签名校验和标签/UI 组件回归。两套构建均通过后才发布 Release，并附自动生成的变更说明及签名状态说明。

每个架构生成三个文件：

- `Winway-<版本>-macos-<架构>.zip`
- `Winway-<版本>-macos-<架构>.dmg`
- `Winway-<版本>-macos-<架构>.sha256`

ZIP 会重新解压并检查应用资源和签名，并执行解压后程序的 `--check-resources` 自检，确保生产资源定位指向应用包内部。DMG 使用 `hdiutil verify` 校验。发布前再次核对两个架构的 SHA-256。已发布版本不会被流水线覆盖，重复发布同一标签会失败；应使用新版本标签。

## 本地复现

```sh
./scripts/package-release.sh v0.1.0
# 较旧的 Xcode SwiftPM 可使用 native 后端：
WINWAY_BUILD_SYSTEM=native ./scripts/package-release.sh v0.1.0
```

输出位于 `dist/release/`，本地只生成当前 Mac 架构的包。当前流程仅使用 ad-hoc 签名，无需额外 GitHub secrets；发布作业通过 GitHub 自带的 `GITHUB_TOKEN` 获取 `contents: write` 权限。尚未接入 Apple Developer ID 签名与公证，无法承诺下载后免安全提示。

参考：[GitHub 工作流权限](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#permissions)、[macOS runner 镜像](https://github.com/actions/runner-images#available-images)。
