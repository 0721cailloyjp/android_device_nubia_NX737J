# NX737J 类原生 ROM 移植分析报告（供第三方 AI 复核）

> 本文档自包含，不依赖对话上下文。目标是让另一个 AI（DeepSeek/Claude/GPT 等）能独立理解方案、复核正确性、找出遗漏。

---

## 1. 项目目标

把 **nubia Z70S Ultra 摄影师版（型号 NX737J）** 从 HyperOS 4（Android 17）移植包，换成**类原生 ROM**（PixelOS 17 / LineageOS 24.0 / AviumUI 17，都是 Android 17 / SDK 37）。

- SoC：高通 **SM8750**（骁龙 8 Elite，AOSP 平台名 `sun`，CPU 为 Oryon 核心）
- 当前手机跑的是 **HyperOS 4 移植包**（日用水平），移植包作者把设备标识改成了小米 15 Pro（`haotian` / `2410DPN6CC` / `Xiaomi`）
- 内核：`6.6.143-android15-8-zte-1006-4k`（ZTE 编译，**未开源**）

---

## 2. 核心架构：system-side hybrid

**只编译 `system` + `system_ext` 两个分区**，其余全部原样保留（不编译、不刷写）：

| 分区 | 处置 | 说明 |
|---|---|---|
| system | **编译替换** | AOSP 框架 |
| system_ext | **编译替换** | AOSP system_ext |
| product | **保留原厂** | 见 §6.3 |
| vendor | 保留原厂 | ZTE 硬件 HAL（相机/指纹/音频/显示/传感器） |
| odm | 保留原厂 | 薄分区（仅 bin/etc/lib64） |
| vendor_dlkm / system_dlkm | 保留原厂 | 内核模块 |
| boot / init_boot / vendor_boot / dtbo / vbmeta | 保留原厂 | 内核 + 启动链 |

**关键点：内核、boot、vendor 一个字节都不动。** 只有 system / system_ext 被 AOSP 替换。

---

## 3. 设备实测基线（关键数据，用于交叉验证）

```
屏幕        : 1216x2688 @ 480 dpi（BOE AMOLED，144Hz，屏下摄像头）
ABI         : 顶层 ro.product.cpu.abilist = arm64-v8a（64-bit only）
              底层 system 分区 abilist = arm64-v8a,armeabi-v7a,armeabi（带 32 位库 + Tango）
SoC         : SM8750, ro.board.platform=sun, ro.hardware=qcom
              dalvik.vm.isa.arm64.variant = oryon
NFC 芯片    : 意法半导体 ST54L（ro.vendor.feature.board_uses_nfc = ST54L）
WiFi 芯片   : WCN7861（board_wlan_bt_chip = WCN7861）
指纹        : goodix G7（zte_fingerprint_default_goodix_g7_aidl = 1）
红外        : ro.hardware.consumerir = zte（有红外发射器）
vendor 版本 : Android 15 / SDK 35（ro.vendor.build.version.sdk = 35）
system 版本 : Android 17 / SDK 37（ro.system.build.version.sdk = 37）
board API   : ro.board.api_level = 202404, ro.board.first_api_level = 202404
VNDK        : ro.vndk.version = （空）—— 不走 VNDK，靠 LLNDK + vendor snapshot
vendor SPL  : 2026-05-01（ro.vendor.build.security_patch）
vendor HAL 数量 : ~100 个（manifest 目录），QTI 全套 + ZTE 特有（vendor.zte.bert/bge/llm/radio/nook.modem/voice）
```

**内核**：`prebuilts/Image`，sha256 = `96e5b2e4c7198283a7b7adec9c3a20c77e4dd6f051cf575a65761512bb206051`，**与红魔10（NX789J）的 Image 完全一致**（跨设备通用，ZTE 同平台共享）。

---

## 4. super.img 分区布局（LP metadata 实测）

super 总大小 16 GiB。**extent 单位是 512 字节**（不是 geometry 里声明的 4096）。Slot A：

| 分区 | 起始偏移 | 大小 |
|---|---|---|
| odm_a | 0x00100000 | 91.2 MB |
| system_a | 0x05f00000 | **1.033 GiB**（1,109,176,320 B） |
| system_dlkm_a | 0x48100000 | 7.2 MB |
| system_ext_a | 0x48900000 | **0.825 GiB**（885,358,592 B） |
| product_a | 0x7d600000 | 3.926 GiB |
| vendor_a | 0x178a00000 | 2.694 GiB |
| vendor_dlkm_a | 0x225200000 | 31 MB |

- Slot A 已用 8.61 GiB，空闲 7.39 GiB
- **Slot B 完全为空**（Virtual A/B 的 B 槽从未写入）→ 无 A/B 回退，super 写坏只能 EDL 救砖
- group `qti_dynamic_partitions_a` max = 9,241,726,976 B（8.61 GiB）

---

## 5. 设备树关键配置

### BoardConfig.mk 要点

```make
# 架构（64-bit only）
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-2a-dotprod
TARGET_CPU_VARIANT_RUNTIME := oryon
# 无 TARGET_2ND_*（骁龙 8 Elite 无 AArch32，见 §6.1）

# board
TARGET_BOARD_PLATFORM := sun
TARGET_BOOTLOADER_BOARD_NAME := qcom   # ← ro.hardware=qcom，不是 sun（实测）

# 内核（prebuilt，不编源码）
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilts/Image
TARGET_FORCE_PREBUILT_KERNEL := true
TARGET_KERNEL_VERSION := 6.6
BOARD_USES_GENERIC_KERNEL_IMAGE := true

# 屏幕
TARGET_SCREEN_DENSITY := 480

# dexpreopt 最小化（省时间+省体积，system 槽位只有 1.033 GiB）
WITH_DEXPREOPT_BOOT_IMG_AND_SYSTEM_SERVER_ONLY := true

# 文件系统（stock 全 EROFS）
BOARD_SYSTEMIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_SYSTEM_EXTIMAGE_FILE_SYSTEM_TYPE := erofs
（...其余分区同 erofs）

# super / 动态分区
BOARD_SUPER_PARTITION_SIZE := 17179869184
BOARD_SUPER_PARTITION_GROUPS := qti_dynamic_partitions
BOARD_QTI_DYNAMIC_PARTITIONS_SIZE := 17175674880

# sepolicy（骑 stock vendor，不编 vendor policy）
TARGET_USES_PREBUILT_VENDOR_SEPOLICY := true
# 条件包含 qcom sepolicy_vndr（ROM 自带，路径 device/qcom/sepolicy_vndr/sm8750）

# AVB（刷机时 patch 原厂 vbmeta flags=3，见 §8）
BOARD_AVB_ENABLE := true
BOARD_AVB_VBMETA_SYSTEM := system system_ext   # 不含 product（不编）
BOARD_AVB_VBMETA_SYSTEM_KEY_PATH := external/avb/test/data/testkey_rsa2048.pem

# WiFi（对齐 OnePlus sm8750-common，qcwcn）
BOARD_WLAN_DEVICE := qcwcn
BOARD_HOSTAPD_PRIVATE_LIB := lib_driver_cmd_qcwcn
```

### device.mk 要点

```make
PRODUCT_USE_DYNAMIC_PARTITIONS := true
PRODUCT_SHIPPING_API_LEVEL := 35

# 无 android.hardware.boot-service（vendor 已提供 IBootControl/default）
PRODUCT_PACKAGES += update_engine update_engine_sideload update_verifier fastbootd

# WiFi
PRODUCT_PACKAGES += android.hardware.wifi-service hostapd libwifi-hal-ctrl libwifi-hal-qcom wpa_supplicant wpa_supplicant.conf

# NFC（ST54L，vendor 提供 AIDL HAL）
PRODUCT_PACKAGES += NfcNci com.android.nfc_extras

PRODUCT_SOONG_NAMESPACES += $(LOCAL_PATH) hardware/qcom/wlan

-include $(LOCAL_PATH)/nubia-apps.mk
```

### system.prop 全部内容

```properties
ro.zygote=zygote64
ro.product.marketname=nubia Z70S Ultra
ro.board.api_level=202404
ro.board.first_api_level=202404
ro.control_privapp_permissions=log
ro.telephony.default_network=32,32
```

### lineage_NX737J.mk 身份

```make
PRODUCT_NAME := lineage_NX737J
PRODUCT_DEVICE := NX737J
PRODUCT_MANUFACTURER := nubia
PRODUCT_BRAND := nubia
PRODUCT_MODEL := nubia Z70S Ultra   # 无引号（make 的 := 不解析引号）
```

---

## 6. 关键决策 & 已排除的坑

### 6.1 64-bit only（不用 32 位）

- 骁龙 8 Elite（Oryon）**无 AArch32 执行单元**，纯 64 位。
- 移植包能跑 32 位 App 靠 HyperOS 集成的 **Tango 转译器**（Amanieu Systems，闭源，把 ARM32 翻译成 ARM64），AOSP 搬不过来。
- 所以用 `core_64_bit_only`，不设 `TARGET_2ND_*`。顶层 abilist=arm64-v8a，与移植包一致。
- 32 位 App 装上也会 SIGILL 崩（CPU 执行不了 ARM32），故不引入。

### 6.2 不设 BOARD_VNDK_VERSION

- `ro.vndk.version` 实测为空 → 设备不走 VNDK，靠 LLNDK + vendor snapshot。
- 这是 A17 system 能配 A15 vendor 的根本原因。

### 6.3 保留原厂 product（理由已实测更正）

product 里**没有**努比亚组件（zte 库 0 / zte 权限 0 / zte 包 0，全是小米的）。
保留它的真实理由：
1. QTI 电话 Java 层（`qti_telephony_*`、`vendor.qti.hardware.data.connection*`、`lpa.xml`、`UimGba*`）→ 丢了 VoLTE/eSIM 废
2. `/product/etc/vintf/` 兼容性矩阵片段
3. 71 个设备配置 RRO

### 6.4 ro.hardware=qcom（不是 sun）

`ro.hardware` 来自 `TARGET_BOOTLOADER_BOARD_NAME`，决定 libhardware 找 vendor HAL 的命名（`/vendor/lib64/hw/<module>.qcom.so`）。实测 stock vendor 的 ro.hardware=qcom。

### 6.5 NFC

- 芯片 ST54L，vendor 提供 `android.hardware.nfc` AIDL HAL + 全部 feature XML。
- 剔除小米的 Nfc_st（com.android.nfc，依赖 miui 类，且与 AOSP NfcNci 撞包名）。
- system 侧补 `NfcNci` + `com.android.nfc_extras`。
- 回注 ST 扩展库（com.st.android.nfc_extensions{, _16}.jar）供钱包 eSE 刷卡。

### 6.6 boot HAL 不加

vendor 已提供 `android.hardware.boot.IBootControl/default`（boot-service.qti.xml），system 侧再加会抢 instance。

### 6.7 5G

`ro.telephony.default_network=32,32`（双 NR SA），实测移植包值。

### 6.8 32 位库 / Tango

见 6.1。移植包有 801 个 32 位库 + 213 个 `.so.tango` 预翻译缓存，但真正跑 32 位靠 Tango（闭源），AOSP 复刻不了。

### 6.9 vendor HAL 自包含（实测证实）

`linkerconfig` 证实：vendor 进程走独立 namespace（只搜 /vendor + /odm + VNDK），**不搜 /system_ext**。`/vendor/lib64` 有完整 perf 库（vendor.qti.hardware.perf@2.0~2.2.so + libqti-perfd.so）。→ 替换 system/system_ext 不影响 vendor HAL。

### 6.10 framework HAL 兼容

vendor 的 compatibility_matrix（type=device）只要求 framework 提供 4 个 HAL（android.frameworks.sensorservice + 3 个 optional QTI），AOSP 全覆盖。

### 6.11 已排除的编译坑（都是踩过/查过的）

| 坑 | 处置 |
|---|---|
| local_manifest 重复/嵌套项目（sepolicy_vndr、device/lineage/sepolicy） | ROM 自带，不进 local_manifest |
| WifiResTarget（设备树自带 overlay，非全局模块） | 删 |
| TARGET_HAS_GENERIC_KERNEL_IMAGE_HEADERS（死变量，AOSP 无） | 删 |
| lib_driver_cmd_qcwcn（来自 hardware/qcom/wlan，ROM 自带） | 恢复完整 WiFi 栈 |
| sepolicy filter-out（no-op 死代码） | 删 |
| BOARD_SHIPPING_API_LEVEL 写在 device.mk（无效） | 删，统一走 system.prop |

---

## 7. 努比亚组件回注清单（dex 校验定稿）

**保留（dex 零 miui/xiaomi 外部依赖，能在 AOSP 跑）**：

| 文件 | 包名 | 目标路径 |
|---|---|---|
| NBAccount.apk | cn.nubia.accounts | system/app |
| NBUserCenter.apk | cn.nubia.usercenter | system/app |
| zteaccount_mfv.apk | org.zx.AuthComp | system/app |
| Wallet.apk | com.zte.wallet | system/priv-app |
| WalletCore.apk | com.zte.wallet.core | system/priv-app |
| CCSetting.apk | com.cc.setting（移植者「高级设置」） | system/app/cc |
| transferclient.jar | — | system_ext/framework |
| com.st.android.nfc_extensions{, _16}.jar | — | system_ext/framework |
| 4 个权限 XML（钱包白名单 + transferclient + ST nfc ×2） | — | 各分区 etc/permissions |

**剔除（看着像努比亚，其实是小米/移植者的）**：
- Nfc_st = com.android.nfc（小米定制版，与 NfcNci 撞包名）
- CameraMind = com.xiaomi.cameramind（依赖 miui 类）
- CameraExtensionsProxy = com.android.cameraextensions
- RomFixCameraCompat = com.cc.romfix.cameracompat

**已知缺失类（与移植包现状一致，非退化）**：Wallet 缺 `com.zte.feature.Feature`；zteaccount_mfv 缺 `com.zte.aimodel.*`（4 个）。这些类在移植包里同样不存在。

---

## 8. 刷机 & 救砖流程

1. 编译出 system.img + system_ext.img（云端）
2. 本地 `assemble-super.sh` 把两个镜像原地 dd 进 stock super 的 Slot A（system 超 1.033 GiB 时走 lpmake 重组）
3. `patch-vbmeta.py --flags 3` 打两个 vbmeta（flags 在 offset 120，大端 u32）
4. `fastboot flash super` + `fastboot --set-active=a` + `fastboot -w` + reboot
5. 刷挂恢复：EDL 9008 + 原厂一键刷机.bat（原厂包 17GB 在 E 盘）

**关键**：只刷 super（含新 system/system_ext），boot/vendor 等一个字节不动。

---

## 9. 请第三方 AI 重点复核的问题

1. **编译能否一次通过**：设备树变量/模块名/仓库依赖是否还有遗漏？（已逐个 code search 验证，但欢迎独立复核）
2. **vendor 依赖**：有没有我们没发现的 vendor → system/system_ext 依赖？（已确认 vendor HAL 自包含，但可能还有边界情况）
3. **sepolicy**：`TARGET_USES_PREBUILT_VENDOR_SEPOLICY=true` + 条件 include qcom sepolicy_vndr，这个组合在 AOSP 17 下是否正确？
4. **AVB**：`BOARD_AVB_ENABLE=true` + 不编 vbmeta_system，刷 stock vbmeta patch flags=3，这条路径有没有漏洞？
5. **dexpreopt**：`WITH_DEXPREOPT_BOOT_IMG_AND_SYSTEM_SERVER_ONLY` 在 core_64_bit_only 下，首启 boot.oat 是否完整？
6. **EROFS**：Ubuntu 24.04 的 mkfs.erofs 1.7 是否满足 AOSP 17 的 build_image 要求？
7. **product 保留**：保留 HyperOS 的 product，其中的 MIUI priv-app 在 AOSP 下会怎样？处置：`ro.control_privapp_permissions=log`（开机不因特权权限阻塞）+ 开机后 `disable-miui.sh` 批量 `pm disable-user` 52 个 MIUI App（不崩、不显示、不触发）+ 可选 `11-strip-product.sh` 物理删除。（欢迎复核这个组合是否有漏洞）
8. **还有什么我们完全没考虑到的风险？**

---

## 10. 仓库 & 现状

- 设备树仓库：https://github.com/0721cailloyjp/android_device_nubia_NX737J（46 文件 / 100 MB，含 prebuilts/Image 38MB + 回注 APK 62MB）
- ROM 分支已实测存在：PixelOS `seventeen` / LineageOS `lineage-24.0` / AviumUI `avium-17`
- 编译环境：腾讯云按量 16核32G，Ubuntu 24.04，两阶段变配（sync → build → 下载），预算 ¥25
- 状态：设备树 + 脚本就绪，等服务器开编
