#!/usr/bin/env bash
#
# extract-vendor.sh — pull the four stock vendor partitions out of the
#                     HyperOS 4 port package's super.img.
#
# HYBRID STRATEGY: we do NOT build vendor. We take the nubia vendor binary
# partitions as-is and flash them alongside our source-built system images.
#
# Verified from the LP metadata inside super.img:
#   Slot A logical partitions: odm, system, system_dlkm, system_ext,
#                              product, vendor, vendor_dlkm
#   All EROFS. The four we keep: vendor, vendor_dlkm, odm, system_dlkm.
#   The three we replace:      system, system_ext, product.
#
# Usage:
#   ./extract-vendor.sh /path/to/super.img /path/to/output-dir
#
set -euo pipefail

SUPER_IMG="${1:?usage: extract-vendor.sh <super.img> <outdir>}"
OUTDIR="${2:?usage: extract-vendor.sh <super.img> <outdir>}"

log() { echo -e "\n\033[1;32m[extract]\033[0m $*"; }

command -v lpunpack >/dev/null 2>&1 || {
    echo "!! lpunpack not found."
    echo "!! Get it from a LineageOS/AOSP build, or use the Python fallback below."
    exit 1
}

log "unpacking super.img -> ${OUTDIR}"
mkdir -p "${OUTDIR}"
lpunpack --slot=0 asuper "${SUPER_IMG}" "${OUTDIR}"

log "done. You should have:"
ls -la "${OUTDIR}"

cat <<'EOF'

Next: flash these four to the device (keep them, do not overwrite):
    vendor.img        -> vendor_a / vendor_b
    vendor_dlkm.img   -> vendor_dlkm_a / vendor_dlkm_b
    odm.img           -> odm_a / odm_b
    system_dlkm.img   -> system_dlkm_a / system_dlkm_b

And REPLACE these three with your built images:
    system.img        -> system_a / system_b
    system_ext.img    -> system_ext_a / system_b
    product.img       -> product_a / product_b
EOF
