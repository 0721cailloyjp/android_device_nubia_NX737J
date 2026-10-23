#!/usr/bin/env bash
#
# 11-strip-product.sh — 物理删除 product 里的 MIUI/小米 App（可选，实验性）
#
# 背景：
#   我们的 hybrid 方案「原样保留」stock product.img。里面 52 个 MIUI App 缺
#   miui 框架类（在 system_ext，已被 AOSP 替换），开机后由 disable-miui.sh 批量
#   pm disable-user 禁用 → 已经不崩、桌面不显示、广播不触发，彻底无感。
#
#   本脚本是「更进一步」：把这些 App 从 product.img 里物理删掉，让它们文件都不存在。
#   收益只是「更干净 + 包管理器完全不扫描」，功能上和开机禁用没有区别。
#
# ⚠️ 风险（务必读）：
#   1. 需要 erofs-utils（sudo apt install erofs-utils），并以 root 运行。
#   2. EROFS 重打包会重建 SELinux context：fsck.erofs --extract 默认保留 xattr，
#      但在非 SELinux 的编译机上 security.selinux 可能丢失 → 刷机后 product 文件
#      context 出错。**刷机后必须实测**，context 坏了就用回开机禁用方案（不跑本脚本）。
#   3. 删错文件会破坏 QTI 电话栈。删除清单是白名单外的精确目录，跑前用 --dry-run 核对。
#
# 结论：开机禁用已经无感且零风险。本脚本只在「想要文件都不存在」时用，默认不跑。
#
# 用法：
#   ./11-strip-product.sh <product.img> <out.img> [--dry-run]
#
set -euo pipefail

SRC="${1:?usage: 11-strip-product.sh <product.img> <out.img> [--dry-run]}"
OUT="${2:?usage: 11-strip-product.sh <product.img> <out.img> [--dry-run]}"
DRY="${3:-}"

command -v fsck.erofs >/dev/null 2>&1 || { echo "缺 fsck.erofs：sudo apt install erofs-utils"; exit 1; }
command -v mkfs.erofs >/dev/null 2>&1 || { echo "缺 mkfs.erofs：sudo apt install erofs-utils"; exit 1; }
[[ -f "$SRC" ]] || { echo "缺 $SRC"; exit 1; }
[[ "$(id -u)" == "0" ]] || { echo "需要 root（EROFS xattr 保留要特权）"; exit 1; }

# 52 个 MIUI/小米 App 目录（相对 product 根）。与 disable-miui.sh 的 52 个包一一对应。
# 保留：QTI 电话栈（ConferenceDialer/RideModeAudio/remotesim*/uimgba*）、
#       InCallUI/ImsServiceEntitlement、IFAA/微信支付（org.ifaa / com.tencent.soter）、
#       Google 全家（GmsCore/ConfigUpdater/SettingsIntelligence 等）。
DEL_DIRS=(
  app/Biometric app/CameraTools_beta app/CarWith app/ContentCatcherOS4
  app/DeviceInfoQR app/LyraSdkSpp app/MINextpay app/MIUIAiasstService
  app/MIUIFrequentPhrase app/MIUIMiCloudSync app/MIUINotificationCenter
  app/MIUIReporter app/MIUISecurityInputMethod app/MIUISystemUIPlugin
  app/MIUITouchAssistant app/MIUIgreenguard app/MediaViewer app/MiAONServiceW
  app/MiDevAuthService app/MiSound app/MiTrustService app/MiWallpaper
  app/MiuiCit app/MiuiPasswords app/MiuixEditor app/SecurityCoreAdd
  app/SecurityOnetrackService app/ThirdAppAssistant app/VoiceTrigger app/WMService
  app/XMSFKeeperCN app/XiaoaiRecommendation app/XmsCore app/com.xiaomi.macro
  app/com.xiaomi.ugd app/system data-app/VoiceAssistProxy
  priv-app/AutoRegistration priv-app/Backup priv-app/Bdsms priv-app/MISettings
  priv-app/MIUIAccessibility priv-app/MIUIAod priv-app/MIUICloudBackup
  priv-app/MIUIContentExtension priv-app/MIUIYellowPage priv-app/MetokNLP
  priv-app/MiuiBarrage priv-app/MiuiCamera priv-app/MiuiExtraPhoto priv-app/NewCall
  priv-app/Toolbox
)

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "[strip] 解包 $SRC ..."
fsck.erofs --extract="$WORK/root" "$SRC" >/dev/null 2>&1 || {
  echo "[strip] 解包失败（不是 EROFS？）"; exit 1;
}

echo "[strip] 待删目录（共 ${#DEL_DIRS[@]} 个）："
for d in "${DEL_DIRS[@]}"; do
  if [[ -e "$WORK/root/$d" ]]; then
    echo "  DEL  $d"
  else
    echo "  MISS $d  (不存在，跳过)"
  fi
done

if [[ "$DRY" == "--dry-run" ]]; then
  echo "[strip] --dry-run：只列不改。"
  exit 0
fi

for d in "${DEL_DIRS[@]}"; do
  [[ -e "$WORK/root/$d" ]] && rm -rf "$WORK/root/$d"
done

echo "[strip] 重打包（lz4hc，与 stock 默认一致）..."
# -T 0 用当前时间戳；如要复现 stock 需知道原时间戳，但 mount 不校验这个。
mkfs.erofs -zlz4hc -T 0 "$OUT" "$WORK/root"

echo "[strip] 完成：$OUT ($(stat -c%s "$OUT") B，原 $(stat -c%s "$SRC") B)"
echo "[strip] ⚠️ 刷机后务必实测 product 的 SELinux context 是否正常；"
echo "[strip]    若 context 坏（大量 avc denied / 电话栈异常），改回开机禁用方案（不跑本脚本）。"
