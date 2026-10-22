#!/usr/bin/env bash
#
# 03-build.sh — 编译（只出 system/system_ext/product）
#
# 前台执行，日志同时进 /data/build.log。外层建议在 tmux 里跑 run-all.sh。
#
set -euo pipefail

ROM="${ROM:-pixelos}"
DATA="${DATA:-/data}"
TREE="${TREE:-${DATA}/pixelos}"
VARIANT="${VARIANT:-userdebug}"

log() { echo -e "\n\033[1;32m[build]\033[0m $*"; }
die() { echo -e "\n\033[1;31m[build:FAIL]\033[0m $*"; exit 1; }

cd "${TREE}" || die "源码目录 ${TREE} 不存在"

# ── 自适应线程数：每个 ninja job 链接时吃 1.5~2 GB ─────────────────────────
CORES="$(nproc)"
RAM_GB="$(free -g | awk '/^Mem:/{print $2}')"
[[ "${RAM_GB:-0}" -gt 0 ]] || RAM_GB=8
JOBS="${JOBS:-$(( RAM_GB / 2 ))}"
(( JOBS > CORES )) && JOBS=${CORES}
(( JOBS < 1 )) && JOBS=1

SWAP_GB="$(free -g | awk '/^Swap:/{print $2}')"

log "cores=${CORES}  ram=${RAM_GB}G  swap=${SWAP_GB:-0}G  ->  jobs=${JOBS}"
if (( ${SWAP_GB:-0} < 8 )); then
    log "警告：swap 只有 ${SWAP_GB:-0}G。32G 内存建议至少 16G swap 兜底大链接"
    log "      补：fallocate -l 16G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile"
fi

# ── 环境 ────────────────────────────────────────────────────────────────────
export USE_CCACHE=1
export CCACHE_DIR="${DATA}/ccache"
command -v ccache >/dev/null && ccache -M "${CCACHE_GB:-60}G" >/dev/null 2>&1 || true

log "source build/envsetup.sh"
# shellcheck disable=SC1091
source build/envsetup.sh || die "envsetup.sh 失败，源码树可能不完整"

# ── 选目标：优先 breakfast，它自己处理 release config 后缀 ──────────────────
# Android 17 的 release config 是 CP2A（不是 Android 16 的 BP4A），
# 所以绝不能硬编码 lunch lineage_NX737J-userdebug。
log "选择目标 breakfast NX737J ${VARIANT}"
if breakfast NX737J "${VARIANT}" 2>/dev/null; then
    log "breakfast 成功"
else
    log "breakfast 失败，回退到探测 lunch 目标"
    # lunch 无参数时打印菜单，抓完整的目标串（含 -xxxx- 段）
    CHOICE="$( { lunch 2>/dev/null || true; } \
               | grep -oE '[a-zA-Z_]*NX737J[^ ]*' \
               | sed 's/.*\b\(lineage_NX737J[^ ]*\)/\1/' \
               | head -1 )"
    if [[ -z "${CHOICE}" ]]; then
        echo
        echo "!! 找不到任何含 NX737J 的 lunch 目标。逐个排查："
        echo "!!   1) device/nubia/NX737J/AndroidProducts.mk 是否存在"
        echo "!!   2) .repo/local_manifests/nx737j.xml 是否指向你的仓库"
        echo "!!   3) repo sync 有没有 FAILED 的项目"
        echo "!!   4) 手动看菜单： source build/envsetup.sh && lunch"
        die "无可用目标"
    fi
    log "改用 lunch ${CHOICE}"
    lunch "${CHOICE}" || die "lunch ${CHOICE} 失败"
fi

# ── 编译（前台，日志 tee 到文件）────────────────────────────────────────────
log "开始编译，日志 ${DATA}/build.log（也实时输出到屏幕）"

set +e
build/soong/soong_ui.bash --make-mode \
    systemimage systemextimage productimage \
    -j"${JOBS}" 2>&1 | tee "${DATA}/build.log"
RC=${PIPESTATUS[0]}
set -e

echo "BUILD_EXIT=${RC}" >> "${DATA}/build.log"

if (( RC != 0 )); then
    echo
    echo "──────────── 失败诊断 ────────────"
    if grep -qiE 'out of memory|Killed|signal 9|virtual memory exhausted' "${DATA}/build.log"; then
        echo "→ 判定：OOM"
        echo "  降线程重试（增量续编，不用重 sync）："
        echo "    JOBS=$(( JOBS / 2 )) bash scripts/03-build.sh"
    elif grep -qiE 'module .* not found|depends on undefined module' "${DATA}/build.log"; then
        echo "→ 判定：缺模块/缺仓库"
        grep -oE "module \"[^\"]+\" .*not found" "${DATA}/build.log" | sort -u | head -10
        echo "  常见原因：local_manifests 少加了仓库，见 RUNBOOK 第 7.2 节"
    elif grep -qiE 'No such file or directory.*\.mk' "${DATA}/build.log"; then
        echo "→ 判定：缺 .mk 文件（缺仓库）"
        grep -oE '[a-z0-9_/]+\.mk' "${DATA}/build.log" | sort -u | head -10
        echo "  对照 RUNBOOK 第 7.2 / 7.4 节"
    else
        echo "→ 未匹配已知模式，贴最后 80 行给我："
        echo "    tail -80 ${DATA}/build.log"
    fi
    die "编译失败 (exit ${RC})"
fi

OUT="${TREE}/out/target/product/NX737J"
log "编译成功。产物："
ls -la "${OUT}"/*.img 2>/dev/null | grep -E 'system|product' || true
