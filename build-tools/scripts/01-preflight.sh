#!/usr/bin/env bash
#
# 01-preflight.sh — sync 之后、编译之前的 2 分钟体检
#
# 为什么要有这一步：
#   编译一次要 65~160 分钟（¥9~15）。而绝大多数失败原因（缺仓库、.mk 写错、
#   变量没生效、工具版本不够）都能在 lunch 阶段就暴露，几秒钟的事。
#   这个脚本把能提前验的全验一遍，把失败成本从"半小时 + 十几块"降到"两分钟 + 零"。
#
# 用法（必须在 00-prep 和 02-sync 之后）：
#   bash scripts/01-preflight.sh
#
set -uo pipefail

DATA="${DATA:-/data}"
TREE="${TREE:-${DATA}/pixelos}"
VARIANT="${VARIANT:-userdebug}"

FAIL=0
ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
bad()  { printf '  \033[1;31m✗\033[0m %s\n' "$*"; FAIL=$((FAIL+1)); }
warnp(){ printf '  \033[1;33m!\033[0m %s\n' "$*"; }
sec()  { printf '\n\033[1;36m── %s ──\033[0m\n' "$*"; }

cd "${TREE}" 2>/dev/null || { echo "源码目录 ${TREE} 不存在，先跑 02-sync.sh"; exit 1; }

# ═══ 1. 源码树完整性 ════════════════════════════════════════════════════════
sec "1/6 源码树"
for d in build frameworks/base system/core hardware/interfaces prebuilts/clang \
         prebuilts/tools external/soong; do
    [[ -d "$d" ]] && ok "$d" || bad "$d 缺失（sync 没跑完）"
done

# ═══ 2. 设备树与依赖仓库 ════════════════════════════════════════════════════
sec "2/6 设备树与依赖仓库"
for d in device/nubia/NX737J device/qcom/sepolicy_vndr device/lineage/sepolicy vendor/lineage; do
    [[ -d "$d" ]] && ok "$d" || bad "$d 缺失 —— 见 RUNBOOK 7.2"
done

if [[ -d device/nubia/NX737J ]]; then
    for f in AndroidProducts.mk BoardConfig.mk device.mk lineage_NX737J.mk system.prop prebuilts/Image; do
        p="device/nubia/NX737J/$f"
        [[ -e "$p" ]] && ok "  $f ($(stat -c%s "$p" 2>/dev/null || echo '?') B)" \
                      || bad "  $f 缺失"
    done
    # 内核镜像不能是空壳
    if [[ -f device/nubia/NX737J/prebuilts/Image ]]; then
        SZ=$(stat -c%s device/nubia/NX737J/prebuilts/Image)
        MAGIC=$(dd if=device/nubia/NX737J/prebuilts/Image bs=1 skip=56 count=4 2>/dev/null | od -An -c | tr -d ' \n')
        if [[ "${SZ}" -gt 20000000 ]]; then ok "  内核 ${SZ} B"; else bad "  内核只有 ${SZ} B，太小"; fi
        [[ "${MAGIC}" == "ARMd" ]] && ok "  ARM64 magic 正确（ARMd）" \
            || warnp "  ARM64 magic 读到 '${MAGIC}'（期望 ARMd），可能内核被压缩了"
    fi
fi

# ═══ 3. lunch（这一步会真正解析所有 .mk）════════════════════════════════════
sec "3/6 lunch 解析（最关键的体检）"
log_lunch() { echo "$*"; }
# shellcheck disable=SC1091
source build/envsetup.sh >/dev/null 2>&1 || { bad "build/envsetup.sh 失败"; exit 1; }

LUNCH_LOG=$(mktemp)
if breakfast NX737J "${VARIANT}" >"${LUNCH_LOG}" 2>&1; then
    ok "breakfast NX737J ${VARIANT} 成功"
else
    bad "breakfast 失败。错误摘录："
    tail -25 "${LUNCH_LOG}" | sed 's/^/      /'
    rm -f "${LUNCH_LOG}"
    echo
    echo "  常见原因："
    echo "    · product makefile 路径写错（device/nubia/NX737J/device.mk）"
    echo "    · 缺 include 的 .mk（sepolicy_vndr / vendor/lineage / qcom-caf）"
    echo "    · 变量名拼错"
    exit 1
fi
rm -f "${LUNCH_LOG}"

# ═══ 4. 关键变量是否真的生效 ═════════════════════════════════════════════════
sec "4/6 关键变量回读（get_build_var）"
gbv() {
    local v="$1" want="$2" got
    got=$(get_build_var "$v" 2>/dev/null)
    if [[ -z "${want}" ]]; then
        printf '  %-42s = %s\n' "$v" "${got:-<空>}"
        return
    fi
    if [[ "${got}" == "${want}" ]]; then
        ok "$(printf '%-40s = %s' "$v" "${got}")"
    else
        bad "$(printf '%-40s = %s (期望 %s)' "$v" "${got:-<空>}" "${want}")"
    fi
}

gbv TARGET_BOARD_PLATFORM sun
gbv TARGET_BOOTLOADER_BOARD_NAME sun
gbv BOARD_SYSTEMIMAGE_FILE_SYSTEM_TYPE erofs
gbv BOARD_SYSTEM_EXTIMAGE_FILE_SYSTEM_TYPE erofs
gbv BOARD_PRODUCTIMAGE_FILE_SYSTEM_TYPE erofs
gbv PRODUCT_USE_DYNAMIC_PARTITIONS true
gbv PRODUCT_SHIPPING_API_LEVEL 35
gbv BOARD_SUPER_PARTITION_SIZE 17179869184
gbv BOARD_AVB_ENABLE true
gbv TARGET_USES_PREBUILT_VENDOR_SEPOLICY true
echo
printf '  %-42s = %s\n' "TARGET_PREBUILT_KERNEL"  "$(get_build_var TARGET_PREBUILT_KERNEL 2>/dev/null)"
printf '  %-42s = %s\n' "TARGET_KERNEL_VERSION"   "$(get_build_var TARGET_KERNEL_VERSION 2>/dev/null)"
printf '  %-42s = %s\n' "PRODUCT_OUT"             "$(get_build_var PRODUCT_OUT 2>/dev/null)"
printf '  %-42s = %s\n' "PRODUCT_DEVICE"          "$(get_build_var PRODUCT_DEVICE 2>/dev/null)"

P_OUT="$(get_build_var PRODUCT_OUT 2>/dev/null)"
[[ -n "${P_OUT}" ]] && ok "PRODUCT_OUT = ${P_OUT}" || bad "PRODUCT_OUT 为空"

# ═══ 5. 工具链版本 ══════════════════════════════════════════════════════════
sec "5/6 工具链"
EROFS_V="$(mkfs.erofs --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)"
if [[ -n "${EROFS_V}" ]]; then
    MAJ="${EROFS_V%%.*}"; MIN="${EROFS_V##*.}"
    if (( MAJ > 1 )) || (( MAJ == 1 && MIN >= 6 )); then
        ok "mkfs.erofs ${EROFS_V}（≥1.6，支持 -C/dedupe）"
    else
        warnp "mkfs.erofs ${EROFS_V} < 1.6，若编译报 'unknown option -C' 需升级（见 00-prep.sh 提示）"
    fi
else
    bad "mkfs.erofs 不存在"
fi

command -v fsck.erofs >/dev/null && ok "fsck.erofs 可用" || warnp "fsck.erofs 缺失（打包校验会跳过）"
command -v java >/dev/null && ok "java $(java -version 2>&1 | head -1 | grep -oE '[0-9]+[^ ]*' | head -1)" \
    || warnp "系统 java 不在 PATH（AOSP 自带 prebuilts/jdk 通常够用）"
command -v ccache >/dev/null && ok "ccache 可用" || warnp "ccache 缺失（不影响编译，只是慢）"

# ═══ 6. 资源 ════════════════════════════════════════════════════════════════
sec "6/6 资源"
RAM=$(free -g | awk '/^Mem:/{print $2}')
SWAP=$(free -g | awk '/^Swap:/{print $2}')
FREE=$(df -BG "${TREE}" | awk 'NR==2{gsub("G","",$4); print $4}')
CORES=$(nproc)
printf '  CPU %-3s 核   RAM %-3s G   SWAP %-3s G   可用磁盘 %-4s G\n' "${CORES}" "${RAM}" "${SWAP:-0}" "${FREE}"
(( RAM >= 32 )) && ok "内存 ${RAM}G 够用" || warnp "内存只有 ${RAM}G，建议 ≥32G，否则 soong 分析阶段会很慢"
(( ${SWAP:-0} >= 8 )) && ok "swap ${SWAP}G" || warnp "swap 只有 ${SWAP:-0}G，建议 ≥16G 兜底"
(( FREE >= 40 )) && ok "磁盘余量 ${FREE}G" || bad "磁盘只剩 ${FREE}G，编译 + out 目录可能不够"

# ═══ 结论 ════════════════════════════════════════════════════════════════════
printf '\n\033[1;36m════════════════════════════════════════════════════\033[0m\n'
if (( FAIL == 0 )); then
    printf '\033[1;32m  体检通过，可以开始编译\033[0m\n'
    printf '    bash scripts/03-build.sh\n'
    printf '  预计：%s 核 / %s G 内存 → jobs=%s，耗时 65~160 分钟\n' \
        "${CORES}" "${RAM}" "$(( RAM/2 < CORES ? RAM/2 : CORES ))"
else
    printf '\033[1;31m  有 %d 项不通过，先修再编译（省时间省钱）\033[0m\n' "${FAIL}"
fi
printf '\033[1;36m════════════════════════════════════════════════════\033[0m\n'
exit $(( FAIL > 0 ? 1 : 0 ))
