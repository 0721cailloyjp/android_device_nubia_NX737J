#!/usr/bin/env bash
#
# 10-verify-out.sh — 编完立刻自检 $OUT，把「刷上去才发现」的问题提前抓出来
#
# 为什么需要：编译成功 ≠ 能开机。这里检查的都是**编译能过、但上去必挂**的项：
#   · build.prop 少了 ro.board.api_level   → VINTF 判不兼容，开机直接卡住
#   · build.prop 多了 ro.vndk.version      → 与「A15 vendor 不声明 VNDK」的现状冲突
#   · 努比亚 App 没进镜像                  → 白折腾，特性没了
#   · transferclient.jar 有 XML 没 jar     → PackageManager 报 Could not find library
#   · 镜像大小超出 super 分区槽位           → 刷机失败 / 写坏相邻分区
#
# 用法：
#   bash scripts/10-verify-out.sh                 # 用 $OUT 或 out/target/product/NX737J
#   bash scripts/10-verify-out.sh /path/to/out    # 指定
#
# 退出码：0 = 全过；1 = 有 FAIL
set -uo pipefail

export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && { pwd -W 2>/dev/null || pwd; })"
ROOT="$(cd "${HERE}/.." && { pwd -W 2>/dev/null || pwd; })"
DEV="${ROOT}/device-nubia-NX737J"

OUT="${1:-${OUT:-${ROOT}/out/target/product/NX737J}}"

PASS=0; FAIL=0; WARN=0
pass() { printf '  \033[1;32m✓\033[0m %s\n' "$*"; PASS=$((PASS+1)); }
fail() { printf '  \033[1;31m✗\033[0m %s\n' "$*"; FAIL=$((FAIL+1)); }
warn() { printf '  \033[1;33m!\033[0m %s\n' "$*"; WARN=$((WARN+1)); }
head_() { printf '\n\033[1;36m▸ %s\033[0m\n' "$*"; }

[[ -d "$OUT" ]] || { echo "找不到 $OUT"; exit 1; }
echo "自检目录：$OUT"

# ── 1. build.prop 关键属性 ──────────────────────────────────────────────────
head_ "build.prop 关键属性"
BP="$OUT/system/build.prop"
if [[ -f "$BP" ]]; then
    getprop_() { grep -E "^$1=" "$BP" | tail -1 | cut -d= -f2- | tr -d '\r'; }

    v=$(getprop_ ro.board.api_level)
    case "$v" in
        202404) pass "ro.board.api_level = $v" ;;
        "")     fail "ro.board.api_level **缺失** —— VINTF 会退回 sdk=37，和厂商 manifest 的 202404 判不兼容，开不了机" ;;
        *)      fail "ro.board.api_level = $v（应为 202404）" ;;
    esac

    v=$(getprop_ ro.vndk.version)
    case "$v" in
        "")     pass "ro.vndk.version 未设置（与原机一致，走 LLNDK + vendor snapshot）" ;;
        *)      warn "ro.vndk.version = $v —— 原机是空的。不一定会挂，但要留意 linker 会不会去找 vndk-$v" ;;
    esac

    v=$(getprop_ ro.product.first_api_level)
    case "$v" in
        35) pass "ro.product.first_api_level = $v" ;;
        "") fail "ro.product.first_api_level 缺失（PRODUCT_SHIPPING_API_LEVEL 没生效？）" ;;
        *)  warn "ro.product.first_api_level = $v（原机 35）" ;;
    esac

    v=$(getprop_ ro.zygote)
    case "$v" in
        zygote64) pass "ro.zygote = zygote64" ;;
        *)        warn "ro.zygote = ${v:-<空>}（树里写的是 zygote64）" ;;
    esac

    # 目标机型身份，确认没被别的树覆盖
    v=$(getprop_ ro.product.device)
    case "$v" in
        NX737J) pass "ro.product.device = NX737J" ;;
        *)      warn "ro.product.device = ${v:-<空>}" ;;
    esac
    v=$(getprop_ ro.product.model)
    case "$v" in
        *Z70S*) pass "ro.product.model = $v" ;;
        *)      warn "ro.product.model = ${v:-<空>}（预期含 Z70S Ultra）" ;;
    esac
else
    fail "没有 $BP（没编 systemimage？）"
fi

# ── 2. 努比亚组件是否真的进了镜像 ───────────────────────────────────────────
head_ "努比亚组件回注"
declare -a NEED=(
    "system/app/NBAccount/NBAccount.apk"
    "system/app/NBUserCenter/NBUserCenter.apk"
    "system/app/zteaccount_mfv/zteaccount_mfv.apk"
    "system/priv-app/Wallet/Wallet.apk"
    "system/priv-app/WalletCore/WalletCore.apk"
    "system/app/cc/cc.apk"
    "system_ext/framework/vendor.zte.hardware.camera.transferclient.jar"
    "system_ext/framework/com.st.android.nfc_extensions.jar"
    "system_ext/framework/com.st.android.nfc_extensions_16.jar"
    "system_ext/etc/permissions/vendor.zte.hardware.camera.transferclient.xml"
    "system_ext/etc/permissions/com.st.android.nfc_extensions.xml"
    "system_ext/etc/permissions/com.st.android.nfc_extensions_16.xml"
    "system/etc/permissions/privapp_permissions_whitelist_com.zte.wallet.xml"
)
for f in "${NEED[@]}"; do
    if [[ -s "$OUT/$f" ]]; then
        pass "$(printf '%-70s %8.1f KB' "$f" "$(stat -c%s "$OUT/$f" | awk '{print $1/1024}')")"
    else
        fail "缺 $f"
    fi
done

# 库声明指向的 jar 必须存在，否则 PackageManager 报 Could not find library
# 逐个扫 system_ext/etc/permissions，凡是声明了 file="/system_ext/framework/..." 的都要核对
if [[ -d "$OUT/system_ext/etc/permissions" ]]; then
    found_any=0
    while IFS= read -r x; do
        found_any=1
        jar=$(grep -oE 'file="[^"]+"' "$x" 2>/dev/null | head -1 | sed 's/file="//;s/"//')
        [[ -n "$jar" ]] || continue
        rel="${jar#/}"
        if [[ -s "$OUT/$rel" ]]; then
            pass "$(basename "$x") → ${jar} 存在"
        else
            fail "$(basename "$x") 指向 ${jar}，但镜像里**没有这个文件**"
        fi
    done < <(grep -l 'file="/system_ext/framework/' "$OUT"/system_ext/etc/permissions/*.xml 2>/dev/null)
    (( found_any )) || warn "system_ext/etc/permissions 里没有任何 <library> 声明（库都丢了？）"
fi

# ── 3. 不该出现的东西 ───────────────────────────────────────────────────────
head_ "冲突检查（AOSP 同名包 / 小米残留）"
for bad in \
    "system/app/Nfc_st"          `# com.android.nfc，会和 NfcNci 撞包` \
    "system_ext/app/CameraMind"  `# com.xiaomi.cameramind，依赖 miui 类` \
    "system/app/CameraExtensionsProxy" \
    "system/app/RomFixCameraCompat" ; do
    [[ -e "$OUT/$bad" ]] && warn "$bad 竟然在镜像里（应当排除）" || pass "$bad 已排除"
done
for bad in "system/framework/miui-framework.jar" "system_ext/framework/miui-services.jar"; do
    [[ -e "$OUT/$bad" ]] && warn "$bad 出现在镜像里（小米残留？）" || pass "无 $(basename "$bad")"
done

# ── 4. 镜像文件与大小 ───────────────────────────────────────────────────────
head_ "镜像产物"
# super 槽位（NX737J 实测，512B 单位换算成字节）
declare -A SLOT=(
    [system.img]=1109176320
    [system_ext.img]=885358592
    [product.img]=4215025664
)
for img in system.img system_ext.img product.img; do
    p="$OUT/$img"
    if [[ ! -f "$p" ]]; then
        # product 默认沿用原厂，不编是正常的
        [[ "$img" == "product.img" ]] && { pass "$img 未编（沿用原厂 product，符合预期）"; continue; }
        fail "缺 $img"
        continue
    fi
    sz=$(stat -c%s "$p")
    lim=${SLOT[$img]:-0}
    if (( lim > 0 && sz > lim )); then
        fail "$(printf '%s 大小 %.1f MiB 超出 super 槽位 %.1f MiB' "$img" "$(awk "BEGIN{print $sz/1048576}")" "$(awk "BEGIN{print $lim/1048576}")")"
    else
        pass "$(printf '%-16s %8.1f MiB (槽位 %.1f MiB)' "$img" "$(awk "BEGIN{print $sz/1048576}")" "$(awk "BEGIN{print $lim/1048576}")")"
    fi
done

# 文件系统类型：必须是 erofs / f2fs 之一，不能是 ext4（原厂是 erofs，fstab 依赖）
head_ "文件系统类型"
for img in system.img system_ext.img; do
    p="$OUT/$img"
    [[ -f "$p" ]] || continue
    magic=$(dd if="$p" bs=1 skip=1024 count=4 2>/dev/null | od -An -tx1 | tr -d ' \n')
    case "$magic" in
        e2e1f5e0*) pass "$img = erofs" ;;
        *)         warn "$img 魔数 $magic（预期 erofs 的 e2e1f5e0）" ;;
    esac
done

# ── 汇总 ────────────────────────────────────────────────────────────────────
printf '\n────────────────────────────────────────────\n'
printf '  通过 %d   警告 %d   失败 %d\n' "$PASS" "$WARN" "$FAIL"
if (( FAIL > 0 )); then
    printf '  \033[1;31m有 %d 项失败，先修完再刷机\033[0m\n' "$FAIL"
    exit 1
fi
printf '  \033[1;32m可以进打包流程\033[0m\n'
[[ "$WARN" -gt 0 ]] && printf '  （警告项不阻塞，但刷上去留意对应功能）\n'
