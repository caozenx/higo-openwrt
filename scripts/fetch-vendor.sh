#!/usr/bin/env bash
#
# 把 MTK SDK 里的专有 tarball 收集到 ./dl/
#
# 用法:
#   scripts/fetch-vendor.sh /path/to/mtk-wifi-sdk/dl
#   # 或
#   DL_BASE_URL=https://mirror.example.com/higo scripts/fetch-vendor.sh
#
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
mkdir -p dl

FILES=(
  mt7993_20250919-39602c.tar.xz
  warp_20250919-9c1cfa.tar.xz
  mt_wifi_osal-a53418.tar.xz
)

SRC="${1:-}"
for f in "${FILES[@]}"; do
  if [[ -f "dl/$f" ]]; then echo "exists  dl/$f"; continue; fi
  if [[ -n "$SRC" && -f "$SRC/$f" ]]; then
    cp -p "$SRC/$f" "dl/$f"; echo "copied  dl/$f"
  elif [[ -n "${DL_BASE_URL:-}" ]]; then
    echo "download dl/$f"; curl -fL --retry 3 -o "dl/$f" "$DL_BASE_URL/$f"
  else
    echo "missing dl/$f（给出 SDK 目录参数或设置 DL_BASE_URL）" >&2; exit 1
  fi
done

( cd dl && shasum -a 256 *.tar.* > SHA256SUMS )
echo "==> dl/SHA256SUMS"; cat dl/SHA256SUMS
