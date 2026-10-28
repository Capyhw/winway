# FSearch

上游：[noahdunnagan/fsearch](https://github.com/noahdunnagan/fsearch)，许可证见 [LICENSE](LICENSE)。

## Intel 预编译程序

`bin/0.2.1/x86_64/fsearch` 是 Winway 自行编译的 Intel 程序，上游 v0.2.1 只提供 Apple Silicon 预编译包。

- FSearch 版本：`v0.2.1`
- 上游源码提交：`88e63fdf850cf7749deae8198b187accd21f8ba5`
- 来源：[Winway v0.2.5](https://github.com/Capyhw/winway/releases/tag/v0.2.5) 的 `Winway-0.2.5-macos-x86_64.zip`，提取路径 `Winway.app/Contents/Helpers/fsearch`
- 构建与回归记录：[Release macOS](https://github.com/Capyhw/winway/actions/runs/40696598452/job/122844917139)
- Winway 构建提交：`3a568a29645c70300269604c602dedb082dc69d6`
- 架构：`x86_64`；最低 macOS：`13.0`；签名：ad-hoc
- SHA-256：`605255e12a82c2b0ab27f0bc2fc4bf39824e567e2c10f869898e54cee7207f80`

Intel 发布使用仓库中的程序，不需要安装 Rust 或重新编译 FSearch。`scripts/prepare-fsearch.sh` 每次校验 SHA-256、复制到构建目录并验证架构，随后由应用打包脚本重新签名。Apple Silicon 继续下载官方包并校验其固定 SHA-256。

## 更新 Intel 程序

在 Intel Mac 或具备相应交叉编译工具链的环境中，检出目标版本的固定源码提交，使用其 `Cargo.lock` 构建：

```sh
MACOSX_DEPLOYMENT_TARGET=13.0 RUSTFLAGS='-C target-cpu=x86-64' \
  cargo build --release --locked --target x86_64-apple-darwin
```

将产物放入新版本目录；如需签名，应先签名再生成 `fsearch.sha256`。同步更新本文件的来源、源码提交、校验值以及 `scripts/prepare-fsearch.sh` 中的版本和 Apple Silicon 校验值。发布前运行 Intel 打包、签名校验与真实搜索回归；禁止仅修改校验文件来绕过损坏文件检查。
