#!/usr/bin/env bash
#
# 11-strip-product.sh — 物理删除 product 里的 MIUI/小米 App（可选）
#
# 背景：
#   我们的 hybrid 方案「原样保留」stock product.img。里面 52 个 MIUI App 缺
#   miui 框架类（在 system_ext，已被 AOSP 替换），开机后由 disable-miui.sh 批量
#   pm disable-user 禁用 → 已经不崩、桌面不显示、广播不触发，彻底无感。
#
#   本脚本是「更进一步」：把这些 App 从 product.img 里物理删掉，让它们文件都不存在。
#   收益只是「更干净 + 包管理器完全不扫描」，功能上和开机禁用没有区别。
#
# 自动回退设计（关键）：
#   EROFS 重打包的最大风险是 security.selinux xattr 在非 SELinux 的编译机上可能
#   丢。丢了 → 刷机后 product 文件 context 出错 → SELinux 拒绝。所以本脚本在删文件
#   前先自检 xattr：
#     - xattr 保留完好 → 删文件 + 重打包，退出码 0（成功）
#     - xattr 丢失/不可测 → 不碰原镜像，退出码 2（= 放弃物理删除，调用方应回退到
#       开机禁用方案）
#   这样「能去掉就自动去掉，不能去掉就自动回退禁用」。
#
# 用法：
#   ./11-strip-product.sh <product.img> <out.img> [--dry-run]
#   退出码：0=成功生成精简 product.img；2=放弃（xattr 不可靠）；其他=出错
#
set -euo pipefail

SRC="${1:?usage: 11-strip-product.sh <product.img> <out.img> [--dry-run]}"
OUT="${2:?usage: 11-strip-product.sh <product.img> <out.img> [--dry-run]}"
DRY="${3:-}"

command -v fsck.erofs >/dev/null 2>&1 || { echo "[strip] 缺 fsck.erofs：sudo apt install erofs-utils"; exit 3; }
command -v mkfs.erofs >/dev/null 2>&1 || { echo "[strip] 缺 mkfs.erofs：sudo apt install erofs-utils"; exit 3; }
[[ -f "$SRC" ]] || { echo "[strip] 缺 $SRC"; exit 3; }
[[ "$(id -u)" == "0" ]] || { echo "[strip] 需要 root（EROFS xattr 保留要特权）"; exit 3; }

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
if ! fsck.erofs --extract="$WORK/root" "$SRC" >/dev/null 2>&1; then
  echo "[strip] 解包失败（不是 EROFS？）"; exit 3
fi

# ── 关键自检：security.selinux xattr 是否保留 ─────────────────────────────
# 抽查一个「保留文件」（QTI 电话栈，不在删除清单里）的 security.selinux xattr。
# 若丢失，重打包后 product 的 SELinux context 会坏 → 放弃物理删除。
SAMPLE="app/ConferenceDialer/ConferenceDialer.apk"
XATTR_OK=0
if [[ -f "$WORK/root/$SAMPLE" ]]; then
  if command -v getfattr >/dev/null 2>&1; then
    if getfattr -n security.selinux "$WORK/root/$SAMPLE" 2>/dev/null | grep -q 'security.selinux='; then
      XATTR_OK=1
      echo "[strip] ✓ security.selinux xattr 保留完好（抽查 $SAMPLE）"
    else
      echo "[strip] ✗ 解包后 $SAMPLE 的 security.selinux xattr 丢失"
    fi
  else
    # 没 getfattr 也能用 python 读（os.getxattr），双保险
    if python3 -c "import os,sys; sys.exit(0 if os.getxattr('$WORK/root/$SAMPLE','security.selinux') else 1)" 2>/dev/null; then
      XATTR_OK=1
      echo "[strip] ✓ security.selinux xattr 保留完好（python 抽查）"
    else
      echo "[strip] ✗ 无法确认 security.selinux xattr（getfattr/python 均失败）"
    fi
  fi
else
  echo "[strip] ✗ 抽查文件 $SAMPLE 不存在（product 结构变了？），不敢删"
fi

if [[ "$XATTR_OK" != "1" ]]; then
  echo "[strip] 放弃物理删除：SELinux context 不可靠，重打包后 product 可能挂载异常。"
  echo "[strip] 回退到开机禁用方案（disable-miui.sh，已内置、零风险、效果无感）。"
  exit 2
fi

# ── 列出待删目录 ──────────────────────────────────────────────────────────
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
# -T 0 用当前时间戳；mount 不校验时间戳。
mkfs.erofs -zlz4hc -T 0 "$OUT" "$WORK/root"

# ── 重打包后验证：magic + fsck ────────────────────────────────────────────
MAGIC=$(dd if="$OUT" bs=1 skip=1024 count=4 2>/dev/null | od -An -tx1 | tr -d ' \n')
if [[ "$MAGIC" != "e2e1f5e0" ]]; then
  echo "[strip] ✗ 重打包产物 EROFS magic 不对（$MAGIC）"; exit 3
fi
if command -v fsck.erofs >/dev/null 2>&1 && ! fsck.erofs "$OUT" >/dev/null 2>&1; then
  echo "[strip] ✗ 重打包产物 fsck 不通过"; exit 3
fi

echo "[strip] ✓ 完成：$OUT ($(stat -c%s "$OUT") B，原 $(stat -c%s "$SRC") B)"
echo
echo "[strip] 怎么用精简后的 product 组装 super（走 lpmake 重组，参考 assemble-super.sh 的模板）："
echo "[strip]   1. 从原 super 提取 vendor/vendor_dlkm/odm/system_dlkm（dd，偏移见 lpdump）"
echo "[strip]   2. lpmake 里把 --partition product_a 的 --image 换成 $OUT"
echo "[strip]   3. 因为 product 变小了，group 要按新大小重算（assemble-super.sh 的 overflow 分支会提示）"
echo "[strip] 提示：不想折腾 lpmake 就直接用开机禁用方案（disable-miui.sh），效果同样无感、零风险。"
