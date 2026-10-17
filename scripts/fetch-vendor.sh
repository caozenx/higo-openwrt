#!/usr/bin/env bash
#
# 把 MTK 专有 tarball 收集 / 下载 / 从归档中提取到 dl/
#
# ── 先说明「解压」这件事 ────────────────────────────────────────────────
# 构建**不需要**预先解压。这 4 个 tarball 走 OpenWrt 标准 PKG_SOURCE 流程：
# include/download.mk 只负责把文件放进 <openwrt>/dl/，真正的解压发生在**编译时**，
# 落到 build_dir/.../PKG_BUILD_DIR（mt_wifi7 / warp 的 Makefile 用 TAR_CMD 定制了
# 解压落点）。所以本脚本的核心职责只是「让这几个文件出现在 dl/」。
#
# 唯一的例外：你手上是一个**大归档**（例如整个 SDK 的打包，里面才装着这几个
# tarball）。这种情况用 --archive，脚本会：下载(可选) → 解压 → 按文件名找出这几个
# 文件 → 拷进 dl/。
#
# ── 用法 ────────────────────────────────────────────────────────────────
#   scripts/fetch-vendor.sh /path/to/mtk-wifi-sdk/dl      # 从本地 SDK 目录取
#   scripts/fetch-vendor.sh --from /path/to/dir           # 同上（显式写法）
#   scripts/fetch-vendor.sh --base-url https://host/dir   # 逐文件下载
#   scripts/fetch-vendor.sh --archive vendor.tar.gz       # 本地归档：解压后挑文件
#   scripts/fetch-vendor.sh --archive https://host/vendor.zip
#   scripts/fetch-vendor.sh --gh-repo owner/higo-vendor-dl [--gh-tag v1.0.0]
#   scripts/fetch-vendor.sh --list-missing                # 只报告缺哪些（CI 可用）
#
# 几种来源可以叠加（先满足的优先；已存在的文件默认不覆盖）。
#
# ── 选项 ────────────────────────────────────────────────────────────────
#   --force        已存在也重新获取 / 覆盖
#   --set-hashes   结束后调用 scripts/set-vendor-hashes.sh（把 PKG_HASH 的 skip
#                  升级成真实 sha256；会改动 5 个 Makefile，请 review 后再提交）
#   DL_DIR=<dir>   目标目录，默认 ./dl（与 scripts/build.sh 一致）
#
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

DL_DIR="${DL_DIR:-dl}"
mkdir -p "$DL_DIR"

DATCONF=datconf-757f9679.tar.bz2        # 已入库，一般无需获取
REQUIRED=(                              # 需要自备的 3 个
  mt7993_20250919-39602c.tar.xz         # mt_wifi7 + mt_hwifi 共用
  mt_wifi_osal-a53418.tar.xz            # mt_wifi_osal
  warp_20250919-9c1cfa.tar.xz           # warp
)
ALL=("$DATCONF" "${REQUIRED[@]}")       # 按文件名字典序，保证 SHA256SUMS 稳定

die() { echo "错误: $*" >&2; exit 1; }
log() { printf '\033[1;32m==> %s\033[0m\n' "$*"; }

usage() { sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; }

# 是否需要获取该文件：0=需要  1=已存在可跳过
need() {
  if [[ "${FORCE:-0}" -eq 1 ]]; then return 0; fi
  if [[ -f "$DL_DIR/$1" ]]; then return 1; fi
  return 0
}

is_target_name() {
  local f
  for f in "${ALL[@]}"; do
    if [[ "$1" == "$f" ]]; then return 0; fi
  done
  return 1
}

sha256_of() { # 兼容 Linux / macOS
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}

download_to() { # $1=URL  $2=目标路径
  local url="$1" out="$2" curl_bin
  curl_bin="$(command -v curl || true)"
  [[ -n "$curl_bin" ]] || die "找不到 curl，无法下载 $url"
  echo "  download $url"
  "$curl_bin" -fL --retry 3 --retry-delay 2 -o "$out" "$url"
}

extract_archive() { # $1=归档文件  $2=解压目标目录
  local a="$1" d="$2"
  case "$a" in
    *.zip)                 unzip -q -o "$a" -d "$d" ;;
    *.tar.zst|*.tzst)      tar -xf "$a" -C "$d" 2>/dev/null || tar --zstd -xf "$a" -C "$d" ;;
    *.tar|*.tar.gz|*.tgz|*.tar.xz|*.txz|*.tar.bz2|*.tbz2|*.tbz|*.tar.lzma)
                           tar -xf "$a" -C "$d" ;;
    *)                     tar -xf "$a" -C "$d" 2>/dev/null || unzip -q -o "$a" -d "$d" ;;
  esac
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 在一个目录树里找目标文件；找不到时若其中有归档，则解开一层再找（默认 1 层）
harvest() { # $1=目录  $2=还可解开的层数
  local d="$1" depth="$2" f hit a sub
  for f in "${ALL[@]}"; do
    if ! need "$f"; then echo "  exists   $DL_DIR/$f"; continue; fi
    hit="$(find "$d" -type f -name "$f" -print -quit 2>/dev/null || true)"
    if [[ -n "$hit" ]]; then
      cp -p "$hit" "$DL_DIR/$f"
      echo "  ok       $DL_DIR/$f"
    fi
  done

  if (( depth <= 0 )); then return 0; fi
  while IFS= read -r a; do
    [[ -n "$a" ]] || continue
    # 本身就是要找的 tarball → 别当容器解（写成显式 if：`f && continue` 在 set -e 下语义微妙）
    if is_target_name "$(basename "$a")"; then continue; fi
    case "$(basename "$a")" in
      *.tar|*.tar.gz|*.tgz|*.tar.xz|*.txz|*.tar.bz2|*.tbz2|*.tar.zst|*.tzst|*.zip) ;;
      *) continue ;;
    esac
    sub="$TMP/unpack/$depth/$(basename "$a")"
    mkdir -p "$sub"
    if extract_archive "$a" "$sub" 2>/dev/null; then
      echo "  unpack   $(basename "$a")"
      harvest "$sub" $((depth - 1))
    else
      echo "  ⚠️ 无法解开 $(basename "$a")（跳过）" >&2
    fi
  done < <(find "$d" -type f 2>/dev/null)
}

# ---------------------------------------------------------------------------
# 参数
# ---------------------------------------------------------------------------
FROM_DIR=""
BASE_URL="${DL_BASE_URL:-${VL_BASE_URL:-}}"
GH_REPO="${VL_REPO:-}"
GH_TAG=""
FORCE=0
SET_HASHES=0
LIST_MISSING=0
ARCHIVES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from)        [[ $# -ge 2 ]] || die "--from 需要一个目录"; FROM_DIR="$2"; shift 2 ;;
    --base-url)    [[ $# -ge 2 ]] || die "--base-url 需要一个 URL"; BASE_URL="$2"; shift 2 ;;
    --archive)     [[ $# -ge 2 ]] || die "--archive 需要一个文件或 URL"; ARCHIVES+=("$2"); shift 2 ;;
    --gh-repo)     [[ $# -ge 2 ]] || die "--gh-repo 需要 owner/repo"; GH_REPO="$2"; shift 2 ;;
    --gh-tag)      [[ $# -ge 2 ]] || die "--gh-tag 需要一个 tag"; GH_TAG="$2"; shift 2 ;;
    --force)       FORCE=1; shift ;;
    --set-hashes)  SET_HASHES=1; shift ;;
    --list-missing) LIST_MISSING=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    -*)            die "未知选项: $1（--help 看用法）" ;;
    *)             [[ -z "$FROM_DIR" ]] || die "目录参数给了两次"
                   FROM_DIR="$1"; shift ;;
  esac
done

# ---------------------------------------------------------------------------
# --list-missing：只报告（CI 里可用来提前失败）
# ---------------------------------------------------------------------------
if [[ "$LIST_MISSING" -eq 1 ]]; then
  missing=()
  for f in "${REQUIRED[@]}"; do
    if [[ ! -f "$DL_DIR/$f" ]]; then missing+=("$f"); fi
  done
  if ((${#missing[@]})); then
    echo "缺少 ${#missing[@]} 个专有 tarball:"
    for f in "${missing[@]}"; do echo "  $DL_DIR/$f"; done
    exit 1
  fi
  echo "专有 tarball 齐全 ✅"
  exit 0
fi

# ---------------------------------------------------------------------------
# 各来源
# ---------------------------------------------------------------------------
did_something=0

if [[ -n "$FROM_DIR" ]]; then
  did_something=1
  [[ -d "$FROM_DIR" ]] || die "不是目录: $FROM_DIR"
  log "从本地目录取: $FROM_DIR"
  for f in "${ALL[@]}"; do
    if ! need "$f"; then echo "  exists   $DL_DIR/$f"; continue; fi
    if [[ -f "$FROM_DIR/$f" ]]; then
      cp -p "$FROM_DIR/$f" "$DL_DIR/$f"; echo "  ok       $DL_DIR/$f"
    elif [[ -f "$DL_DIR/$f" ]]; then
      echo "  keep     $DL_DIR/$f（源里没有，保留现有）"
    else
      echo "  missing  $f（$FROM_DIR 里没有）"
    fi
  done
fi

if [[ -n "$BASE_URL" ]]; then
  did_something=1
  BASE_URL="${BASE_URL%/}"
  log "逐文件下载: $BASE_URL"
  for f in "${ALL[@]}"; do
    if ! need "$f"; then echo "  exists   $DL_DIR/$f"; continue; fi
    if download_to "$BASE_URL/$f" "$DL_DIR/$f"; then
      echo "  ok       $DL_DIR/$f"
    elif [[ -f "$DL_DIR/$f" ]]; then
      echo "  keep     $DL_DIR/$f（下载失败，保留现有）"
    else
      echo "  FAILED   $f"
    fi
  done
fi

if [[ -n "$GH_REPO" ]]; then
  did_something=1
  log "GitHub Release 资产: $GH_REPO${GH_TAG:+ @ $GH_TAG}"
  command -v gh >/dev/null 2>&1 || die "需要 gh CLI（brew install gh / apt-get install gh）"
  gh_args=(release download --repo "$GH_REPO" --pattern '*' --dir "$TMP/gh" --clobber)
  if [[ -n "$GH_TAG" ]]; then gh_args+=(--tag "$GH_TAG"); fi
  mkdir -p "$TMP/gh"
  gh "${gh_args[@]}"
  harvest "$TMP/gh" 1
fi

if ((${#ARCHIVES[@]})); then
  did_something=1
  for a in "${ARCHIVES[@]}"; do
    # 情况一：给的「归档」本身就是我们要的 tarball → 直接落盘，别当容器去解
    if is_target_name "$(basename "$a")"; then
      base="$(basename "$a")"
      if need "$base"; then
        case "$a" in
          http://*|https://*) download_to "$a" "$DL_DIR/$base" ;;
          *)                  [[ -f "$a" ]] || die "文件不存在: $a"
                              cp -p "$a" "$DL_DIR/$base" ;;
        esac
        echo "  ok       $DL_DIR/$base（直接放入）"
      else
        echo "  exists   $DL_DIR/$base"
      fi
      continue
    fi

    # 情况二：给的是一层容器归档，里面才是这些 tarball
    case "$a" in
      http://*|https://*)
        dest="$TMP/$(basename "$a")"
        log "下载归档: $a"
        download_to "$a" "$dest"
        ;;
      *)
        [[ -f "$a" ]] || die "归档不存在: $a"
        dest="$a"
        log "使用本地归档: $a"
        ;;
    esac
    sub="$TMP/archive/$(basename "$dest")"
    mkdir -p "$sub"
    log "解压归档 → 找文件"
    extract_archive "$dest" "$sub" || die "无法解开归档: $a"
    harvest "$sub" 1
  done
fi

if [[ "$did_something" -eq 0 ]]; then
  usage
  echo
  echo "提示: 什么都没给，所以什么都没做。"
  echo "      缺哪些文件可以跑: scripts/fetch-vendor.sh --list-missing"
  exit 0
fi

# ---------------------------------------------------------------------------
# 结果 + SHA256SUMS
# ---------------------------------------------------------------------------
echo
log "$DL_DIR/ 现状"
ls -l "$DL_DIR" | sed 's/^/  /'

missing=()
for f in "${REQUIRED[@]}"; do
  if [[ ! -f "$DL_DIR/$f" ]]; then missing+=("$f"); fi
done

if ((${#missing[@]})); then
  echo
  echo "⚠️  还缺 ${#missing[@]} 个专有 tarball:"
  for f in "${missing[@]}"; do echo "     $DL_DIR/$f"; done
  echo "   缺了它们 scripts/build.sh 会直接退出（见 dl/README.md）"
  exit 2
fi

: > "$DL_DIR/SHA256SUMS"
for f in "${ALL[@]}"; do
  if [[ -f "$DL_DIR/$f" ]]; then
    printf '%s  %s\n' "$(sha256_of "$DL_DIR/$f")" "$f" >> "$DL_DIR/SHA256SUMS"
  fi
done
echo
log "$DL_DIR/SHA256SUMS"
sed 's/^/  /' "$DL_DIR/SHA256SUMS"

if [[ "$SET_HASHES" -eq 1 ]]; then
  echo
  log "升级 PKG_HASH（skip → 真实 sha256）"
  scripts/set-vendor-hashes.sh
fi

echo
echo "✅ 3 个专有 tarball 齐全，可以构建了:"
echo "     scripts/build-docker.sh        # macOS / Windows"
echo "     scripts/build.sh               # Linux 本机"
