#!/usr/bin/env bash
#
# run-all.sh — 一条命令跑完全程（前台串行，无嵌套 tmux）
#
# 用法（务必在 tmux 里跑，断开 SSH 不中断）：
#   tmux new -s all
#   bash run-all.sh 2>&1 | tee /data/runall.log
#   # 查看：Ctrl-b 然后 d 退出；回来： tmux attach -t all
#
# 任何阶段失败立即停下并打印下一步。
#
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

DATA="${DATA:-/data}"
ROM="${ROM:-pixelos}"
TREE="${TREE:-${DATA}/pixelos}"
STAGE="${STAGE:-all}"        # all | prep | sync | build | pack
SKIP_SYNC="${SKIP_SYNC:-0}"  # 1 = 跳过 sync（树已完整，只重编）
VARIANT="${VARIANT:-userdebug}"

# 传给子脚本（02-sync / 03-build / 04-pack 都读这些），否则各自用默认、可能不一致
export DATA ROM TREE VARIANT

say()  { printf '\033[1;32m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '\033[1;33m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
hr()   { printf '\n\033[1;36m%s\033[0m\n' "────────────────────────────────────────────────────────"; }
die()  { printf '\n\033[1;31m[FAIL]\033[0m %s\n' "$*"; exit 1; }

T0=$(date +%s)
el() { echo "$(( ($(date +%s) - T0) / 60 )) 分 $(( ($(date +%s) - T0) % 60 )) 秒"; }

hr
say "NX737J 一次开机流程   ROM=${ROM}   STAGE=${STAGE}"
say "tmux 会话：$(tmux display-message -p '#S' 2>/dev/null || echo '不在 tmux 里（建议 tmux new -s all）')"
hr

# ── 0. 准备 ─────────────────────────────────────────────────────────────────
if [[ "$STAGE" == "all" || "$STAGE" == "prep" ]]; then
    say "阶段 0/3  环境准备"
    bash scripts/00-prep.sh || die "准备阶段失败，看上面报错"
    hr
    say "阶段 0 完成，累计 $(el)"
fi

# ── 1. 拉源码 ───────────────────────────────────────────────────────────────
if [[ "$STAGE" == "all" || "$STAGE" == "sync" ]] && [[ "$SKIP_SYNC" != "1" ]]; then
    say "阶段 1/3  拉源码（45~90 分钟，唯一的大未知数）"
    bash scripts/02-sync.sh || die "sync 失败，看上面诊断"
    hr

    say "完整性检查（树不完整就别浪费钱编译）"
    MISSING=0
    for d in build frameworks/base hardware/interfaces prebuilts/clang \
             prebuilts/tools external/soong device/nubia/NX737J \
             device/qcom/sepolicy_vndr device/lineage/sepolicy; do
        if [[ -d "${TREE}/${d}" ]]; then
            echo "  OK      ${d}"
        else
            echo "  MISSING ${d}"; MISSING=$((MISSING+1))
        fi
    done
    if (( MISSING > 0 )); then
        die "${MISSING} 个关键目录缺失。
    device/nubia/NX737J 缺 → local_manifests 里的仓库地址错了
    device/qcom/* 缺      → sepolicy 依赖没拉下来，见 RUNBOOK 7.2
    其它缺                → sync 中途断流，重跑： bash scripts/02-sync.sh"
    fi
    say "阶段 1 完成，累计 $(el)"
fi

# ── 2. 编译 ─────────────────────────────────────────────────────────────────
# ── 体检（sync 之后、编译之前）──────────────────────────────────────────────
if [[ "$STAGE" == "all" || "$STAGE" == "preflight" ]]; then
    say "阶段 1.5  编译前体检（2 分钟，能省下半小时的失败编译）"
    if ! bash scripts/01-preflight.sh; then
        die "体检不通过，先按上面 ✗ 修掉。修完单独重跑： bash scripts/01-preflight.sh"
    fi
    hr
fi

if [[ "$STAGE" == "all" || "$STAGE" == "build" ]]; then
    say "阶段 2/3  编译（65~160 分钟，取决于核数）"
    bash scripts/03-build.sh || die "编译失败，看上面诊断
    OOM 的话降线程重跑（增量续编）：
      JOBS=$(($(nproc)/2)) bash scripts/03-build.sh"
    hr
    say "阶段 2 完成，累计 $(el)"
fi

# ── 3. 打包 ─────────────────────────────────────────────────────────────────
if [[ "$STAGE" == "all" || "$STAGE" == "pack" ]]; then
    say "阶段 3/3  校验 + 打包"
    bash scripts/04-pack.sh || die "打包或校验失败"
    hr
fi

# ── 汇总 ────────────────────────────────────────────────────────────────────
hr
say "全部完成，总耗时 $(el)"
cat <<EOF

产物： ${DATA}/nx737j-img.tar.zst

接下来：
  1. 本地下载
       scp -P <端口> root@<IP>:${DATA}/nx737j-img.tar.zst .
       scp -P <端口> root@<IP>:${DATA}/nx737j-img.tar.zst.sha256 .
  2. 核对花费
       bash scripts/cost.sh
  3. 销毁云资源
       bash scripts/05-teardown.sh

EOF
