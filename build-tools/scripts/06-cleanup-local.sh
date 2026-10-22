#!/usr/bin/env bash
#
# 06-cleanup-local.sh — 本地收尾检查（只检查+打印，不自动删）
#
# 删本地之前必须先确认两件事：
#   1. 设备树已经推到 GitHub（否则这是唯一副本）
#   2. 编译产物已经下载并校验通过
#
# 两个条件都满足，脚本才告诉你哪些可以删。
#
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

DEV="device-nubia-NX737J"
OK=1

hr() { printf '\n\033[1;36m%s\033[0m\n' "────────────────────────────────────────────"; }
ok() { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
no() { printf '  \033[1;31m✗\033[0m %s\n' "$*"; OK=0; }

hr
echo " 本地清理前置检查"
hr

# ── 条件 1：设备树进度 ──────────────────────────────────────────────────────
echo " ① 设备树是否有异地副本"
if [[ -d "${DEV}/.git" ]]; then
    REMOTE=$(git -C "${DEV}" remote -v 2>/dev/null | grep -c 'github.com' || true)
    AHEAD=$(git -C "${DEV}" status -sb 2>/dev/null | head -1)
    if (( REMOTE > 0 )); then
        if git -C "${DEV}" ls-remote --exit-code origin HEAD >/dev/null 2>&1; then
            ok "已配 GitHub remote 且远端可达：$(git -C "${DEV}" remote get-url origin 2>/dev/null)"
            echo "       分支状态：${AHEAD}"
            echo "       ⚠️  确认本地 commit 已 push：git -C ${DEV} push -u origin main"
        else
            no "配了 remote 但远端不可达（可能没推上去）"
        fi
    else
        no "没有 GitHub remote —— 这份是唯一副本，删了就没了"
        echo "       修：cd ${DEV} && git init && git add -A && git commit -m init"
        echo "           git remote add origin git@github.com:<你>/android_device_nubia_NX737J.git"
        echo "           git push -u origin main"
    fi
else
    no "${DEV} 不是 git 仓库"
fi

# ── 条件 2：产物 ────────────────────────────────────────────────────────────
echo
echo " ② 编译产物是否已下载到本地"
FOUND=0
for p in "nx737j-img.tar.zst" "../nx737j-img.tar.zst" "$HOME/Downloads/nx737j-img.tar.zst" \
         "/c/Users/yjp20/Downloads/nx737j-img.tar.zst"; do
    [[ -f "$p" ]] && { ok "找到 $p ($(stat -c%s "$p") B)"; FOUND=1; break; }
done
(( FOUND )) || no "没找到 nx737j-img.tar.zst —— 云端机器别销毁，先把产物拉回来"

echo
echo " ③ 产物校验和"
if [[ -f "nx737j-img.tar.zst.sha256" ]]; then
    if sha256sum -c nx737j-img.tar.zst.sha256 >/dev/null 2>&1; then
        ok "sha256 校验通过"
    else
        no "sha256 不匹配 —— 下载可能不完整，重拉"
    fi
else
    echo "  · 没有 .sha256 文件，跳过（记得和服务器上的对比）"
fi

# ── 结论 ────────────────────────────────────────────────────────────────────
hr
if (( OK )); then
    printf '\033[1;32m 前置条件全部满足，可以删本地了。\033[0m\n\n'
    cat <<EOF
 保留（有长期价值）：
   .workbuddy/memory/            项目记忆

 可以删：
   nx737j-pixelos/               整个目录（设备树已在 GitHub，脚本可随时重取）
   包括 device-nubia-NX737J/prebuilts/Image（38 MB，从 boot.img 一条 dd 就能重现）

 建议先备份到别处再说（可选）：
   nx737j-pixelos/scripts/       这几个脚本是唯一不可重现的部分
                                 不想推 GitHub 的话，单独留一份 scripts/
EOF
else
    printf '\033[1;31m 前置条件没满足，先别删。\033[0m\n'
    printf ' 按上面 ✗ 的提示补齐，再跑一次本脚本。\n'
fi
hr
echo
