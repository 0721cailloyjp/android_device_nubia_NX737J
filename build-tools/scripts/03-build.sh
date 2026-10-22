#!/usr/bin/env bash
#
# 03-build.sh — 编译（只出 system/system_ext/product 三个镜像）
#
# hybrid 路线：不编内核、不编 vendor、不出 recovery。
# 这就是社区维护者能快速出包的原因。
#
# 自适应规格：-j 按 min(RAM/2, 核数) 自动算，不用手改。
#
set -euo pipefail

ROM="${ROM:-pixelos}"
DATA="${DATA:-/data}"
TREE="${TREE:-${DATA}/pixelos}"
VARIANT="${VARIANT:-userdebug}"

log() { echo -e "\n\033[1;32m[build]\033[0m $*"; }

cd "${TREE}"

# ── 自适应线程数 ────────────────────────────────────────────────────────────
CORES="$(nproc)"
RAM_GB="$(free -g | awk '/^Mem:/{print $2}')"
[[ "${RAM_GB}" -gt 0 ]] || RAM_GB=8
JOBS="${JOBS:-$(( RAM_GB / 2 ))}"
(( JOBS > CORES )) && JOBS=${CORES}
(( JOBS < 1 )) && JOBS=1

SWAP_GB="$(free -g | awk '/^Swap:/{print $2}')"

log "cores=${CORES} ram=${RAM_GB}G swap=${SWAP_GB}G -> jobs=${JOBS}"
if (( SWAP_GB < 8 )); then
    log "警告：swap 只有 ${SWAP_GB}G。32G 内存建议配 16G swap 兜底大链接。"
    log "      现在补： fallocate -l 16G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile"
fi

# ── 环境 ────────────────────────────────────────────────────────────────────
export USE_CCACHE=1
export CCACHE_DIR="${DATA}/ccache"
log "ccache: $(ccache -s 2>/dev/null | grep -i 'cache size' || echo 'n/a')"

log "source build/envsetup.sh"
# shellcheck disable=SC1091
source build/envsetup.sh

# ── lunch 目标（前缀不确定，自动探测）────────────────────────────────────────
# LineageOS/PixelOS 产品名可能是 lineage_NX737J 或 pixelos_NX737J。
# 让 lunch 自己列出来，抓含 NX737J 的第一个。
log "探测 lunch 目标"
CANDIDATES="$( { lunch 2>/dev/null || true; } | grep -oE '[a-zA-Z_]*NX737J' | sort -u )"

if [[ -z "${CANDIDATES}" ]]; then
    echo "!! 没找到任何含 NX737J 的 lunch 目标。"
    echo "!! 说明设备树没被 manifest 识别。检查："
    echo "!!   1. .repo/local_manifests/nx737j.xml 是否指向你的仓库"
    echo "!!   2. device/nubia/NX737J/AndroidProducts.mk 是否存在"
    echo "!!   3. repo sync 是否完整（有没有 FAILED 项目）"
    echo "!! 手动列出：  source build/envsetup.sh && lunch"
    exit 1
fi

TARGET="$(echo "${CANDIDATES}" | head -1)"
log "选用目标：${TARGET}-${VARIANT}  （候选：$(echo "${CANDIDATES}" | tr '\n' ' ')）"
lunch "${TARGET}-${VARIANT}"

# ── 编译（后台 tmux，断开不中断）──────────────────────────────────────────────
log "启动编译，日志 ${DATA}/build.log"
log "实时看进度：  tail -f ${DATA}/build.log"

tmux kill-session -t build 2>/dev/null || true
tmux new-session -d -s build \
    "build/soong/soong_ui.bash --make-mode \
        systemimage systemextimage productimage \
        -j${JOBS} > ${DATA}/build.log 2>&1; \
     echo \"BUILD_EXIT=\$?\" >> ${DATA}/build.log; \
     tmux wait-for -S build-done"

log "编译已在后台 tmux 会话 'build' 中启动"
log "查看：  tmux attach -t build     （退出用 Ctrl-b d，不会中断）"
log "等待：  tmux wait-for build-done"
echo
echo "预计耗时：65~120 分钟（取决于核数）。"
echo "成功后跑：  bash 04-pack.sh"
