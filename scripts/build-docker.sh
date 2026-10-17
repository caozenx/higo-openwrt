#!/usr/bin/env bash
#
# 在 Linux 容器里构建（适合 macOS / Windows 等无法原生编译 OpenWrt 的主机）。
# OpenWrt 要求区分大小写的文件系统 + Linux 工具链，macOS 默认文件系统不满足，
# 因此构建目录用 docker 命名卷（区分大小写），只把产物拷回宿主机。
#
# 运行时（macOS）：
#   colima start --cpu 6 --memory 12 --disk 60   # arm64 原生 VM，够用
#   （Docker Desktop 需为较新版本；2022 年的 4.6.x 在 macOS 15+ 上后端起不来）
#   本机为 Apple Silicon 时用它自带的 aarch64 容器即可，无需 x86 模拟：
#   gcc-multilib/g++-multilib 只对 x86 target 有意义，脚本已按架构条件安装。
#
# 注意：容器内以 root 编译，必须带 FORCE_UNSAFE_CONFIGURE=1（脚本已加）。
#       GNU tar 的 configure 会检测到 root 并直接报错：
#         "you should not run configure as root (set FORCE_UNSAFE_CONFIGURE=1 ...)"
#       官方 openwrt/sdk 镜像也是用这个变量绕过；非 root 身份编译则无此问题。
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
  -e FORCE_UNSAFE_CONFIGURE=1 \
  -e NO_BRAND="${NO_BRAND:-}" \
  -e SKU="${SKU:-}" \
  -e DL_BASE_URL="${DL_BASE_URL:-}" \
  -e CLEAN_CHIP="${CLEAN_CHIP:-}" \
  -e JOBS="${JOBS:-}" \
  -e DEBIAN_FRONTEND=noninteractive \
  "$IMAGE" bash -lc '
    set -euo pipefail
    apt-get update -qq
    # gcc-multilib / g++-multilib 只存在于 amd64（用于 x86 target 的编译）；
    # 在 arm64 上这两个包不存在，无条件安装会让 apt 直接失败。
    extra=""
    [ "$(dpkg --print-architecture)" = "amd64" ] && extra="gcc-multilib g++-multilib"
    apt-get install -y -qq \
      build-essential clang flex bison g++ gawk \
      gettext git libncurses-dev libssl-dev python3-setuptools rsync unzip \
      zlib1g-dev file wget qemu-utils ccache libelf-dev patch sudo $extra
    scripts/build.sh "$PROFILE"
  '

echo "==> 拷贝产物到 ./artifacts/$PROFILE/"
# 必须先清空：$VOLUME 是持久化命名卷，bin/targets 里会残留上一次构建的产物
# （例如后来被 config 关掉、不再生成的包与 *-bl2.bin 镜像）。
# 只拷贝不清空的话，这些陈旧文件会一直留在 ./artifacts 里，可能混进发布物 ——
# 由此产生的「profiles.json 里还写着已删除的包」也是同一类问题。
rm -rf "$REPO_DIR/artifacts/$PROFILE"
mkdir -p "$REPO_DIR/artifacts/$PROFILE"
docker run --rm -v "$VOLUME":/build -v "$REPO_DIR/artifacts/$PROFILE":/out \
  "$IMAGE" bash -lc '
    set -euo pipefail
    src=/build/openwrt/bin/targets/mediatek/filogic
    ls "$src"/*.manifest >/dev/null 2>&1 || {
      echo "错误：$src 下没有 manifest，构建可能没真正产出镜像" >&2
      ls -l "$src" 2>/dev/null >&2 || true
      exit 1
    }
    cp -a "$src"/. /out/
  '
ls -lh "$REPO_DIR/artifacts/$PROFILE/"
