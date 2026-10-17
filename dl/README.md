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

## 获取方式（`scripts/fetch-vendor.sh`）

先澄清一件事：**构建不需要你预先解压**。这 4 个 tarball 走 OpenWrt 标准
`PKG_SOURCE` 流程 —— 只要文件出现在 `dl/` 里，`include/download.mk` 就会用本地
文件，真正的解压发生在**编译时**、落到 `build_dir/.../PKG_BUILD_DIR`
（`mt_wifi7` / `warp` 的 Makefile 还用 `TAR_CMD` 定制了解压落点）。
所以脚本唯一的职责就是「让文件出现在 `dl/`」。

六种来源，可叠加（已存在的文件默认跳过）：

```bash
# ① 本地 SDK 目录（推荐）
scripts/fetch-vendor.sh /path/to/mtk-wifi-sdk/dl
scripts/fetch-vendor.sh --from /path/to/mtk-wifi-sdk/dl        # 同上，显式写法

# ② 逐文件下载（从同一目录/基础 URL 按文件名取）
scripts/fetch-vendor.sh --base-url https://mirror.example.com/higo
DL_BASE_URL=https://mirror.example.com/higo scripts/fetch-vendor.sh    # 环境变量写法

# ③ 一个「大归档」里装着这几个 tarball → 自动解压 + 按文件名挑出来
scripts/fetch-vendor.sh --archive vendor-sdk.tar.gz             # 本地归档
scripts/fetch-vendor.sh --archive https://host/vendor-sdk.zip   # 远程归档
scripts/fetch-vendor.sh --archive mt7993_20250919-39602c.tar.xz # 给的就是目标文件本身也行

# ④ 私有 GitHub Release 资产
scripts/fetch-vendor.sh --gh-repo owner/higo-vendor-dl --gh-tag v1.0.0

# ⑤ 只报告缺哪些（CI 里可以用来提前失败）
scripts/fetch-vendor.sh --list-missing

# ⑥ 顺手把 PKG_HASH 的 skip 升级成真实 sha256（会改 5 个 Makefile，请 review 后再提交）
scripts/fetch-vendor.sh --archive vendor-sdk.tar.gz --set-hashes
```

其他要点：

- `--force` 已存在也覆盖；`DL_DIR=<dir>` 换目标目录（默认 `./dl`）。
- 归档支持 `.tar` / `.tar.gz` / `.tar.xz` / `.tar.bz2` / `.tar.zst` / `.zip`，
  并且**支持套一层**（归档里还有归档）。内部按**文件名精确匹配**，
  所以归档里的目录层级怎么排都行。
- 结束后会按实际存在的文件重写 `dl/SHA256SUMS`；**缺文件时以退出码 2 明确失败**并列出缺哪几个。
- 也可以完全手工拷：
  ```bash
  cp /path/to/mt7993_20250919-39602c.tar.xz /path/to/warp_20250919-9c1cfa.tar.xz \
     /path/to/mt_wifi_osal-a53418.tar.xz  dl/
  ```

放好之后，`scripts/build.sh` 会把它们拷到 `build/openwrt/dl/`（**总是覆盖**，
这样构建目录里的旧文件不会与新的 `SHA256SUMS` 对不上而报出难查的校验失败）。

## CI

推荐放一个**私有** Release / 仓库（如 `owner/higo-vendor-dl`），由 workflow 用 secret
`VL_REPO` + `VL_TOKEN` 拉取；或在构建环境里设 `DL_BASE_URL`（脚本会 `curl` 下载）。
**不要提交到公共仓库。**

## 校验

`dl/SHA256SUMS` 用于构建前校验 tarball（`scripts/build.sh` 会执行）。

各 Makefile 里的 `PKG_HASH` 只有两种合法取值：
- **真实 sha256** —— `datconf` 用它（该包已入库，哈希确定）
- **字面量 `skip`** —— 3 个 MTK 专有包默认用它，这样把 tarball 丢进 `dl/` 就能直接构建

⚠️ **绝不能留空**：空值会被 `download.mk` 当成哨兵 `x`，`download.pl` 直接报
`Cannot find appropriate hash command`，**即使 `dl/` 里已有文件也失败**。

生成/更新清单，并**顺带把 `skip` 升级成真实 sha256**（更严格，推荐做一次）：

```bash
scripts/set-vendor-hashes.sh
```
