# Winway 官网

地址：<https://capyhw.github.io/winway/>，通过 GitHub Pages 托管。

## 文件与本地预览

- `website/`：静态 HTML、CSS、JavaScript 和应用图标，无 npm 依赖。
- `docs/screenshots/2026-10-28/`：当前 README 和官网共用的真实应用截图。
- `scripts/build-site.py`：把截图复制到 `.build/site/assets/`，从 GitHub Release 数据填入版本号与两个架构的 DMG 链接。
- `.github/workflows/pages.yml`：构建并部署 `.build/site/`，不上传应用源码或其他构建产物。

在仓库根目录执行：

```sh
gh api repos/Capyhw/winway/releases/latest > /tmp/winway-site-release.json
python3 scripts/build-site.py --release-json /tmp/winway-site-release.json
python3 -m http.server 8080 --directory .build/site
```

打开 <http://localhost:8080>。无需 Node.js 或前端构建工具。下载链接在构建时写入 HTML，访客无需访问 GitHub API；禁用 JavaScript 时，下载、正文、FAQ 仍可使用，截图有直接链接。

## 自动发布

仓库 Settings → Pages → Build and deployment 的 Source 为 **GitHub Actions**。

下列情况触发发布：

- `main` 上官网、当前截图、构建脚本或 Pages 工作流发生变更。
- 手动触发 **Deploy GitHub Pages**。
- 发布 Release，或 **Release macOS** 工作流成功完成。

`workflow_run` 用于覆盖默认 `GITHUB_TOKEN` 发布 Release 不会再触发 `release` 工作流的情况。网站始终从 `main` 构建，并读取 `/releases/latest` 的稳定版本；失败、预发布或仅手动构建不会将未发布安装包作为下载目标。新正式版本发布成功后，无需手改版本号和安装包链接。

构建必须找到两个架构的已上传 DMG，否则失败并保留线上站点。发布权限仅在部署作业授予 `pages: write` 与 `id-token: write`，不需要额外 secrets。应用发布流程保持独立。

## 更新截图

重新运行当前构建，用专门准备的示例文件拍摄真实界面。新建日期目录，记录源码提交、环境和截图含义，然后同步修改 README、`build-site.py` 的 `SCREENSHOTS` 路径、工作流的截图路径过滤和本说明。历史验收截图保留原路径。
