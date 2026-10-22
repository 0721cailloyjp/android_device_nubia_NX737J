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
# Stock vendor is Android 15 / board API 202404 (GRF-frozen). The HyperOS 4
# port proves an Android 17 system rides this A15 vendor fine.
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

# ── WiFi system-side HAL glue (dodge/sm8750-common pattern) ────────────────
PRODUCT_PACKAGES += \
    libwifi-hal-qcom

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
# wifi HAL + qcwcn driver-cmd lib live in namespaced dirs.
PRODUCT_SOONG_NAMESPACES += \
    hardware/qcom-caf/wlan \
    hardware/qcom-caf/wlan/qcwcn \
    $(LOCAL_PATH)
