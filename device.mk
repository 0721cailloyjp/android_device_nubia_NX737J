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
#   /system/etc/vintf/compatibility_matrix.202404.xml 存在 ← A15 FCM 被 A17 框架正式支持
# 也就是说「A17 framework + A15 vendor」是 Google 官方支持的组合，不是野路子。
# 我们的 TARGET_PREBUILT_KERNEL 来自一台 A17 系统，vendor 是 A15，同构。
PRODUCT_SHIPPING_API_LEVEL := 35
BOARD_SHIPPING_API_LEVEL := 202404

# ── Boot control / update engine (A/B device) ──────────────────────────────
PRODUCT_PACKAGES += \
    android.hardware.boot-service.default_recovery

PRODUCT_PACKAGES += \
    update_engine \
    update_engine_sideload \
    update_verifier

# ── Fastbootd ───────────────────────────────────────────────────────────────
PRODUCT_PACKAGES += \
    fastbootd

# ── WiFi system-side HAL glue ───────────────────────────────────────────────
# DISABLED for the bootstrap build.
# NX789J builds `libwifi-hal-qcom` from hardware/qcom-caf/wlan, but that path
# does not exist in the LineageOS org (404 as of 2026-10) and is NOT in the
# default PixelOS/LineageOS manifest. Keeping the dependency = guaranteed
# "module not found" build failure.
#
# WiFi on this hybrid comes from the STOCK vendor partition anyway, so it is
# not needed for first boot. Re-enable together with the correct repo once
# you have a booting build and want to chase wifi.
# PRODUCT_PACKAGES += libwifi-hal-qcom

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
# Only the device tree itself. hardware/qcom-caf/wlan is intentionally dropped
# (repo does not exist at that path), so no qcwcn namespace here.
PRODUCT_SOONG_NAMESPACES += \
    $(LOCAL_PATH)

# ── 努比亚专有 App 回注（可选）───────────────────────────────────────────────
# 原厂 system 里有几个努比亚自己的 App，换 system 会丢：
#   NBAccount / NBUserCenter / zteaccount_mfv / Nfc_st /
#   CameraMind / CameraExtensionsProxy / RomFixCameraCompat
#
# 移植包作者在把 system 换成澎湃4之后仍然保留了这批 App，说明摘掉会出问题
# （账号登录、NFC、相机扩展）。所以这里默认带上。
#
# 怎么拿到这些 APK（二选一，本地跑）：
#   bash scripts/09-pull-nubia-apps.sh            ← 直接从手机 adb pull，最快（几十 MB）
#   bash scripts/08-extract-nubia-apps.sh super.img  ← 从 super.img 解包（服务器上跑）
#
# 两个脚本都会生成 prebuilts/nubia-apps/ + nubia-apps.mk。
# 下面用 -include（带减号）：文件不存在时静默跳过，不会编译失败。
# 所以只要产物在，就自动生效；没有就编纯 AOSP。
-include $(LOCAL_PATH)/nubia-apps.mk
