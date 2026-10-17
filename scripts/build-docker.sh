#!/usr/bin/env bash
#
# 在 Linux 容器里构建（适合 macOS / Windows 等无法原生编译 OpenWrt 的主机）。
# OpenWrt 要求区分大小写的文件系统 + Linux 工具链，macOS 默认文件系统不满足，
# 因此构建目录用 docker 命名卷（区分大小写），只把产物拷回宿主机。
#
# 用法:
#   scripts/build-docker.sh [h5000m] [额外传给 build.sh 的环境变量...]
#   本仓库只支持 Hiveton H5000M，参数可省略。
# 例:
#   scripts/build-docker.sh
#   NO_BRAND=1 scripts/build-docker.sh
#   SKU=BE3600SDB scripts/build-docker.sh
#   DL_BASE_URL=https://mirror.example.com/higo scripts/build-docker.sh
#
# 产物：./artifacts/h5000m/
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${1:-h5000m}"
if [[ "$PROFILE" != "h5000m" ]]; then
  echo "用法: $0 [h5000m]   （本仓库只支持 Hiveton H5000M）" >&2
  exit 1
fi

IMAGE="${IMAGE:-ubuntu:24.04}"
VOLUME="${VOLUME:-higo-openwrt-build}"

docker volume create "$VOLUME" >/dev/null

docker run --rm \
  -v "$REPO_DIR":/work \
  -v "$VOLUME":/build \
  -w /work \
  -e PROFILE="$PROFILE" \
  -e BUILD_ROOT=/build \
  -e DL_DIR=/work/dl \
  -e NO_BRAND="${NO_BRAND:-}" \
  -e SKU="${SKU:-}" \
  -e DL_BASE_URL="${DL_BASE_URL:-}" \
  -e CLEAN_CHIP="${CLEAN_CHIP:-}" \
  -e JOBS="${JOBS:-}" \
  -e DEBIAN_FRONTEND=noninteractive \
  "$IMAGE" bash -lc '
    set -euo pipefail
    apt-get update -qq
    apt-get install -y -qq \
      build-essential clang flex bison g++ gawk gcc-multilib g++-multilib \
      gettext git libncurses-dev libssl-dev python3-setuptools rsync unzip \
      zlib1g-dev file wget qemu-utils ccache libelf-dev sudo
    scripts/build.sh "$PROFILE"
  '

echo "==> 拷贝产物到 ./artifacts/$PROFILE/"
mkdir -p "$REPO_DIR/artifacts/$PROFILE"
docker run --rm -v "$VOLUME":/build -v "$REPO_DIR/artifacts/$PROFILE":/out \
  "$IMAGE" bash -lc 'cp -av /build/openwrt/bin/targets/mediatek/filogic/* /out/ 2>/dev/null || true'
ls -lh "$REPO_DIR/artifacts/$PROFILE/"
