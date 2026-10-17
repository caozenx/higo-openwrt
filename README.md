# HiGoWRT 增量构建仓库（OpenWrt Overlay / 方案 A）

本仓库**不包含官方 OpenWrt 源码**，只在构建时把「HiGoWRT 的必要增量」贴到官方 OpenWrt 上：

```
官方 OpenWrt @ upstream.env:OPENWRT_REF
  + overlay/          新增文件（MTK 专有驱动、6.12 适配 patch、板级 DTS…）
  + patches/*.patch   对官方文件的少量“追加式”改动
  + configs/*.config  设备 defconfig（只有一个设备）
  + dl/               需自备的专有 tarball（不随仓库分发）
        ↓
  bin/targets/mediatek/filogic/*sysupgrade*  *recovery*
```

优点：仓库极小；「对官方做了什么」= `overlay/` + `patches/` 两个目录，一眼可见；跟随上游只需改 `upstream.env` 里的一个 ref；天然适合 CI 流水线。

---

## 支持设备

本仓库**只支持一个设备**：

| 设备 | SoC | Wi-Fi | 存储 | 平台 |
|---|---|---|---|---|
| **Hiveton H5000M** | MT7987A | MT7992 (Kite) | eMMC | MTK filogic |

各用途对应的文件（**只有一个设备，所以每个用途都只有一份**）：

| 用途 | 文件 |
|---|---|
| 编译配置（defconfig） | `configs/mt7987_h5000m.config` |
| 板级设备树 | `overlay/target/linux/mediatek/dts/mt7987a-hiveton-h5000m.dts` |
| 设备定义（打包/镜像） | `patches/0003-filogic-add-devices.patch` |
| 网口 LAN/WAN 映射 | `patches/0004-filogic-h5000m-network.patch` |
| LED 默认 / 风扇默认 | `overlay/.../etc/board.d/02_higowrt`、`overlay/.../etc/uci-defaults/99-higowrt-fan` |

> 构建时**不需要**传设备名，`scripts/build.sh` 直接就是 H5000M（参数 `h5000m` 可省略，仅为将来加设备留的扩展位）。

> **关于 Wi-Fi 的「BE3600」**：这是产品的 Wi-Fi 速率档位（营销名），**不是**驱动的 SKU 名。
> 驱动实际用的是 `CONFIG_MTK_WIFI7_SKU_TYPE="BE5040"`，依据是原厂随包提供的 MT7992 参考计划
> `overlay/package/mtk/drivers/wifi-profile/files/mt7992-be5400/`（`l1profile.dat` → `mt7992.5040.1.dat` → 双频 `b0`+`b1`）。
> 详见下方「[Wi-Fi SKU](#wi-fi-sku)」。若实机验证发现频段异常，可一行覆盖：
> `SKU=BE3600SDB scripts/build.sh`

---

## 目录

| 路径 | 说明 |
|---|---|
| `upstream.env` | 上游仓库地址 + 固定 ref（**跟随上游只改这里**） |
| `overlay/` | 直接覆盖进官方源码树的新增文件 |
| `overlay/package/mtk/` | MTK 专有 Wi-Fi7 驱动栈 + 原厂工具/LuCI（来源见 `docs/MANIFEST.md`） |
| `overlay/package/luci-theme-higowrt/` | 自研主题 |
| `overlay/target/linux/mediatek/` | 板级 DTS、`files-6.12` 源码、`patches-6.12` 内核补丁 |
| `patches/` | 只对**官方已有文件**做的改动（品牌 / kernel config / 设备定义 / HNAT 包 / 板级网口） |
| `configs/mt7987_h5000m.config` | H5000M 的 **defconfig**（`make menuconfig` 出来的完整快照，7700 行左右；零散选项看着琐碎，但能保证可复现，**不建议手改**） |
| `configs/common.extra` | 可选功能配置片段（当前=**5G 模组**），`build.sh` 在写 `.config` 后自动追加，**默认生效** |
| `configs/<profile>.extra` | 扩展位：按 profile 的额外片段（存在才追加，当前没有此文件） |
| `dl/` | 专有 tarball 存放/校验（大文件不入库，见 `dl/README.md`） |
| `scripts/build.sh` | 本地/CI 一键构建（Linux） |
| `scripts/build-docker.sh` | 在 Docker 容器里构建（macOS/Windows 可用） |
| `scripts/fetch-vendor.sh` | 收集 MTK SDK tarball + 生成校验和 |
| `scripts/set-vendor-hashes.sh` | 计算并回填 `PKG_HASH`（让 OpenWrt 下载机制可用） |
| `docs/HANDOFF.md` | **工作交接**：已完成/待办/关键信息（**下次从这里继续**） |
| `AGENTS.md` | **给 AI 助手/维护者的仓库规则**：铁律、改动该放哪、验证清单、易踩的坑 |
| `docs/MANIFEST.md` | **必要 / 按需 / 可删** 改动清单 + 与原仓库的映射 |
| `docs/5G-MODEM.md` | 5G 模组选包说明 + 设备端验证方法 |
| `docs/MIGRATION_ISSUES.md` | 原仓库带入的**历史档案**（多设备时期的移植问题记录；部分结论已过时，见文首提示） |
| `.github/workflows/build.yml` | CI 构建（单 profile）+ Release |

---

## 编译指引

### 0. 关于「上游」

本仓库**不含** OpenWrt 源码；构建时**自动从官方拉取** `upstream.env` 里固定的版本。
所以：

- ✅ **不依赖原来的 `higowrt` 仓库**，可完全独立构建；
- ✅ 不依赖本地已有一份 OpenWrt（首次构建会自动 clone）；
- ⚠️ 但构建过程**需要联网**去 `github.com/openwrt/openwrt`（或你的镜像）拉源码 + feeds；
- ⚠️ **唯一的外部依赖**是那 3 个 MTK 专有 tarball（见下）。

### 1. 准备专有 tarball（必做）

MTK Wi-Fi7 闭源 SDK 的三个 tarball（**不随仓库分发**，缺一不可），放到 `dl/`：

```bash
cp /path/to/mt7993_20250919-39602c.tar.xz   dl/   # mt_wifi7 / mt_hwifi 共用
cp /path/to/warp_20250919-9c1cfa.tar.xz     dl/   # warp
cp /path/to/mt_wifi_osal-a53418.tar.xz      dl/   # mt_wifi_osal
# 可选：顺便算哈希写回 Makefile（让 CI 的下载校验生效）
scripts/set-vendor-hashes.sh
```

> 来源：MTK `mtk-wifi-mt7987-mt7990-mt7992-mt7993-v8.3.1.3` SDK 的 `dl/` 目录。

### 2. 方式 A：Linux 本机直接编译（推荐）

**环境要求**：Linux x86_64（Ubuntu 22.04/24.04 或 Debian 12）、≥4 核、≥8G 内存（链接 `mt_wifi.ko`≈45MB 较吃内存；不足用 `JOBS=2`）、≥50G 空闲磁盘、能联网。

```bash
# 依赖
sudo apt update && sudo apt install -y build-essential clang flex bison g++ gawk \
  gcc-multilib g++-multilib gettext git libncurses-dev libssl-dev \
  python3-setuptools rsync unzip zlib1g-dev file wget qemu-utils ccache libelf-dev

# 构建（首跑会 clone 上游 + 装 feeds，耗时较长）
scripts/build.sh
# 产物：build/openwrt/bin/targets/mediatek/filogic/
#   *-squashfs-sysupgrade.bin   （正式刷写）
#   *-recovery.itb              （initramfs 内存启动调试）
```

可选环境变量：`BUILD_ROOT`、`DL_DIR`、`DL_BASE_URL`、`JOBS`、
`NO_BRAND=1`（跳过品牌补丁，得到尽量贴近官方的版本）、
`SKU=<值>`（覆盖 `CONFIG_MTK_WIFI7_SKU_TYPE`，默认 `BE5040`，详见下方「Wi-Fi SKU」）、
`CLEAN_CHIP=1`（清理 `mt_wifi7`/`warp` 构建目录后再编）。

> 脚本参数 `h5000m` 可以省略（只有一个设备），写上也等价。

> ⚠️ **不要用 macOS 直接跑 `scripts/build.sh`**：OpenWrt 需要区分大小写的文件系统与 Linux 工具链，macOS 默认文件系统不满足。macOS 请用方式 B。

### 3. 方式 B：Docker 编译（macOS / Windows）

构建目录用 docker **命名卷**（区分大小写），只把产物拷回宿主机：

```bash
# 依赖：一个能用的容器运行时 + dl/ 里先放好专有 tarball
# macOS（Intel/Apple Silicon 均可）用 Colima，一条命令搞定：
brew install colima docker
colima start --cpu 6 --memory 12 --disk 60
# 然后：
scripts/build-docker.sh
# 产物：./artifacts/h5000m/
```

> ⚠️ 别用 2022 年版的 Docker Desktop（4.6.x）：在 macOS 15+ 上后端起不来（`docker info` 直接 panic）。
> Apple Silicon 用 Colima 自带的 aarch64 容器即可，无需 x86 模拟；
> `gcc-multilib`/`g++-multilib` 只对 x86 target 有意义，脚本会按架构自动决定装不装。

可用 `IMAGE=ubuntu:24.04`、`VOLUME=higo-openwrt-build`、`NO_BRAND=1`、`SKU=...`、`DL_BASE_URL=...` 等环境变量。

### 4. 方式 C：GitHub Actions 流水线

`.github/workflows/build.yml`：手动触发 / 每周定时 / 打 `v*` tag 自动构建，产物上传 Artifact，打 tag 时自动建 Release。

**一次性配置**（仓库 Settings → Secrets and variables → Actions）：

| Secret | 说明 |
|---|---|
| `VL_REPO` | 存放专有 tarball 的**私有** Release 所在仓库，如 `caozenx/higo-vendor-dl` |
| `VL_TOKEN` | 对该仓库有读权限的 PAT（用于 `gh release download`） |

> 也可以不用私有 Release：改用 `DL_BASE_URL` 指向任意可下载的镜像（届时在 workflow 里传该环境变量）。

---

## Wi-Fi SKU

`CONFIG_MTK_WIFI7_SKU_TYPE` 决定 MT7992 加载哪一组 band 固件，**与设备选择是两件独立的事**：
`make menuconfig` 里的 `Target Profile → Hiveton H5000M` 只决定 DTS / 网口 / 设备包，
不会自动帮你选 SKU（它是驱动包级的一个自由字符串，`default "BE19000"`）。

本仓库 H5000M 用 **`BE5040`**，依据：

| 证据 | 内容 |
|---|---|
| 原厂 MT7992 参考计划（随包分发） | `wifi-profile/files/mt7992-be5400/l1profile.dat` → `INDEX0_init_path=/etc/wireless/mediatek/mt7992.5040.1.dat` → `BN0/BN1 = mt7992.b0.dat / mt7992.b1.dat`（双频） |
| 该数据安装条件 | `first_card_name=MT7992` 时**无条件**安装，与 `SKU_TYPE` 无关 → 原厂对 MT7992 的默认就是 5040 计划 |
| 原仓库提交 `af22d76` | `fix(h5000m): WiFi SKU_TYPE BE3600SDB->BE5040 对齐 imm 修复 EEPROM timeout` —— 用 `BE3600SDB` 会 **EEPROM timeout**，所以后来改回 `BE5040` |
| 原仓库最终 defconfig | = `BE5040`，也是实际出过包的配置 |

> ⚠️ **未在真机验证**：原移植是在 x86 虚拟机上完成的，Wi-Fi 从未在真实 H5000M 上跑过。
> 若实机出现「频段缺失 / 起不来」，用 `SKU=BE3600SDB CLEAN_CHIP=1 scripts/build.sh` 重新出一包做 A/B 对比
> （`BE3600SDB` 是驱动里 MT7992 的另一套 band 计划，会走 4_1+5_1+6_1 拼接固件路径）。

---

## 刷机（H5000M，eMMC）

产物是 OpenWrt sysupgrade **tar** 格式，只更新 kernel + rootfs 两个分区，**不动 bootloader**（bl2 / u-boot / gpt 保持原样）。

| 方式 | 步骤 |
|---|---|
| **A. U-Boot Web 恢复（推荐首刷）** | 断电 → 按住 reset 上电 → 浏览器打开恢复页面 → 上传 `*-squashfs-sysupgrade.bin` → 等待写入完成自动重启 |
| **B. 串口 + 内存启动（推荐先验证）** | 串口 115200 8N1 进 U-Boot → TFTP 载入 `*-recovery.itb` 内存启动 → 确认 WiFi/网口正常后，系统内 `sysupgrade -n *-squashfs-sysupgrade.bin` 写入 eMMC |

> 首刷建议走 **B** 先确认驱动能起来（`-recovery.itb` 不写 flash，断电即恢复），再刷 sysupgrade。

Wi-Fi 配置走标准 UCI：编辑 `/etc/config/wireless` 后 `wifi up`（LuCI 里「网络 → 无线」同样可以）。

LED / 风扇默认脚本首次启动自动生效，日志见 `logread | grep higowrt`。

---

## 跟随上游

```bash
# 1. 改 upstream.env: OPENWRT_REF=<新 tag 或 commit>
# 2. 验证增量是否仍能贴上
scripts/build.sh
```

若 `patches/` 报 FAIL，说明官方对应文件上下文变了，用 `git apply --3way` 或手工 rebase 那一个补丁即可（都是追加式改动，冲突面很小）。

---

## 约束

- **专有 tarball 不入库**：CI 必须能从私有镜像拿到，否则构建失败。
- **只支持 H5000M**（MT7987A + MT7992）：设备集是 `CONFIG_TARGET_mediatek_filogic_DEVICE_hiveton_h5000m`，
  已不再包含 TL-7DR7230 / MT7988 设备。
- **芯片固定**：`CONFIG_WARP_CHIPSET=mt7987`、`CONFIG_WARP_VERSION=3_1`，不需要也不能在本次构建里改。
- **可变的只有 SKU**：`CONFIG_MTK_WIFI7_SKU_TYPE`（编译期单值）。换 SKU 时要 `CLEAN_CHIP=1`
  （等价于 `make package/mtk/drivers/mt_wifi7/clean package/mtk/drivers/warp/clean`），否则会残留上一次的固件文件。
- 链接 `mt_wifi.ko`(≈45MB) 吃内存，建议 ≥8G；CI runner 16G 足够。
- `patches/` 与 `OPENWRT_REF` 强绑定：ref 一动就要回归。

---

## 当前状态

- ✅ 增量仓库已搭好，并**已验证** `overlay/` + `patches/` 能在固定上游提交上干净应用。
- ✅ **与原仓库一致性已核对**：`overlay/` 442 个文件 + 8 个补丁打完的结果，与原仓库 HEAD `25a3aef` **逐字节一致**
  （仅 5 个 Makefile 加了 `PKG_SOURCE_URL`/`PKG_HASH`，并删了 TL-7DR7230 与 3 个第三方 LuCI）。
- ✅ 已裁剪未使用的第三方 LuCI（`mwan3helper` / `wrtbwmon`）。
- ✅ 已为 5 个包补 `PKG_SOURCE_URL` + `PKG_HASH`（含 `scripts/set-vendor-hashes.sh`）。
- ✅ 已加 5G 模组选包（`common.extra` + `docs/5G-MODEM.md` + 自检脚本）与 风扇/LED 默认脚本。
- ✅ 已把编译环境与工具链查清（macOS 用 Colima）并修掉编译前的 6 个问题：
  `CONFIG_PACKAGE_lua=y`（`/sbin/wifi` 是 Lua 脚本，缺它会开机静默失败）、defconfig 手工尾巴合并归位、
  删 `knot-resolver` 残留（约 5 MB）、删不存在的包名 `bsbf-quectel-usbnet`、
  `build-docker.sh` 在 arm64 装 `gcc-multilib` 必失败、容器里 `shasum` 不可靠。
  详见 `docs/HANDOFF.md` §1.8。
- ⏳ **尚未做完整编译**：3 个 MTK 专有 tarball 暂时拿不到（公开渠道没有，只能自备）。
  拿到后请先跑一次 `scripts/build.sh`。
- ✅ **编译验证已跑通**（用「半量验证」方式：临时关掉依赖那 3 个 tarball 的 10 个 vendor kmod）：
  `tools` / toolchain / 内核 / DTS / 补丁 / feeds / LuCI / 5G 选包 / 镜像打包**全部真编通过**。
  产物为 **213 个包、rootfs 40.5 MB、`-recovery.itb` 11.4 MB、`-sysupgrade.bin` 12.1 MB**。
  **结论：除 vendor tarball 本身，不缺任何构建工具或依赖。** 详见 `docs/HANDOFF.md` §1.9。
- ✅ 已按该次验证做一轮精简：关掉 7 个只产 `*-bl2.bin` 的 TF-A 包、移除死重量 `kmod-sfp`、
  补上 `f2fsck`（设备定义一直声明它，且它提供 `resize.f2fs`）。

下次继续请先读 **`docs/HANDOFF.md`**。改动分级与裁剪建议见 `docs/MANIFEST.md`。
