# AGENTS.md —— 在本仓库里干活须知

> 面向 AI 编码助手 / 未来的维护者。**只讲规则和雷区**；「怎么编译、怎么刷机」看 `README.md`、
> 「已经做过什么、下一步做什么」看 `docs/HANDOFF.md`、「哪些改动必要」看 `docs/MANIFEST.md`。

---

## 0. 一句话定位

这是一个 **OpenWrt 增量（overlay / delta）仓库**：**不含 OpenWrt 源码**，构建时才把
`overlay/` + `patches/` + `configs/` 贴到 `upstream.env` 里钉死的官方 OpenWrt 提交上。
目标是**尽可能贴近官方，只保留必要修改**，并且只支持 **Hiveton H5000M 一个设备**。

```
官方 OpenWrt @ upstream.env:OPENWRT_REF
  + overlay/          新增文件（MTK 闭源驱动栈、板级 DTS…）
  + patches/*.patch   对官方已有文件的少量“追加式”改动
  + configs/          设备 defconfig（只有一个）
  + dl/               需自备的专有 tarball（不入库）
```

---

## 1. 铁律（违反即视为改坏了）

**改动要放对地方**

1. **新增文件** → 放进 `overlay/`，路径与它在官方树里的最终位置**完全一致**
   （如 `overlay/package/mtk/drivers/...`、`overlay/target/linux/mediatek/dts/...`）。
2. **修改官方已有文件** → 一律写成 `patches/000N-描述.patch`，**不要**在 `overlay/` 里放同名文件去覆盖它。
3. `patches/` 的**序号与文件名有引用关系**（README / MANIFEST / HANDOFF 都按序号写），
   不要重排、不要重命名、不要在没有同步文档的情况下增删。

**不要做的事**

4. **不要加第二个设备**。「只支持 H5000M」是明确需求；`scripts/build.sh` 也硬编码只接受 `h5000m`。
5. **不要手改 `configs/mt7987_h5000m.config`**。它是 `make menuconfig` 导出的**完整快照**（≈7700 行），
   手改会在下次生成时丢失，也难以复现。要加/改选项请用 `configs/common.extra`、
   `configs/h5000m.extra`（`build.sh` 会自动追加，后出现者覆盖前面的），或环境变量（见 §3）。
6. **不要提交专有 tarball**：`dl/mt7993_*.tar.xz`、`dl/warp_*.tar.xz`、`dl/mt_wifi_osal-*.tar.xz`
   （已被 `dl/.gitignore` 挡住，别绕过）。只有一个小的 `dl/datconf-*.tar.bz2` 是入库的。
7. **不要 `git add build/` 或 `artifacts/`**（`.gitignore` 已挡）。
8. **不要在提交里留内网 IP、绝对路径、用户名**（本仓库是 public）。示例：`10.211.55.3` → `<构建机 IP>`。
9. **不要随意升 `upstream.env` 的 `OPENWRT_REF`**。升了必须回归全部补丁（见 §5），并把结论写进 HANDOFF。
10. **不要为了“干净”去动上游风格的代码**（`overlay/` 里是厂商代码，保持原样便于与原仓库逐字节对比）。

**做改动时要一起做的**

11. 每次有实质决策/结论 → 追加到 `docs/HANDOFF.md`；改动的必要性分级 → 更新 `docs/MANIFEST.md`。
12. 所有文档用**中文**（仓库既有约定），代码/路径/符号保持英文。

---

## 2. 目录 → 改动该放哪

| 我要做的事 | 改哪里 |
|---|---|
| 加/改 MTK 驱动、原厂工具、band 计划（`.dat`） | `overlay/package/mtk/...`（路径对齐官方树） |
| 改板级硬件描述（LED/风扇/网口/USB/HNAT） | `overlay/target/linux/mediatek/dts/mt7987a-hiveton-h5000m.dts` |
| 改内核 6.12 适配源 / 内核补丁 | `overlay/target/linux/mediatek/files-6.12/`、`patches-6.12/` |
| 改设备定义（镜像格式、`sysupgrade.bin`） | `patches/0003-filogic-add-devices.patch` |
| 改 LAN/WAN 口序 | `patches/0004-filogic-h5000m-network.patch` |
| 改品牌 / hostname / banner | `patches/0001-brand-openwrt-to-higowrt.patch`（`NO_BRAND=1` 可跳过） |
| 改 kernel config | `patches/0005`（filogic）/ `0006`（generic）/ `0007`（HNAT 包） |
| 改编译期选项（SKU、蜂窝选包…） | `configs/common.extra` / `configs/h5000m.extra`，不要碰 defconfig |
| 改构建流程 | `scripts/build.sh`（唯一入口）、`scripts/build-docker.sh` |
| 改 CI | `.github/workflows/build.yml`（单 job，勿引入 matrix 表达式的 job 级 `if`——曾因此导致 push/schedule 不触发） |

---

## 3. 常用命令

```bash
scripts/build.sh                      # 唯一构建入口（参数 h5000m 可省略）
NO_BRAND=1 scripts/build.sh           # 尽量贴近官方（跳过品牌补丁）
SKU=BE3600SDB CLEAN_CHIP=1 scripts/build.sh   # 换 SKU 做 A/B（必须 CLEAN_CHIP=1）
scripts/build-docker.sh               # macOS/Windows 用（Docker 命名卷，规避大小写敏感问题）
scripts/fetch-vendor.sh /path/to/sdk/dl        # 收集 3 个专有 tarball
scripts/set-vendor-hashes.sh          # 算 sha256 并回填各 Makefile 的 PKG_HASH:=
```

环境变量（全部可选）：`BUILD_ROOT`、`DL_DIR`、`DL_BASE_URL`、`JOBS`、`NO_BRAND`、`SKU`、`CLEAN_CHIP`。

---

## 4. 提交前必跑的验证

```bash
# 1) 脚本语法
bash -n scripts/*.sh

# 2) workflow 语法
ruby -ryaml -e 'YAML.load_file(".github/workflows/build.yml")'

# 3) 补丁能否干净贴到固定上游（在临时树里做，别污染仓库）
source upstream.env
R="$PWD"                      # 注意：git -C 会切换目录，补丁一律用绝对路径
T="$(mktemp -d)/openwrt"
git init -q "$T"
git -C "$T" remote add origin "$OPENWRT_REPO"
git -C "$T" fetch --depth 1 -q origin "$OPENWRT_REF"
git -C "$T" checkout -q -f FETCH_HEAD
for p in "$R"/patches/*.patch; do
  git -C "$T" apply --check "$p" && echo "ok   $(basename "$p")" || echo "FAIL $(basename "$p")"
done

# 4) 反向复验（证明补丁与树完全对应，不重不漏）
for p in "$R"/patches/*.patch; do git -C "$T" apply "$p"; done
for p in $(ls "$R"/patches/*.patch | sort -r); do git -C "$T" apply -R "$p"; done
git -C "$T" status --porcelain   # 应为空

# 5) 改了 overlay/patches 时的强验证：与原仓库逐字节对比（见 §6）

# 6) 改了 configs/*.config 时：同一符号只能出现一次（defconfig 是快照，但符号不能重复）
grep -oE '^#? ?CONFIG_[A-Za-z0-9_-]+' configs/mt7987_h5000m.config \
  | sed 's/^# //' | sort | uniq -d
# 输出应为空（`lua5.3`/`golang1.26` 这类带点版本号会被上面的正则误截，注意肉眼排除）
```

> 改了 `overlay/` 或 `patches/` 之后，**必须**跑 3) 和 4)；改了脚本跑 1)；改了 CI 跑 2)。
> 3) 需要联网拉上游；无网时可直接用 `scripts/build.sh`（它自己是 `git apply` + `patch -p1` 兜底，
> 失败会打印 `FAIL` 并退出）。

---

## 5. 跟随上游（升 `OPENWRT_REF`）

1. 改 `upstream.env` 的 `OPENWRT_REF`。
2. 跑 §4 的 3)/4)。若某个补丁 FAIL，官方上下文变了 → 重新生成**那一个**补丁（都是追加式改动，冲突面很小）。
3. 跑一次完整 `scripts/build.sh` 确认能出包。
4. 把「升到哪个 ref、哪几个补丁重生成、有什么行为变化」写进 `docs/HANDOFF.md`。

---

## 6. 参考实现：原仓库 `~/Workspace/higowrt`

`~/Workspace/higowrt` 是**源头（多提交、可运行过的）仓库**，本仓库是它的「增量重排版」+
收窄（只留 H5000M）。怀疑自己改错时，用逐字节对比来判断：

```bash
# overlay 文件是否与原仓库一致（预期：仅 5 个 Makefile 多了 PKG_SOURCE_URL/PKG_HASH）
while IFS= read -r f; do
  rel="${f#overlay/}"; cmp -s "$f" "/Users/caozheng/Workspace/higowrt/$rel" || echo "diff: $rel"
done < <(git ls-files overlay)

# 打完补丁的结果是否与原仓库一致（预期：完全一致）
# 注意 §4 第 4) 步把补丁反向撤销了，这里先正向重新应用：
for p in "$R"/patches/*.patch; do git -C "$T" apply "$p"; done
for f in $(git -C "$T" diff --name-only HEAD); do
  cmp -s "$T/$f" "/Users/caozheng/Workspace/higowrt/$f" || echo "diff: $f"
done
```

已知的**有意差异**（出现这些不算错）：
5 个 Makefile 加了 `PKG_SOURCE_URL`/`PKG_HASH`（`mt_wifi7`/`mt_hwifi`/`mt_wifi_osal`/`warp`/`datconf`）；
删掉 TL-7DR7230（MT7988）与 3 个第三方 LuCI（`luci-app-mwan3helper-chinaroute`/`luci-app-wrtbwmon`/`wrtbwmon`）；
新增 3 个板级脚本（`board.d/02_higowrt`、`uci-defaults/99-higowrt-fan`、`usr/bin/higowrt-modem-check`）；
删掉 defconfig 里 2 行指向已删包的 `# ... is not set`。

---

## 7. 关键事实（别重新推导，这些已经查清）

- **设备**：Hiveton H5000M = MT7987A + MT7992，eMMC 启动，MTK filogic target。
- **Wi-Fi SKU = `BE5040`**（`CONFIG_MTK_WIFI7_SKU_TYPE`）。**不是** `BE3600SDB`。
  「BE3600」是产品速率档位/营销名，不是驱动 SKU。证据：原厂 `mt7992-be5400/l1profile.dat`
  → `mt7992.5040.1.dat` → 双频 `b0`+`b1`；且原仓库提交 `af22d76` 明确记录
  `BE3600SDB → BE5040`（用 BE3600SDB 会 EEPROM timeout）。详见 `docs/HANDOFF.md` §1.5。
- **`CONFIG_MTK_WIFI7_SKU_TYPE` 与设备选择无关**：它是驱动包级自由字符串，`menuconfig` 不会自动设置。
  改它必须配 `CLEAN_CHIP=1`（编译期单值，否则残留上次的固件）。
- **`WARP_CHIPSET=mt7987` / `WARP_VERSION=3_1` 固定**，本次构建不改。
- **`mt_wifi7` 与 `mt_hwifi` 共用 `PKG_BUILD_DIR`** → `mt_hwifi` 的补丁要放在 `mt_wifi7/patches/`。
- **`PKG_HASH` 只能填真实 sha256/md5 或字面量 `skip`，绝不留空**。
  留空 → `include/download.mk` 把空值当哨兵 `x` → `download.pl` 报
  `Cannot find appropriate hash command`，**`dl/` 里已有 tarball 也一样失败**（已实测）。
  现状：3 个 MTK 专有包用 `skip`（tarball 未到），`datconf` 用它自己的真实 sha256。
  `scripts/set-vendor-hashes.sh` 可把 `skip` 升级成真实 sha256。
- **`PKG_SOURCE_URL` 必须非空**，否则 OpenWrt 的下载规则不生效。
- **`wifi-profile` 是启用的**（原厂 `wifi_jedi` 顶掉官方 `/sbin/wifi`，见 `patches/0008`）。
  `docs/MIGRATION_ISSUES.md` §6.1、§7 的相反结论是**改动前的历史档案**，不要照它改。
- **`/sbin/wifi` 是 Lua 脚本，所以 `CONFIG_PACKAGE_lua=y` 是硬需求**（别把它关掉）。
  依据：`overlay/package/mtk/drivers/wifi-profile/files/common/wifi_jedi` 首行是
  `#!/usr/bin/env lua`；`/etc/init.d/boot` 会无条件执行 `/sbin/wifi config`。
  ⚠️ `datconf-lua` 只依赖 `liblua`，而 `liblua` 只装 `/usr/lib/liblua.so*` ——
  **`/usr/bin/lua` 只由 `lua` 包提供**；LuCI 25.12 是 ucode-only，已不再带 lua。
  关掉 `lua` 的后果是开机 wifi 配置静默失败（build 不会报错）。
- **defconfig 是 `make menuconfig` 的完整快照，同一符号只能出现一次**。
  历史上尾部手工追加过 10 行（与正文早先的 `is not set` 冲突），已合并进正文。
  加新包请改对应位置那一行，**不要在文件尾部追加**。
- **写进配置的包名必须真实存在**（主树 / pinned feeds 里查得到）。不存在的符号
  `make defconfig` 会**静默丢弃**，不报错 —— 表现是「功能莫名缺失」。
  典型事故：`common.extra` 里的 `bsbf-quectel-usbnet` 就是个不存在的包名（已删）。
  校验方法：`grep -rhoE '^define (Kernel)?Package/[^ ]+' package/ target/` 对比配置里的
  `CONFIG_PACKAGE_*`。
- **`CONFIG_PACKAGE_knot-resolver_dnstap` 是残留，已关**：它是 `knot-resolver` 的一个
  `config` 子项（feed `net/knot-resolver/Makefile` 里确有），打开会拉进
  约 5 MB 的递归 DNS 解析器（+ knot-libs/luajit/libgnutls/libstdcpp/libuv1/lmdb/
  libnghttp2/libprotobuf-c/libfstrm/luasocket），本设备用不到。

---

## 8. 提交信息规范

`type(scope): 中文简述`，body 用 `-` 列表分点。type 用 `feat` / `fix` / `docs` / `ci` / `chore`；
scope 常用 `h5000m` / `wifi` / `ci` / `docs`（可省）。示例：

```
fix(h5000m): 互换 LAN/WAN — eth0(RTL8221)=WAN, eth1(内置2.5G)+hnat=LAN

- patches/0004: ucidef_set_interfaces_lan_wan "eth1 hnat" eth0
- README: 更新口序说明
```

个人署名统一为 `caozenx <caozenx@gmail.com>`（与既有提交一致）。

---

## 9. 环境限制（踩过）

- **macOS 不能原生编译 OpenWrt**（需要大小写敏感文件系统 + Linux 工具链）→ 用 `scripts/build-docker.sh`。
- **本机（Apple Silicon / macOS 27）的容器运行时**：Docker Desktop 4.6.1（2022）已无法启动后端
  （`docker info` 直接 panic），改用 **Colima**：
  ```bash
  brew install colima docker
  colima start --cpu 6 --memory 12 --disk 60
  ```
  用 Colima 自带的 aarch64 容器即可（目标本身也是 aarch64，无需 x86 模拟）。
- ⚠️ **容器里以 root 编译必须带 `FORCE_UNSAFE_CONFIGURE=1`**（`build-docker.sh` 已加）：
  否则 GNU tar 的 configure 直接报 *"you should not run configure as root"* → 构建在
  `tools/tar` 阶段就挂掉。官方 `openwrt/sdk` 镜像同样用这个变量绕过。
- ⚠️ **`gcc-multilib`/`g++-multilib` 在 arm64 上不存在**：`build-docker.sh` 已按
  `dpkg --print-architecture` 条件安装，别改回无条件安装（会让容器里 apt 直接失败）。
- ⚠️ 容器里没有 `shasum` 的可能性（属 `perl` 包）→ 脚本里校验一律**优先 `sha256sum`**，回退 `shasum`。
- 链接 `mt_wifi.ko`（≈45 MB）吃内存，建议 ≥8 G；不足时 `JOBS=2`。
- 本机**没有**那 3 个专有 tarball，所以「完整编译」尚未跑过；Wi-Fi 也**从未在真机上验证**过
  （原移植在 x86 VM 上完成）。首刷建议先用 `*-recovery.itb` 内存启动确认，再写 eMMC。
- 那 3 个 tarball **无法从公开渠道获取**（MTK 授权 SDK；公开镜像 `mediatek/mtk-openwrt-feeds`
  里没有 wifi7/osal/warp 驱动源码）→ 只能由本人提供。
- CI 需要配置 secret `VL_REPO` / `VL_TOKEN`（私有 Release 镜像）或 `DL_BASE_URL`，否则拿不到 tarball 必然失败。
