# 小米平板 6S Pro 的 macOS 双系统构建

目标为已实测分区的小米平板 6S Pro（`sheng`、SM8550）和 macOS 27.3（`26C5035r`）。macOS 将替代原 Linux，复用原有 GPT 名称 `linux`。HyperOS 继续使用 A 槽及既有 `userdata`。现有 B 槽镜像已在 Windows 主机单独备份。

| 实测项目 | 结果 |
| --- | --- |
| Bootloader | 已解锁，当前槽 A，A 已标记启动成功 |
| 逻辑扇区 | UFS LUN 0，4096 字节，主备 GPT CRC 与条目一致 |
| HyperOS `userdata` | `/dev/block/sda29`，LBA 3,094,784–33,550,847，116.18 GiB |
| macOS 目标 `linux` | `/dev/block/sda30`，LBA 33,550,848–64,006,911，116.18 GiB |
| `boot_b` | 192 MiB，原镜像已用设备端和本机 SHA-256 校验 |
| macOS Data | 构建预留 90 GiB，根卷和诊断区共用 `linux` 分区 |

## 平台种子

平板在 Fastboot 模式时，在 Windows PowerShell 运行以下命令。

```powershell
& 'E:\Projects\UniXNU\out\host-tools\platform-tools\fastboot.exe' getvar cpuid
```

设备返回的 16 位十六进制 CPUID 填入 `UNIXNU_UNIQUE_CHIP_ID`。若输出带 `0x`，去掉前缀并保留所有 16 位。初始 macOS 用户名为 `unixnu`，密码由 `UNIXNU_LAB_PASSWORD` 设置。

## 使用 GitHub 托管 macOS runner

将本目录内容放在 GitHub 仓库根目录，保留 `.github/workflows/`。在仓库 **Settings → Secrets and variables → Actions** 添加 `UNIXNU_UNIQUE_CHIP_ID` 和 `UNIXNU_LAB_PASSWORD`。用 `age-keygen` 生成密钥，在 Actions Variables 中添加公钥 `UNIXNU_ARTIFACT_RECIPIENT`，将私钥保存在本机。再从 **Actions → sheng macOS dual boot → Run workflow** 启动。工作流使用标准 `macos-26` 和 Xcode 26.6。公共仓库的标准 runner 不扣私有仓库的计算额度。

在同一条 Release 草稿中下载加密产物，并校验 `SHA256SUMS`。按文件名顺序拼接 `unixnu-root.img.zst.age.part-*`，用本机 age 私钥解密，再用 zstd 解压得到 `unixnu-root.img`。其余 `.age` 文件可以单独解密。实际目标分区在 `unixnu-root.json` 里应为 `linux`。保留原始 `data.dbr` 供后续更新使用。

上游已有托管 macOS 上完成根镜像步骤的记录。
[上游完整构建记录](https://github.com/UniXNU/UniXNU-sheng/actions/runs/43849817601/job/133260084829) · [GitHub Actions 用量和计费](https://docs.github.com/en/billing/concepts/product-billing/github-actions)

## 本地 WSL2 的范围

WSL2 可运行 UniXNU 的 Linux 工具链，用于源码准备、离线验证及尝试编译 XNU。当前 sheng macOS 首装流程仍调用 macOS 的 `aea` 处理指定 IPSW 的加密根卷，以及 `hdiutil`、`diskutil` 和 `ditto` 生成保留权限的 APFS Data 种子。仅用 WSL2 和仓库源码无法跑通这台设备的完整首装构建。

若有符合版本和哈希要求的已解密根卷、APFS Data 种子及其签名策略输入，Linux 可以继续部分后续处理。本配置尚未在 WSL2 完成整包验证。
[UniXNU 工具链要求](https://unixnu.com/guide/requirements) · [macOS Data 种子](https://unixnu.com/porting/macos#data-seed)

## 在 Mac 上构建

在 Apple Silicon Mac 上准备 Xcode 26.6、Python 3.14 和 Homebrew。预留约 100 GiB 存储空间用于 IPSW、工具链及 XNU 构建树。

```sh
brew install dtc llvm lld llvm@22 lld@22 cmake mtools ninja glslang shaderc \
  spirv-tools bison pkgconf rustup unifdef openssl@3 zstd blacktop/tap/ipsw
rustup toolchain install 1.98.0 --profile minimal --component rust-src
bash build-macos.sh "$PWD/sheng-build"
```

脚本会提示输入平台种子和 macOS 初始密码。预计产物位于 `sheng-build/UniXNU/out/sheng/macos-27.3-26C5035r/sheng_macos/`。

| 文件 | 用途 |
| --- | --- |
| `boot/boot.img` | 可用 Fastboot 单次加载，构建上限 192 MiB |
| `userdata/unixnu-root.img` | 对应 `linux` 的原始根镜像 |
| `userdata/unixnu-root.json` | 目标分区、空间要求和根镜像 SHA-256 |
| `runtime/data.dbr` | 90 GiB 的可写 APFS Data 种子，后续更新时保留 |
| `package.manifest.json` | 源码版本和启动产物哈希 |

## 真机验证

1. 备份还需要的 Linux 文件。写入根镜像会覆盖现有 `linux` 内容。分区大小和位置已核对，可直接复用现有分区。
2. 确认 `unixnu-root.json` 的目标为 `linux`，让镜像 SHA-256 和 `storage_required_bytes` 与实际文件及分区容量相符。将根镜像写入 `linux` 后，优先通过 `fastboot boot boot.img` 单次验证。首次启动选择 **Initialize macOS Data and boot**。
3. 验证桌面、可写 Data 和 HyperOS A 槽仍能启动，再决定是否将新镜像放入 `boot_b`。B 槽的完整启动链尚未验证。

当前完成了 GPT 实机核对、B 槽备份、IPSW 清单预检和三个分区目标的离线解析测试。可刷写镜像尚未生成。
