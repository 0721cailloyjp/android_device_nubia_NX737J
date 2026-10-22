#!/usr/bin/env python3
"""
dump-lp-metadata.py — read the dynamic-partition (LP) metadata from a
super.img and print every logical partition's start offset and size.

VERIFIED against the NX737J HyperOS 4 port package's super.img:

  * LP metadata v10.2
  * geometry copies @ 0x1000 and 0x2000 (52 B, magic 0x616C4467)
  * metadata header @ 0x3000 (magic 0x414C5030)
  * table descriptors @ 0x3054  (3 x 12 B: count, entry_size, end_offset)
  * partition table @ 0x3100    (14 entries x 52 B = A + B slots)
  * extent table    @ 0x33D8    (7 entries  x 24 B)
  * group table     @ 0x3480    (3 entries  x 48 B)

  *** IMPORTANT ***
  The geometry struct claims logical_block_size = 4096, but the extent
  target_data / num_sectors fields are in **512-byte** units. This was
  proven empirically: every EROFS superblock magic in the image sits at
  exactly (target_data * 512) + 1024. Do not trust the geometry's
  logical_block_size on this image.

  Slot B partitions have extent_index = 7, num_extents = 0 — i.e. the B
  slot is EMPTY (no OTA has ever been applied). Only slot A matters.

Usage:
    python3 dump-lp-metadata.py /path/to/super.img
"""
import os
import struct
import sys

GEOMETRY_MAGIC = 0x616C4467      # "gDla"
HEADER_MAGIC = 0x414C5030        # "0PLA"  (empirically observed, NOT 0x414a5030)
EXTENT_UNIT = 512                # PROVEN by EROFS magic placement

GEOMETRY_OFF = 0x1000
HEADER_OFF = 0x3000
DESCRIPTORS_OFF = 0x3054
PARTITION_TABLE_OFF = 0x3100

PARTITION_NAMES_A = [
    "odm_a", "system_a", "system_dlkm_a", "system_ext_a",
    "product_a", "vendor_a", "vendor_dlkm_a",
]


def _die(msg):
    sys.exit("dump-lp-metadata: " + msg)


def main(path):
    size = os.path.getsize(path)
    with open(path, "rb") as f:
        blob = f.read(0x8000)

    # ── geometry ────────────────────────────────────────────────────────────
    magic, struct_size, _cksum, meta_max, slots, lbs_claim = struct.unpack_from(
        "<II32sIII", blob, GEOMETRY_OFF)
    if magic != GEOMETRY_MAGIC:
        _die("no LP geometry at 0x%x (got 0x%08x)" % (GEOMETRY_OFF, magic))
    print("geometry    : struct_size=%d metadata_max=%d slots=%d "
          "claimed_logical_block=%d  (ACTUAL extent unit = %d B)"
          % (struct_size, meta_max, slots, lbs_claim, EXTENT_UNIT))

    # ── header ──────────────────────────────────────────────────────────────
    hmagic, major, minor, hdr_size, _hc, tables_size, _tc = struct.unpack_from(
        "<IHHI32sI32s", blob, HEADER_OFF)
    if hmagic != HEADER_MAGIC:
        _die("no LP header at 0x%x (got 0x%08x)" % (HEADER_OFF, hmagic))
    print("header      : v%d.%d header_size=%d tables_size=%d"
          % (major, minor, hdr_size, tables_size))

    # ── descriptors ─────────────────────────────────────────────────────────
    p_count, p_esize, p_end = struct.unpack_from("<III", blob, DESCRIPTORS_OFF)
    e_count, e_esize, e_end = struct.unpack_from("<III", blob, DESCRIPTORS_OFF + 12)
    g_count, g_esize, g_end = struct.unpack_from("<III", blob, DESCRIPTORS_OFF + 24)
    print("descriptors : partitions=%d/%dB extents=%d/%dB groups=%d/%dB"
          % (p_count, p_esize, e_count, e_esize, g_count, g_esize))

    ext_off = PARTITION_TABLE_OFF + p_count * p_esize
    grp_off = ext_off + e_count * e_esize
    if p_end != e_count * e_esize + p_count * p_esize:
        print("  ! descriptor chain odd: partitions end %d, extents claim %d"
              % (p_count * p_esize, p_end))
    if e_end != g_count * g_esize + e_end:
        print("  ! descriptor chain odd: extents end %d, groups claim %d"
              % (e_count * e_esize + e_end, e_end))

    # ── partition table ─────────────────────────────────────────────────────
    parts = {}
    for i in range(p_count):
        base = PARTITION_TABLE_OFF + i * p_esize
        e = blob[base: base + p_esize]
        name = e[:36].split(b"\x00")[0].decode(errors="replace")
        if not name:
            continue
        # observed field order: group_index, extent_index, num_extents, attributes
        _grp, ext_idx, num_ext, _attr = struct.unpack_from("<4I", e, 36)
        parts[name] = (ext_idx, num_ext)

    # ── extent table ────────────────────────────────────────────────────────
    extents = []
    for i in range(e_count):
        base = ext_off + i * e_esize
        num_sectors, target_type, target_data, _ts = struct.unpack_from(
            "<QIII", blob, base)
        extents.append((num_sectors, target_type, target_data))

    # ── group table ─────────────────────────────────────────────────────────
    groups = []
    for i in range(g_count):
        base = grp_off + i * g_esize
        e = blob[base: base + g_esize]
        gname = e[:36].split(b"\x00")[0].decode(errors="replace")
        flags, = struct.unpack_from("<I", e, 36)
        maximum, = struct.unpack_from("<Q", e, 40)
        groups.append((gname, flags, maximum))

    if not any(g[0].startswith("qti_dynamic") for g in groups):
        _die("group table did not parse — offsets wrong")

    # ── report ──────────────────────────────────────────────────────────────
    print("\n=== groups ===")
    for gname, flags, maximum in groups:
        print("  %-32s flags=%-6d max=%d (%.2f GiB if bytes)"
              % (gname, flags, maximum, maximum / 1024 ** 3))

    print("\n=== slot A partitions (512-byte extent units) ===")
    print("  %-16s %-14s %14s %9s %9s" % ("name", "start", "bytes", "GiB", "end GiB"))
    layout = {}
    for name in PARTITION_NAMES_A:
        if name not in parts:
            continue
        ext_idx, num_ext = parts[name]
        if num_ext == 0:
            print("  %-16s %-14s %14s %9s %9s" % (name, "(empty)", "-", "-", "-"))
            continue
        ns, tt, td = extents[ext_idx]
        start = td * EXTENT_UNIT
        nbytes = ns * EXTENT_UNIT
        end = start + nbytes
        flag = "" if end <= size else "  <== EXCEEDS IMAGE"
        print("  %-16s 0x%012x %14d %9.3f %9.3f%s"
              % (name, start, nbytes, nbytes / 1024 ** 3, end / 1024 ** 3, flag))
        layout[name[:-2]] = (start, nbytes)

    print("\n=== slot B partitions ===")
    any_b = False
    for name in sorted(parts):
        if not name.endswith("_b"):
            continue
        ext_idx, num_ext = parts[name]
        if num_ext:
            any_b = True
            ns, tt, td = extents[ext_idx]
            print("  %-16s 0x%x %d B" % (name, td * EXTENT_UNIT, ns * EXTENT_UNIT))
    if not any_b:
        print("  (all empty — Virtual A/B B slot has never been written)")

    total = sum(v[1] for v in layout.values())
    print("\n=== summary ===")
    print("  image size      : %.2f GiB" % (size / 1024 ** 3))
    print("  slot A used     : %.2f GiB" % (total / 1024 ** 3))
    print("  free            : %.2f GiB" % ((size - total) / 1024 ** 3))
    print("\n  Replace these three with your build (keep everything else):")
    for n in ("system", "system_ext", "product"):
        if n in layout:
            s, b = layout[n]
            print("    %-12s start=0x%012x  max=%d B (%.3f GiB)"
                  % (n + "_a", s, b, b / 1024 ** 3))
    print("\n  Keep these four byte-identical:")
    for n in ("vendor", "vendor_dlkm", "odm", "system_dlkm"):
        if n in layout:
            s, b = layout[n]
            print("    %-12s start=0x%012x  %d B" % (n + "_a", s, b))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
