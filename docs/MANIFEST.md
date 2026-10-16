# 改动清单（原 higowrt 相对官方 OpenWrt 的增量）

基准：官方 OpenWrt `4ccb782af7`（`r32933-4ccb782af7`，25.12，内核 6.12）。
统计：全树 **503 文件不同 = 488 新增 / 14 修改 / 1 删除**。

本清单用于：**保留必要、裁掉非必要**，并说明每块内容在新仓库中的位置。

---

## 一、对官方已有文件的改动（已转为 `patches/`）

| patch | 原文件 | 改动 | 分级 |
|---|---|---|---|
| `0001-brand-openwrt-to-higowrt.patch` | `include/version.mk`、`package/base-files/image-config.in`、`.../bin/config_generate`、`.../etc/banner`、`banner.failsafe` | HiGoWRT 品牌 / 默认 hostname | **可选**（`NO_BRAND=1` 可跳过） |
| `0002-feeds-pin-commits.patch` | `feeds.conf.default` | feed 由分支名改为 **hash 固定**（更可复现） | 建议保留 |
| `0003-filogic-add-devices.patch` | `target/linux/mediatek/image/filogic.mk` | 追加 `hiveton_h5000m`、`tplink_tl-7dr7230-*` 设备定义 | **必要** |
| `0004-filogic-h5000m-network.patch` | `mediatek/filogic/base-files/etc/board.d/02_network` | 追加 H5000M LAN/WAN 映射 | **必要** |
| `0005-kernel-config-filogic.patch` | `mediatek/filogic/config-6.12` | `CONFIG_NET_MEDIATEK_HNAT=m` | **必要** |
| `0006-kernel-config-generic.patch` | `target/linux/generic/config-6.12` | `MEDIATEK_NETSYS_V2/V3/RX_V2`、`NF_FLOW_TABLE_NETLINK` | **必要**（见备注） |
| `0007-kernel-modules-netdevices-mtkhnat.patch` | `package/kernel/linux/modules/netdevices.mk` | 追加 `KernelPackage/mediatek_hnat` | **必要** |
| `0008-wifi-scripts-drop-sbin-wifi.patch` | `package/network/config/wifi-scripts/Makefile` | `rm -f /sbin/wifi`（让位给原厂 `wifi_jedi`） | **仅当保留原厂管理栈时需要**；改用标准栈则删掉 |

> 备注：`0006` 把 `MEDIATEK_NETSYS_*` 放进 `generic/`，会影响所有 target。可评估只留在 `mediatek/filogic/config-6.12`（`0005`）里，减少对上游 generic 的侵入。

删除项：`.vscode/settings.json`（无关构建，新仓库直接不引入即可）。

---

## 二、新增文件（已放到 `overlay/`，共 481）

### A. `overlay/package/mtk/`（317）—— 分类见下

| 路径 | 内容 | 分级 |
|---|---|---|
| `drivers/mt_wifi7/` | 主驱动 `mt_wifi.ko` + 11 个 6.12 适配 patch | **必要** |
| `drivers/mt_hwifi/` | HW 抽象 / PCI / WED + 3 patch | **必要** |
| `drivers/mt_wifi_osal/` | OSAL 抽象层 + 5 patch | **必要** |
| `drivers/warp/` | WED 硬件加速 `mtk_warp.ko` + 3 patch | **必要** |
| `drivers/wifi-profile/` | 原厂 `/sbin/wifi`(wifi_jedi) + 119 个 dat | **按需**（用原厂管理栈才要；标准栈可删） |
| `applications/luci-app-mtk`、`datconf`、`datconf-lua`、`mwctl`、`kvcedit/libkvcutil` | 原厂用户态管理/`dat` 工具 | **按需**（同上） |
| `applications/switch`、`mii_mgr`、`regs`、`mtkhqos_util`、`mtk-smp` | 原厂底层工具 | 按需 |
| `applications/mt798x-2p5g-phy-firmware-internal` | 2.5G PHY 内置固件 | **建议删**（defconfig 用官方 `mt7987-2p5g-phy-firmware`） |
| `applications/luci-app-Airpifanctrl` | **风扇**控制 UI | 按需（有 PWM 风扇则留） |
| `applications/luci-app-eqos-mtk`、`luci-app-turboacc-mtk` | QoS / 硬件加速 UI | 按需 |
| `applications/luci-app-mwan3helper-chinaroute`、`wrtbwmon`、`luci-app-wrtbwmon` | 第三方分流/流量统计 | **可删**（defconfig 未启用） |

### B. `overlay/target/linux/mediatek/`（147）

| 路径 | 内容 | 分级 |
|---|---|---|
| `patches-6.12/999-27xx`、`999-30xx`、`999-41xx`、`999-9100/9101` 等 59 个 | HNAT / flow-offload / PCS / dual-boot / 6.12 兼容等内核补丁 | **必要**（HNAT 相关）；其余逐项确认 |
| `patches-6.12/999-9000/9001` | mtk 6.12 compat | **必要** |
| `patches-6.12/0101-add-mtk-wifi-utility-rbus.patch` | WiFi utility rbus | 必要（若走 TSF/utility） |
| `files-6.12/drivers/net/ethernet/mediatek/mtk_hnat/` + `mtk_eth_dbg/reset` | HNAT 厂商源 | **必要** |
| `files-6.12/drivers/net/phy/`（40）| `air_en8811h`（2.5G）、`mt753x`、`an8801` 等 | **按需**（本板用到的才留） |
| `files-6.12/drivers/net/dsa/`（10）+ `net/dsa/`（2）| `an8855`、`mxl862xx` DSA | **按需/可能可删** |
| `files-6.12/drivers/usb/host/xhci-mtk-*` | 厂商 USB 测试/增强码 | **按需**（5G 模组走 USB 时相关） |
| `files-6.12/drivers/net/wireless/wifi_utility/` | WiFi utility 内核侧 | 按需 |
| `files-6.12/include/`、`include/uapi/` | `ra_nat.h`、`mtk_vendor_nl80211.h`、`wapp/*` 头 | **必要**（驱动依赖） |
| `dts/mt7987a-hiveton-h5000m.dts`、`dts/mt7988d-tplink-tl-7dr7230-rev1.0-sp2.dts` | 板级 DTS | **必要** |

### C. 其它

| 路径 | 内容 | 分级 |
|---|---|---|
| `overlay/package/luci-theme-higowrt/`（17）| 自研主题 | 可选 |
| `configs/mt7987_h5000m.config`、`configs/mt7988_7dr7230.config` | 预置配置 | **必要** |
| `dl/datconf-757f9679.tar.bz2` | datconf 源码包（小，已入库） | 保留 |

---

## 三、你点名的几项对应的具体位置

| 需求 | 位置 |
|---|---|
| **MTK 驱动** | `overlay/package/mtk/drivers/{mt_wifi7,mt_hwifi,mt_wifi_osal,warp}` + `overlay/target/linux/mediatek/files-6.12/.../mtk_hnat` + `patches/0007` + `patches/0005/0006` |
| **无线 RF** | 各 profile `configs/*.config` 里的 `MTK_WIFI7_*_IF_RF_OFFSET`、`FIRST_IF_IPAILNA`/`SECOND_IF_EPAELNA`、`SKU_TYPE`；2.5G/PHY 固件包 |
| **风扇** | DTS `&fan (pwm-fan)` + thermal cooling + `overlay/package/mtk/applications/luci-app-Airpifanctrl` |
| **LED** | DTS `gpio-leds`(WiFi_2G/WiFi_5G) + `kmod-leds-gpio` + `MTK_WIFI7_LED_CONTROL_SUPPORT` |
| **5G 模组** | ⚠️ 目前**未启用任何蜂窝栈**，仅 HNAT `ext-devices-prefix="usb","wwan","rmnet"`。要用需在 `configs/*.config` 增加：`kmod-usb-net-qmi-wwan`（或 `kmod-usb-net-cdc-mbim`）、`kmod-mhi-wwan-*`、`uqmi`/`umbim` 或 `ModemManager`、`luci-proto-qmi`/`mbim`，以及 feed 的 `bsbf-quectel-usbnet`、`quectel-timesync`；USB 侧 DTS `&ssusb` 已 `okay` |

---

## 四、对应关系（新仓库 ← 原 higowrt）

| 原 higowrt | 新仓库 |
|---|---|
| `package/mtk/**`（新增） | `overlay/package/mtk/**` |
| `target/linux/mediatek/{dts,files-6.12,patches-6.12}`（新增） | `overlay/target/linux/mediatek/**` |
| `package/luci-theme-higowrt/**` | `overlay/package/luci-theme-higowrt/**` |
| 14 个被改的官方文件 | `patches/*.patch` |
| `defconfig/*.config` | `configs/*.config` |
| `_prep_build.sh` | `scripts/build.sh` |
| `MIGRATION_ISSUES.md` | `docs/MIGRATION_ISSUES.md` |
| `.github/workflows/build-on-comment.yml`（OpenWrt 自带，不适用于本 fork） | `.github/workflows/build.yml`（本 fork 的矩阵构建） |
