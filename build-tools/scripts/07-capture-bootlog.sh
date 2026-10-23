#!/usr/bin/env bash
#
# 07-capture-bootlog.sh — 刷机后抓开机日志（在**本地电脑**上跑）
#
# 首次移植最常见的结局是"编出来了但开不了机"。这个脚本把能拿到的证据一次抓全，
# 方便判断卡在哪一层。
#
# 用法：
#   bash 07-capture-bootlog.sh              # 自动 adb，输出到 ./bootlog-<时间>/
#   bash 07-capture-bootlog.sh -s           # 用 adb shell 交互模式（设备已起）
#
set -uo pipefail

# Git Bash 会把 /system/... 这类参数改写成 Windows 路径（09 脚本踩过坑），
# 这里统一关掉；本脚本没有本地路径参数，关掉无害。
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'

# 自动找 adb（和 09-pull-nubia-apps.sh 同一套逻辑）
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

OUT="bootlog-$(date +%Y%m%d-%H%M%S)"
mkdir -p "${OUT}"

say()  { printf '\033[1;36m[diag]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[diag]\033[0m %s\n' "$*"; }

say "输出目录 ${OUT}"

# ── 0. 设备在不在 ───────────────────────────────────────────────────────────
if ! adb devices | grep -qw device; then
    warn "adb 看不到设备。分情况："
    cat <<'EOF'

  ① 完全黑屏 / 卡在开机动画，adb 不通
     说明系统在 init / system_server 早期就挂了，靠 adb 抓不到。
     只能从三个地方找线索：

     a) 内核日志（pstore / ramoops）—— 需要重启进 recovery 或 EDL 之后读
        adb shell cat /sys/fs/pstore/console-ramoops-0
        （设备能进 recovery 的话）

     b) 串口 / UART —— 需要拆机，一般没有

     c) 最实用：二分法缩小范围
        · 先只刷 system，保留 stock system_ext/product → 能起说明问题在 system_ext/product
        · 只刷 system_ext → 同理
        · 全刷就挂 → 逐个排除

  ② 能进 recovery
     用 stock recovery 的 "Mount system" 或 adb shell，读：
        /sys/fs/pstore/*
        /proc/last_kmsg（老内核）
        /metadata/vold/... 之类

  ③ 卡在 "Your device is corrupt"
     → vbmeta 没关校验。跑 scripts/patch-vbmeta.py 重新打，两个都刷。

EOF
    exit 1
fi

say "设备已连接，开始抓取"

grab() {  # grab <文件名> <adb 参数...>
    local name="$1"; shift
    say "  ${name}"
    # timeout 兜底：某些 /proc 或 dumpsys 命令可能挂住
    if command -v timeout >/dev/null 2>&1; then
        timeout 20 adb "$@" > "${OUT}/${name}.txt" 2>&1 \
            || echo "(failed or timed out)" >> "${OUT}/${name}.txt"
    else
        adb "$@" > "${OUT}/${name}.txt" 2>&1 \
            || echo "(failed)" >> "${OUT}/${name}.txt"
    fi
}

# ── 1. 基础身份 ─────────────────────────────────────────────────────────────
grab getprop        shell getprop
grab devices_props  shell 'getprop | grep -E "ro\.(product|build|vendor|system|boot)"'
grab uname          shell uname -a
grab cmdline        shell cat /proc/cmdline
grab mounts         shell cat /proc/mounts
grab df             shell df -h
grab version         version

# ── 2. 启动阶段证据 ─────────────────────────────────────────────────────────
grab boot_completed shell getprop sys.boot_completed
grab init_svc       shell 'getprop | grep -E "init\.svc"'
grab pstore         shell ls -la /sys/fs/pstore/
grab dmesg          shell dmesg
# /proc/kmsg 会永久阻塞（它是流式设备），改用 dmesg（上面已抓）+ pstore
# 真要抓 kmsg 用： timeout 5 adb shell cat /proc/kmsg > kmsg.txt
grab last_kmsg      shell cat /proc/last_kmsg

# ── 3. 日志缓冲区（全抓，不只 main）─────────────────────────────────────────
say "  logcat (all buffers, dump)"
adb logcat -b all -d -v threadtime > "${OUT}/logcat-all.txt" 2>&1 || true
say "  logcat (crashes only)"
adb logcat -b crash -d -v threadtime > "${OUT}/logcat-crash.txt" 2>&1 || true

# ── 4. SELinux ──────────────────────────────────────────────────────────────
grab selinux_enforce shell getenforce
say "  avc denials"
adb logcat -b all -d 2>/dev/null | grep -iE 'avc: *denied' \
    | sed -E 's/.*avc: *denied *\{ *([^}]+) *\}.*scontext=([^ ]+).*tcontext=([^ ]+).*tclass=([^ ]+).*/\1 | \2 -> \3 (tclass=\4)/' \
    | sort | uniq -c | sort -rn > "${OUT}/avc-denials.txt" 2>&1 || true
head -30 "${OUT}/avc-denials.txt" 2>/dev/null

# ── 5. HAL / VINTF ──────────────────────────────────────────────────────────
grab vintf          shell 'dumpsys -l 2>/dev/null | head -50'
grab lshal          shell lshal 2>/dev/null
grab hal_list       shell 'service list 2>/dev/null | head -80'

# ── 6. 关键进程 ─────────────────────────────────────────────────────────────
grab ps             shell ps -A
grab zygote         shell 'ps -A | grep -E "zygote|system_server|surfaceflinger"'
grab sf_status      shell 'dumpsys SurfaceFlinger --display-id 2>/dev/null | head -20'

# ── 7. 常见卡点摘要 ─────────────────────────────────────────────────────────
say "生成摘要"
{
  echo "=== sys.boot_completed = $(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
  echo "=== getenforce        = $(adb shell getenforce 2>/dev/null | tr -d '\r')"
  echo "=== 关键进程 ==="
  adb shell 'ps -A 2>/dev/null' | grep -E 'system_server|zygote|surfaceflinger|servicemanager' || echo "(缺失!)"
  echo
  echo "=== 致命错误 logcat 摘录 ==="
  adb logcat -b all -d 2>/dev/null | grep -iE 'FATAL|Fatal signal|system_server crash|Watchdog|BOOT FAILURE|Failed to start|avc: denied|vintf.*incompatible|Cannot load' | head -40
  echo
  echo "=== avc 拒绝 TOP 10 ==="
  head -10 "${OUT}/avc-denials.txt" 2>/dev/null
} > "${OUT}/SUMMARY.txt" 2>&1

echo
say "完成。先看这个文件："
echo "    ${OUT}/SUMMARY.txt"
echo
say "打包方便发出来："
echo "    tar -czf ${OUT}.tar.gz ${OUT}/"
echo
cat <<'EOF'
── 判读速查 ──────────────────────────────────────────────────────────────

症状                              最可能的层          看哪个文件
─────────────────────────────────────────────────────────────────────────
卡开机动画、adb 通                  system / 框架      logcat-all.txt 里的 FATAL
卡开机动画、adb 不通                init / 内核        pstore / 二分法
"Your device is corrupt"            vbmeta             没关 AVB 校验
反复重启在 logo                     内核 / vendor      dmesg.txt
起来但黑屏                          SurfaceFlinger    sf_status.txt
起来但触摸没用                      vendor 触摸 HAL    lshal.txt 里找 touch
没有信号/无 IMS                     vendor RIL        logcat 里搜 RIL/ims
大量 avc denied                     SELinux           avc-denials.txt
vintf 不兼容                        Treble 版本       logcat 搜 vintf
─────────────────────────────────────────────────────────────────────────
EOF
