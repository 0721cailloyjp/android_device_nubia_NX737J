#!/usr/bin/env bash
#
# 00-prep.sh — 一次性备好编译前的一切。幂等，可重复执行。
#
# 做这些事：
#   1. 找到并挂载 500G 数据盘到 /data（没格式化就格式化）
#   2. 装构建依赖 + repo 工具
#   3. 配 TUNA 镜像（git 全局 insteadOf）
#   4. 建 swap（默认 16G，够用且建得快）
#   5. ccache + git 身份
#   6. vm 调优
#
# 用法：  bash 00-prep.sh
#
set -euo pipefail

SWAP_GB="${SWAP_GB:-16}"
CCACHE_GB="${CCACHE_GB:-60}"
BUILD_USER="${BUILD_USER:-$(whoami)}"
DATA_MNT="${DATA_MNT:-/data}"

log()  { echo -e "\n\033[1;32m[prep]\033[0m $*"; }
warn() { echo -e "\n\033[1;33m[prep]\033[0m $*"; }

[[ $EUID -eq 0 ]] || { echo "请用 root 跑（sudo bash 00-prep.sh）"; exit 1; }

# ── 1. 数据盘 ───────────────────────────────────────────────────────────────
log "步骤 1/6：挂载数据盘到 ${DATA_MNT}"

if mountpoint -q "${DATA_MNT}"; then
    log "${DATA_MNT} 已挂载，跳过"
else
    # 找未挂载的块设备。排除系统盘（含 / 的那个）和已挂载的。
    DATA_DEV=""
    for dev in /dev/vdb /dev/vdc /dev/vdd /dev/nvme1n1 /dev/nvme2n1 /dev/sdb /dev/sdc; do
        [[ -b "$dev" ]] || continue
        if ! lsblk -no MOUNTPOINTS "$dev" 2>/dev/null | grep -q '/'; then
            # 整盘没有已挂载的子分区 → 是候选
            if ! blkid "$dev" >/dev/null 2>&1; then
                DATA_DEV="$dev"; break          # 空白盘，直接用
            elif ! lsblk -no MOUNTPOINTS "$dev" 2>/dev/null | grep -q '[^[:space:]]'; then
                DATA_DEV="$dev"; break          # 有 fs 但没挂载
            fi
        fi
    done

    if [[ -z "$DATA_DEV" ]]; then
        warn "没找到可用的数据盘。现有块设备："
        lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS
        warn "手动确认后改 DATA_DEV 重跑，例如：DATA_DEV=/dev/vdb bash 00-prep.sh"
        exit 1
    fi

    log "选中数据盘 ${DATA_DEV}"
    if ! blkid "$DATA_DEV" >/dev/null 2>&1; then
        log "空白盘，格式化为 ext4"
        mkfs.ext4 -F "$DATA_DEV"
    fi

    mkdir -p "${DATA_MNT}"
    mount "$DATA_DEV" "${DATA_MNT}"
    # 开机自动挂载（这台机器反正会销毁，写 fstab 只是防意外重启）
    if ! grep -q "${DATA_MNT}" /etc/fstab; then
        echo "${DATA_DEV} ${DATA_MNT} ext4 defaults,nofail 0 2" >> /etc/fstab
    fi
    log "已挂载：$(df -h "${DATA_MNT}" | tail -1)"
fi

# 源码放数据盘上
mkdir -p "${DATA_MNT}/pixelos" "${DATA_MNT}/ccache" "${DATA_MNT}/out"
chown -R "${BUILD_USER}:${BUILD_USER}" "${DATA_MNT}"

# ── 2. 依赖 + repo ──────────────────────────────────────────────────────────
log "步骤 2/6：安装构建依赖"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
# AOSP 官方依赖集 + EROFS/AVB 相关工具。分两批装：
# 第一批是硬需求（缺了必失败），第二批尽力而为（缺了只是某些可选步骤不可用）。
apt-get install -y -qq \
    git git-lfs curl wget zip unzip tar xz-utils zstd lz4 lzop \
    python3 python3-pip python-is-python3 python3-venv \
    build-essential bc bison flex g++-multilib gcc-multilib \
    libssl-dev libelf-dev libncurses-dev lib32z1-dev lib32ncurses-dev \
    libxml2-utils xsltproc imagemagick device-tree-compiler \
    rsync tmux e2fsprogs util-linux ccache \
    erofs-utils android-sdk-libsparse-utils \
    >/dev/null

# 第二批：可选工具，装不上不阻断
apt-get install -y -qq squashfs-tools pngcrush schedtool liblz4-tool \
    >/dev/null 2>&1 || warn "部分可选工具未装上（不影响主流程）"

# JDK：Android 17 时代 AOSP 自带 prebuilts/jdk，系统 JDK 只用于 bootstrap。
# 24.04 默认 21，22.04 默认 17 —— 两个都尝试，谁成功都能编。
if apt-get install -y -qq openjdk-21-jdk-headless >/dev/null 2>&1; then
    log "JDK 21 已装"
elif apt-get install -y -qq openjdk-17-jdk-headless >/dev/null 2>&1; then
    log "JDK 17 已装（21 不可用）"
else
    warn "系统 JDK 没装上。AOSP 自带 prebuilts/jdk 通常够用，但 envsetup 可能报 java 找不到"
fi
log "依赖装完"

# ── erofs-utils 版本检查 ────────────────────────────────────────────────────
# build_image.py 生成 EROFS 镜像时会用 mkfs.erofs 的这些参数：
#   -b / --mount-point / --product-out / --fs-config-file / --file-contexts
#   -T / -U / --block-list-file          ← 1.4 起支持
#   -C（pcluster）/ -E dedupe / --chunksize  ← 需要 1.6+
# Ubuntu 22.04 自带 1.4，如果设备树里设了 erofs_pcluster_size 之类就会
# 报 "unknown option -C"，白烧编译时间。所以这里先查。
EROFS_VER="$(mkfs.erofs --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)"
if [[ -z "${EROFS_VER}" ]]; then
    warn "mkfs.erofs 不存在（erofs-utils 没装上？）"
else
    log "mkfs.erofs 版本 ${EROFS_VER}"
    MAJ="${EROFS_VER%%.*}"; MIN="${EROFS_VER##*.}"
    if (( MAJ == 0 )) || (( MAJ == 1 && MIN < 6 )); then
        warn "erofs-utils ${EROFS_VER} 偏老（< 1.6）。"
        warn "若编译时报 'unknown option -C' / '--chunksize'，先升级："
        warn "  apt install -y liblz4-dev libzstd-dev libselinux1-dev uuid-dev libtool automake autoconf pkg-config"
        warn "  git clone --depth=1 https://github.com/erofs/erofs-utils && cd erofs-utils"
        warn "  ./autogen.sh && ./configure && make -j\$(nproc) && make install && ldconfig"
        warn "推荐直接用 Ubuntu 24.04（自带 1.7，无需折腾）"
    fi
fi

# repo 工具：优先 apt，没有就用 TUNA 镜像的
if ! command -v repo >/dev/null 2>&1; then
    log "安装 repo 工具（TUNA 镜像）"
    install -d -m0755 /usr/local/bin
    curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/git/git-repo \
        -o /usr/local/bin/repo
    chmod +x /usr/local/bin/repo
fi
log "repo: $(command -v repo)"

# ── 3. TUNA 镜像 ────────────────────────────────────────────────────────────
log "步骤 3/6：配置 TUNA 镜像"
# AOSP 主体（占总量 90%+）走 TUNA
git config --global url.https://mirrors.tuna.tsinghua.edu.cn/git/AOSP/.insteadof \
    https://android.googlesource.com
# git-repo 自身也走 TUNA
git config --global url.https://mirrors.tuna.tsinghua.edu.cn/git/git-repo.insteadof \
    https://gerrit.googlesource.com/git-repo
log "TUNA insteadOf 已配置："
git config --global --get-regexp 'url\..*insteadof' || true

# ── 4. swap ─────────────────────────────────────────────────────────────────
log "步骤 4/6：配置 ${SWAP_GB}G swap"
if ! swapon --show=NAME --noheadings | grep -q swapfile; then
    if [[ ! -f /swapfile ]]; then
        fallocate -l "${SWAP_GB}G" /swapfile 2>/dev/null \
            || dd if=/dev/zero of=/swapfile bs=1M count=$((SWAP_GB*1024)) status=none
        chmod 600 /swapfile
        mkswap /swapfile >/dev/null
    fi
    swapon /swapfile
fi
grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
swapon --show=NAME,SIZE

# ── 5. ccache + git 身份 ────────────────────────────────────────────────────
log "步骤 5/6：配置 ccache (${CCACHE_GB}G) 与 git 身份"
cat > /etc/profile.d/99-aosp.sh <<EOF
export USE_CCACHE=1
export CCACHE_EXEC=\$(which ccache)
export CCACHE_DIR=${DATA_MNT}/ccache
ccache -M ${CCACHE_GB}G >/dev/null 2>&1 || true
EOF
chmod 0644 /etc/profile.d/99-aosp.sh
# 立即在当前 shell 也生效
export USE_CCACHE=1 CCACHE_DIR="${DATA_MNT}/ccache"
command -v ccache >/dev/null && ccache -M "${CCACHE_GB}G" || true

if [[ "${BUILD_USER}" != "root" ]]; then
    sudo -u "${BUILD_USER}" git config --global user.name  "yjpyydslove"
    sudo -u "${BUILD_USER}" git config --global user.email "yjpyydslove@users.noreply.github.com"
    sudo -u "${BUILD_USER}" git config --global http.postBuffer 524288000
else
    git config --global user.name  "yjpyydslove"
    git config --global user.email "yjpyydslove@users.noreply.github.com"
    git config --global http.postBuffer 524288000
fi

# ── 6. vm 调优 ──────────────────────────────────────────────────────────────
log "步骤 6/6：vm 调优"
cat > /etc/sysctl.d/99-aosp.conf <<'EOF'
vm.swappiness=10
vm.dirty_ratio=20
vm.dirty_background_ratio=5
vm.max_map_count=1048576
fs.inotify.max_user_watches=524288
EOF
sysctl -p /etc/sysctl.d/99-aosp.conf >/dev/null

# ── 汇总 ────────────────────────────────────────────────────────────────────
log "准备完成。当前状态："
echo "  源码目录 : ${DATA_MNT}/pixelos"
echo "  ccache   : ${DATA_MNT}/ccache (上限 ${CCACHE_GB}G)"
echo "  swap     : $(swapon --show=SIZE --noheadings | tr -d ' ')"
echo "  内存     : $(free -g | awk '/^Mem:/{print $2"G"}')"
echo "  CPU      : $(nproc) 核"
echo "  TUNA     : $(git config --global --get url.https://mirrors.tuna.tsinghua.edu.cn/git/AOSP/.insteadof || echo '未配置!')"
echo
echo "下一步：  bash 02-sync.sh"
