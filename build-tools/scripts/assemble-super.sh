#!/usr/bin/env bash
#
# assemble-super.sh — get your built system images onto the NX737J.
#
# VERIFIED layout (512-byte extent units, from dump-lp-metadata.py):
#
#   partition        start           size          action
#   odm_a            0x00100000      91205760      KEEP
#   system_a         0x05f00000      1109176320    REPLACE
#   system_dlkm_a    0x48100000      7602176       KEEP
#   system_ext_a     0x48900000      885358592     REPLACE
#   product_a        0x7d600000      4215025664    REPLACE
#   vendor_a         0x178a00000     2893135872    KEEP
#   vendor_dlkm_a    0x225200000     33603584      KEEP
#
#   super.img total  16.00 GiB, slot A used 8.61 GiB, free 7.39 GiB
#   Slot B is entirely empty.
#
# Usage:
#   ./assemble-super.sh <built-dir> <original-super.img> <out.img>
#
set -euo pipefail

BUILT_DIR="${1:?usage: assemble-super.sh <built-dir> <orig-super.img> <out.img>}"
ORIG_SUPER="${2:?usage: assemble-super.sh <built-dir> <orig-super.img> <out.img>}"
OUT="${3:?usage: assemble-super.sh <built-dir> <orig-super.img> <out.img>}"

log() { echo -e "\n\033[1;32m[super]\033[0m $*"; }

# ── sanity ──────────────────────────────────────────────────────────────────
for f in system system_ext product; do
    [[ -f "${BUILT_DIR}/${f}.img" ]] || { echo "missing ${BUILT_DIR}/${f}.img"; exit 1; }
done
[[ -f "${ORIG_SUPER}" ]] || { echo "missing ${ORIG_SUPER}"; exit 1; }

# slot geometry (bytes)
declare -A START=(
    [odm]=1048576        [system]=99614720
    [system_dlkm]=1208221696  [system_ext]=1216348160
    [product]=2105544704  [vendor]=6291456000
    [vendor_dlkm]=9109688320
)
declare -A MAXSIZE=(
    [odm]=91205760       [system]=1109176320
    [system_dlkm]=7602176    [system_ext]=885358592
    [product]=4215025664 [vendor]=2893135872
    [vendor_dlkm]=33603584
)

log "checking built image sizes against their slots"
OVER=0
for p in system system_ext product; do
    sz=$(stat -c%s "${BUILT_DIR}/${p}.img")
    max=${MAXSIZE[$p]}
    if (( sz > max )); then
        echo "  !! ${p}.img is ${sz} B but slot ${p}_a is only ${max} B"
        echo "     -> in-place overwrite impossible, use the lpmake route below"
        OVER=1
    else
        echo "  ok ${p}.img ${sz} B <= ${max} B"
    fi
done

if (( OVER )); then
    cat <<'EOF'

════════════════════════════════════════════════════════════════════
 Your images do not fit the existing slots. Two ways forward:

 (a) lpmake reassembly — you have 7.39 GiB free and an empty Slot B,
     so there is room. Build the new super with lpmake, giving each
     partition its new size. Template:

     lpmake \
       --metadata-size 65536 --metadata-slots 3 \
       --device super:16777216:4096 \
       --group qti_dynamic_partitions_a:9241726976 \
       --group qti_dynamic_partitions_b:9241726976 \
       --partition system_a:readonly:<sys_size>:qti_dynamic_partitions_a \
          --image system=./system.img \
       --partition system_ext_a:readonly:<sysext_size>:qti_dynamic_partitions_a \
          --image system_ext=./system_ext.img \
       --partition product_a:readonly:<prod_size>:qti_dynamic_partitions_a \
          --image product=./product.img \
       --partition vendor_a:readonly:2893135872:qti_dynamic_partitions_a \
          --image vendor=./vendor.img \
       --partition vendor_dlkm_a:readonly:33603584:qti_dynamic_partitions_a \
          --image vendor_dlkm=./vendor_dlkm.img \
       --partition odm_a:readonly:91205760:qti_dynamic_partitions_a \
          --image odm=./odm.img \
       --partition system_dlkm_a:readonly:7602176:qti_dynamic_partitions_a \
          --image system_dlkm=./system_dlkm.img \
       --sparse --output ./super.img

     Extract vendor.img etc. first with scripts/extract-vendor.sh.

 (b) Trim your build (drop GApps, drop unused products) until it fits.

 DO NOT flash a mismatched super. Wrong extent table = unbootable slot.
════════════════════════════════════════════════════════════════════
EOF
    exit 2
fi

# ── in-place overwrite ──────────────────────────────────────────────────────
log "assembling ${OUT} by in-place overwrite"
cp "${ORIG_SUPER}" "${OUT}"

for p in system system_ext product; do
    log "writing ${p}.img at 0x$(printf '%x' ${START[$p]})"
    dd if="${BUILT_DIR}/${p}.img" of="${OUT}" \
       bs=1048576 seek=$(( ${START[$p]} / 1048576 )) conv=notrunc status=none
done

log "done: ${OUT}"
log "next: patch vbmeta AVB flags to 0x02, then EDL flash super + vbmeta"
cat <<'EOF'

  python3 - <<'PY'
  data = bytearray(open('vbmeta.img','rb').read())
  data[12:16] = b'\x02\x00\x00\x00'      # disable verification + verity
  open('vbmeta_patched.img','wb').write(data)
  PY

  # then flash via the port package's fh_loader:
  #   super.img  -> label "super"   (start_sector 8968, 4194304 sectors)
  #   vbmeta_patched.img -> label "vbmeta_a" / "vbmeta_b"
  #   (or just the three logical partitions if you extracted them)

  Do NOT touch: vendor, vendor_dlkm, odm, system_dlkm, boot, init_boot,
  vendor_boot, dtbo, modem, dsp, tz, abl, xbl, recovery.
EOF
