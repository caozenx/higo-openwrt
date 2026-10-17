#!/usr/bin/env bash
#
# scripts/fetch-vendor.sh 的自测（全部在临时副本里跑，不污染仓库）
#
# 真实 tarball 不在手上时，也能验证「下载 / 解压归档 / 按名挑文件 / 落 dl/ / 算哈希 /
# 回填 PKG_HASH」整条链路 —— 包括用**真实的** datconf tarball 做一次真数据校验。
#
#   scripts/selftest-fetch-vendor.sh
#
# 退出码 0 = 全部通过。
#
# 注意：本脚本可在 macOS 自带 bash 3.2 上运行（刻意不用 declare -A / mapfile）。
#
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

PASS=0; FAIL=0
ok()  { echo "  ✅ $*"; PASS=$((PASS + 1)); }
bad() { echo "  ❌ $*"; FAIL=$((FAIL + 1)); }
hdr() { echo; echo "──────── $* ────────"; }
strip() { sed 's/\x1b\[[0-9;]*m//g'; }

REAL_DATCONF="$REPO/dl/datconf-757f9679.tar.bz2"
NAMES=(mt7993_20250919-39602c.tar.xz mt_wifi_osal-a53418.tar.xz warp_20250919-9c1cfa.tar.xz)

# 干净副本：dl/ 严格恢复到 git HEAD 的状态
# （排除本机临时放进去的占位 tarball、以及被改写的 SHA256SUMS，否则测试结果受本地状态影响）
make_clone() {
  rm -rf "$1"; mkdir -p "$1"
  ( cd "$REPO" && tar cf - --exclude=.git --exclude=build --exclude=artifacts . ) \
    | ( cd "$1" && tar xf - )
  rm -rf "$1/dl"; mkdir -p "$1/dl"
  ( cd "$REPO" && git archive HEAD dl ) | ( cd "$1" && tar xf - )
}

# 素材：SDK 目录 + 装着它的归档 + 嵌套归档 + 缺文件的归档
mkdir -p "$W/src/sdk/dl" "$W/src/sdk/doc"
for f in "${NAMES[@]}"; do echo "FAKE-PAYLOAD $f" > "$W/src/sdk/dl/$f"; done
echo readme > "$W/src/sdk/doc/README"
( cd "$W/src" && tar -czf "$W/vendor-sdk.tar.gz" sdk )

mkdir -p "$W/nest/inner"
( cd "$W/src/sdk/dl" && tar -czf "$W/nest/inner/inner-files.tar.gz" "${NAMES[@]}" )
( cd "$W/nest" && tar -czf "$W/nested.tar.gz" inner )

mkdir -p "$W/partial" && cp "$W/src/sdk/dl/${NAMES[0]}" "$W/partial/"
( cd "$W" && tar -czf "$W/partial.tar.gz" partial )

all_present() { # $1=目录
  local f
  for f in "${NAMES[@]}"; do
    [[ -f "$1/dl/$f" ]] || return 1
  done
  return 0
}

echo "仓库: $REPO"
echo "工作区: $W"

hdr "T1  --list-missing：缺 3 个时 exit 1 并逐行列出"
CL="$W/t1"; make_clone "$CL"; cd "$CL"
out="$(scripts/fetch-vendor.sh --list-missing 2>&1)"; rc=$?
if [[ $rc -eq 1 ]] && [[ "$(grep -c '^  dl/' <<<"$out")" = "3" ]]; then
  ok "exit=1，逐行列出 3 个缺失文件"
else bad "rc=$rc"; echo "$out" | strip | sed 's/^/      /'; fi

hdr "T2  --archive：容器归档（文件在 sdk/dl/ 下）"
CL="$W/t2"; make_clone "$CL"; cd "$CL"
scripts/fetch-vendor.sh --archive "$W/vendor-sdk.tar.gz" >"$W/t2.log" 2>&1; rc=$?
n="$(wc -l < dl/SHA256SUMS | tr -d ' ')"
if [[ $rc -eq 0 ]] && all_present "$CL" && [[ "$n" = "4" ]]; then
  ok "3 个文件就位，SHA256SUMS 4 行"
else bad "rc=$rc SHA256SUMS=$n 行"; fi

hdr "T3  真数据校验：真实的 datconf 走一遍，哈希必须与入库值一致"
COMMITTED="$(grep datconf-757f9679 "$REPO/dl/SHA256SUMS" | awk '{print $1}')"
CL="$W/t3"; make_clone "$CL"; rm -f "$CL"/dl/*.tar.*
mkdir -p "$W/realdl" && cp "$REAL_DATCONF" "$W/realdl/"
( cd "$W" && tar -czf real.tar.gz realdl )
cd "$CL"
scripts/fetch-vendor.sh --archive "$W/real.tar.gz" >"$W/t3.log" 2>&1
got="$(grep datconf-757f9679 dl/SHA256SUMS | awk '{print $1}')"
if [[ -n "$got" && "$got" = "$COMMITTED" ]]; then ok "哈希一致 ($got)"
else bad "committed=$COMMITTED got=$got"; fi

hdr "T4  --from 目录 / T5 位置参数（旧用法）"
CL="$W/t4"; make_clone "$CL"; cd "$CL"
scripts/fetch-vendor.sh --from "$W/src/sdk/dl" >/dev/null 2>&1; rc=$?
[[ $rc -eq 0 ]] && all_present "$CL" && ok "--from 正常" || bad "--from rc=$rc"
CL="$W/t5"; make_clone "$CL"; cd "$CL"
scripts/fetch-vendor.sh "$W/src/sdk/dl" >/dev/null 2>&1; rc=$?
[[ $rc -eq 0 ]] && all_present "$CL" && ok "位置参数兼容" || bad "位置参数 rc=$rc"

hdr "T6  --base-url：起本地 HTTP 服务，走真实下载"
CL="$W/t6"; make_clone "$CL"
if command -v python3 >/dev/null 2>&1; then
  PORT=$(( 18000 + RANDOM % 2000 ))
  ( cd "$W/src/sdk/dl" && python3 -m http.server "$PORT" >/dev/null 2>&1 ) &
  SRV=$!
  sleep 1
  cd "$CL"
  scripts/fetch-vendor.sh --base-url "http://127.0.0.1:$PORT" >"$W/t6.log" 2>&1; rc=$?
  kill "$SRV" 2>/dev/null
  wait "$SRV" 2>/dev/null
  [[ $rc -eq 0 ]] && all_present "$CL" && ok "HTTP 下载正常" || bad "rc=$rc"
else
  echo "  ⏭  跳过（没有 python3）"
fi

hdr "T7  嵌套归档（两层）/ T8 --archive 给的是目标文件本身"
CL="$W/t7"; make_clone "$CL"; cd "$CL"
scripts/fetch-vendor.sh --archive "$W/nested.tar.gz" >"$W/t7.log" 2>&1; rc=$?
[[ $rc -eq 0 ]] && all_present "$CL" && ok "两层解压后找到" || bad "rc=$rc"
CL="$W/t8"; make_clone "$CL"; cd "$CL"
cp "$W/src/sdk/dl/${NAMES[0]}" "$W/${NAMES[0]}"
scripts/fetch-vendor.sh --archive "$W/${NAMES[0]}" >/dev/null 2>&1
cmp -s "dl/${NAMES[0]}" "$W/${NAMES[0]}" && ok "原样落盘（未被当容器解开）" || bad "内容不一致"

hdr "T9  归档缺文件：exit 2 且明确列出"
CL="$W/t9"; make_clone "$CL"; cd "$CL"
out="$(scripts/fetch-vendor.sh --archive "$W/partial.tar.gz" 2>&1)"; rc=$?
if [[ $rc -eq 2 ]] && grep -q "还缺 2 个" <<<"$out"; then ok "exit=2，报「还缺 2 个」"
else bad "rc=$rc"; echo "$out" | strip | sed 's/^/      /'; fi

hdr "T10 --set-hashes：PKG_HASH 从 skip 升级为真实 sha256（bash 3.2 兼容）"
CL="$W/t10"; make_clone "$CL"; cd "$CL"
scripts/fetch-vendor.sh --archive "$W/vendor-sdk.tar.gz" --set-hashes >"$W/t10.log" 2>&1; rc=$?
if [[ $rc -eq 0 ]] && ! grep -q '^PKG_HASH:=skip' overlay/package/mtk/drivers/mt_wifi7/Makefile; then
  ok "PKG_HASH 已升级"
else bad "rc=$rc"; tail -5 "$W/t10.log" | strip | sed 's/^/      /'; fi

echo
echo "════════ 结果: 通过 $PASS / 失败 $FAIL ════════"
[[ $FAIL -eq 0 ]]
