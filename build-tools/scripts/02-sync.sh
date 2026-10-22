#!/usr/bin/env bash
#
# 02-sync.sh — 拉源码（浅克隆 + TUNA 镜像）
#
# 必须在 00-prep.sh 之后跑。
# 这一步是唯一的耗时未知数，日志在 /data/sync.log。
#
# ROM=pixelos|avium|lineage   默认 pixelos
#
set -euo pipefail

ROM="${ROM:-pixelos}"
DATA="${DATA:-/data}"
TREE="${TREE:-${DATA}/pixelos}"
JOBS="${JOBS:-4}"          # TUNA 限并发，别调高，会 503

case "${ROM}" in
  pixelos) MANIFEST_URL="https://github.com/PixelOS-AOSP/android_manifest.git"
           BRANCH="seventeen" ;;
  avium)   MANIFEST_URL="https://github.com/AviumUI/android_manifests.git"
           BRANCH="avium-17" ;;
  lineage) MANIFEST_URL="https://github.com/LineageOS/android.git"
           BRANCH="lineage-24.0" ;;
  *) echo "unknown ROM=${ROM}"; exit 1 ;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { echo -e "\n\033[1;32m[sync]\033[0m $*"; }

mkdir -p "${TREE}"
cd "${TREE}"

# ── repo init ───────────────────────────────────────────────────────────────
if [[ ! -d .repo ]]; then
    log "repo init ${MANIFEST_URL} -b ${BRANCH} (depth=1)"
    repo init -u "${MANIFEST_URL}" -b "${BRANCH}" --git-lfs --depth=1
else
    log ".repo 已存在，跳过 init"
fi

# ── local manifest ──────────────────────────────────────────────────────────
log "安装 local manifest"
mkdir -p .repo/local_manifests
cp -f "${REPO_ROOT}/local_manifests/nx737j.xml" .repo/local_manifests/

# ── 设备树 ──────────────────────────────────────────────────────────────────
# 设备树已在 GitHub（0721cailloyjp/android_device_nubia_NX737J），
# local_manifests 里有对应 project 条目，repo sync 会自己拉。
# 这里只处理"manifest 里被注释掉"和"本地有 git 仓库要覆盖"两种旁路情况。
if [[ -d device/nubia/NX737J/.git ]]; then
    log "设备树已存在（repo sync 会更新它）"
elif grep -q 'device/nubia/NX737J' .repo/local_manifests/nx737j.xml 2>/dev/null \
     && ! grep -q '^\s*<!--.*device/nubia/NX737J' .repo/local_manifests/nx737j.xml 2>/dev/null; then
    log "设备树由 local_manifests 提供，repo sync 会拉"
    mkdir -p device/nubia
elif [[ -d "${REPO_ROOT}/device-nubia-NX737J" ]]; then
    log "manifest 未启用，从本地目录复制设备树"
    mkdir -p device/nubia
    cp -a "${REPO_ROOT}/device-nubia-NX737J" device/nubia/NX737J
else
    echo "!! 找不到设备树来源："
    echo "!!   · local_manifests/nx737j.xml 里没有启用的 project 条目"
    echo "!!   · 本地也没有 ${REPO_ROOT}/device-nubia-NX737J"
    exit 1
fi

# ── sync（后台 + tmux，断开不中断）────────────────────────────────────────────
log "启动 repo sync（jobs=${JOBS}），日志 ${DATA}/sync.log"
log "实时看进度：  tail -f ${DATA}/sync.log"

tmux kill-session -t sync 2>/dev/null || true
tmux new-session -d -s sync \
    "repo sync -c -j${JOBS} --force-sync --no-tags --no-clone-bundle \
        --optimized-fetch --prune > ${DATA}/sync.log 2>&1; \
     echo \"SYNC_EXIT=\$?\" >> ${DATA}/sync.log; \
     tmux wait-for -S sync-done"

log "sync 已在后台 tmux 会话 'sync' 中启动"
log "查看：  tmux attach -t sync     （退出用 Ctrl-b d，不会中断）"
log "等待：  tmux wait-for sync-done"
echo
echo "预计耗时：45~90 分钟。跑到 60% 以上再决定是否继续编译。"
