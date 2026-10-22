#!/usr/bin/env bash
#
# 08-extract-nubia-apps.sh — 从原厂 super.img 里把努比亚系统 App 抽出来，回注到我们编的 system
#
# 背景：
#   我们替换了 system 分区，努比亚自己装在 system 里的 App 会一并丢掉。
#   实测原厂系统里这几个是努比亚的：
#       NBAccount.apk           努比亚账号
#       NBUserCenter.apk        用户中心
#       zteaccount_mfv.apk      账号框架（mfv = mifavor）
#       Nfc_st.apk              NFC
#       CameraMind.apk          相机
#       CameraExtensionsProxy.apk
#       RomFixCameraCompat.apk
#   （对照：MiuiSystemUI.apk / Joyose.apk 是小米的，不用管）
#
# 为什么要跑这个：
#   移植包作者特意把这批 App 留在 system 里，说明摘掉会出问题
#   （账号登录、NFC、相机扩展）。回注成本很低，留着更稳。
#
# 前提：
#   · 已经在服务器上跑过 00-prep.sh（有 erofs-utils）
#   · super.img 在本地（从移植包里拷过来）
#
# 用法：
#   bash scripts/08-extract-nubia-apps.sh /path/to/super.img
#   # 产物：device/nubia/NX737J/prebuilts/nubia-apps/*.apk
#   #       device/nubia/NX737J/nubia-apps.mk（自动生成的打包规则）
#
set -euo pipefail

SUPER="${1:?用法：08-extract-nubia-apps.sh <super.img>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/.." && pwd)"
DEV="${ROOT}/device-nubia-NX737J"
WORK="${WORK:-/data/nubia-extract}"

log() { echo -e "\n\033[1;32m[nubia]\033[0m $*"; }
die() { echo -e "\n\033[1;31m[nubia:FAIL]\033[0m $*"; exit 1; }

command -v fsck.erofs >/dev/null || die "需要 fsck.erofs（apt install erofs-utils）"
[[ -f "${SUPER}" ]] || die "找不到 ${SUPER}"
[[ -d "${DEV}" ]] || die "找不到设备树 ${DEV}"

mkdir -p "${WORK}" "${DEV}/prebuilts/nubia-apps"

# ── 1. 从 super 里切出 system 分区 ──────────────────────────────────────────
log "读取 LP 元数据确定 system 分区位置"
LPSH=$(python3 "${HERE}/dump-lp-metadata.py" --shell "${SUPER}") || die "LP 解析失败"
eval "${LPSH}"

SYS_START="${LP_system_START:-}"
SYS_SIZE="${LP_system_SIZE:-}"
[[ -n "${SYS_START}" && -n "${SYS_SIZE}" ]] || die "元数据里没有 system 分区"

log "system 分区 @ ${SYS_START} 大小 $(( SYS_SIZE / 1024 / 1024 )) MiB"
SYS_IMG="${WORK}/system.img"

if [[ -f "${SYS_IMG}" ]] && [[ "$(stat -c%s "${SYS_IMG}")" -eq "${SYS_SIZE}" ]]; then
    log "已存在 ${SYS_IMG}，跳过切割"
else
    log "切出 system 分区……"
    dd if="${SUPER}" of="${SYS_IMG}" bs=1048576 \
       skip=$(( SYS_START / 1048576 )) count=$(( SYS_SIZE / 1048576 + 1 )) \
       status=progress 2>&1 | tail -2
    truncate -s "${SYS_SIZE}" "${SYS_IMG}"
fi

# ── 2. 解包 EROFS ───────────────────────────────────────────────────────────
SYS_DIR="${WORK}/system"
if [[ -d "${SYS_DIR}/app" || -d "${SYS_DIR}/priv-app" ]]; then
    log "已解包，跳过"
else
    log "解包 EROFS 到 ${SYS_DIR}……（约 1 GiB，要几十秒）"
    rm -rf "${SYS_DIR}"
    mkdir -p "${SYS_DIR}"
    fsck.erofs --extract="${SYS_DIR}" "${SYS_IMG}" 2>&1 | tail -3 || true
    [[ -d "${SYS_DIR}/app" || -d "${SYS_DIR}/priv-app" ]] || die "解包失败，检查 erofs-utils 版本"
fi

# ── 3. 找出努比亚 App ───────────────────────────────────────────────────────
log "定位努比亚 App"
declare -a WANT=(NBAccount NBUserCenter zteaccount_mfv Nfc_st CameraMind CameraExtensionsProxy RomFixCameraCompat)
FOUND=()

for w in "${WANT[@]}"; do
    hit=$(find "${SYS_DIR}" -type d -name "${w}" 2>/dev/null | head -1)
    if [[ -n "${hit}" ]]; then
        apk=$(find "${hit}" -maxdepth 1 -name "*.apk" 2>/dev/null | head -1)
        if [[ -n "${apk}" ]]; then
            echo "  ✓ ${w}  ->  $(basename "${apk}")  ($(stat -c%s "${apk}") B)"
            FOUND+=( "${w}|${apk}" )
        else
            echo "  ? ${w}  目录在但没有 apk"
        fi
    else
        echo "  ✗ ${w}  未找到"
    fi
done

(( ${#FOUND[@]} > 0 )) || die "一个都没找到，检查 WANT 列表里的名字是否和这版系统一致"

# ── 4. 拷贝 + 权限 xml ──────────────────────────────────────────────────────
log "拷贝到设备树"
OUT="${DEV}/prebuilts/nubia-apps"
rm -f "${OUT}"/*.apk 2>/dev/null || true

MK="${DEV}/nubia-apps.mk"
{
    echo "# 自动生成，勿手改 —— 由 scripts/08-extract-nubia-apps.sh 产出"
    echo "#"
    echo "# 从原厂 super.img 回注的努比亚系统 App。去掉这些努比亚的部分功能会废。"
    echo ""
} > "${MK}"

for entry in "${FOUND[@]}"; do
    dir="${entry%%|*}"
    apk="${entry##*|}"
    cp -f "${apk}" "${OUT}/"
    base=$(basename "${apk}")
    echo "  copied ${base}"
    {
        echo "PRODUCT_COPY_FILES += \\"
        echo "    \$(LOCAL_PATH)/prebuilts/nubia-apps/${base}:\$(TARGET_COPY_OUT_SYSTEM)/app/${dir}/${base}"
        echo ""
    } >> "${MK}"
done

# 顺带把对应的 privapp-permissions 也带上（如果原厂有）
log "找 privapp-permissions"
shopt -s nullglob
for x in "${SYS_DIR}"/etc/permissions/*.xml; do
    bn=$(basename "$x")
    if grep -qiE 'nubia|zte' "$x" 2>/dev/null; then
        cp -f "$x" "${OUT}/"
        echo "  + ${bn}"
        {
            echo "PRODUCT_COPY_FILES += \\"
            echo "    \$(LOCAL_PATH)/prebuilts/nubia-apps/${bn}:\$(TARGET_COPY_OUT_SYSTEM)/etc/permissions/${bn}"
            echo ""
        } >> "${MK}"
    fi
done
shopt -u nullglob

# ── 5. 提示怎么启用 ─────────────────────────────────────────────────────────
cat <<EOF

────────────────────────────────────────────────────────────
完成。产物：
  ${OUT}/
  ${MK}

要在编译里生效，在 device.mk 末尾加一行：
  include \$(LOCAL_PATH)/nubia-apps.mk

然后重新编（增量，几分钟）：
  bash scripts/03-build.sh

⚠️ 注意
  · 这些 APK 是从 HyperOS 4（Android 17）里抽的，和我们编的 A17 系统同版本，
    理论兼容。但它们原本跑在小米框架上，AOSP 框架缺不缺接口只能实机验。
  · 首版建议**先不带**，确认能开机之后再回注，避免"开不了机"和"App 崩"
    两个问题混在一起查。
  · 想撤销：删掉 nubia-apps.mk 里那行 include 即可。
────────────────────────────────────────────────────────────
EOF
