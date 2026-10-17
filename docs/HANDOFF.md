# 工作交接（HANDOFF）

> 给「下一次继续这个项目的人（或未来的你）」看的一页。记录了背景、已完成、关键信息、如何继续。

---

## 0. 背景与目标

- 原始仓库 `~/Workspace/higowrt`（HiGoWRT）：**官方 OpenWrt `4ccb782af7`（r32933，25.12，内核 6.12）+ MTK MT7987/MT7992 Wi-Fi7 闭源驱动栈移植**，支持 Hiveton H5000M、TP-Link TL-7DR7230。
- **本仓库已收窄为只支持 Hiveton H5000M**（MT7987A + MT7992，eMMC）：删掉了 TL-7DR7230（MT7988）的 DTS / 设备定义 / defconfig / CI 项；共享的 MTK 驱动代码原样保留（不做编译验证不了的风险裁剪）。
- 问题：原始仓库把整棵 OpenWrt 树压成**一个提交**导入（无上游父提交），无法 rebase/merge 上游，也看不出「哪些是官方、哪些是自制」。
- 目标：**新开一个「增量仓库」= 尽可能贴近官方 + 只保留必要修改 + 流水线自动化构建**。

---

## 1. 本次已完成

### 1.1 分析（相对官方 OpenWrt `4ccb782af7`）
- 全树 **503 文件不同 = 488 新增 / 14 修改 / 1 删除**。
- 14 处修改里除「品牌 4 处 + `wifi-scripts` 1 行 hack」外，**全是文件末尾追加**。
- 新增：`package/mtk` 317、`target/linux/mediatek` 147、主题 17、其余 7。
- 说明：`MIGRATION_ISSUES.md` 提到的 `immortalwrt-hiveton-mt-6.6` 是**厂商分支**；immortalwrt 官方现在已到 6.18 且**不带 MTK 闭源栈**，所以现实可跟随的上游只有**官方 OpenWrt**。
- 详细分级清单见 `docs/MANIFEST.md`。

### 1.2 搭建增量仓库 `~/Workspace/higo-openwrt`
- Overlay 模型：构建时拉官方源码 + 覆盖 `overlay/` + 打 `patches/` + 用 `configs/`。
- **已实测验证**：在固定上游提交上，`overlay` + 8 个 `patches` 全部干净应用，最终变更 = 481(overlay) + 12(patch)，与原仓库增量一致（差异仅 `.gitignore`/`README.md` 这类非构建项，以及 8 项已迁移到 `configs//dl//docs/`）。

### 1.3 三项后续工作
1. **裁剪第三方 LuCI**：删除 `luci-app-mwan3helper-chinaroute`、`luci-app-wrtbwmon`、`wrtbwmon`（无人依赖，defconfig 也未启用）。
2. **补 PKG_SOURCE_URL + PKG_HASH**：`mt_wifi7`/`mt_hwifi`/`mt_wifi_osal`/`warp`/`datconf` 五个 Makefile 已加私有镜像 URL 与 `PKG_HASH` 占位；新增 `scripts/set-vendor-hashes.sh` 自动填 sha256。
3. **5G 模组 + 风扇/LED 默认**：
   - `configs/common.extra`：5G 选包（QMI/MBIM/MHI/ModemManager + LuCI proto + Quectel 工具），`build.sh` 自动追加。
   - `docs/5G-MODEM.md`：选包说明 + 设备端验证方法与命令。
   - `overlay/.../usr/bin/higowrt-modem-check`：设备端自检脚本。
   - `overlay/.../etc/board.d/02_higowrt`：WiFi 2G/5G LED 默认触发。
   - `overlay/.../etc/uci-defaults/99-higowrt-fan`：风扇低速下限（保守、不关 thermal）。

### 1.4 收窄为「只支持 H5000M」
- 删除 `configs/mt7988_7dr7230.config`、`overlay/.../dts/mt7988d-tplink-tl-7dr7230-rev1.0-sp2.dts`。
- `patches/0003` 去掉 `tplink_tl-7dr7230-rev1.0-sp2` 设备定义（已重新生成、并实测可干净贴在官方树上）。
- `scripts/build.sh` / `build-docker.sh`：profile 参数**可省略**，省略即 H5000M（传别的值会报错）。
- CI 由「两 profile 矩阵」简化为**单个 job**（顺手修掉了原来 job 级 `if` 用 `matrix` 导致 push/schedule 不构建的 bug）。
- README / MANIFEST / HANDOFF 同步更新。

### 1.5 Wi-Fi SKU 调查结论（重要）
原仓库有两个自相矛盾的说法，本次查清了：

| 来源 | 说法 |
|---|---|
| 原仓库最终 defconfig `defconfig/mt7987_mt7992.config` | `SKU_TYPE="BE5040"`（实际出包的配置） |
| 原仓库提交 `af22d76` | `fix(h5000m): WiFi SKU_TYPE BE3600SDB->BE5040 对齐 imm 修复 EEPROM timeout` —— **原仓库自己踩过 `BE3600SDB` 的坑（EEPROM timeout），后来改回 `BE5040`** |
| `MIGRATION_ISSUES.md` §6.1 | 「h5000m SKU = BE3600SDB」（**这是改动之前的历史记录**，与最终代码不符） |
| 原仓库 README「支持设备」表 | H5000M = MT7992 **(BE3600)**（这是产品速率档位/营销名）；同页「芯片↔SKU」表又写 MT7991→BE5040（自相矛盾） |
| 你提供的设备规格 | MT7992 (BE3600) |

**结论：保持 `BE5040`**，决定性证据是原厂随包数据：

```
overlay/package/mtk/drivers/wifi-profile/files/mt7992-be5400/l1profile.dat
  INDEX0_init_path = /etc/wireless/mediatek/mt7992.5040.1.dat        ← 5040 计划
    └─ BN0_profile_path=.../mt7992.b0.dat ; BN1_profile_path=.../mt7992.b1.dat   ← 双频 b0+b1
```

且 `wifi-profile` 的 install 规则里，`first_card_name=MT7992` 就**无条件**装这套 5040 数据，**不因 `SKU_TYPE` 而变**
→ MTK 对 MT7992 的参考计划本来就是 5040，H5000M 用它自洽。

另外两个常识点（回答「原仓库为什么是 BE5040」）：
- `CONFIG_MTK_WIFI7_SKU_TYPE` 是**驱动包级自由字符串**（`mt_wifi7/config.in`，`default "BE19000"`），
  和 device 选择**没有任何联动**，每个 defconfig 都是手工写死的。
- `make menuconfig` 里的 `Target Profile → Hiveton H5000M` 只决定 DTS/网口/设备包，**不会**帮你选 SKU。

> ⚠️ **仍未上真机验证**：原移植全程在 x86 虚拟机上，Wi-Fi 从未在真实 H5000M 上跑过（见 `MIGRATION_ISSUES.md` §9.9）。
> 因此 `build.sh` 加了 `SKU=<值>` 覆盖开关，实机若发现频段异常，直接 `SKU=BE3600SDB CLEAN_CHIP=1 scripts/build.sh` 出第二个包做 A/B。

### 1.6 与原仓库 HEAD 的一致性核对（已做）
原仓库并非只有一个提交，实际是 `a111f44`（整棵树压一个提交导入）+ 13 个修复提交，**当前 HEAD = `25a3aef`**。
为确认本仓库没漏掉后续修复，逐字节对比过：

| 对比 | 结果 |
|---|---|
| `overlay/` 全部 442 个文件 vs 原仓库同名文件 | 仅 4+1 处有意差异（5 个 Makefile 加了 `PKG_SOURCE_URL`/`PKG_HASH`），其余**完全一致** |
| 对固定上游打完 8 个补丁后的 12 个目标文件 vs 原仓库 | **逐字节一致**（含 LAN/WAN 互换 `eac85b5`） |
| `configs/mt7987_h5000m.config` vs 原仓库 defconfig | 仅少了 2 行指向已删包的 `# ... is not set` |

即后续修复**都已包含**：`b830975`(WED dts) / `c27d511`(HNAT dts) / `fca56ca`(mtketh 属性) /
`af22d76`(SKU→BE5040) / `d01a9b9`(5040 iPA 校准装到 `/lib/firmware/e2p`) /
`a61ff78`(启用原厂 WiFi 用户态栈) / `eac85b5`(LAN/WAN 互换) /
`25a3aef`(LuCI split nil 防护 + 默认纯 WPA2 + 开机自动 `wifi up`)。

### 1.7 文档与配置清晰化
只支持一个设备后，把文档里多余的「选设备」表述清掉，并补齐缺失信息：
- 所有文档里的 `scripts/build.sh h5000m` → `scripts/build.sh`（参数可省略，只说明一次）。
- README 新增「**刷机（H5000M，eMMC）**」章节（U-Boot Web 恢复 / 串口 + `-recovery.itb` 内存启动验证）。
- README「支持设备」改为**表格列出各用途对应的具体文件**（defconfig / DTS / 0003 / 0004 / LED / 风扇）。
- README 说明 `configs/mt7987_h5000m.config` 是 `make menuconfig` 的**完整快照**（7700 行），琐碎但可复现、不建议手改。
- 修正 `docs/5G-MODEM.md` 里「默认不含蜂窝功能」与「`common.extra` 自动追加」的**自相矛盾**表述。
- 修正 `dl/README.md`：区分「3 个需自备」与「1 个已入库的 datconf」，校验改为指向 `scripts/set-vendor-hashes.sh`。
- 清掉 defconfig 里 2 行指向**已删除包**的 `# CONFIG_PACKAGE_{luci-app-wrtbwmon,wrtbwmon} is not set`。
- `MANIFEST.md` 的数量改为裁减后实测值（overlay 442 = mtk 276 + target/linux 149 + 主题 17）。
- 新增 **`AGENTS.md`**：给 AI 助手/维护者的规则书（overlay 铁律 / 改动该放哪 / 验证清单 /
  已查清的关键事实 / 提交规范 / 环境坑），并在 README 目录表登记。

### 1.8 构建环境核查 + 静态验证 + 编译前修复（未编译）

> 目标本来是「装 MTK tarball → 真机编译验证」。**MTK 专有 tarball 暂时拿不到，编译验证顺延**，
> 但把「编译需要什么环境/工具」全部查清并修掉了 6 个编译前就该修的问题。

**构建环境（本机 macOS 27 / Apple Silicon）**

| 项 | 结论 |
|---|---|
| Docker Desktop 4.6.1（2022） | ❌ 太老，在 macOS 27 上后端根本起不来（`docker info` 直接 panic） |
| **Colima 0.10.3 + docker CLI 29.9.1** | ✅ 已安装（`brew install colima docker`），用它跑 `scripts/build-docker.sh` |
| 大小写敏感 FS | macOS 不满足 → 必须在 VM 卷里编译；`build-docker.sh` 用 docker 命名卷，设计正确 |
| 资源 | 8 核 / 16 GB / 140 GB 可用，够用（Colima 给 6 核 12 G） |
| `gh` CLI | 未安装（只有用 CI / 私有 Release 时才需要） |

**脚本里查出并修掉的问题**

1. 🔴 `scripts/build-docker.sh`：apt 装了 `gcc-multilib g++-multilib`，**arm64 上不存在** →
   容器里 apt 直接失败。已改为按 `dpkg --print-architecture` 条件安装。
2. 🟡 `scripts/build.sh`：tarball 校验用 `shasum -a 256`，但**这步在容器里跑**，
   Ubuntu 基础镜像不一定有 `shasum`（属 `perl` 包）→ 已改为优先 `sha256sum`，回退 `shasum`。
   `scripts/fetch-vendor.sh` 同样处理。
3. 🟡 apt 列表漏了 **`patch`**（`build.sh` 的补丁回退分支要用）→ 已补。
4. ⚪ 官方旧文档里的 `python3-distutils` 在 24.04 已删除，**不能加**（本仓库脚本里本来就没有）。

5. 🔴 **容器里以 root 编译必须带 `FORCE_UNSAFE_CONFIGURE=1`**（`build-docker.sh` 已加）。
   首次真跑构建时在 `tools/tar` 挂掉，报错是 GNU tar 自己的检查：
   `configure: error: you should not run configure as root (set FORCE_UNSAFE_CONFIGURE=1 ...)`。
   官方 `openwrt/sdk` 镜像也是这么绕过的；非 root 身份编译无此问题。

**配置侧修复（编译前就该修）**

6. 🔴 **补 `/usr/bin/lua`**：`/sbin/wifi` = `wifi_jedi`，是 `#!/usr/bin/env lua` 脚本，
   而 `/etc/init.d/boot:58` 会无条件执行 `/sbin/wifi config`；原 defconfig 里
   `CONFIG_PACKAGE_lua` 是关的（`datconf-lua` 只依赖 `liblua`，`liblua` 只装 `.so`；
   LuCI 25.12 是 ucode-only 已不再带 lua）→ **开机 wifi 配置必然失败**。
   已置 `CONFIG_PACKAGE_lua=y`（约 70 KB）。
7. 🧹 **defconfig 归位**：文件 7671–7680 是手工追加的 10 行，与正文里早先的
   `# CONFIG_PACKAGE_xxx is not set` **自相矛盾**（kconfig 后者覆盖前者，所以实际是开的）。
   已把这 10 个开关合并进正文对应位置、删掉尾部 10 行 → 现在**同一符号只出现一次**。
8. 🧹 **删 `knot-resolver` 残留**：`CONFIG_PACKAGE_knot-resolver_dnstap=y` 会带进
   一个完整的递归 DNS 解析器（knot-resolver + knot-libs + luajit + libgnutls + libstdcpp
   + libuv1 + lmdb + libnghttp2 + libprotobuf-c + libfstrm + luasocket，约 5 MB），
   没人用它。已显式关掉。
9. 🧹 **`configs/common.extra` 里 `bsbf-quectel-usbnet` 是个不存在的包名**
   （主树 / 24.10 feed 索引都查不到）→ 写不存在的符号会被 `make defconfig` **静默丢弃**，
   已删除；`quectel-timesync` 确认存在于 feed，保留。

**静态验证结论（不用编译也能查）**

- defconfig + `common.extra` 里 181 个包名逐个核对：**没有拼写错导致构建失败的**。
  `mt7987-2p5g-phy-firmware` 真有（`package/firmware/linux-firmware/mediatek.mk:100`）；
  `kmod-mt_wifi_osal` 由 `KernelPackage/$(PKG_NAME)` 宏生成，存在。
- `CONFIG_PACKAGE_TAR_*` 6 个符号看着可疑，实际是 feed 里 `tar` 包的 `config` 子项
  （`default y`、不依赖父包），属正常，不是残留。
- `trusted-firmware-a-mt7981-*` 等 7 个其它 SoC 的 TF-A **只进 `BIN_DIR`/staging、
  不进 rootfs**，只影响构建时间（**已在 §1.9 验证并关闭**）。

---

### 1.9 真实编译验证（已完成）

> 专有 tarball 仍然拿不到，但用**半量验证**跑通了整条链路：临时关掉 10 个依赖那 3 个
> tarball 的 vendor kmod，其余全部真编。**结论：除 vendor tarball 本身，什么都不缺。**

**环境结论：不需要再装任何工具。** `build-docker.sh` 里那套 apt 包
（`build-essential clang flex bison g++ gawk gettext git libncurses-dev libssl-dev
python3-setuptools rsync unzip zlib1g-dev file wget qemu-utils ccache libelf-dev patch sudo`）
在 arm64 Ubuntu 24.04 上就是 OpenWrt 要求的全集，多一个也不用。两个真正的坑都不是
「缺包」：`FORCE_UNSAFE_CONFIGURE=1`（root 身份编译，已修进脚本）、
VM 内存偏小导致 `-j6 × -j6` 过订阅偶发失败（用 `JOBS=4` 规避）。

**真实产物（半量验证版本，无 Wi-Fi 驱动）**

| 项 | 值 |
|---|---|
| 装机包数 | 213 |
| rootfs 解压后 | 40.5 MB |
| `…-initramfs-recovery.itb` | 11.4 MB |
| `…-squashfs-sysupgrade.bin` | 12.1 MB |

> 加上 `mt_wifi.ko`(≈45 MB) 后，真实 rootfs 约 85 MB。

**rootfs 体积分布（实测）**

| 位置 | 体积 |
|---|---|
| `/usr/lib` | 17.1 MB |
| `/usr/sbin` | 6.8 MB |
| `/lib/modules` | 2.8 MB |
| `/www`（LuCI） | 1.8 MB |
| `/etc`（含 `wifi-profile` 的 728 KB `.dat`） | 1.3 MB |

单文件最大的是 **5G 管理栈**：`libqmi-glib.so` 3.2 MB、`ModemManager` 2.5 MB、
`libgio` 1.8 MB、`libglib`/`libmm-glib` 各 1.2 MB、`libmbim-glib` 0.9 MB、
`/lib/network/wwan` 1.4 MB，合计 **≈12 MB（rootfs 的 30%）**。
这块**刻意不动**：等真机确认模组走 QMI 还是 MBIM/MHI 之后再砍。

**本轮精简 / 修正**

1. 🧹 **关掉 7 个 `trusted-firmware-a-mt798{1,6,7,8}-ram-*`**。实测它们只把
   `*-bl2.bin` 散落到 `bin/targets/`，**既不进 rootfs、也没有任何设备引用**
   （H5000M 设备定义只用 FIT，刷机流程明确不动 bootloader）。纯构建时间浪费。
2. 🧹 **移除 `kmod-sfp`**。H5000M 的 DTS 里**没有任何 sfp 节点**（4 个口都是
   `2500base-x` + 真实 2.5G PHY），设备定义里那个是从 MTK 参考设计抄来的。
   `patches/0003` 与 config 同步清掉（含 `CONFIG_DEFAULT_kmod-sfp`）。
3. 🔴 **`f2fsck` 纠正为 `=y`**。设备定义一直声明 `e2fsprogs f2fsck mkf2fs`（官方
   filogic 设备普遍是这个三件套），但这份 config 把它关着 → `profiles.json` 对外
   声明有、镜像里却没有。`f2fsck` 不只给 `fsck.f2fs`，还有 **`resize.f2fs`**
   （f2fs overlay 首启扩容要用），属真缺口而非可选项。
4. 🔴 **`build-docker.sh` 拷贝产物前先清空 `artifacts/`**。命名卷是持久化的，
   `bin/targets` 只增不减：被 config 关掉后不再生成的包（`kmod-sfp-*.apk`）和
   `*-bl2.bin` 会一直躺在 `artifacts/` 里，可能混进发布物。顺带把原来的
   `cp ... || true` 改成「找不到 manifest 就报错退出」，不再静默吞掉失败。

**顺带确认「不能砍」的两个包**（差点误删，已逐个查过调用方）

| 包 | 为什么必须留 |
|---|---|
| `wireless-tools` | 原厂 `/sbin/wifi`（=`wifi_jedi`，Lua）里直接调 `iwconfig` |
| `ubi-utils` | `package/base-files/files/lib/upgrade/nand.sh` 里调 `ubiformat` 等 |

**验证方法与残留说明**：`bin/targets` 是增量目录，`profiles.json` 的生成脚本
（`json_overview_image_info.py`）在**版本号不变时会沿用旧文件**（上游设计），
所以增量构建里它的 `device_packages` 可能滞后。判断配置是否真的生效，应以
`make` 产出的 `.manifest` 和 `tmp/.targetinfo` 为准；干净构建（CI）没有这个问题。

**「无 vendor tarball」半量验证构建怎么做（可随时复现）**

```bash
# 1) 造 3 个占位 tarball —— build.sh 只检查这 4 个文件「存在」，
#    而 dl/SHA256SUMS 里目前只有 datconf，所以占位文件不会被校验内容。
for f in mt7993_20250919-39602c.tar.xz warp_20250919-9c1cfa.tar.xz \
         mt_wifi_osal-a53418.tar.xz; do echo placeholder > "dl/$f"; done

# 2) 关掉依赖那 3 个 tarball 的 10 个 vendor kmod
#    （写进 configs/h5000m.extra，build.sh 会自动追加；该文件已在 .gitignore 里）
cat > configs/h5000m.extra <<'EOF'
# CONFIG_PACKAGE_kmod-mt_wifi7 is not set
# CONFIG_PACKAGE_kmod-mt_wifi_osal is not set
# CONFIG_PACKAGE_kmod-mt_hwifi is not set
# CONFIG_PACKAGE_kmod-warp is not set
# CONFIG_PACKAGE_kmod-mtk_pci is not set
# CONFIG_PACKAGE_kmod-mtk_wed is not set
# CONFIG_PACKAGE_kmod-connac_if is not set
# CONFIG_PACKAGE_kmod-mt7992 is not set
# CONFIG_PACKAGE_kmod-mt7992_dbg is not set
# CONFIG_PACKAGE_kmod-mt799a is not set
EOF

scripts/build-docker.sh
```

⚠️ 这样出的镜像**没有 Wi-Fi 驱动，只能用来做编译验证，不能刷机**。验证完记得
把 `configs/h5000m.extra` 和 `dl/` 里的占位文件删掉。

### 1.10 专有 SDK 从哪来 + 一条可能不需要它的路线（2026-10-17 查证）

**那 3 个 tarball 的真实出处**（以后找料照这个找）：

```
SDK 包名: mtk-wifi-mt7987-mt7990-mt7992-mt7993-v8.3.1.3_SDK-20250919-external.tar.xz
SHA256  : e1814c2a6726fcf694e452ffc6959a26cf8d5ab0218a246b821ecda3ebbd0119
          （那 3 个 tarball 就在这个包的 dl/ 目录里，另附 Release Note PDF）
官方源  : https://git01.mediatek.com/openwrt/feeds/mtk-openwrt-feeds
          ⚠️ 实测 HTTP 401 —— 需要 MTK **授权账号**，没有任何公开下载地址
```

已搜过 GitHub / OpenWrt 论坛 / iopsys 镜像，以及本机（含废纸篓、其它卷）和原仓库
`higowrt/dl/`：**都没有**。原 README 当年写的就是 `cp /path/to/...`，说明原作者也是从
别处拿的。可行途径：

1. **找 H5000M 移植的作者 / 供应商要**（最实际，他手上一定有）。
2. 问 Hiveton（整机厂）或 MT7992 模组厂要对应 SDK 发布。
3. 向 MTK 申请 SDK 授权（一般需 NDA / 客户身份）。

拿到 SDK 包后**一条命令即可**（`--archive` 会自动解压并挑出那 3 个文件）：

```bash
scripts/fetch-vendor.sh --archive mtk-wifi-mt7987-mt7990-mt7992-mt7993-v8.3.1.3_SDK-20250919-external.tar.xz --set-hashes
```

**另一条路线：改用主线开源 `mt76`（SoftMAC），完全不需要这些文件。**

- 我们锁定的 OpenWrt 版本里**已经带了** `kmod-mt7996e`（驱动，覆盖 MT7990/7992/7996）
  + `kmod-mt7992-firmware`（含 `mt7992_eeprom.bin` 等），**全部公开可下载**；
  而 defconfig 里这些是 `is not set`，走的是闭源 `kmod-mt_wifi7`。
- **MTK 自己的 Release Note**（`Mediatek Upstream SoftMAC WiFi Driver - MT76 Release Note`）
  明确列出：`Filogic860/MT7992 802.11a/b/g/n/ac/ax/be BE7200/BE5000 2.4/5G PCIe Chip`，
  默认 EEPROM = `mt7992_eeprom.bin` → **MT7992 + 主线 mt76 是 MTK 官方支持的组合**。
- 旁证：`openwrt/mt76` issue #1078 有人贴出 MT7992E 在 mt76 下完整的 2.4G+5G
  `iw phy0 info`（HE/EHT 齐全）；mt76 上游 2025-11 仍在提交
  `mt7996: fix implicit beamforming support for mt7992` 一类的修复。
- H5000M 的 `&pcie0`/`&pcie1` 都是 `okay`，而 MT7992 是 PCIe 设备 → 具备切换条件。

风险（**必须真机验证**）：

| 项 | 说明 |
|---|---|
| 校准数据 | 用公开的 `mt7992_eeprom.bin`（参考板默认值）；若 H5000M 的出厂校准存在专有格式里，功率/速率可能不对 |
| 已知 bug | 5G 160MHz 高信道（≥149）可能被误判为 6GHz（openwrt#20519）；低信道正常 |
| 功能面 | 失去 `mwctl`/`luci-app-mtk`/MTK 专有 MLO；UI 走标准 OpenWrt |
| 无法本地验证 | 无真机 → 只能做到"编译出镜像 + 写 DTS"，跑起来看 `dmesg` 得靠真机 |

闭源 vs 开源的大致差异：闭源在峰值吞吐与多客户端 offload 上略优（量级 10~20% 以内）、
厂验更稳、功能最全，但**绑定 SDK 指定的内核版本**，且**拿不到包就完全无法构建**；
mt76 体积小（省掉 ≈12 MB 的 mt_wifi7/mwctl/datconf/luci-app-mtk 整套）、可跟随内核升级、
可审计、CI 友好。

---


## 2. 仓库结构 `~/Workspace/higo-openwrt`

```
upstream.env                 # 上游仓库 + 固定 ref（唯一跟随上游入口）
overlay/                     # 覆盖进官方树的新增文件
  package/mtk/               #   MTK 闭源驱动栈 + 原厂工具（已裁掉 3 个第三方 LuCI）
  package/luci-theme-higowrt/
  target/linux/mediatek/     #   板级 DTS + files-6.12 源 + patches-6.12
patches/                     # 对官方已有文件的 8 个补丁
configs/                     # mt7987_h5000m.config（唯一 profile）/ common.extra
dl/                          # 专有 tarball（大文件不入库）+ SHA256SUMS
scripts/build.sh             # 一键构建
scripts/build-docker.sh      # Docker 构建（macOS/Windows）
scripts/fetch-vendor.sh      # 收集/下载/解压归档 → dl/ + 生成校验和
scripts/set-vendor-hashes.sh # 计算并回填 PKG_HASH
docs/                        # MANIFEST / MIGRATION_ISSUES / 5G-MODEM / HANDOFF(本文件)
.github/workflows/build.yml  # CI 单 profile 构建 + Release
```

远端：`git@github.com:caozenx/higo-openwrt.git`（公开，分支 `main`）。

---

## 3. 关键信息（务必知道）

| 项 | 值 |
|---|---|
| 上游 pin | `upstream.env: OPENWRT_REF=4ccb782af7194604ee6cc3496e86fdb47f134cec`（= 原仓库 `version` 里的 `r32933-4ccb782af7`） |
| 内核 | 6.12（`config-6.12`） |
| 设备（**唯一**） | H5000M = MT7987A + MT7992，`SKU_TYPE=BE5040`，`WARP_CHIPSET=mt7987`，`WARP_VERSION=3_1`，eMMC 启动 |
| Wi-Fi SKU | `BE5040`（理由见 §1.5）；可用 `SKU=... scripts/build.sh` 覆盖；**未上真机验证** |
| 编译期单值 | `CONFIG_WARP_CHIPSET` / `CONFIG_WARP_VERSION` / `CONFIG_MTK_WIFI7_SKU_TYPE` 都是单值 → 改之前先 `CLEAN_CHIP=1` |
| 闭环 feed | `feeds.conf.default` 用 **hash 固定**（patch 0002），比上游分支名更可复现 |
| 原厂管理栈 | defconfig 当前启用 `wifi-profile`(原厂 `/sbin/wifi`) + `luci-app-mtk` + `datconf` + `mwctl`；如改回标准栈，需删 `patches/0008` 及上述包 |

### 3.1 专有 tarball（构建硬前提，不入库）
放到 `dl/` 或私有镜像：

| 文件 | 被哪些包用 |
|---|---|
| `mt7993_20250919-39602c.tar.xz` | `mt_wifi7`、`mt_hwifi`（**共用**） |
| `warp_20250919-9c1cfa.tar.xz` | `warp` |
| `mt_wifi_osal-a53418.tar.xz` | `mt_wifi_osal` |
| `datconf-757f9679.tar.bz2` | `datconf`（已在 `dl/`，13KB） |

来源：MTK `mtk-wifi-mt7987-mt7990-mt7992-mt7993-v8.3.1.3` SDK 的 `dl/`。
**CI 必须能拿到**：用私有 Release（workflow 里的 secret `VL_REPO` / `VL_TOKEN`）或 `DL_BASE_URL`。

### 3.2 8 个补丁（`patches/`）
`0001` 品牌（可用 `NO_BRAND=1` 跳过）/ `0002` feeds 固定 / `0003` 设备定义 / `0004` H5000M 网口 / `0005` filogic kernel config / `0006` generic kernel config / `0007` mtkhnat 包 / `0008` wifi-scripts 让 `/sbin/wifi`。

---

## 4. 如何继续（常用命令）

```bash
cd ~/Workspace/higo-openwrt

# 备好专有 tarball（任选一种；详见 dl/README.md）
scripts/fetch-vendor.sh /path/to/mtk-sdk/dl            # 本地 SDK 目录
scripts/fetch-vendor.sh --archive vendor-sdk.tar.gz    # 大归档 → 解压挑文件
scripts/fetch-vendor.sh --base-url https://host/dir    # 逐文件下载
scripts/fetch-vendor.sh --list-missing                 # 只报告缺哪些
scripts/fetch-vendor.sh --from /path/to/mtk-sdk/dl --set-hashes   # 顺便回填真实 sha256

# 构建（默认带品牌 + 5G 选包）；参数 h5000m 可省略
scripts/build.sh
# macOS / Windows：     scripts/build-docker.sh
# 尽量贴近官方：        NO_BRAND=1 scripts/build.sh
# 换 SKU 做 A/B：       SKU=BE3600SDB CLEAN_CHIP=1 scripts/build.sh
# 仅本地文件不做下载：保持 PKG_SOURCE_URL 为 example.com 亦可，只要 dl/ 里有 tarball

# 产物
ls build/openwrt/bin/targets/mediatek/filogic/
```

跟随上游：改 `upstream.env:OPENWRT_REF` → 跑 `scripts/build.sh`。若 `patches/` 报 FAIL，用 `git apply --3way` 或手工 rebase 那一个（都是追加式，冲突小）。

CI：`.github/workflows/build.yml` 支持手动触发 / 每周定时 / 打 `v*` tag → 出 `sysupgrade`、`recovery`、`sha256sums` 并建 Release。

---

## 5. 待办 / 未验证（下次优先）

- [x] ~~半量验证构建~~：**已完成**（见 §1.9）。整条链路（tools / toolchain / 内核 / DTS /
      全部补丁 / feeds / LuCI / 5G 选包 / 镜像打包）真编通过，并拿到真实包清单与体积。
- [ ] **完整编译（带 10 个 vendor kmod）仍未做**：缺的就是那 3 个 MTK 专有 tarball
      （本机没有、MTK 官方 feed 需授权、公开镜像 `mediatek/mtk-openwrt-feeds` 不含
      wifi7/osal/warp 源码）。**它们来自
      `mtk-wifi-mt7987-mt7990-mt7992-mt7993-v8.3.1.3_SDK-20250919-external.tar.xz`
      （SHA256 `e1814c2a…0119`）的 `dl/` 目录**，拿料途径见 §1.10。
      **拿到后第一件事：`scripts/fetch-vendor.sh --archive <SDK包> --set-hashes`
      → 删掉临时片段 `configs/h5000m.extra` → `scripts/build.sh`**（见 §3.1）。
      若拿到的是已经在 `dl/` 里的 3 个文件，直接 `--from <dir> --set-hashes` 即可。
- [ ] **上真机验证 Wi-Fi SKU**：默认 `BE5040`；若频段异常，用 `SKU=BE3600SDB CLEAN_CHIP=1 scripts/build.sh` 出第二包 A/B（见 §1.5）。
- [ ] 把专有 tarball 放到私有 Release，并在 GitHub 配好 secret `VL_REPO`/`VL_TOKEN`（或设仓库 Variable `SKU` 切换 SKU）。
- [ ] `patches/0006` 把 `MEDIATEK_NETSYS_*` 放进 `generic/config-6.12`（影响所有 target），可评估只留在 `mediatek/filogic`。
- [ ] 进一步裁剪 `overlay`（**保守，等上机确认后再做**）：`mt798x-2p5g-phy-firmware-internal`、
      未用到的 DSA/PHY（`mxl862xx`/`mt753x`/`an8855`/`an8801`）、USB xhci-mtk 厂商测试码。
      （纯构建期浪费的 7 个 TF-A 包、以及死重量 `kmod-sfp` 已在 §1.9 处理掉。）
- [ ] **5G 管理栈精简（≈12 MB，占 rootfs 30%）**：已决定**等真机验证过再砍**。届时按
      `higowrt-modem-check` 实测结果决定保留 QMI / MBIM / MHI 中的哪几套。
      备选档位：只留 QMI → 省 `libmbim-glib` 0.9 MB + `umbim` + `kmod-mhi-*`；
      更激进可连 `ModemManager` 2.5 MB + `dbus` 一起砍、改用 netifd 直连 QMI。
- [ ] **评估改写开源 `mt76`（SoftMAC）**（弃 `wifi-profile`/`luci-app-mtk`/`datconf`/`mwctl`，
      删 `patches/0008`）—— 详见 §1.10。要点：MT7992 + 主线 mt76 是 **MTK 官方支持**的组合，
      驱动与固件都公开；改用后可彻底摆脱 3 个专有 tarball、省 ≈12 MB、可跟内核升级。
      待改：defconfig 打开 `kmod-mt7996e` + `kmod-mt7992-firmware`、关掉闭源栈、
      可能要给 DTS 补 Wi-Fi/PCIe 相关节点（当前 DTS 没有任何 Wi-Fi 节点）。
      ⚠️ 校准数据与实机行为**必须真机验证**。
      另：`MIGRATION_ISSUES.md` §7 写着「已禁用 wifi-profile」，但**原仓库最终代码是启用它的**（`wifi-scripts/Makefile` 里那句 `rm -f /sbin/wifi` 就是为它让路），本仓库按**原代码**保留。§7 那段是历史记录，不可作为依据。
- [ ] `NO_BRAND=1` 与 `common.extra` 至少各出一次固件做对比。
- [ ] 5G 模组上机验证：跑 `higowrt-modem-check` 看 USB / 串口 / QMI / MBIM 的实际形态，
      再按上面那条决定精简到哪一档。

---

## 6. 已知坑

1. `PKG_HASH` **绝不能留空**：`include/download.mk` 会把空值当哨兵 `x` 传给 `download.pl`，
   后者直接报 `Cannot find appropriate hash command` —— **即使 `dl/` 里已经有 tarball 也照样失败**。
   已实测三种写法：空值 ❌ ／ 字面量 `skip` ✅ ／ 真实 sha256 ✅。
   所以合法写法只有两种：**真实 sha256**（已验证的包用它，如 `datconf`）或**字面量 `skip`**
   （暂时拿不到 tarball 的 3 个 MTK 包用它；完整性由 `dl/SHA256SUMS` + `build.sh` 兜底）。
   `scripts/set-vendor-hashes.sh` 可随时把 `skip` 升级成真实 sha256。
   ⚠️ 本节早先写的「`skip` 不能用」是**错的**（会误导），已按实测结论更正。
2. `PKG_SOURCE_URL` **非空**才会启用 OpenWrt 的下载规则；为空时「必须有 dl/ 本地文件」。
3. `mt_wifi7` 与 `mt_hwifi` **共享** `PKG_BUILD_DIR`，hwifi 的补丁必须并进 wifi7 的 `patches/`（本仓库已如此）。
4. SKU/CHIP 是编译期单值，换 SKU 或芯片必须 `CLEAN_CHIP=1`（清理 `mt_wifi7`/`warp`）。
5. 链接 `mt_wifi.ko`(≈45MB) 吃内存，建议 ≥8G（CI runner 足够）。
6. LED：若驱动 `MTK_WIFI7_LED_CONTROL_SUPPORT` 自己点灯，`board.d/02_higowrt` 的 netdev 触发可能冲突，不确定就删该文件。
7. 风扇：`99-higowrt-fan` 只写低速下限、**不改 `pwm1_enable`**，不影响 thermal；要停用直接删文件。
8. **增量构建的陈旧产物**：`bin/targets` **只增不减** —— 被 config 关掉后不再生成的包和镜像
   会留在原地（实测残留过 `kmod-sfp-*.apk` 和 7 个 `*-bl2.bin`，并因此混进了 `artifacts/`）。
   更隐蔽的是 `profiles.json`：它的生成脚本 `json_overview_image_info.py` 在**版本号不变时
   会沿用旧文件**（上游设计，见顶层 `Makefile` 的 `WORK_DIR=$(BUILD_DIR)/json_info_files`），
   所以增量构建里它的 `device_packages` 可能是滞后的。**判断配置是否生效要看 `.manifest`
   和 `tmp/.targetinfo`，别信 `profiles.json`**；干净构建（CI）没有这个问题。
9. **不要开 `CONFIG_BUILD_LOG`**：本树的 `CONFIG_BUILD_LOG_DIR` 是空符号，写
   `CONFIG_BUILD_LOG=y` 会被静默丢弃（拿不到日志）；而 `BUILD_LOG` 会给 make 注入 `-d`，
   把日志彻底淹掉。要定位失败包，直接跑
   `make package/<路径>/compile V=s -j1`（datconf 那次就是这么定位的）。
10. **并行度过高会「无声失败」**：12 G 的 VM 上 `-j6` 时，`arm-trusted-firmware-mediatek`
    的某个变体和 `linux-firmware` 都出现过「日志里一行错误文本都没有就直接失败」，
    而 `-j1` 重编就过、`dmesg` 里没有 OOM。遇到这种失败先降并行度重试（`JOBS=4`），
    不要一头扎进代码里找问题。
11. **`openwrt/dl/` 里的旧文件会骗过你**：构建根目录（`build/`）是**持久化**的。
    早期 `build.sh` 的逻辑是「`$O/dl/$f` 已存在就跳过拷贝」，于是换了 `dl/` 里的文件后
    构建树里仍是旧文件，紧接着的 `SHA256SUMS` 校验用的是**新清单** → 报
    「tarball 校验失败」，但**完全不提「你用的是旧文件」**，极难查。
    已改成**总是覆盖**（`cp -f`，几个文件的拷贝开销可忽略）。
12. **macOS 自带的是 bash 3.2**（不支持 `declare -A` / `mapfile`）。
    `scripts/set-vendor-hashes.sh` 早期版本用 `declare -A`，在 `set -u` 下会把
    `[文件名]` 当变量下标解析 → 直接崩 `unbound variable`；而文档恰好让用户在
    macOS 上跑它。已改成 `case` 映射。**新增脚本时不要用关联数组。**
    同源问题：`printf '  %s/%s\n' "$dir" "${arr[@]}"` 会把参数**两两配对**导致输出
    错位（实测踩到），列多项请用 `for` 循环。

---

## 7. 关系图

```
~/Workspace/higowrt        (原始仓库，本次未改动其工作树；仅加了一个只读 remote `upstream`)
        │  分析得到增量
        ▼
~/Workspace/higo-openwrt   (新·增量仓库，方案 A)
        │  构建时
        ▼
  官方 OpenWrt @ OPENWRT_REF  +  overlay/  +  patches/  →  固件
```

> 备注：为做精确对比，原始 `higowrt` 仓库里加过 `git remote add upstream https://github.com/openwrt/openwrt.git`（只读，不影响原有分支）。不再需要可 `git remote remove upstream`。
