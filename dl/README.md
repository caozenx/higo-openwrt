# dl/ —— 专有 tarball 存放目录

MTK Wi-Fi7 闭源 SDK 的源码包**不随本仓库分发**（体积 + 授权原因），
但**构建时缺一不可**（缺哪个，对应驱动包就报 `No such file` 编译失败）。

| 文件 | 被哪个包用 | 是否入库 |
|---|---|---|
| `mt7993_20250919-39602c.tar.xz` | `mt_wifi7` + `mt_hwifi`（**共用**） | ❌ 需自备（被 `.gitignore` 忽略） |
| `warp_20250919-9c1cfa.tar.xz` | `warp`（WED 硬件加速） | ❌ 需自备 |
| `mt_wifi_osal-a53418.tar.xz` | `mt_wifi_osal`（OSAL 抽象层） | ❌ 需自备 |
| `datconf-757f9679.tar.bz2` | `datconf`（用户态工具，13 KB） | ✅ **已入库**，无需自备 |

来源：MTK `mtk-wifi-mt7987-mt7990-mt7992-mt7993-v8.3.1.3` SDK 的 `dl/` 目录。

> 所以**真正要你准备的只有 3 个**（前三个）。

## 本地

```bash
# 方式一：从 SDK 目录收集（推荐，会顺带重算 SHA256SUMS）
scripts/fetch-vendor.sh /path/to/mtk-wifi-sdk/dl

# 方式二：自己拷进去
cp /path/to/mt7993_20250919-39602c.tar.xz /path/to/warp_20250919-9c1cfa.tar.xz \
   /path/to/mt_wifi_osal-a53418.tar.xz  dl/
```

放好之后，`scripts/build.sh` 会自动把它们拷到 `build/openwrt/dl/`。

## CI

推荐放一个**私有** Release / 仓库（如 `owner/higo-vendor-dl`），由 workflow 用 secret
`VL_REPO` + `VL_TOKEN` 拉取；或在构建环境里设 `DL_BASE_URL`（脚本会 `curl` 下载）。
**不要提交到公共仓库。**

## 校验

构建前会用本目录的 `SHA256SUMS` 校验 tarball。生成/更新清单**请用脚本**（它会同时把
sha256 回填进各 Makefile 的 `PKG_HASH:=`，让 OpenWrt 的下载机制也能用）：

```bash
scripts/set-vendor-hashes.sh
```
