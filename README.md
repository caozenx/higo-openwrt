# HiGoWRT 增量构建仓库（OpenWrt Overlay / 方案 A）

本仓库**不包含官方 OpenWrt 源码**，只在构建时把「HiGoWRT 的必要增量」贴到官方 OpenWrt 上：

```
官方 OpenWrt @ upstream.env:OPENWRT_REF
  + overlay/          新增文件（MTK 专有驱动、6.12 适配 patch、板级 DTS…）
  + patches/*.patch   对官方文件的少量“追加式”改动
  + configs/*.config  各设备 defconfig
  + dl/               需自备的专有 tarball（不随仓库分发）
        ↓
  bin/targets/mediatek/filogic/*sysupgrade*  *recovery*
```

优点：仓库极小；「对官方做了什么」= `overlay/` + `patches/` 两个目录，一眼可见；跟随上游只需改 `upstream.env` 里的一个 ref；天然适合 CI 流水线。

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
| `configs/` | 两个 profile 的 defconfig（H5000M / TL-7DR7230） |
| `configs/common.extra` | 可选功能配置片段（当前=**5G 模组**），`build.sh` 自动追加 |
| `dl/` | 专有 tarball 存放/校验（大文件不入库，见 `dl/README.md`） |
| `scripts/build.sh` | 本地/CI 一键构建 |
| `scripts/fetch-vendor.sh` | 收集 MTK SDK tarball + 生成校验和 |
| `scripts/set-vendor-hashes.sh` | 计算并回填 `PKG_HASH`（让 OpenWrt 下载机制可用） |
| `docs/HANDOFF.md` | **工作交接**：已完成/待办/关键信息（下次从这里继续） |
| `docs/MANIFEST.md` | **必要 / 按需 / 可删** 改动清单 + 与原仓库的映射 |
| `docs/5G-MODEM.md` | 5G 模组选包说明 + 设备端验证方法 |
| `.github/workflows/build.yml` | CI 矩阵构建 + Release |

---

## 快速开始

### 1) 准备专有 tarball

MTK Wi-Fi7 闭源 SDK 的三个 tarball（**不随仓库分发**），放到 `dl/`：

```bash
cp /path/to/mt7993_20250919-39602c.tar.xz   dl/
cp /path/to/warp_20250919-9c1cfa.tar.xz     dl/
cp /path/to/mt_wifi_osal-a53418.tar.xz      dl/
```

（它们均来自 MTK `mtk-wifi-mt7987-mt7990-mt7992-mt7993-v8.3.1.3` SDK 的 `dl/` 目录，缺一不可。）

### 2) 本地构建

```bash
scripts/build.sh h5000m          # 或 7dr7230
# 产物：build/openwrt/bin/targets/mediatek/filogic/
```

可选环境变量：`BUILD_ROOT`、`DL_DIR`、`DL_BASE_URL`、`JOBS`、
`NO_BRAND=1`（跳过品牌补丁，得到尽量贴近官方的版本）、
`CLEAN_CHIP=1`（切芯片前清理 mt_wifi7/warp 构建目录）。

### 3) 流水线

- 手动触发 / 每周定时 / 打 `v*` tag 时自动构建；
- 两个 profile 分矩阵 job（**WARP/CHIP 是编译期单值，必须分开**）；
- 专有 tarball 通过私有 Release 拉取（secret：`VL_REPO`、`VL_TOKEN`，见 workflow）。

---

## 跟随上游

```bash
# 1. 改 upstream.env: OPENWRT_REF=<新 tag 或 commit>
# 2. 验证增量是否仍能贴上
scripts/build.sh h5000m
```

若 `patches/` 报 FAIL，说明官方对应文件上下文变了，用 `git apply --3way` 或手工 rebase 那一个补丁即可（都是追加式改动，冲突面很小）。

---

## 约束

- **专有 tarball 不入库**：CI 必须能从私有镜像拿到，否则构建失败。
- **一次 build 只出一个芯片**（`CONFIG_WARP_VERSION` / `CHIP_MT*` 编译期单值）。
- 链接 `mt_wifi.ko`(≈45MB) 吃内存，建议 ≥8G；CI runner 16G 足够。
- `patches/` 与 `OPENWRT_REF` 强绑定：ref 一动就要回归。

---

## 当前状态

- ✅ 增量仓库已搭好，并**已验证** `overlay/` + `patches/` 能在固定上游提交上干净应用（与原仓库增量一致）。
- ✅ 已裁剪未使用的第三方 LuCI（`mwan3helper` / `wrtbwmon`）。
- ✅ 已为 5 个包补 `PKG_SOURCE_URL` + `PKG_HASH`（含 `scripts/set-vendor-hashes.sh`）。
- ✅ 已加 5G 模组选包（`common.extra` + `docs/5G-MODEM.md` + 自检脚本）与 风扇/LED 默认脚本。
- ⏳ **尚未做完整编译**（本机缺专有 tarball）。拿到 tarball 后请先跑一次 `scripts/build.sh`。

下次继续请先读 **`docs/HANDOFF.md`**。改动分级与裁剪建议见 `docs/MANIFEST.md`。
