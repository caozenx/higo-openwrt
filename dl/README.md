# dl/ —— 专有 tarball 存放目录

MTK Wi-Fi7 闭源 SDK 的源码包**不随本仓库分发**（体积 + 授权原因），但构建时`缺一不可`：

| 文件 | 内容 | 大小参考 |
|---|---|---|
| `mt7993_20250919-39602c.tar.xz` | 主驱动（`mt_wifi7` / `mt_hwifi`） | ~几十 MB |
| `warp_20250919-9c1cfa.tar.xz` | WED 硬件加速（`warp`） | ~ |
| `mt_wifi_osal-a53418.tar.xz` | OSAL 抽象层（`mt_wifi_osal`） | ~ |
| `datconf-757f9679.tar.bz2` | datconf 用户态工具源码（小，已入库） | 13 KB |

来源：MTK `mtk-wifi-mt7987-mt7990-mt7992-mt7993-v8.3.1.3` SDK 的 `dl/` 目录。

## 本地

把三个 tarball 放进本目录即可，`scripts/build.sh` 会自动拷到 `build/openwrt/dl/`。

## CI

推荐放一个**私有** Release/仓库（如 `owner/higo-vendor-dl`），由 workflow 用 secret `VL_REPO` + `VL_TOKEN` 拉取；
或在构建环境里设 `DL_BASE_URL`（脚本会 `curl` 下载）。**不要提交到公共仓库。**

## 校验

`SHA256SUMS` 用于构建前校验。补齐后请生成完整清单：

```bash
cd dl && shasum -a 256 *.tar.* > SHA256SUMS
```
