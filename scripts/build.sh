#!/usr/bin/env bash
#
# HiGoWRT 增量构建脚本（方案 A：Overlay）
#
#   官方 OpenWrt 源码树(固定 OPENWRT_REF)
#     + overlay/          新增文件（含 MTK 专有驱动、patch、DTS…）
#     + patches/*.patch   对官方文件的少量“追加式”改动
#     + configs/*.config  设备 defconfig（本仓库只有一个设备）
#     + dl/               需自备的专有 tarball（见 dl/README.md）
#   -> bin/targets/mediatek/filogic/*
#
# 用法:
#   scripts/build.sh [h5000m] [选项]
#   profile: h5000m                      （对应 configs/mt7987_h5000m.config）
#            本仓库只支持 Hiveton H5000M 一个设备，省略参数即默认 h5000m。
#
# 选项(环境变量):
#   BUILD_ROOT=<dir>   构建根目录，默认 ./build
#   DL_DIR=<dir>       本地专有 tarball 目录，默认 ./dl
#   DL_BASE_URL=<url>  本地缺失时从此 URL 下载
#   NO_BRAND=1         跳过品牌补丁(0001)，得到“接近官方”的版本
#   SKU=<值>           覆盖 CONFIG_MTK_WIFI7_SKU_TYPE（默认 BE5040）
#   JOBS=<n>           make -j 并行度，默认 nproc
#   CLEAN_CHIP=1       换 SKU/芯片前清理 mt_wifi7 构建目录(WARP_VERSION 单值)
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${1:-h5000m}"
if [[ "$PROFILE" != "h5000m" ]]; then
  echo "用法: $0 [h5000m]   （本仓库只支持 Hiveton H5000M）" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$REPO_DIR/upstream.env"

CFG="$REPO_DIR/configs/mt7987_${PROFILE}.config"
[[ -f "$CFG" ]] || { echo "找不到 profile 配置: $CFG" >&2; exit 1; }

BUILD_ROOT="${BUILD_ROOT:-$REPO_DIR/build}"
O="$BUILD_ROOT/openwrt"
DL_DIR="${DL_DIR:-$REPO_DIR/dl}"
JOBS="${JOBS:-$( (nproc 2>/dev/null || sysctl -n hw.ncpu) )}"

log() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }

# ---------------------------------------------------------------------------
# 1. 取上游源码树（对齐 OPENWRT_REF）
# ---------------------------------------------------------------------------
log "上游 OpenWrt: $OPENWRT_REPO @ $OPENWRT_REF"
mkdir -p "$BUILD_ROOT"
if [[ ! -d "$O/.git" ]]; then
  git init -q "$O"
  git -C "$O" remote add origin "$OPENWRT_REPO"
fi
git -C "$O" fetch --depth 1 -q origin "$OPENWRT_REF"
git -C "$O" checkout -q -f FETCH_HEAD
git -C "$O" clean -qfd -e dl   # 保留 dl/ 下载缓存

# ---------------------------------------------------------------------------
# 2. 覆盖 overlay（新增文件）
# ---------------------------------------------------------------------------
log "应用 overlay"
cp -a "$REPO_DIR/overlay/." "$O/"

# ---------------------------------------------------------------------------
# 3. 应用对官方文件的补丁
# ---------------------------------------------------------------------------
log "应用 patches"
shopt -s nullglob
for p in "$REPO_DIR"/patches/*.patch; do
  name="$(basename "$p")"
  if [[ "$name" == 0001-* && "${NO_BRAND:-0}" == "1" ]]; then
    echo "  skip $name (NO_BRAND=1)"; continue
  fi
  if git -C "$O" apply --whitespace=nowarn "$p"; then
    echo "  ok   $name"
  elif ( cd "$O" && patch -p1 --forward --silent < "$p" ); then
    echo "  fuzzy $name"
  else
    echo "  FAIL $name" >&2; exit 1
  fi
done

# ---------------------------------------------------------------------------
# 4. 专有 tarball（不随仓库分发）
# ---------------------------------------------------------------------------
log "准备专有 tarball -> openwrt/dl"
mkdir -p "$O/dl"
for f in mt7993_20250919-39602c.tar.xz warp_20250919-9c1cfa.tar.xz mt_wifi_osal-a53418.tar.xz datconf-757f9679.tar.bz2; do
  if [[ -f "$O/dl/$f" ]]; then continue; fi
  if [[ -f "$DL_DIR/$f" ]]; then
    cp -p "$DL_DIR/$f" "$O/dl/$f"
  elif [[ -n "${DL_BASE_URL:-}" ]]; then
    echo "  download $f"; curl -fL --retry 3 -o "$O/dl/$f" "$DL_BASE_URL/$f"
  else
    echo "  缺少 $f（放到 $DL_DIR/ 或设 DL_BASE_URL）" >&2; exit 1
  fi
done
if [[ -f "$DL_DIR/SHA256SUMS" ]]; then
  # 兼容 Linux(sha256sum) / macOS(shasum)。注意本步骤在容器里执行，
  # 而 Ubuntu 基础镜像不一定带 shasum（属 perl 包），所以优先 sha256sum。
  if command -v sha256sum >/dev/null 2>&1; then
    sha256cmd=(sha256sum)
  else
    sha256cmd=(shasum -a 256)
  fi
  ( cd "$O/dl" && grep -E "mt7993_|warp_|mt_wifi_osal-|datconf-" "$DL_DIR/SHA256SUMS" | "${sha256cmd[@]}" -c - || {
      echo "tarball 校验失败" >&2; exit 1; } )
fi

# ---------------------------------------------------------------------------
# 5. feeds + 配置 + 编译
# ---------------------------------------------------------------------------
log "feeds update/install"
( cd "$O" && [[ -f feeds.conf ]] || cp feeds.conf.default feeds.conf \
  && ./scripts/feeds update -a && ./scripts/feeds install -a )

log "写入配置: $(basename "$CFG")"
cp -f "$CFG" "$O/.config"
# 追加可选功能配置片段（5G 模组等）；后出现的选择覆盖前面的，随后 make defconfig 解析
for frag in "$REPO_DIR/configs/common.extra" "$REPO_DIR/configs/${PROFILE}.extra"; do
  if [[ -f "$frag" ]]; then
    log "追加配置片段: $(basename "$frag")"
    cat "$frag" >> "$O/.config"
  fi
done

# SKU 覆盖（defconfig 里默认 BE5040；实机验证时可用 SKU=BE3600SDB 做 A/B）
if [[ -n "${SKU:-}" ]]; then
  log "覆盖 SKU: CONFIG_MTK_WIFI7_SKU_TYPE=\"$SKU\""
  echo "CONFIG_MTK_WIFI7_SKU_TYPE=\"$SKU\"" >> "$O/.config"
fi

( cd "$O" && make defconfig )

if [[ "${CLEAN_CHIP:-0}" == "1" ]]; then
  ( cd "$O" && make package/mtk/drivers/mt_wifi7/clean package/mtk/drivers/warp/clean || true )
fi

log "编译 (-j$JOBS)"
( cd "$O" && make -j"$JOBS" )

log "完成。产物："
ls -lh "$O"/bin/targets/mediatek/filogic/ 2>/dev/null || true
