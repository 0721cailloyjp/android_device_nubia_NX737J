#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#
# nubia Z70S Ultra Photographer Edition (NX737J) — bootstrap device.mk.
# System side only. Mirrors IronShing/android_device_nubia_NX789J.
#

# ── Virtual A/B ─────────────────────────────────────────────────────────────
# This device is true Virtual A/B (LP groups qti_dynamic_partitions_a/_b).
# launch_with_vendor_ramdisk is what the stock boot chain expects.
$(call inherit-product, $(SRC_TARGET_DIR)/product/virtual_ab_ota/launch_with_vendor_ramdisk.mk)

# ── Dynamic partitions ──────────────────────────────────────────────────────
# Also defaults PRODUCT_USE_DYNAMIC_PARTITION_SIZE, which the EROFS image
# builder needs — without it build_image dies with KeyError: 'partition_size'.
PRODUCT_USE_DYNAMIC_PARTITIONS := true

# ── API levels ──────────────────────────────────────────────────────────────
# Stock vendor is Android 15 / board API 202404 (GRF-frozen).
#
# 2026-10-22 用一台真机（Xiaomi haotian, Android 17 / CP2A）实测交叉验证：
#   ro.system.build.version.sdk  = 37      ← A17 系统
#   ro.vendor.build.version.sdk  = 35      ← A15 vendor
#   ro.product.build.version.sdk = 37
#   ro.product.first_api_level   = 35
#   ro.board.api_level           = 202404   ← 和我们的 BOARD_SHIPPING_API_LEVEL 一字不差
#   /system/etc/vintf/compatibility_matrix.202404.xml 存在 ← A15 FCM 被 A17 框架正式支持
#   指纹：system :17/CP2A.260605.016  /  odm :15/AQ3A.250226.002（同机共存）
# 也就是说「A17 framework + A15 vendor」是 Google 官方支持的组合，不是野路子。
# 我们的 TARGET_PREBUILT_KERNEL 来自一台 A17 系统，vendor 是 A15，同构。
PRODUCT_SHIPPING_API_LEVEL := 35

# ⚠️ 这里原来还有一行 BOARD_SHIPPING_API_LEVEL := 202404 —— **删掉了**。
#    原因：BOARD_* 是 BoardConfig 阶段读的变量，写在 device.mk（product 阶段）里
#    完全不起作用，只会让人误以为已经设好了。
#
#    真正要让 ro.board.api_level = 202404 生效（VINTF 检查要用，缺了开不了机），
#    统一交给 system.prop：
#        ro.board.api_level=202404
#        ro.board.first_api_level=202404
#    这样只有一个来源，不会出现「BoardConfig 生成一遍 + system.prop 再写一遍」
#    的重复属性（AOSP 对重复属性是会报错的，那种错很难一眼看出来）。

# ── Boot control / update engine (A/B device) ──────────────────────────────
# ⚠️ 不加 android.hardware.boot-service.default_recovery —— 实测 Z70S 的 vendor
# 已经提供 android.hardware.boot.IBootControl/default（boot-service.qti.xml），
# system 侧再加会两边抢同一个 instance，boot control 状态不确定。
# （NX789J 加是因为它的 vendor 没这个 HAL；Z70S 有，情况不同。）
PRODUCT_PACKAGES += \
    update_engine \
    update_engine_sideload \
    update_verifier

# ── Fastbootd ───────────────────────────────────────────────────────────────
PRODUCT_PACKAGES += \
    fastbootd

# ── WiFi system-side HAL glue ───────────────────────────────────────────────
# 2026-10-23 更正：之前以为 hardware/qcom-caf/wlan 仓库不存在，其实存在 ——
#   LineageOS/android_hardware_qcom_wlan 就在 PixelOS/LineageOS 的 manifest 里
#   （路径 hardware/qcom/wlan 与 hardware/qcom-caf/wlan 都指向它）。
# 它提供 libwifi-hal-qcom / libwifi-hal-ctrl / lib_driver_cmd_qcwcn。
#
# 配置对齐官方 OnePlus sm8750-common（同 SoC，LineageOS 24.0）。
# ⚠️ 注意：OnePlus 树里有 WifiResTarget，但那是它设备树自带的 overlay
#   （device/xxx/overlay/WifiResTarget/Android.bp），不是全局模块。我们没有那个
#   overlay（之前因资源类型错误删了 overlay 目录），加它会 "module not found"。
#   它是装饰性 wifi 图标 RRO，删掉不影响 wifi 功能。
PRODUCT_PACKAGES += \
    android.hardware.wifi-service \
    hostapd \
    libwifi-hal-ctrl \
    libwifi-hal-qcom \
    wpa_supplicant \
    wpa_supplicant.conf

# ── NFC ─────────────────────────────────────────────────────────────────────
# 芯片是意法半导体 ST54L（实测 ro.vendor.feature.board_uses_nfc = ST54L）。
# vendor 已经提供 android.hardware.nfc AIDL HAL + 全部 feature XML（实测在跑），
# 但 system 侧缺 NFC 应用 —— 之前剔除了小米的 Nfc_st（com.android.nfc，依赖 miui 类），
# 得用 AOSP 标准 NfcNci 顶上，否则 NFC 开关整个消失。
# NfcNci 用标准 NCI 协议配 ST HAL，基础读写 + HCE 能工作；eSE 刷卡靠已回注的
# com.st.android.nfc_extensions 库（见 nubia-apps.mk）。
PRODUCT_PACKAGES += \
    NfcNci \
    com.android.nfc_extras

# ── Overlays ────────────────────────────────────────────────────────────────
# DISABLED for the bootstrap build. An overlay that names a resource which
# does not exist (or uses the wrong type) fails the build in aapt2 with
# "resource not found". Display tuning rides on the stock vendor RROs anyway.
# Re-enable once you have a verified overlay taken from a working tree.
# DEVICE_PACKAGE_OVERLAYS += $(LOCAL_PATH)/overlay

# ── Rootdir (goes to SYSTEM, not vendor — we do not build vendor) ──────────
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/rootdir/etc/init/init.nx737j.rc:$(TARGET_COPY_OUT_SYSTEM)/etc/init/init.nx737j.rc

# ── Soong namespaces ────────────────────────────────────────────────────────
# 设备树自身 + qcom wlan HAL（libwifi-hal-qcom 所在的 namespace）。
# 注意：官方 sm8750-common 还会加 qcom/opensource/wlan/* 等 namespace，
# 那些是给「从源码编译 wlan 内核驱动」用的 —— 我们保留 stock vendor_dlkm，
# 驱动已经在里面了，所以不加。
PRODUCT_SOONG_NAMESPACES += \
    $(LOCAL_PATH) \
    hardware/qcom/wlan

# ── 努比亚组件回注（已实测确定清单）────────────────────────────────────────
# 换掉 /system 和 /system_ext 会丢厂商 App。**清单不能靠目录名猜**，必须逐个解析 dex。
# 当前回注 6 个包 + 3 个 Java 库 + 3 个权限/库声明 XML，详见 nubia-apps.mk：
#
#   保留（dex 里零 miui/xiaomi 外部依赖，能在 AOSP 上跑）
#     NBAccount        cn.nubia.accounts        努比亚账号
#     NBUserCenter     cn.nubia.usercenter      用户中心
#     zteaccount_mfv   org.zx.AuthComp          统一认证（登录依赖它）
#     Wallet           com.zte.wallet           钱包（priv-app，带白名单）
#     WalletCore       com.zte.wallet.core      钱包核心
#     CCSetting        com.cc.setting           ★移植者的「高级设置」，sysfs 开关
#     transferclient.jar / com.st.android.nfc_extensions{,_16}.jar
#
#   剔除（看着像努比亚，其实是小米/移植者的）
#     Nfc_st                   = com.android.nfc（小米定制版，且与 AOSP NfcNci 撞包名）
#     CameraMind               = com.xiaomi.cameramind（依赖 miui 类）
#     CameraExtensionsProxy    = com.android.cameraextensions（与 AOSP 同名包冲突风险）
#     RomFixCameraCompat       = com.cc.romfix.cameracompat（移植者的相机补丁）
#
# 怎么拿：bash scripts/09-pull-nubia-apps.sh   （从手机 adb pull，已实测通过）
# 有产物就自动生效，没有就编纯 AOSP。
-include $(LOCAL_PATH)/nubia-apps.mk
