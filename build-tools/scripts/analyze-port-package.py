#!/usr/bin/env python3
"""
analyze-port-package.py — 一键分析任意 EDL 刷机包/移植包

给一个目录（或直接给 boot.img / super.img），输出：
  · 所有分区镜像的大小（对照另一台机器看是否同布局）
  · boot.img 里的内核版本、偏移、格式
  · super.img 的 LP 动态分区表（分区名 / 起始 / 大小 / A-B 槽）
  · EROFS 魔数实测校验（验证 extent 单位假设）
  · vendor 归属字符串统计（zte/nubia vs xiaomi/miui）

用法：
    python3 analyze-port-package.py E:\\NX737J_HyperOS_4.0.0.10_A17_10.12
    python3 analyze-port-package.py /path/to/Firmware
    python3 analyze-port-package.py /path/to/boot.img        # 单文件模式
"""
import os
import re
import sys
import struct

GEOMETRY_MAGIC = 0x616C4467      # "gDla"
HEADER_MAGIC = 0x414C5030        # "0PLA"（实测值，非 0x414a5030）

# 已知的 LP 布局（NX737J / NX789J 系列实测）
GEOMETRY_OFF = 0x1000
HEADER_OFF = 0x3000
DESCRIPTORS_OFF = 0x3054
PARTITION_TABLE_OFF = 0x3100

MB = 1024 * 1024


def human(n):
    if n >= 1024 ** 3:
        return "%.3f GiB" % (n / 1024 ** 3)
    if n >= MB:
        return "%.1f MiB" % (n / MB)
    return "%d B" % n


# ── boot.img ────────────────────────────────────────────────────────────────
def analyze_boot(path):
    print("=" * 64)
    print(" boot.img: %s" % path)
    print("=" * 64)
    size = os.path.getsize(path)
    with open(path, "rb") as f:
        h = f.read(0x2000)
    if h[:8] != b"ANDROID!":
        print("  不是 Android boot image（magic=%r）" % h[:8])
        return
    ks = struct.unpack_from("<I", h, 0x08)[0]
    rs = struct.unpack_from("<I", h, 0x0C)[0]
    hv = struct.unpack_from("<I", h, 0x28)[0]
    hs = struct.unpack_from("<I", h, 0x14)[0]
    print("  文件大小   : %s" % human(size))
    print("  header 版本: %d  header_size=%d" % (hv, hs))
    print("  kernel_size: %d (%.2f MiB)" % (ks, ks / MB))
    print("  ramdisk    : %d B" % rs)

    # 内核：在 hs 之后找 ARM64 magic 反推起点
    with open(path, "rb") as f:
        f.seek(min(hs, 0x1000))
        probe = f.read(min(64 << 20, size))
    idx = probe.find(b"ARM\x64")
    if idx < 0:
        print("  ❌ 没找到 ARM64 magic —— 内核可能是压缩的")
        for sig, name in ((b"\x1f\x8b\x08", "gzip"), (b"\x02\x21\x4c\x18", "lz4"),
                          (b"\x28\xb5\x2f\xfd", "zstd"), (b"BZh", "bzip2")):
            j = probe.find(sig)
            if j >= 0:
                print("     找到 %s 压缩头 @+0x%x" % (name, j))
        return
    start = min(hs, 0x1000) + idx - 0x38
    with open(path, "rb") as f:
        f.seek(start)
        ih = f.read(0x40)
    to, isz, fl = struct.unpack_from("<QQQ", ih, 8)
    print("  内核偏移   : 0x%x" % start)
    print("  内核格式   : 原生 ARM64 Image")
    print("  image_size : 0x%x (%.1f MiB)  flags=0x%x" % (isz, isz / MB, fl))

    # 版本串
    with open(path, "rb") as f:
        f.seek(start)
        blob = f.read(ks if ks else 40 << 20)
    m = re.search(rb"Linux version [ -~]{20,160}", blob)
    if m:
        print("  内核版本   : %s" % m.group().decode(errors="replace"))
    print("  提取命令   : dd if=%s of=Image bs=4096 skip=%d count=%d"
          % (os.path.basename(path), start // 4096, ks // 4096))


# ── super.img ───────────────────────────────────────────────────────────────
def analyze_super(path):
    print()
    print("=" * 64)
    print(" super.img: %s" % path)
    print("=" * 64)
    size = os.path.getsize(path)
    print("  文件大小   : %s" % human(size))

    with open(path, "rb") as f:
        blob = f.read(0x8000)

    if len(blob) < 0x4000:
        print("  文件太小，不是 LP super"); return

    magic, ssz, _ck, mmeta, slots, lbs = struct.unpack_from("<II32sIII", blob, GEOMETRY_OFF)
    if magic != GEOMETRY_MAGIC:
        print("  ❌ 0x1000 处没有 LP geometry（读到 0x%08x）" % magic)
        print("     可能：非动态分区镜像，或 LP 头在别的偏移")
        return
    print("  几何       : struct_size=%d meta_max=%d slots=%d claimed_lbs=%d"
          % (ssz, mmeta, slots, lbs))

    hmagic, maj, mi, hsz, _hc, tsz, _tc = struct.unpack_from("<IHHI32sI32s", blob, HEADER_OFF)
    if hmagic != HEADER_MAGIC:
        print("  ❌ 0x3000 处没有 LP header（读到 0x%08x）" % hmagic)
        return
    print("  LP header  : v%d.%d  header_size=%d  tables_size=%d" % (maj, mi, hsz, tsz))

    pc, psz, _pe = struct.unpack_from("<III", blob, DESCRIPTORS_OFF)
    ec, esz, _ee = struct.unpack_from("<III", blob, DESCRIPTORS_OFF + 12)
    gc, gsz, _ge = struct.unpack_from("<III", blob, DESCRIPTORS_OFF + 24)
    print("  描述符     : partitions=%d/%dB  extents=%d/%dB  groups=%d/%dB"
          % (pc, psz, ec, esz, gc, gsz))

    parts = {}
    for i in range(pc):
        base = PARTITION_TABLE_OFF + i * psz
        e = blob[base: base + psz]
        name = e[:36].split(b"\x00")[0].decode(errors="replace")
        if not name:
            continue
        _g, eidx, numext, _a = struct.unpack_from("<4I", e, 36)
        parts[name] = (eidx, numext)

    ext_off = PARTITION_TABLE_OFF + pc * psz
    exts = []
    for i in range(ec):
        ns, tt, td, _ts = struct.unpack_from("<QIII", blob, ext_off + i * esz)
        exts.append((ns, tt, td))

    grp_off = ext_off + ec * esz
    groups = []
    for i in range(gc):
        e = blob[grp_off + i * gsz: grp_off + (i + 1) * gsz]
        gname = e[:36].split(b"\x00")[0].decode(errors="replace")
        flags, = struct.unpack_from("<I", e, 36)
        mx, = struct.unpack_from("<Q", e, 40)
        groups.append((gname, flags, mx))

    print()
    print("  ── groups ──")
    for gname, flags, mx in groups:
        print("    %-34s flags=%d  max=%d (%.2f GiB)" % (gname, flags, mx, mx / 1024 ** 3))

    # 逐个 extent 单位假设验证
    print()
    print("  ── extent 单位实证（用 EROFS 魔数）──")
    unit = None
    for u in (512, 4096):
        ok = 0
        checked = 0
        for name, (eidx, numext) in parts.items():
            if numext == 0 or not name.endswith("_a"):
                continue
            ns, tt, td = exts[eidx]
            if tt != 0:
                continue
            checked += 1
            off = td * u
            if off + 1024 + 4 > size:
                continue
            with open(path, "rb") as f:
                f.seek(off + 1024)
                if f.read(4) == b"\xe2\xe1\xf5\xe0":
                    ok += 1
        print("    unit=%4d B : %d/%d 个分区在起始+1024 处命中 EROFS magic"
              % (u, ok, checked))
        if checked and ok == checked:
            unit = u
    if unit is None:
        unit = 512
        print("    ⚠️ 没有全部命中，默认按 512 B 解释")
    else:
        print("    ✅ 采用 unit=%d B" % unit)

    print()
    print("  ── slot A 分区 ──")
    print("    %-16s %-14s %12s %10s" % ("name", "start", "bytes", "GiB"))
    total = 0
    for name in sorted(parts):
        if not name.endswith("_a"):
            continue
        eidx, numext = parts[name]
        if numext == 0:
            print("    %-16s %-14s %12s %10s" % (name, "(empty)", "-", "-"))
            continue
        ns, tt, td = exts[eidx]
        if tt != 0:
            print("    %-16s type=%d" % (name, tt)); continue
        start = td * unit
        nb = ns * unit
        total += nb
        print("    %-16s 0x%012x %12d %10.3f" % (name, start, nb, nb / 1024 ** 3))

    b_used = any(parts[n][1] > 0 for n in parts if n.endswith("_b"))
    print()
    print("  slot B     : %s" % ("有内容" if b_used else "全空（无 A/B 回退保护）"))
    print("  slot A 合计: %.2f GiB / 镜像 %.2f GiB" % (total / 1024 ** 3, size / 1024 ** 3))


# ── 字符串归属 ──────────────────────────────────────────────────────────────
def analyze_strings(path, limit=6 << 30):
    print()
    print("  ── vendor 归属（抽样 %s）──" % human(min(os.path.getsize(path), limit)))
    keys = [b"Xiaomi", b"xiaomi", b"MIUI", b"Miui", b"HyperOS",
            b"ZTE", b"zte", b"nubia", b"NUBIA", b"NX7"]
    tot = {k: 0 for k in keys}
    CH = 1 << 25
    with open(path, "rb") as f:
        off = 0
        while off < min(os.path.getsize(path), limit):
            f.seek(off)
            d = f.read(CH)
            if not d:
                break
            for k in keys:
                tot[k] += d.count(k)
            off += CH
    for k in sorted(keys, key=lambda x: -tot[x]):
        if tot[k]:
            print("    %-10s %d" % (k.decode(), tot[k]))
    xi = tot[b"Xiaomi"] + tot[b"xiaomi"] + tot[b"MIUI"] + tot[b"Miui"]
    zt = tot[b"ZTE"] + tot[b"zte"] + tot[b"nubia"] + tot[b"NUBIA"]
    print("    → %s" % ("小米/MIUI 主导（系统层是小米）" if xi > zt else "中兴/nubia 主导"))


# ── 目录扫描 ────────────────────────────────────────────────────────────────
def scan_dir(root):
    imgs = []
    for dp, dn, fns in os.walk(root):
        for fn in fns:
            if fn.endswith(".img") or fn.endswith(".img.zst"):
                imgs.append(os.path.join(dp, fn))
    if not imgs:
        print("目录里没找到 .img 文件：%s" % root); return
    print("=" * 64)
    print(" 分区镜像清单 (%d 个)" % len(imgs))
    print("=" * 64)
    for p in sorted(imgs, key=lambda x: -os.path.getsize(x)):
        rel = os.path.relpath(p, root).replace("\\", "/")
        print("  %-34s %12d B  %10s" % (rel,
                                        os.path.getsize(p), human(os.path.getsize(p))))
    print()

    for p in imgs:
        base = os.path.basename(p)
        if base.startswith("boot") and base.endswith(".img"):
            analyze_boot(p)
        elif base.startswith("super") and base.endswith(".img"):
            analyze_super(p)
            analyze_strings(p)
        elif base.startswith("recovery"):
            analyze_boot(p)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    target = sys.argv[1]
    if os.path.isdir(target):
        scan_dir(target)
    elif os.path.basename(target).startswith("super"):
        analyze_super(target); analyze_strings(target)
    else:
        analyze_boot(target)


if __name__ == "__main__":
    main()
