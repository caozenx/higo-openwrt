#!/usr/bin/env bash
#
# 从 dl/ 里的专有 tarball 计算 sha256，并写回对应 Makefile 的 PKG_HASH:= 行。
# 运行前请先把 4 个 tarball 放进 dl/（见 dl/README.md）。
#
# 各 Makefile 默认值：datconf = 真实 sha256（已入库）；3 个 MTK 专有包 = 字面量 skip
# （tarball 未到位也能构建）。本脚本会把它们**升级**成真实 sha256，更严格，推荐做一次。
# 注意：PKG_HASH 绝不能留空（空值 = 哨兵 "x"，download.pl 会直接报错）。
#
#   scripts/set-vendor-hashes.sh
#
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

sha256() { # 兼容 macOS / Linux
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}';
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}

set_hash() { # $1=Makefile  $2=hash
  local mf="$1" h="$2"
  [ -f "$mf" ] || { echo "  跳过（无文件）$mf"; return; }
  if ! grep -q '^PKG_HASH:=' "$mf"; then
    echo "  警告: $mf 中没有 PKG_HASH:= 行，请手动添加"; return
  fi
  perl -0pi -e "s/^PKG_HASH:=.*\$/PKG_HASH:=$h/m" "$mf"
  echo "  ok  $mf  ->  $h"
}

declare -a NAMES=(datconf-757f9679.tar.bz2 mt7993_20250919-39602c.tar.xz \
                  mt_wifi_osal-a53418.tar.xz warp_20250919-9c1cfa.tar.xz)

# 文件名 → 需要改写 PKG_HASH 的 Makefile
# 用 case 而不是 `declare -A`：macOS 自带的是 bash 3.2，**不支持关联数组**，
# 在 `set -u` 下 `declare -A X=( [k]=v )` 会把 [k] 当变量下标解析 →
# 直接报 "unbound variable"（本机实测踩到过）。
targets_for() {
  case "$1" in
    mt7993_20250919-39602c.tar.xz)
      echo "overlay/package/mtk/drivers/mt_wifi7/Makefile"
      echo "overlay/package/mtk/drivers/mt_hwifi/Makefile" ;;
    warp_20250919-9c1cfa.tar.xz)
      echo "overlay/package/mtk/drivers/warp/Makefile" ;;
    mt_wifi_osal-a53418.tar.xz)
      echo "overlay/package/mtk/drivers/mt_wifi_osal/Makefile" ;;
    datconf-757f9679.tar.bz2)
      echo "overlay/package/mtk/applications/datconf/Makefile" ;;
  esac
}

: > dl/SHA256SUMS
missing=0
for f in "${NAMES[@]}"; do
  if [ ! -f "dl/$f" ]; then
    echo "缺少 dl/$f（先跑 scripts/fetch-vendor.sh 或手工放入）" >&2
    missing=1
    continue
  fi
  h="$(sha256 "dl/$f")"
  echo "$h  $f" >> dl/SHA256SUMS
  echo "== $f"
  while IFS= read -r mf; do
    [ -n "$mf" ] && set_hash "$mf" "$h"
  done < <(targets_for "$f")
done

echo
echo "==> dl/SHA256SUMS"; cat dl/SHA256SUMS
[ "$missing" -eq 0 ] || exit 2
