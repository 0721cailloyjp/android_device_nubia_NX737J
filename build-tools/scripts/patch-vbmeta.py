#!/usr/bin/env python3
"""
patch-vbmeta.py — 关闭 AVB 校验（刷自定义 system 必做）

为什么需要它：
  你替换了 system/system_ext/product，而 vbmeta 里存着它们的 hash。
  不改 vbmeta 就刷，开机会停在 "Your device is corrupt and will not boot"。

AVB vbmeta 头的真实布局（已用 E://NX737J 包的 vbmeta.img 实测确认）：
    offset  size  字段
    0       4     magic "AVB0"
    4       4     required_libavb_version_major   （大端）
    8       4     required_libavb_version_minor   （大端）
    12      8     authentication_data_block_size
    20      8     auxiliary_data_block_size
    28      4     algorithm_type
    32      8     hash_offset
    40      8     hash_size
    48      8     signature_offset
    56      8     signature_size
    64      8     public_key_offset
    72      8     public_key_size
    80      8     public_key_metadata_offset
    88      8     public_key_metadata_size
    96      8     descriptors_offset
    104     8     descriptors_size
    112     8     rollback_index
    120     4     flags                ← 就是这里
    124     4     rollback_index_location
    128     48    release_string（"avbtool 1.3.0"）
    176     80    reserved

  ⚠️ 网上有教程说 flags 在 offset 12 —— 那是错的。
     offset 12 是 authentication_data_block_size 的高 32 位，
     改那里会破坏整个头部，直接刷坏。

flags 位：
    0x01 = HASHTREE_DISABLED      （关 dm-verity）
    0x02 = VERIFICATION_DISABLED  （关 vbmeta 签名校验）
    0x03 = 两个都关（我们要的）

用法：
    python3 patch-vbmeta.py vbmeta.img
    python3 patch-vbmeta.py vbmeta.img vbmeta_system.img
    python3 patch-vbmeta.py --flags 3 vbmeta.img          # 默认就是 3
    python3 patch-vbmeta.py --out-dir patched/ vbmeta.img vbmeta_system.img
    python3 patch-vbmeta.py --check vbmeta.img            # 只读，不改
"""
import argparse
import os
import struct
import sys

MAGIC = b"AVB0"
FLAGS_OFF = 120
RELEASE_STR_OFF = 128


def read_flags(data: bytes) -> int:
    return struct.unpack_from(">I", data, FLAGS_OFF)[0]


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("images", nargs="+", help="vbmeta.img [vbmeta_system.img ...]")
    ap.add_argument("--flags", type=lambda x: int(x, 0), default=3,
                    help="要写入的 flags（默认 3 = 关校验 + 关 verity）")
    ap.add_argument("--out-dir", default=None,
                    help="输出目录（默认在原文件旁生成 <名字>_patched.img）")
    ap.add_argument("--check", action="store_true", help="只打印，不修改")
    args = ap.parse_args()

    rc = 0
    for path in args.images:
        print("=" * 60)
        print(path)
        if not os.path.isfile(path):
            print("  ✗ 文件不存在"); rc = 1; continue

        data = bytearray(open(path, "rb").read())
        if len(data) < 256 or data[0:4] != MAGIC:
            print("  ✗ magic 不是 AVB0（读到 %r）" % bytes(data[0:4]))
            print("    这可能是 Android sparse image，先 simg2img 解开")
            rc = 1
            continue

        maj, mnr = struct.unpack_from(">II", data, 4)
        auth, aux = struct.unpack_from(">QQ", data, 12)
        desc_off, desc_sz = struct.unpack_from(">QQ", data, 96)
        rbi = struct.unpack_from(">Q", data, 112)[0]
        old = read_flags(data)
        rbl = struct.unpack_from(">I", data, 124)[0]
        rel = bytes(data[RELEASE_STR_OFF:RELEASE_STR_OFF + 48]).split(b"\x00")[0].decode(errors="replace")

        print("  magic          : AVB0 ✓")
        print("  版本           : %d.%d" % (maj, mnr))
        print("  auth_blk_size  : %d" % auth)
        print("  aux_blk_size   : %d" % aux)
        print("  descriptors    : off=%d size=%d" % (desc_off, desc_sz))
        print("  rollback_index : %d   (location %d)" % (rbi, rbl))
        print("  release_string : %r" % rel)
        print("  flags @%d      : 0x%02x  (%s)" % (
            FLAGS_OFF, old,
            " + ".join([n for b, n in ((0x01, "HASHTREE_DISABLED"),
                                       (0x02, "VERIFICATION_DISABLED")) if old & b]) or "0 = 全开"))

        if args.check:
            continue

        if old == args.flags:
            print("  已是 0x%02x，无需修改" % args.flags)
            continue

        struct.pack_into(">I", data, FLAGS_OFF, args.flags)

        if args.out_dir:
            os.makedirs(args.out_dir, exist_ok=True)
            outp = os.path.join(args.out_dir, os.path.basename(path))
        else:
            base, ext = os.path.splitext(path)
            outp = base + "_patched" + ext

        open(outp, "wb").write(data)

        # 回读校验
        back = read_flags(open(outp, "rb").read())
        ok = "✓" if back == args.flags else "✗"
        print("  写入           : 0x%02x -> 0x%02x   %s" % (old, back, ok))
        print("  输出           : %s" % outp)
        if back != args.flags:
            rc = 1

    print()
    print("注意：")
    print("  · 改了 flags 之后签名就对不上了，但 bootloader 先读 flags 再决定是否校验，")
    print("    所以 flags=DISABLE 时签名不会被检查。这是社区通用做法。")
    print("  · vbmeta 和 vbmeta_system 都要刷。先刷 vbmeta_system，最后刷 vbmeta。")
    print("  · 更干净的做法是让构建自己产出 flags=3 的 vbmeta，")
    print("    但那需要把 vbmetaimage/vbmeta_systemimage 也加进 --make-mode 目标。")
    return rc


if __name__ == "__main__":
    sys.exit(main())
