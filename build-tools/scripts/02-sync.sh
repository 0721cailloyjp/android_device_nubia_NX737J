#!/usr/bin/env bash
#
# 02-sync.sh — 拉源码（浅克隆 + TUNA 镜像）
#
# 前台执行，直接看到 repo sync 的输出，同时 tee 到 /data/sync.log。
# 外层建议在 tmux 里跑 run-all.sh（断开 SSH 不中断）。
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
die() { echo -e "\n\033[1;31m[sync:FAIL]\033[0m $*"; exit 1; }

mkdir -p "${TREE}"
cd "${TREE}"

# ── repo init ───────────────────────────────────────────────────────────────
if [[ ! -d .repo ]]; then
    log "repo init ${MANIFEST_URL} -b ${BRANCH} (--depth=1)"
    repo init -u "${MANIFEST_URL}" -b "${BRANCH}" --git-lfs --depth=1 \
        || die "repo init 失败（网络到 GitHub / TUNA 不通？）"
else
    log ".repo 已存在，跳过 init"
fi

# ── local manifest ──────────────────────────────────────────────────────────
log "安装 local manifest"
mkdir -p .repo/local_manifests
cp -f "${REPO_ROOT}/local_manifests/nx737j.xml" .repo/local_manifests/

# ── 设备树 ──────────────────────────────────────────────────────────────────
# 设备树在 GitHub，local_manifests 里有对应 project，repo sync 会拉。
if [[ -d device/nubia/NX737J/.git ]]; then
    log "设备树已存在（repo sync 会更新）"
elif grep -q 'path="device/nubia/NX737J"' .repo/local_manifests/nx737j.xml 2>/dev/null; then
    log "设备树由 local_manifests 提供，repo sync 会拉"
    mkdir -p device/nubia
elif [[ -d "${REPO_ROOT}/device-nubia-NX737J" ]]; then
    log "manifest 未启用，从本地目录复制"
    mkdir -p device/nubia
    cp -a "${REPO_ROOT}/device-nubia-NX737J" device/nubia/NX737J
else
    die "找不到设备树来源（manifest 没启用 + 本地也没有）"
fi

# ── sync ────────────────────────────────────────────────────────────────────
FREE_GB=$(df -BG "${TREE}" | awk 'NR==2{gsub("G","",$4); print $4}')
log "磁盘可用 ${FREE_GB}G；预计需要 150~200 GB"
if (( ${FREE_GB:-0} < 180 )); then
    log "⚠️ 磁盘可能不够。repo sync 中途满盘会留下残缺树，比从头来更难受"
fi

log "repo sync -c -j${JOBS}（TUNA 限并发，开高会 503）"
log "预计 45~90 分钟。日志 ${DATA}/sync.log"

set +e
# 注意：**不能加 --no-tags** —— PixelOS manifest 里 external/tinyxml 的 revision
# 是 tag（refs/tags/android-11.0.0_r46），--no-tags 可能拉不到它导致 sync 失败。
# 也不加 --optimized-fetch（和 --depth=1 浅克隆兼容性存疑）。
# 只保留无害的 --force-sync（覆盖本地）和 --no-clone-bundle（不走 bundle，更稳）。
repo sync -c -j"${JOBS}" --force-sync --no-clone-bundle --prune 2>&1 | tee "${DATA}/sync.log"
RC=${PIPESTATUS[0]}
set -e

echo "SYNC_EXIT=${RC}" >> "${DATA}/sync.log"

if (( RC != 0 )); then
    echo
    echo "──────────── 失败诊断 ────────────"
    if grep -qiE 'error: 503|Service Unavailable|429' "${DATA}/sync.log"; then
        echo "→ TUNA 限流。等 5 分钟，用更低的 -j 重跑： JOBS=2 bash scripts/02-sync.sh"
    elif grep -qiE 'No space left' "${DATA}/sync.log"; then
        echo "→ 磁盘满。扩容后再跑，repo sync 支持断点续传。"
    elif grep -qiE 'Could not resolve host|Connection timed out|Connection reset' "${DATA}/sync.log"; then
        echo "→ 网络问题。确认 TUNA 镜像配置生效："
        echo "    git config --global --get url.https://mirrors.tuna.tsinghua.edu.cn/git/AOSP/.insteadof"
        echo "  没输出就跑一遍 scripts/00-prep.sh"
    else
        echo "→ 未匹配已知模式，贴最后 60 行："
        echo "    tail -60 ${DATA}/sync.log"
    fi
    die "repo sync 失败 (exit ${RC})"
fi

log "sync 完成，树大小 $(du -sh "${TREE}" 2>/dev/null | cut -f1)"
