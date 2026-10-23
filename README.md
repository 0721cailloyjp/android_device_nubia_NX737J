# NX737J (nubia Z70S Ultra Photographer Edition) → PixelOS / 类原生 完整方案

**设备**：努比亚 Z70S Ultra 摄影师版，型号 NX737J，SoC 高通骁龙 8 Elite (SM8750, AOSP 平台名 `sun`)
**已有资产**：E 盘 `NX737J_HyperOS_4.0.0.10_A17_10.12` —— HyperOS 4 (Android 17) 移植包，EDL 9008 直刷，日用水平
**目标**：基于该移植包的硬件适配成果，构建类原生 ROM（PixelOS 17 / AviumUI 17 / LineageOS 24.0）

> ⚠️ **本文档是早期概览**。最新、完整、可执行的操作步骤以 **RUNBOOK.md** 为准。
> 关键结论变化：`product` 分区由"替换"改为"**保留原厂**"（理由见 RUNBOOK 2.5）。

---

## 0. 一句话结论

内核、vendor、公共树、ROM 基底、构建模板**全部现成**；唯一缺口是 device tree，且工作量已被压缩到最小。**不需要破解任何源码。**

---

## 1. 已核实的资产清单

### 1.1 内核 —— 已提取，格式正确

从移植包 `Firmware/boot.img` 提取（本仓库 `device-nubia-NX737J/prebuilt/Image`）：

| 项 | 值 |
|---|---|
| 偏移 | `0x1000` |
| 大小 | 38,729,088 B (36.93 MB) |
| 格式 | **原生 ARM64 Image**（非 gzip/lz4/zstd） |
| ARM64 magic | `ARM\x64` @ 0x38 |
| image_size | 0x2350000 (35.3 MB) |
| flags | 0xa（KASLR + 随机化基址） |
| 版本 | `6.6.143-android15-8-zte-1006-4k` |

这是 `TARGET_PREBUILT_KERNEL` 直接可用的格式。提取命令：

```bash
dd if=boot.img of=Image bs=4096 skip=1 count=9455
```

**内核层双重证明**：
1. 红魔10 有人用同内核编译类原生并开机（跨设备验证）
2. 你自己的移植包 = Android 17 系统 + 此内核 + 此 vendor，在 Z70S 上运行（同设备验证）

中兴**未开放** NX737J 内核源码（`opensource.ztedevices.com` 只有 NX789S），所以预编译是唯一路线，也正好是最省事的路线。

### 1.2 super.img 分区表 —— 已完整解析

LP metadata v10.2。**实测 extent 单位是 512 字节**（geometry 里写的 4096 是错的，已用 7 个 EROFS 魔数位置逐一证伪/证实）。

| 分区 | 起始偏移 | 大小 | 处置 |
|---|---|---|---|
| `odm_a` | `0x00100000` | 91.2 MiB | **保留** |
| `system_a` | `0x05f00000` | 1.033 GiB | **替换** |
| `system_dlkm_a` | `0x48100000` | 7.2 MiB | **保留** |
| `system_ext_a` | `0x48900000` | 0.825 GiB | **替换** |
| `product_a` | `0x7d600000` | 3.926 GiB | **保留（原厂）** |
| `vendor_a` | `0x178a00000` | 2.694 GiB | **保留** |
| `vendor_dlkm_a` | `0x225200000` | 31.3 MiB | **保留** |

- 镜像总大小 16.00 GiB，Slot A 已用 **8.61 GiB**，空闲 **7.39 GiB**
- group `qti_dynamic_partitions_a` max = 9,241,726,976 B = 8.61 GiB，与实测总量**精确吻合**，交叉验证通过
- **Slot B 全部为空**（Virtual A/B 的 B 槽从未被写入过）→ 只需处理 Slot A

分区归属已验证：`zte`×2043 / `ZTE`×237 / `nubia`×95 / `NX737J`×6 集中在 6~16 GB 段（vendor 所在），Xiaomi/MIUI 集中在 0~6 GB 段（system/product 所在）→ **vendor 是 nubia 原生，未被 HyperOS 污染**。

复现命令：

```bash
python3 scripts/dump-lp-metadata.py /path/to/super.img
```

### 1.3 公共树 —— 现成

`LineageOS/android_device_oneplus_sm8750-common`，有 **`lineage-24.0` 分支**（527 KB / 81 文件）：
`fstab.default`、`init.qcom.rc`、`ueventd.qcom.rc`、`audio_module_config_primary.xml`、`gps.conf`、`manifest_sun.xml`、NFC/WiFi/CarrierConfig overlay、`modules.list.msm.sun`。

### 1.4 ROM 基底 —— 三个都可用，同版本

| ROM | manifest 分支 | Android |
|---|---|---|
| PixelOS | `PixelOS-AOSP/android_manifest` `seventeen` | 17 |
| AviumUI | `AviumUI/android_manifests` `avium-17` | 17 (= LOS 24.0) |
| LineageOS | `LineageOS/android` `lineage-24.0` | 17 |

**版本对齐是关键利好**：HyperOS 4 移植包本身就是 "Android 17 系统 + Android 15 vendor" 在跑的实例，Treble 接缝已被亲自验证。

### 1.5 构建模板 —— 现成

`CaoBill0522/PixelOS_diting`（PixelOS 17 for 红米K50至尊版，2026-10 活跃）证明 **LineageOS 设备树可以直接套 PixelOS**：它的 device tree 就是 fork LineageOS `lineage-24.0`，分支名改 `pixelos-17`，其余不动。

---

## 2. 完整流程

### 阶段 1：本地准备（零流量，本仓库已做）

```bash
# 已在本仓库完成：
#   device-nubia-NX737J/prebuilt/Image   ← 从 boot.img 提取，已验证
```

需要你做的：把 `device-nubia-NX737J/` 推到你自己的 GitHub 仓库，然后在 `local_manifests/nx737j.xml` 里把 `yjpyydslove/android_device_nubia_NX737J` 改成你的仓库名。

### 阶段 2：租服务器（学生用代金券，接近零成本）

hybrid 只编 system 三件套，不编内核和 vendor，**内存门槛比全量 `m bacon` 低一大截**。

#### 学生党的正确姿势

**⚠️ 学生机（2核2G / 2核4G）编译不了 AOSP，别浪费认证。要的是代金券，不是机器本身。**

| 平台 | 学生权益 | 用途 |
|---|---|---|
| **阿里云高校计划** | **学生认证后领 300 元无门槛代金券**（有效期 1 年，每年 1 次） | **← 首选。用它开按量付费的大规格** |
| 阿里云飞天加速计划 | 2核2G 免费 7 个月 | 规格太小，编不了，忽略 |
| 腾讯云云+校园 | 轻量 2核4G ¥46 起 / CVM 2核4G ¥789/年 | 规格太小，编不了 |
| 百度智能云校园 | 2核4G 免费体验 | 规格太小 |

**操作路径**：
1. 阿里云实名认证 → 学生认证（学信网授权，几秒完成）
2. 领 300 元代金券
3. 开 **16核32G 按量实例**（¥3.77/h）→ 300 元 = **79 小时额度**
4. sync（1~3h）+ 首编（3~6h）≈ 9 小时，实花 ¥34，**代金券全覆盖**
5. **用完立刻释放实例和云盘**（云硬盘关机后仍计费）

代金券有产品/地域适用范围限制，领之前看清规则。

#### 非学生 / 代金券用完

腾讯云按量计费（华北/华南，元/小时）：

| 规格 | 按量价 | 参考时长 | 费用 |
|---|---|---|---|
| **16核32GB（推荐）** | **3.77** | sync 1~3h + 首编 3~6h ≈ **5~9h** | **¥19~34** |
| 16核64GB | 5.53 | 快一截，不必 | — |
| 32核128GB | 10.42~11.06 | 过剩 | — |

**竞价实例（Spot）**可再压到 1~3 折（16核32G 约 ¥0.5~1/h），代价是可能被回收（5 分钟通知）。ninja 是增量编译，回收后重跑会接着编，适合不赶时间。

32G 跑 hybrid 的两个注意点（`build.sh` 已自动处理）：
- `-j` 会按 `RAM/2` 自动算（32G → 16 jobs），防大链接 OOM
- **加 16~32 GB swap** 兜底。`setup-build-server.sh` 默认给 64 GB，嫌大可调 `SWAP_GB=16`

**国内机真正的问题不是价格，是镜像。** 国内访问 `android.googlesource.com` 慢，用 TUNA 镜像把占总量 90%+ 的 AOSP 部分转到国内：

```bash
git config --global url.https://mirrors.tuna.tsinghua.edu.cn/git/AOSP/.insteadof \
    https://android.googlesource.com
```

`sync.sh` 已内置（`MIRROR=tuna` 默认开启）。

**TUNA 限并发，`-j` 必须设 4**，开高会 HTTP 503。所以国内机 sync 不一定比国外机快——国外机带宽高但距离远，国内机距离近但被限流。哪个快得实测，`MIRROR=none JOBS=16` 可切回直连。

剩下约 10% 在 GitHub（PixelOS fork、你的设备树、内核），国内直连慢但量小，可接受。

### 阶段 3：出包

```bash
./build.sh
# 产物：out/target/product/NX737J/{system,system_ext,product}.img
```

**关键：不要 `m bacon`，不要编 recovery/boot/vendor。** 这就是"别人能一下子出大量包"的原因——soong/ninja 仍会分析整棵树，但只编译链接三个系统侧镜像。首次编译后，改 device tree 重编是分钟级。

### 阶段 4：刷回

> **⚠️ 前提：这台机器没有 A/B 回退保护。**
>
> LP 元数据显示 **Slot B 完全为空**（Virtual A/B 的 B 槽从未被写入过）。你的系统确认在 A 槽。
> 正常 A/B 设备刷挂了能 `fastboot --set-active=b` 切另一个槽，你这台槽 B 是空的，切过去直接起不来。
>
> **但恢复很简单**：E 盘那个移植包就是完整恢复点——全套固件 + super + EDL 工具 + 一键脚本。
> 刷挂了重跑 `一键刷机.bat` 就回到现在的状态，**不需要额外备份 super.img**。
>
> 实操上仍建议第一次只刷 `system_a` / `system_ext_a` / `product_a` 三个分区，
> 别动 boot 链和固件，把恢复面缩到最小。

见 `scripts/assemble-super.sh`。两个选项：

**选项 A（推荐）—— 原地覆盖三个逻辑分区**

用移植包已有的 EDL 流程，只写 `system_a` / `system_ext_a` / `product_a` 三个分区，其余（vendor/odm/*_dlkm/boot/init_boot/vendor_boot/dtbo/modem/dsp/tz/abl/xbl）**一个字节都不动**。

```bash
python3 scripts/dump-lp-metadata.py super.img   # 拿真实偏移
```

注意：AOSP 编出来的 `system.img` 通常 1.5~2.5 GB，**可能超过现有 1.033 GiB 的槽位**。超了就走选项 B。

**选项 B —— lpmake 重组 super**

有空闲 7.39 GiB + Slot B 全空，重组是安全的。`scripts/assemble-super.sh` 里有模板，用 `dump-lp-metadata.py` 输出的真实数值填。

**无论如何**：刷修改过的 `init_boot` / `system` 前，先把 `vbmeta` 的 AVB 校验关掉（flags 设 `0x02`），否则必现 "device is corrupt"。

---

## 3. 设备树内容说明

```
device-nubia-NX737J/
├── AndroidProducts.mk        # 产品定义 + lunch 选项
├── BoardConfig.mk            # TARGET_PREBUILT_KERNEL 指向 prebuilt/Image
├── device.mk                 # 继承 sm8750-common，叠 NX737J 特例
├── lineage_NX737J.mk         # lunch 目标 lineage_NX737J-userdebug
├── system.prop               # 仅放 vendor 不提供的属性
├── recovery.fstab            # 分区表（rawprogram0.xml 派生）
├── prebuilt/Image            # 36.93 MB 内核，已提取验证
├── rootdir/etc/init/init.nx737j.rc
└── overlay/.../config.xml    # 无开孔屏、144Hz、密度 480
```

**设计原则：这个树尽量小。** hybrid 架构下硬件支持全来自 stock vendor 分区，设备树只负责让 soong 认识这台机器。

标了 `TODO` 的地方（ZTE 内部代号、fstab 设备节点名）需要在真机上用
`adb shell ls -l /dev/block/bootdevice/by-name/` 核对后再定，我不替你猜。

---

## 4. 风险与未解决

| 项 | 状态 |
|---|---|
| 内核 | ✅ 已解决，双重证明 |
| vendor blobs | ✅ 已解决，super.img 四分区直接 dd |
| Treble 版本接缝 | ✅ 已被现有移植包验证 |
| 公共树 / ROM 基底 / 构建模板 | ✅ 现成 |
| device tree | ❌ **本仓库已写骨架，需真机调** |
| 编译资源 | ⚠️ 需租服务器（本机 16 GB 内存 + 单盘 ≤62 GB 不够） |
| 无真机联调 | ⚠️ 相机 HAL 调试没有真机基本是盲猜 |
| ZTE 内核源码 | ❌ NX737J 未开放，只能用预编译 |

**最大单项风险仍是相机**：OV50H(35mm,1/1.3") + OV50E(13mm UW) + OV64B(85mm 潜望) 的 HAL 配置在 vendor 里，但 AOSP 相机 App 能否完整驱动未知。移植包里是 `MiuiCamera`×16 + `cn.nubia.camera`×1 + `nubia.camera`×2，说明第三方 App 调 nubia vendor camera HAL 是跑通过一条路的。

---

## 5. 文件清单

```
nx737j-pixelos/
├── README.md                          ← 本文档
├── device-nubia-NX737J/               ← 设备树（推到 GitHub）
├── local_manifests/nx737j.xml         ← repo local manifest
└── scripts/
    ├── setup-build-server.sh          ← 服务器初始化（root）
    ├── sync.sh                        ← repo init + sync
    ├── build.sh                       ← 只编 system 三件套
    ├── extract-vendor.sh              ← lpunpack 拆 super
    ├── assemble-super.sh              ← super 重组/原地覆盖指引
    └── dump-lp-metadata.py            ← LP 分区表解析（已实测通过）
```

---

## 6. 立即可做的三件事

1. `python3 scripts/dump-lp-metadata.py <super.img>` 在自己机器上复现，确认输出一致
2. 把 `device-nubia-NX737J/` 推到 GitHub，改 `local_manifests/nx737j.xml` 里的仓库名
3. 租服务器，跑 `setup-build-server.sh` → `sync.sh` → `build.sh`

刷现有移植包验证相机能不能配第三方相机 App，是投入硬件前最值得做的一次零成本测试。
