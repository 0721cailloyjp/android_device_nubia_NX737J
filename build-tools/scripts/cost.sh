#!/usr/bin/env bash
#
# cost.sh — 实时算这一趟已经烧了多少钱
#
# 用法：
#   bash cost.sh                     # 用上次记录的起点、自动识别机型单价
#   bash cost.sh 3.77 500            # 手动指定 ¥/小时 和磁盘 GB
#   bash cost.sh reset               # 重置起点（换机器后跑）
#
# 起点存在 /data/.cost_start，换实例/重启后跑一次 reset。
#
set -euo pipefail

DATA="${DATA:-/data}"
STATE="${DATA}/.cost_start"
BUDGET="${BUDGET:-25}"

# 按内存自动猜单价（腾讯云华北/华南按量，元/小时）
guess_rate() {
    local gb
    gb=$(free -g 2>/dev/null | awk '/^Mem:/{print $2}')
    [[ -z "${gb}" ]] && gb=32          # free 不存在时按 16核32G 算
    case "${gb}" in
        1[0-9])  echo "1.89"  ;;   # 8核16G
        2[0-9])  echo "2.76"  ;;   # 8核32G
        3[0-9])  echo "3.77"  ;;   # 16核32G
        6[0-9])  echo "7.55"  ;;   # 32核64G
        12[0-9]) echo "15.10" ;;   # 64核128G
        *)       echo "3.77"  ;;
    esac
}

if [[ "${1:-}" == "reset" ]]; then
    mkdir -p "${DATA}"
    date +%s > "${STATE}"
    echo "起点已重置：$(date '+%F %T')"
    exit 0
fi

RATE="${1:-$(guess_rate)}"
DISK_GB="${2:-500}"
DISK_RATE_PER_GB_H=$(python3 -c "print(round(0.35/730,6))" 2>/dev/null || echo 0.000479)
EGRESS_GB="${EGRESS_GB:-0}"        # 已经下载了多少 GB，自己填

if [[ ! -f "${STATE}" ]]; then
    mkdir -p "${DATA}"
    date +%s > "${STATE}"
    echo "首次运行，起点记为 $(date '+%F %T')"
fi

START=$(cat "${STATE}")
NOW=$(date +%s)
SECS=$(( NOW - START ))
HOURS=$(python3 -c "print(round(${SECS}/3600,3))")

INST=$(python3 -c "print(round(${HOURS}*${RATE},2))")
DISK=$(python3 -c "print(round(${HOURS}*${DISK_GB}*${DISK_RATE_PER_GB_H},2))")
NET=$(python3 -c "print(round(${EGRESS_GB}*0.8,2))")
TOTAL=$(python3 -c "print(round(${INST}+${DISK}+${NET},2))")
LEFT=$(python3 -c "print(round(${BUDGET}-${TOTAL},2))")

printf '\n'
printf '  %-22s %s\n' "起点"        "$(date -d @${START} '+%F %T')"
printf '  %-22s %s\n' "已运行"      "$(python3 -c "print(f'{$SECS//60} 分 {$SECS%60} 秒')")"
printf '  %-22s ¥%s/h\n' "实例单价"  "${RATE}"
printf '  %-22s ¥%s\n' "实例费用"    "${INST}"
printf '  %-22s ¥%s\n' "磁盘费用"    "${DISK}  (${DISK_GB}G)"
printf '  %-22s ¥%s\n' "流量费用"    "${NET}  (${EGRESS_GB}GB)"
printf '  ─────────────────────────────────\n'
printf '  %-22s ¥%s\n' "已花"        "${TOTAL}"
printf '  %-22s ¥%s\n' "预算余量"    "${LEFT}"
printf '\n'

# 按当前单价还能跑多久
if python3 -c "import sys; sys.exit(0 if ${RATE}>0 else 1)"; then
    REMAIN_H=$(python3 -c "print(round(${LEFT}/${RATE},2))")
    printf '  按当前单价，余量还能跑 %s 小时\n\n' "${REMAIN_H}"
fi

if python3 -c "import sys; sys.exit(0 if ${LEFT} < 3 else 1)"; then
    printf '  \033[1;31m⚠️  余量不足 ¥3，该收尾了\033[0m\n\n'
fi
