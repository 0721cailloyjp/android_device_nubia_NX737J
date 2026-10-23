#!/usr/bin/env bash
#
# 09-pull-nubia-apps.sh — 从你自己的手机里把努比亚系统 App 拉出来（在**本地 PC**上跑）
#
# 为什么用手机而不是 super.img：
#   手机 /system 里现成就有这些 App，6 个 App + 3 个 jar 一共约 62 MB，adb pull 几秒钟。
#   而 super.img 有 16 GB，传到云服务器再解包要很久。
#
# 前提：手机已 root 或至少能 adb 读 /system（移植包的 /system 可读）
#
# 用法：
#   bash 09-pull-nubia-apps.sh                 # 自动找、自动拉
#   bash 09-pull-nubia-apps.sh --list          # 只列出找到什么，不拉
#
set -uo pipefail

# ⚠️ Git Bash / MSYS2 会把「看起来像路径」的参数改写成 Windows 路径：
#      adb pull /system/app/NBAccount/NBAccount.apk  →
#      adb: error: failed to stat remote object
#        'C:/Users/xxx/PortableGit/system/app/NBAccount/NBAccount.apk'
#    所以全局关掉路径转换（MSYS_NO_PATHCONV），改由本脚本自己保证：
#      · 手机端路径  原样传（/system/... 不动）
#      · 本地路径    一开始就用 Windows 形式（pwd -W 取 F:/...），不依赖转换
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && { pwd -W 2>/dev/null || pwd; })"
ROOT="$(cd "${HERE}/.." && { pwd -W 2>/dev/null || pwd; })"
DEV="${ROOT}/device-nubia-NX737J"
OUT="${DEV}/prebuilts/nubia-apps"
MK="${DEV}/nubia-apps.mk"

LISTONLY=0
for a in "$@"; do
    case "$a" in
        --list)  LISTONLY=1 ;;
    esac
done

say()  { printf '\033[1;36m[nubia]\033[0m %s\n' "$*"; }
ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33m!\033[0m %s\n' "$*"; }

# ── 0. adb（自动在常见位置找）───────────────────────────────────────────────
if ! command -v adb >/dev/null 2>&1; then
    for c in "/c/Qntool/adb.exe" \
             "$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe" \
             "/c/platform-tools/adb.exe" "/d/platform-tools/adb.exe" \
             "/e/NX737J_HyperOS_4.0.0.10_A17_10.12/FlashTool/adb.exe"; do
        if [[ -x "$c" ]]; then
            export PATH="$(dirname "$c"):$PATH"
            echo "使用 adb: $c"
            break
        fi
    done
fi
command -v adb >/dev/null 2>&1 || {
    echo "找不到 adb。已试过：C:/Qntool、%LOCALAPPDATA%/Android/Sdk/platform-tools、各盘 platform-tools、"
    echo "                以及移植包自带的 FlashTool/adb.exe"
    echo "装 platform-tools，或把 adb 所在目录加进 PATH 后重跑。"
    exit 1
}
adb devices | grep -qw device || { echo "adb 看不到设备。先开 USB 调试并授权。"; exit 1; }
RDEV=$(adb shell getprop ro.product.device 2>/dev/null | tr -d '\r')
MODEL=$(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r')
BRAND=$(adb shell getprop ro.product.brand 2>/dev/null | tr -d '\r')
REL=$(adb shell getprop ro.build.version.release 2>/dev/null | tr -d '\r')
say "设备：${RDEV}  /  ${MODEL}  /  ${BRAND}  /  Android ${REL}"

# 设备提示（**不阻断**）
#
# 设备标识名是移植包作者**刻意**设成小米 15 Pro 的（ro.product.device=haotian /
# model=2410DPN6CC / brand=Xiaomi），硬件是 Z70S。所以「brand 不是 nubia」不代表
# 连错了机器，只提示一句，继续往下走。
if ! case "${BRAND}${RDEV}${MODEL}" in *nubia*|*Nubia*|*ZTE*|*zte*|*NX737*|*NX789*) true;; *) false;; esac; then
    warn "这台的身份属性不是努比亚（brand=${BRAND} device=${RDEV} model=${MODEL}）"
    warn "移植包保留源 ROM 身份时会出现这种情况，属正常。继续查找。"
fi

# ── 1. 定位 APK ─────────────────────────────────────────────────────────────
# 以「目录名 = APK 名」为主（这是扫 super.img 实测出来的，最可靠），
# pm path 作为辅助（用于确认包名，顺便拿到真实路径）。
#
# ⚠️ 这里的名单是**逐个 dex 校验过**的，不是凭目录名猜的。
#    手机当前跑的是澎湃4 移植包，它的 /system 本身就是小米的，
#    所以里面混着一批「不是努比亚」的东西，必须剔掉：
#
#    ✗ CameraMind        → com.xiaomi.cameramind      小米相机大脑，引用 Lmiui/app/MiuiFreeFormManager
#    ✗ Nfc_st            → com.android.nfc            本质是 AOSP NFC 应用的小米定制版，
#                                                     引用 Lcom/xiaomi/nfc/IMiNfcAdapter、Lmiui/os/HyperOSCustFeatureResolve；
#                                                     而且会和 AOSP 自带的 NfcNci **撞包名**，绝不能带
#    ✗ CameraExtensionsProxy → com.android.cameraextensions
#                                                     与 AOSP 同名包冲突风险 > 收益，v1 不带
#    ✗ RomFixCameraCompat    → com.cc.romfix.cameracompat  移植者自加的兼容补丁，跟我们无关
#
#    ✓ 下面这些是真正的努比亚/ZTE 组件，dex 里没有 miui/xiaomi 框架依赖
#
# ⚠️ WalletSupport（com.zte.wallet.support，47 MB）**故意不带**：
#    1. 它缺 6 个外部类（com.zte.aimodel.*、com.zte.ctsutils.CtsUtils、com.zte.feature.Feature），
#       核心的 AI / 语音能力在 AOSP 上本来就跑不起来 —— 你现在的移植包也一样缺；
#    2. 47 MB 单个 blob 过不了 GitHub Git Data API（实测 HTTP 422
#       "input was too large to process"，JSON base64 的实际上限在 40~50 MB）。
#    真要加的话走 Release 资产（单文件上限 2 GB），别塞进 git：
#        gh release upload <tag> WalletSupport.apk
#    然后在 02-sync 阶段 curl 下来，再在 nubia-apps.mk 里补一行 PRODUCT_COPY_FILES。
#
# 条目格式： 名称  或  名称=安装目录
#   默认「安装目录 = 名称」，即找 <dir>/<dir>.apk。
#   目录名和 APK 名不一致时必须写成 名称=目录，否则找不到。
declare -a WANT=(
    NBAccount              # cn.nubia.accounts      努比亚账号
    NBUserCenter           # cn.nubia.usercenter    努比亚用户中心
    zteaccount_mfv         # org.zx.AuthComp        ZTE 统一认证组件
    Wallet                 # com.zte.wallet         ZTE 钱包（priv-app）
    WalletCore             # com.zte.wallet.core    ZTE 钱包核心（priv-app）
    CCSetting=cc           # com.cc.setting         ★移植者的「高级设置」，见下方说明
)

# ★ CCSetting（/system/app/cc/cc.apk，包名 com.cc.setting，v2.0）
#   移植包作者自己写的努比亚功能开关，dex 完全自包含（1561 个类，零外部依赖），
#   所以搬到 AOSP 上照样能跑。它靠 su 提权直接写 sysfs，控制：
#     风扇    /sys/kernel/fan/fan_enable, fan_speed_level
#     充电    /sys/kernel/nubia_charge/charger_bypass, /sys/class/qcom-battery/charge_mode
#     灯效    /sys/class/leds/aw22xxx_led/cfg, effect
#     SAR     /sys/class/leds/sar0/mode_operation, sar1
#     CPU     /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq
#     设备名  persist.cc.device.name   ← 设置里的设备显示名（用户改的 mix7）
#   只申请普通权限（INTERNET/存储/VIBRATE/ACCESS_WIFI_STATE），没有 priv-app 特权权限，
#   放 /system/app 零风险。
#   ⚠️ 它写 sysfs 要 root。刷完我们的包后如果没装 KernelSU 管理器并授权，
#      这个 App 打开会没有实际效果（界面能开，开关不生效）。

# 非 APK 的配套文件：Java 库 + 它们自己的 <library> 声明
#
# ① transferclient.jar —— 努比亚相机流转（把相机画面投给别的设备）的 Java 层 API。
#    对应的 XML 用 <library file="..."> 指向它。少一个，声明就指向空文件，
#    PackageManager 会报 "Could not find library"，用到它的 App 直接崩。
#
# ② com.st.android.nfc_extensions*.jar —— 意法半导体 ST54L 的 NFC 扩展 API。
#    这台机器 NFC 芯片就是 ST54L（实测 ro.vendor.feature.board_uses_nfc = ST54L），
#    而且 ZTE 钱包的 dex 里有 4 处 Lcom/st/... 引用，说明刷卡走的就是这套。
#    AOSP 的 NfcNci 只能做基础 NFC；门禁卡 / 公交卡这类 eSE 操作要靠这两个库。
#    325 KB，纯 Java 库、不占包名、不会和 AOSP 撞车，没有理由不带。
declare -a EXTRA=(
    /system_ext/framework/vendor.zte.hardware.camera.transferclient.jar
    /system_ext/framework/com.st.android.nfc_extensions.jar
    /system_ext/framework/com.st.android.nfc_extensions_16.jar
)

declare -a FOUND=()
declare -a XSAVED=()

say "逐个定位（先扫目录，再试 find）"
for entry in "${WANT[@]}"; do
    name="${entry%%=*}"
    adir="${entry#*=}"
    [[ "$adir" == "$entry" ]] && adir="$name"     # 没写 =目录 就用同名
    path=""
    # 1a. 扫常见安装目录
    for d in /system/priv-app /system/app /system_ext/priv-app /system_ext/app /product/priv-app /product/app; do
        cand="$d/$adir/$adir.apk"
        if adb shell "[ -f $cand ]" 2>/dev/null; then path="$cand"; break; fi
    done
    # 1b. 目录名不叫这个时，模糊找一次
    if [[ -z "$path" ]]; then
        path=$(adb shell "find /system /system_ext /product -name '${adir}.apk' 2>/dev/null" 2>/dev/null \
               | tr -d '\r' | head -1)
    fi
    if [[ -n "$path" ]]; then
        sz=$(adb shell "stat -c %s $path 2>/dev/null" 2>/dev/null | tr -d '\r')
        ok "$(printf '%-24s %-58s %s B' "$name" "$path" "${sz:-?}")"
        FOUND+=( "${name}|${path}" )
    else
        warn "$(printf '%-24s 未找到（找的是 %s.apk）' "$name" "$adir")"
    fi
done

if (( ${#FOUND[@]} == 0 )); then
    echo
    echo "一个都没找到。先看看这台机器上到底有哪些努比亚包："
    adb shell 'pm list packages | grep -iE "nubia|zte"' | tr -d '\r' | head -40 | sed 's/^/    /'
    echo
    echo "把上面输出贴给我，我按真实包名改 WANT 列表。"
    exit 1
fi

(( LISTONLY )) && { echo; echo "--list 模式，不下载。找到 ${#FOUND[@]} 个。"; exit 0; }

# ── 2. 拉取 ─────────────────────────────────────────────────────────────────
mkdir -p "${OUT}"
say "拉取到 ${OUT}"
declare -a SAVED=()
for entry in "${FOUND[@]}"; do
    IFS='|' read -r name path <<< "$entry"
    dst="${OUT}/${name}.apk"
    if adb pull "$path" "$dst" >/dev/null 2>&1 && [[ -s "$dst" ]]; then
        ok "$(printf '%-24s %8d B' "$name.apk" "$(stat -c%s "$dst")")"
        SAVED+=( "${name}|${path}" )
    else
        warn "$name 拉取失败（$path）"
    fi
done

(( ${#SAVED[@]} > 0 )) || { echo "全部拉取失败。可能 /system 需要 root 才能读，试试：adb root"; exit 1; }

# ── 2b. 配套的 jar / 其它文件 ───────────────────────────────────────────────
declare -a ESAVED=()
for src in "${EXTRA[@]}"; do
    bn="${src##*/}"
    dst="${OUT}/${bn}"
    if adb pull "$src" "$dst" >/dev/null 2>&1 && [[ -s "$dst" ]]; then
        ok "$(printf '%-52s %8d B' "$bn" "$(stat -c%s "$dst")")"
        ESAVED+=( "${bn}|${src}" )
    else
        warn "$bn 拉取失败（$src）"
    fi
done

# ── 3. 找 privapp-permissions ───────────────────────────────────────────────
# 这些 XML 声明了努比亚 App 的特权权限。**必须跟着 App 一起回注**，
# 否则开机时 system_server 会因 Signature|privileged 权限未在白名单里而拒绝授权，
# 表现为 App 打开就崩、或账号/NFC 功能静默失效。
say "找相关的权限 / 库声明 XML"
# 匹配规则要同时覆盖三类：
#   ① 努比亚/ZTE 自家的（nubia|zte）
#   ② ST54L NFC 扩展的 <library> 声明（com.st.android.nfc_extensions）
# 注意别把 com.nxp.nfc.* 一起捞进来 —— 这台机器的 NFC 芯片是 ST，不是 NXP。
PMAP=$(adb shell 'for d in /system/etc/permissions /system_ext/etc/permissions /product/etc/permissions; do ls -1 $d 2>/dev/null | sed "s|^|$d/|"; done' 2>/dev/null \
       | tr -d '\r' | grep -iE 'nubia|zte|com\.st\.android\.nfc_extensions' || true)
if [[ -z "$PMAP" ]]; then
    warn "没找到 nubia/zte 相关的权限 XML（可能本来就没有，或用了别的命名）"
else
    declare -a XSAVED=()
    while IFS= read -r x; do
        [[ -n "$x" ]] || continue
        if adb pull "$x" "${OUT}/" >/dev/null 2>&1; then
            ok "${x##*/}"
            XSAVED+=( "${x##*/}|${x}" )
        fi
    done <<< "$PMAP"
fi

# ── 4. 生成打包规则 ─────────────────────────────────────────────────────────
say "生成 ${MK##*/}"
{
    echo "# 自动生成，勿手改 —— 由 scripts/09-pull-nubia-apps.sh 产出"
    echo "#"
    echo "# 回注的努比亚 / ZTE 组件。每一项都做过 dex 检查，确认不依赖 miui/xiaomi 框架类。"
    echo "#"
    echo "# 为什么要回注：我们把 /system 和 /system_ext 换成 AOSP，这两个分区里的"
    echo "# 厂商 App 会一起消失。账号、钱包这类东西是跟努比亚账号体系绑的，"
    echo "# AOSP 补不出来，只能原样搬回去。"
    echo "#"
    echo "# 为什么放在同一分区：privapp-permissions XML 是按分区的 etc/permissions 扫描的。"
    echo "# 把 priv-app 的 App 挪到别处会让它的特权权限失配，开机后 Signature|privileged 报错。"
    echo ""
} > "${MK}"

for entry in "${SAVED[@]}"; do
    name="${entry%%|*}"
    orig="${entry##*|}"
    # 目标路径 = 原路径，去掉最前面的 /（保持在同一分区）
    #   /system/app/Foo/Foo.apk      → system/app/Foo/Foo.apk
    #   /system_ext/app/Bar/Bar.apk  → system_ext/app/Bar/Bar.apk
    # 分区必须保持一致：privapp-permissions XML 是按分区的 etc/permissions 扫描的，
    # 把 system_ext 的 App 挪到 /system 会让它的特权权限失配（开机后 Signature|privileged 报错）。
    dest="${orig#/}"
    {
        echo "PRODUCT_COPY_FILES += \\"
        echo "    \$(LOCAL_PATH)/prebuilts/nubia-apps/${name}.apk:\$(TARGET_COPY_OUT_$(printf '%s' "${dest%%/*}" | tr '[:lower:]' '[:upper:]'))/${dest#*/}"
        echo ""
    } >> "${MK}"
done

for entry in "${ESAVED[@]:-}"; do
    [[ -n "$entry" ]] || continue
    bn="${entry%%|*}"
    orig="${entry##*|}"
    dest="${orig#/}"
    part="${dest%%/*}"
    {
        echo "PRODUCT_COPY_FILES += \\"
        echo "    \$(LOCAL_PATH)/prebuilts/nubia-apps/${bn}:\$(TARGET_COPY_OUT_$(printf '%s' "$part" | tr '[:lower:]' '[:upper:]'))/${dest#*/}"
        echo ""
    } >> "${MK}"
done

for entry in "${XSAVED[@]:-}"; do
    [[ -n "$entry" ]] || continue
    bn="${entry%%|*}"
    orig="${entry##*|}"
    dest="${orig#/}"
    part="${dest%%/*}"
    {
        echo "PRODUCT_COPY_FILES += \\"
        echo "    \$(LOCAL_PATH)/prebuilts/nubia-apps/${bn}:\$(TARGET_COPY_OUT_$(printf '%s' "$part" | tr '[:lower:]' '[:upper:]'))/${dest#*/}"
        echo ""
    } >> "${MK}"
done

cat <<EOF

────────────────────────────────────────────────────────────
完成。产物：
  ${OUT}/             （$(ls -1 "${OUT}" | wc -l) 个文件，$(du -sh "${OUT}" | cut -f1)）
  ${MK}

device.mk 末尾已经有这一行（带 - 前缀，文件不存在也不报错）：
  -include \$(LOCAL_PATH)/nubia-apps.mk

也就是说**只要这两个产物存在，下次编译自动带上**，不用再改 device.mk。

下一步：
  1. 把 device-nubia-NX737J/ 重新推 GitHub
       python scripts/gh-push.py
  2. 云端 sync 时会拉到，编译时自动打包进去

⚠️ 如果开机后某个 App 闪退，logcat 里搜 NoClassDefFoundError / NoSuchMethodError，
   看是不是指向 com.zte.mifavor.*（努比亚自己的 framework）。那种 AOSP 补不了，
   把对应的 PRODUCT_COPY_FILES 行删掉即可，不影响其他 App。
────────────────────────────────────────────────────────────
EOF
