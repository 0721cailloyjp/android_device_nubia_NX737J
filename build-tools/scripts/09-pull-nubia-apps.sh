#!/usr/bin/env bash
#
# 09-pull-nubia-apps.sh — 从你自己的手机里把努比亚系统 App 拉出来（在**本地 PC**上跑）
#
# 为什么用手机而不是 super.img：
#   手机 /system 里现成就有这些 App，7 个 APK 一共几十 MB，adb pull 几秒钟。
#   而 super.img 有 16 GB，传到云服务器再解包要很久。
#
# 前提：手机已 root 或至少能 adb 读 /system（移植包的 /system 可读）
#
# 用法：
#   bash 09-pull-nubia-apps.sh                 # 自动找、自动拉
#   bash 09-pull-nubia-apps.sh --list          # 只列出找到什么，不拉
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/.." && pwd)"
DEV="${ROOT}/device-nubia-NX737J"
OUT="${DEV}/prebuilts/nubia-apps"
MK="${DEV}/nubia-apps.mk"

LISTONLY=0
FORCE=0
for a in "$@"; do
    case "$a" in
        --list)  LISTONLY=1 ;;
        --force) FORCE=1 ;;
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
DEV=$(adb shell getprop ro.product.device 2>/dev/null | tr -d '\r')
MODEL=$(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r')
BRAND=$(adb shell getprop ro.product.brand 2>/dev/null | tr -d '\r')
REL=$(adb shell getprop ro.build.version.release 2>/dev/null | tr -d '\r')
say "设备：${DEV}  /  ${MODEL}  /  ${BRAND}  /  Android ${REL}"

# 设备校验：拉的是努比亚的东西，连错设备会白忙一场
case "${BRAND}${DEV}${MODEL}" in
    *nubia*|*Nubia*|*ZTE*|*zte*|*NX737*|*NX789*) : ;;
    *)
        echo
        echo -e "  \033[1;31m⚠️  这台看起来不是努比亚设备\033[0m"
        echo "     brand=${BRAND}  device=${DEV}  model=${MODEL}"
        echo "     要拉的是 Z70S（NX737J）或红魔10（NX789J）上的 /system 里的努比亚 App。"
        echo "     如果确认要在这台上找，加 --force 跳过检查。"
        echo
        [[ "${1:-}" == "--force" ]] || exit 2
        ;;
esac

# ── 1. 定位 APK ─────────────────────────────────────────────────────────────
# 以「目录名 = APK 名」为主（这是扫 super.img 实测出来的，最可靠），
# pm path 作为辅助（用于确认包名，顺便拿到真实路径）。
declare -a WANT=(NBAccount NBUserCenter zteaccount_mfv Nfc_st CameraMind CameraExtensionsProxy RomFixCameraCompat)
declare -a FOUND=()

say "逐个定位（先扫目录，再试 pm path）"
for name in "${WANT[@]}"; do
    path=""
    # 1a. 扫常见安装目录
    for d in /system/priv-app /system/app /system_ext/priv-app /system_ext/app /product/priv-app /product/app; do
        cand="$d/$name/$name.apk"
        if adb shell "[ -f $cand ]" 2>/dev/null; then path="$cand"; break; fi
    done
    # 1b. 目录名不叫这个时，模糊找一次
    if [[ -z "$path" ]]; then
        path=$(adb shell "find /system /system_ext /product -name '${name}.apk' 2>/dev/null" 2>/dev/null \
               | tr -d '\r' | head -1)
    fi
    if [[ -n "$path" ]]; then
        sz=$(adb shell "stat -c %s $path 2>/dev/null" 2>/dev/null | tr -d '\r')
        ok "$(printf '%-24s %-58s %s B' "$name" "$path" "${sz:-?}")"
        FOUND+=( "${name}|${path}" )
    else
        warn "$(printf '%-24s 未找到' "$name")"
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

# ── 3. 找 privapp-permissions ───────────────────────────────────────────────
say "找相关的 privapp-permissions XML"
for x in $(adb shell 'ls /system/etc/permissions /system_ext/etc/permissions /product/etc/permissions 2>/dev/null' | tr -d '\r' | grep -iE 'nubia|zte'); do
    adb pull "/system/etc/permissions/$x" "${OUT}/" >/dev/null 2>&1 \
      || adb pull "/system_ext/etc/permissions/$x" "${OUT}/" >/dev/null 2>&1 \
      || adb pull "/product/etc/permissions/$x" "${OUT}/" >/dev/null 2>&1
    [[ -f "${OUT}/$x" ]] && ok "$x"
done

# ── 4. 生成打包规则 ─────────────────────────────────────────────────────────
say "生成 ${MK##*/}"
{
    echo "# 自动生成，勿手改 —— 由 scripts/09-pull-nubia-apps.sh 产出"
    echo "#"
    echo "# 从原厂 /system 回注的努比亚 App。移植包作者在换成澎湃4之后仍保留它们，"
    echo "# 说明摘掉会导致努比亚的账号 / NFC / 相机扩展出问题。"
    echo ""
} > "${MK}"

for entry in "${SAVED[@]}"; do
    name="${entry%%|*}"
    orig="${entry##*|}"
    dir=$(dirname "$orig")
    dest="/system/app/${name}/${name}.apk"
    case "$dir" in
        */priv-app/*) dest="/system/priv-app/${name}/${name}.apk" ;;
    esac
    {
        echo "PRODUCT_COPY_FILES += \\"
        echo "    \$(LOCAL_PATH)/prebuilts/nubia-apps/${name}.apk:${dest}"
        echo ""
    } >> "${MK}"
done

for x in "${OUT}"/*.xml; do
    [[ -f "$x" ]] || continue
    bn=$(basename "$x")
    {
        echo "PRODUCT_COPY_FILES += \\"
        echo "    \$(LOCAL_PATH)/prebuilts/nubia-apps/${bn}:\$(TARGET_COPY_OUT_SYSTEM)/etc/permissions/${bn}"
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
