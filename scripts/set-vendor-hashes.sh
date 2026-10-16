#!/usr/bin/env bash
#
# 从 dl/ 里的专有 tarball 计算 sha256，并写回对应 Makefile 的 PKG_HASH:= 行。
# 运行前请先把 4 个 tarball 放进 dl/（见 dl/README.md）。
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

declare -a NAMES=(mt7993_20250919-39602c.tar.xz warp_20250919-9c1cfa.tar.xz \
                  mt_wifi_osal-a53418.tar.xz datconf-757f9679.tar.bz2)

declare -A TARGETS=(
  [mt7993_20250919-39602c.tar.xz]="overlay/package/mtk/drivers/mt_wifi7/Makefile overlay/package/mtk/drivers/mt_hwifi/Makefile"
  [warp_20250919-9c1cfa.tar.xz]="overlay/package/mtk/drivers/warp/Makefile"
  [mt_wifi_osal-a53418.tar.xz]="overlay/package/mtk/drivers/mt_wifi_osal/Makefile"
  [datconf-757f9679.tar.bz2]="overlay/package/mtk/applications/datconf/Makefile"
)

: > dl/SHA256SUMS
for f in "${NAMES[@]}"; do
  if [ ! -f "dl/$f" ]; then
    echo "缺少 dl/$f（先跑 scripts/fetch-vendor.sh 或手工放入）"
    continue
  fi
  h="$(sha256 "dl/$f")"
  echo "$h  $f" >> dl/SHA256SUMS
  echo "== $f"
  for mf in ${TARGETS[$f]}; do set_hash "$mf" "$h"; done
done

echo
echo "==> dl/SHA256SUMS"; cat dl/SHA256SUMS
