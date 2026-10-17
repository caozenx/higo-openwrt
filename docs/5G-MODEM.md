# 5G / 4G 蜂窝模组支持

蜂窝支持通过 `configs/common.extra` 这个**配置片段**提供，`scripts/build.sh` 会在写 `.config` 之后
**自动追加**它（后出现的选择覆盖前面的 `is not set`），所以：

- **默认构建就会带上**这套 5G 选包（不需要任何额外开关）；
- 不想要，就把 `configs/common.extra` 里的对应行删掉（或整个文件清空 / 删文件，`build.sh` 会跳过）；
- 也可以加一个 `configs/h5000m.extra` 放你自己的覆盖项（第二个自动追加的片段）。

## 一、涉及的文件

| 文件 | 作用 |
|---|---|
| `configs/common.extra` | 选包（USB 数据通道 + 管理协议 + LuCI 界面 + 模组小工具） |
| `overlay/target/linux/mediatek/filogic/base-files/usr/bin/higowrt-modem-check` | 设备端自检脚本（诊断 USB/串口/QMI/MBIM） |
| `overlay/target/linux/mediatek/dts/mt7987a-hiveton-h5000m.dts` | USB 侧 `&ssusb` 已 `okay`（第 228 行）；HNAT 的 `ext-devices-prefix` 已含 `usb`/`wwan`/`rmnet`（第 278 行），一般无需再改 |

## 二、选包说明（configs/common.extra）

- **数据通道**：`kmod-usb-net-qmi-wwan`（QMI）、`kmod-usb-net-cdc-mbim`（MBIM）、`cdc-ncm`/`rndis`。
- **串口/AT**：`kmod-usb-serial-option`、`-qualcomm`、`kmod-usb-acm`、`kmod-usb-wdm`。
- **M.2/MHI**：`kmod-mhi-wwan-ctrl`、`kmod-mhi-wwan-mbim`。
- **管理**：`libqmi`/`libmbim`/`uqmi`/`umbim`、`modemmanager`、`usb-modeswitch`。
- **LuCI**：`luci-proto-qmi`、`luci-proto-mbim`、`luci-proto-modemmanager`。
- **模组小工具**：`bsbf-quectel-usbnet`、`quectel-timesync`。

> 用不到的直接在 `configs/common.extra` 里删掉对应行即可。只要 QMI 就删 `cdc-mbim`/`mhi`/`modemmanager` 等。

## 三、验证（设备端）

刷机后在设备上：

```sh
higowrt-modem-check
```

判断与下一步：

| 现象 | 说明 | 下一步 |
|---|---|---|
| 出现 `/dev/cdc-wdm0` | QMI 就绪 | `uqmi -d /dev/cdc-wdm0 --get-data-status`；或 LuCI 新建 **QMI Cellular** 接口 |
| 出现 `/dev/wwan0mbim0` | MBIM 就绪 | `mbimcli -d /dev/wwan0mbim0 -p --query-device-caps`；或 LuCI 新建 **MBIM**/ModemManager |
| 只有 `/dev/ttyUSB*` | 模组还在 AT 模式或被识别为存储 | 需要 `usb-modeswitch` 切模式；核对 VID:PID |
| 什么都没有 | 未识别 | 查 `dmesg | grep -i usb`；确认供电、`&ssusb=okay`、5G 包已编入 |

LuCI：**网络 → 接口 → 添加新接口 → 协议选 QMI / MBIM / ModemManager**，填 APN 即可。

## 四、注意

- 5G 模组功耗大，务必确认板子 USB 供电能力（`dmesg` 里是否有 over-current）。
- `configs/common.extra` 依赖 `packages` feed；`scripts/build.sh` 已先跑 `feeds install -a`。
- 若想让 5G 接口也走硬件加速（HNAT），板级 DTS 的 `ext-devices-prefix` 已包含 `usb/wwan/rmnet`，一般无需再改。
