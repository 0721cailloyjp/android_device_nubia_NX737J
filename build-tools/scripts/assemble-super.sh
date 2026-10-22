#!/usr/bin/env bash
#
# assemble-super.sh — 把编好的 system/system_ext/product 塞进 super.img
#
# 设计原则：**不硬编码任何分区偏移**。
# 所有 start / size 都在运行时从 ORIG_SUPER 的 LP 元数据现读，
# 因为手抄 hex→十进制踩过坑（7 个偏移错了 5 个，差 2 MiB 就能写坏 super）。
#
# 用法：
#   ./assemble-super.sh <编好的目录> <原始super.img> <输出super.img>
#
set -euo pipefail

BUILT_DIR="${1:?usage: assemble-super.sh <built-dir> <orig-super.img> <out.img>}"
ORIG_SUPER="${2:?usage: assemble-super.sh <built-dir> <orig-super.img> <out.img>}"
OUT="${3:?usage: assemble-super.sh <built-dir> <orig-super.img> <out.img>}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LPTOOL="${HERE}/dump-lp-metadata.py"

log()  { echo -e "\n\033[1;32m[super]\033[0m $*"; }
die()  { echo -e "\n\033[1;31m[super:FAIL]\033[0m $*"; exit 1; }

# ── 前置检查 ────────────────────────────────────────────────────────────────
for f in system system_ext product; do
    [[ -f "${BUILT_DIR}/${f}.img" ]] || die "缺 ${BUILT_DIR}/${f}.img"
done
[[ -f "${ORIG_SUPER}" ]] || die "缺 ${ORIG_SUPER}"
[[ -f "${LPTOOL}" ]] || die "缺 ${LPTOOL}（它和本脚本在同一个 scripts/ 目录）"
command -v python3 >/dev/null || die "需要 python3"

# ── 现读 LP 元数据（eval shell 变量，不落临时文件）──────────────────────────
log "从 $(basename "${ORIG_SUPER}") 读取 LP 元数据"
LPSH=$(python3 "${LPTOOL}" --shell "${ORIG_SUPER}") \
    || die "LP 解析失败，确认是 LP super.img 而不是裸镜像"
eval "${LPSH}"

IMG_SIZE="${LP_IMG_SIZE}"
UNIT="${LP_UNIT}"

lp() {   # lp <partition> <start|size>   大小写不敏感
    local field
    field=$(printf '%s' "$2" | tr '[:lower:]' '[:upper:]')
    local var="LP_$1_${field}"
    local val="${!var:-}"
    [[ -n "${val}" ]] || { echo "0"; return 1; }
    echo "${val}"
    return 0
}

log "super 大小 ${IMG_SIZE} B  extent 单位 ${UNIT} B"

# ── 打印完整表，便于人工核对 ────────────────────────────────────────────────
log "分区表（全部从元数据现读）"
printf "  %-14s %-14s %-14s %s\n" 分区 起始 大小 动作
for p in odm system system_dlkm system_ext product vendor vendor_dlkm; do
    s=$(lp "$p" start 2>/dev/null) || continue
    z=$(lp "$p" size 2>/dev/null) || continue
    case "$p" in
        system|system_ext|product) act="替换" ;;
        *)                          act="保留" ;;
    esac
    printf "  %-14s 0x%-12x %-14s %s\n" "$p" "$s" "$z" "$act"
done

# ── 尺寸检查 ────────────────────────────────────────────────────────────────
log "检查编好的镜像能否放进原槽位"
OVER=0
for p in system system_ext product; do
    SZ=$(stat -c%s "${BUILT_DIR}/${p}.img")
    MAX=$(lp "$p" size)
    if (( SZ > MAX )); then
        echo "  ✗ ${p}.img ${SZ} B > 槽位 ${MAX} B  (超出 $(( (SZ-MAX)/1024/1024 )) MiB)"
        OVER=1
    else
        echo "  ✓ ${p}.img ${SZ} B ≤ 槽位 ${MAX} B  (余量 $(( (MAX-SZ)/1024/1024 )) MiB)"
    fi
done

if (( OVER )); then
    GRP="${LP_GRP_qti_dynamic_partitions_a:-${LP_GRP_qti_dynamic_partitions:-0}}"
    USED=0
    for _v in $(compgen -v | grep -E '^LP_.*_SIZE$'); do USED=$(( USED + ${!_v} )); done
    cat <<EOF

════════════════════════════════════════════════════════════════════
 镜像放不下原槽位。两条路：

 (a) lpmake 重组（推荐，空闲空间足够）
     免费空间 ≈ $(( (IMG_SIZE - USED) / 1024 / 1024 / 1024 )) GiB
     用 scripts/extract-vendor.sh 先拆出 vendor 等四个保留分区，然后：

     lpmake \\
       --metadata-size 65536 --metadata-slots 3 \\
       --device super:${IMG_SIZE}:4096 \\
       --group qti_dynamic_partitions_a:${GRP} \\
       --group qti_dynamic_partitions_b:${GRP} \\
       --partition system_a:readonly:<新大小>:qti_dynamic_partitions_a \\
          --image system=${BUILT_DIR}/system.img \\
       --partition system_ext_a:readonly:<新大小>:qti_dynamic_partitions_a \\
          --image system_ext=${BUILT_DIR}/system_ext.img \\
       --partition product_a:readonly:<新大小>:qti_dynamic_partitions_a \\
          --image product=${BUILT_DIR}/product.img \\
       --partition vendor_a:readonly:$(lp vendor size):qti_dynamic_partitions_a \\
          --image vendor=<拆出来的>/vendor_a.img \\
       --partition vendor_dlkm_a:readonly:$(lp vendor_dlkm size):qti_dynamic_partitions_a \\
          --image vendor_dlkm=<拆出来的>/vendor_dlkm_a.img \\
       --partition odm_a:readonly:$(lp odm size):qti_dynamic_partitions_a \\
          --image odm=<拆出来的>/odm_a.img \\
       --partition system_dlkm_a:readonly:$(lp system_dlkm size):qti_dynamic_partitions_a \\
          --image system_dlkm=<拆出来的>/system_dlkm_a.img \\
       --sparse --output ./super.img

 (b) 砍内容（去掉 GApps、去掉不用的 product 包）直到放得下

 别强行刷不匹配的 super。extent 表错了 = 该槽位起不来。
════════════════════════════════════════════════════════════════════
EOF
    die "尺寸超限，未生成 ${OUT}"
fi

# ── DRY RUN 出口 ────────────────────────────────────────────────────────────
if [[ "${DRY_RUN:-0}" == "1" ]]; then
    log "DRY_RUN=1，不写文件。上面表格即最终偏移与动作。"
    exit 0
fi

# ── 原地覆盖 ────────────────────────────────────────────────────────────────
log "复制原 super 到 ${OUT}"
cp "${ORIG_SUPER}" "${OUT}"

for p in system system_ext product; do
    SRC="${BUILT_DIR}/${p}.img"
    SZ=$(stat -c%s "${SRC}")
    S=$(lp "$p" start)
    M=$(lp "$p" size)

    # 起始必须 1 MiB 对齐，否则 dd 的 bs 就没法用
    if (( S % 1048576 != 0 )); then
        die "${p} 起始 0x$(printf '%x' "${S}") 不是 1 MiB 对齐，需改用 bs=4096 版本"
    fi

    log "写入 ${p}.img  ${SZ} B -> 0x$(printf '%x' "${S}")"
    dd if="${SRC}" of="${OUT}" bs=1048576 seek=$(( S / 1048576 )) \
       conv=notrunc status=none

    # 清零槽位剩余部分（上一版镜像的尾巴不该留着）
    ZERO_FROM=$(( (S + SZ + 4095) / 4096 * 4096 ))
    ZERO_LEN=$(( S + M - ZERO_FROM ))
    if (( ZERO_LEN > 0 )); then
        dd if=/dev/zero of="${OUT}" bs=4096 seek=$(( ZERO_FROM / 4096 )) \
           count=$(( ZERO_LEN / 4096 )) conv=notrunc status=none
        log "  清零尾部 $(( ZERO_LEN / 1024 / 1024 )) MiB"
    fi
done

log "完成：${OUT}  ($(stat -c%s "${OUT}") B)"
cat <<'EOF'

下一步：关掉 vbmeta 的 AVB 校验再刷
  python3 - <<'PY'
  d = bytearray(open('vbmeta.img','rb').read())
  d[12:16] = b'\x02\x00\x00\x00'      # disable verification + verity
  open('vbmeta_patched.img','wb').write(d)
  PY

刷写时只动：
  super.img              -> label "super"
  vbmeta_patched.img     -> vbmeta_a / vbmeta_b

绝对不要碰：
  vendor / vendor_dlkm / odm / system_dlkm 的源文件（已在 super 里原样保留）
  boot / init_boot / vendor_boot / dtbo / modem / dsp / tz / abl / xbl / recovery
EOF
