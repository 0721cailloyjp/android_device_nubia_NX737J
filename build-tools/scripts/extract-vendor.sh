#!/usr/bin/env bash
#
# extract-vendor.sh — 从 super.img 里拆出分区镜像
#
# HYBRID 策略：不编 vendor。四个硬件层分区原样保留。
#
# 已实测的 LP 布局（extent 单位 512 字节，不是 geometry 里写的 4096）：
#   Slot A: odm / system / system_dlkm / system_ext / product / vendor / vendor_dlkm
#   保留：vendor, vendor_dlkm, odm, system_dlkm
#   替换：system, system_ext, product
#
# 用法：
#   ./extract-vendor.sh /path/to/super.img /path/to/outdir
#
set -euo pipefail

SUPER_IMG="${1:?usage: extract-vendor.sh <super.img> <outdir>}"
OUTDIR="${2:?usage: extract-vendor.sh <super.img> <outdir>}"

log() { echo -e "\n\033[1;32m[extract]\033[0m $*"; }

# lpunpack 由 AOSP 的 system/extras/partition_tools 提供，Ubuntu 源里没有。
LPUNPACK=""
for cand in \
    "${LPUNPACK_BIN:-}" \
    "$(command -v lpunpack 2>/dev/null || true)" \
    "$(pwd)/out/host/linux-x86/bin/lpunpack" \
    "$HOME/pixelos/out/host/linux-x86/bin/lpunpack" \
    "/data/pixelos/out/host/linux-x86/bin/lpunpack"; do
    if [[ -n "${cand}" && -x "${cand}" ]]; then LPUNPACK="${cand}"; break; fi
done

if [[ -z "${LPUNPACK}" ]]; then
    cat <<'EOF'
!! 找不到 lpunpack。它不在 Ubuntu 源里，由 AOSP 的 system/extras/partition_tools 提供。

   两个办法：
   a) 源码树编过一次之后（03-build.sh 跑完），它就在
        <tree>/out/host/linux-x86/bin/lpunpack
      本脚本会自动找到。

   b) 单独编它（不用等整个编译完成）：
        source build/envsetup.sh
        m lpunpack
      产物同样在 out/host/linux-x86/bin/lpunpack

   注意：如果还没 sync，先用纯 Python 的 dump-lp-metadata.py 看分区表。
EOF
    exit 1
fi

log "使用 ${LPUNPACK}"
log "解包 ${SUPER_IMG} -> ${OUTDIR}"
mkdir -p "${OUTDIR}"

# --slot=0 只解 Slot A。输出文件名会带 _a 后缀
# （system_a.img / vendor_a.img …），这是 lpunpack 的正常行为。
"${LPUNPACK}" --slot=0 "${SUPER_IMG}" "${OUTDIR}"

log "完成，产物："
ls -la "${OUTDIR}"/*.img 2>/dev/null || ls -la "${OUTDIR}"

cat <<'EOF'

────────────────────────────────────────────────────────────
接下来怎么用这些文件

原样保留（不要覆盖，这些是硬件层）：
    vendor_a.img        -> vendor_a
    vendor_dlkm_a.img   -> vendor_dlkm_a
    odm_a.img           -> odm_a
    system_dlkm_a.img   -> system_dlkm_a

用自己编的替换：
    <out>/system.img      -> system_a
    <out>/system_ext.img  -> system_ext_a
    <out>/product.img     -> product_a

刷写前务必确认槽位大小：
    system_a      上限 1,109,176,320 B (1.033 GiB)
    system_ext_a  上限   885,358,592 B (0.825 GiB)
    product_a     上限 4,215,025,664 B (3.926 GiB)
超了就走 scripts/assemble-super.sh 的 lpmake 路线。
────────────────────────────────────────────────────────────
EOF
