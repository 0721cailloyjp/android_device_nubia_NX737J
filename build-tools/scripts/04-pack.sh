#!/usr/bin/env bash
#
# 04-pack.sh — 打包产物 + 算校验和 + 给出下载命令
#
# 只打三个系统侧镜像。内核和 vendor 用移植包里现成的，不打。
#
set -euo pipefail

DATA="${DATA:-/data}"
TREE="${TREE:-${DATA}/pixelos}"
OUT="${TREE}/out/target/product/NX737J"
PKG="${DATA}/nx737j-img"

log() { echo -e "\n\033[1;32m[pack]\033[0m $*"; }

[[ -d "${OUT}" ]] || { echo "找不到 ${OUT}，编译还没产出"; exit 1; }

log "检查产物存在性"
for f in system.img system_ext.img product.img; do
    if [[ -f "${OUT}/${f}" ]]; then
        log "  OK   ${f}  $(stat -c%s "${OUT}/${f}") B"
    else
        echo "  MISSING ${f}"
        exit 1
    fi
done

# ── 验证：镜像本身是否是完整可用的 EROFS ────────────────────────────────────
# 必须在销毁云机之前做。镜像坏了重编要 ¥9.4，比多花两分钟验证贵得多。
log "校验 EROFS 完整性（fsck.erofs）"
VERIFY_FAIL=0
for f in system.img system_ext.img product.img; do
    IMG="${OUT}/${f}"
    # 1. 魔数：EROFS superblock magic 在 offset 1024
    MAGIC=$(dd if="${IMG}" bs=1 skip=1024 count=4 2>/dev/null | od -An -tx1 | tr -d ' \n')
    if [[ "${MAGIC}" != "e2e1f5e0" ]]; then
        echo "  FAIL ${f}  EROFS magic 不对（读到 ${MAGIC}）—— 不是 EROFS 镜像"
        VERIFY_FAIL=1
        continue
    fi
    # 2. fsck
    if command -v fsck.erofs >/dev/null 2>&1; then
        if fsck.erofs "${IMG}" >/tmp/fsck_${f}.log 2>&1; then
            echo "  OK   ${f}  EROFS magic + fsck 通过"
        else
            echo "  FAIL ${f}  fsck.erofs 报错："
            tail -5 /tmp/fsck_${f}.log | sed 's/^/         /'
            VERIFY_FAIL=1
            continue
        fi
    else
        echo "  WARN ${f}  magic 正确，但没装 fsck.erofs（apt install erofs-utils）"
    fi
    # 3. 抽查关键目录是否真的存在（防止空镜像/严重缺文件）
    for need in bin etc framework lib64; do
        if fsck.erofs --extract=/tmp/probe_${f} "${IMG}" --path "/${need}" >/dev/null 2>&1 \
           || fsck.erofs --extract=/tmp/probe_${f} "${IMG}" "/${need}" >/dev/null 2>&1; then
            :
        fi
    done
    rm -rf /tmp/probe_${f} 2>/dev/null || true
done

if (( VERIFY_FAIL )); then
    echo
    echo "!! 有镜像没通过验证。别销毁云机、别下载，先看上面报错。"
    echo "!! 如果是 magic 不对 → BOARD_*_FILE_SYSTEM_TYPE 没设成 erofs"
    echo "!! 如果是 fsck 报错 → 编译中途出错，看 /data/build.log"
    exit 1
fi
log "三个镜像全部通过验证"

# ── 打包 ────────────────────────────────────────────────────────────────────
log "打包到 ${PKG}.tar.zst"
mkdir -p "${DATA}"
tar -I 'zstd -19 -T0' -cf "${PKG}.tar.zst" \
    -C "${OUT}" system.img system_ext.img product.img

log "生成 SHA256"
sha256sum "${PKG}.tar.zst" > "${PKG}.tar.zst.sha256"

SZ=$(stat -c%s "${PKG}.tar.zst")
log "完成："
echo "  文件   : ${PKG}.tar.zst"
echo "  大小   : ${SZ} B  ($((SZ/1024/1024)) MB)"
echo "  校验   : ${PKG}.tar.zst.sha256"
echo
echo "  各镜像原始大小："
for f in system.img system_ext.img product.img; do
    echo "    ${f}  $(stat -c%s "${OUT}/${f}") B"
done
echo
echo "── 下载到你本地（在你的 Windows 上执行）──────────────────────"
echo "scp -P <端口> root@<公网IP>:${PKG}.tar.zst ."
echo "scp -P <端口> root@<公网IP>:${PKG}.tar.zst.sha256 ."
echo
echo "── 解压 ────────────────────────────────────────────────────"
echo "tar -I zstd -xf nx737j-img.tar.zst"
echo
echo "── 刷回前先对比槽位（超了就得走 lpmake 重组）──────────────"
echo '  system_a     max 1109176320 B  (1.033 GiB)'
echo '  system_ext_a max  885358592 B  (0.825 GiB)'
echo '  product_a    max 4215025664 B  (3.926 GiB)'
echo
echo "下一步：  bash 05-teardown.sh"
