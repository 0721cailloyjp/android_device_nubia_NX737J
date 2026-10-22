#!/usr/bin/env python3
"""
apk-dep-scan.py — 判断一个 APK 引用了哪些「外部」类，从而预测它能否在 AOSP 上跑起来

为什么需要这个：
  移植包 / 原厂 system 里的厂商 App，可能依赖厂商自己的 framework 扩展类
  （小米的 miui.*、ZTE 的 com.zte.mifavor.* …）。这些类不在 AOSP 里，
  把它们搬到 AOSP 上会 NoClassDefFoundError。

原理（精确，不是字符串猜的）：
  dex 里 type_ids 收录了「被引用到的全部类型」，class_defs 收录了「本 dex 定义的类型」。
      external = referenced(type_ids) − defined(class_defs)
  再做一次白名单过滤，去掉 java.* / android.* / kotlin.* 这类必然由系统提供的。

用法：
  python apk-dep-scan.py <apk> [<apk> ...]
  python apk-dep-scan.py --prefix com/zte --prefix miui <apk>

退出码：0 = 无外部厂商依赖；1 = 有（会打印出来）
"""
import sys, zipfile, struct, re, collections

# ── dex 结构偏移（dex-format 官方布局）──────────────────────────────────────
HDR = {
    'string_ids_size': 0x38, 'string_ids_off': 0x3C,
    'type_ids_size':   0x40, 'type_ids_off':   0x44,
    'class_defs_size': 0x60, 'class_defs_off': 0x64,
}
CLASS_DEF_ITEM_SIZE = 32

# 一定由系统 / 语言运行时提供的包，出现也不算问题
PLATFORM_PREFIXES = (
    'Landroid/', 'Ljava/', 'Ljavax/', 'Ldalvik/', 'Lsun/', 'Ljdk/',
    'Lorg/apache/', 'Lorg/json/', 'Lorg/xml/', 'Lorg/w3c/', 'Lorg/xmlpull/',
    'Lkotlin/', 'Lkotlinx/', 'Lcom/google/', 'Lcom/android/',
    'Lorg/chromium/', 'Lorg/bouncycastle/', 'Lorg/conscrypt/',
    'Llibcore/', 'Lcom/qualcomm/', 'Lvendor/qti/', 'Lvendor/qualcomm/',
    'Lcom/airbnb/', 'Lokhttp3/', 'Lokio/', 'Lio/reactivex/',
    'Lcom/squareup/', 'Lretrofit2/', 'Lcom/bumptech/', 'Lcom/alibaba/',
    'Lcom/facebook/', 'Lorg/greenrobot/', 'Lio/flutter/',
)


def uleb128(buf, off):
    """读一个 uleb128，返回 (值, 新偏移)"""
    result = shift = 0
    while True:
        b = buf[off]
        off += 1
        result |= (b & 0x7F) << shift
        if not (b & 0x80):
            return result, off
        shift += 7
        if shift > 35:
            raise ValueError('uleb128 过长')


def read_mutf8(buf, off):
    """读 string_data_item：先 uleb128 字符数，再 MUTF-8 字节"""
    _, off = uleb128(buf, off)
    end = buf.index(b'\x00', off)
    return buf[off:end].decode('utf-8', 'replace')


def dex_classes(data):
    """返回 (referenced, defined) 两个 class descriptor 集合"""
    (s_size, s_off, t_size, t_off,
     c_size, c_off) = (struct.unpack_from('<I', data, HDR[k])[0] for k in
                       ('string_ids_size', 'string_ids_off',
                        'type_ids_size', 'type_ids_off',
                        'class_defs_size', 'class_defs_off'))

    # string pool：string_ids[i] 指向 string_data_item
    strings = []
    for i in range(s_size):
        off = struct.unpack_from('<I', data, s_off + i * 4)[0]
        strings.append(read_mutf8(data, off))

    # type_ids[i] = string_idx
    types = [strings[struct.unpack_from('<I', data, t_off + i * 4)[0]]
             for i in range(t_size)]

    defined = set()
    for i in range(c_size):
        base = c_off + i * CLASS_DEF_ITEM_SIZE
        defined.add(types[struct.unpack_from('<I', data, base)[0]])

    return set(types), defined


def norm(desc):
    """把数组/泛型描述符还原成元素类描述符：[[Lcom/zte/Foo; → Lcom/zte/Foo;"""
    return desc.lstrip('[')


def scan(apk, prefixes=None):
    z = zipfile.ZipFile(apk)
    dexes = sorted(n for n in z.namelist() if re.match(r'classes\d*\.dex$', n))
    ref, defd = set(), set()
    for d in dexes:
        r, defn = dex_classes(z.read(d))
        ref |= r
        defd |= defn

    # 数组元素类型要先归一化，否则 [Lcom/zte/Foo; 会被误判成「外部类」
    ref = {norm(c) for c in ref}
    defd = {norm(c) for c in defd}

    ext = ref - defd
    ext = {c for c in ext if not c.startswith(PLATFORM_PREFIXES)}

    def pkg_of(c):
        parts = c.lstrip('L').split('/')
        return '/'.join(parts[:2]) if len(parts) > 1 else parts[0]

    groups = collections.Counter(pkg_of(c) for c in ext)
    return dexes, defd, ext, groups


def main():
    args = [a for a in sys.argv[1:]]
    prefixes = []
    while '--prefix' in args:
        i = args.index('--prefix')
        prefixes.append(args[i + 1])
        del args[i:i + 2]
    if not args:
        print(__doc__)
        return 2

    bad = 0
    for apk in args:
        dexes, defd, ext, groups = scan(apk)
        print('=' * 78)
        print(f'{apk}')
        print(f'  dex={len(dexes)}  本 dex 定义类={len(defd)}  外部引用类={len(ext)}')
        if prefixes:
            for p in prefixes:
                n_def = sum(1 for c in defd if c.startswith('L' + p))
                n_ext = sum(1 for c in ext if c.startswith('L' + p))
                flag = '打包在内 ✓' if n_def and not n_ext else ('外部依赖 ✗' if n_ext else '-')
                print(f'    {p:24s} 定义={n_def:5d}  外部={n_ext:5d}   {flag}')
                for c in sorted(c for c in ext if c.startswith('L' + p))[:8]:
                    print(f'        缺: {c}')
        if groups:
            print('  外部依赖按包归类（前 12）：')
            for p, n in groups.most_common(12):
                print(f'    {p:40s} {n}')
            bad += 1
        else:
            print('  ✓ 无外部厂商依赖（除平台类）')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
