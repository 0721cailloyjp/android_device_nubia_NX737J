#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#
# nubia Z70S Ultra Photographer Edition (NX737J, SM8750 "sun")
#
# BOOTSTRAP PHASE — SYSTEM SIDE ONLY.
#   Builds:  system / system_ext / product
#   Rides:   STOCK vendor / odm / vendor_dlkm / system_dlkm
#            + STOCK boot chain (boot / init_boot / vendor_boot / dtbo / vbmeta)
#
# Every value below is copied from IronShing/android_device_nubia_NX789J
# (lineage-23.2, boots on RedMagic 10 Pro — same SoC, same display, same
# front camera, same fingerprint sensor) and cross-checked against this
# device's own EDL package (Firmware/*.img sizes + super.img LP metadata).
#
# Partition sizes VERIFIED against E:\NX737J_HyperOS_4.0.0.10_A17_10.12:
#   boot.img 100663296 | init_boot.img 8388608 | vendor_boot.img 100663296
#   dtbo.img 25165824  | recovery.img 104857600 | super.img 17179869184
#

DEVICE_PATH := device/nubia/NX737J

# ── Architecture (same as LOS oneplus/sm8750-common — same SoC) ─────────────
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-2a-dotprod
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 :=
TARGET_CPU_VARIANT := generic
TARGET_CPU_VARIANT_RUNTIME := oryon

# ── Board ───────────────────────────────────────────────────────────────────
BOARD_VENDOR := nubia
TARGET_BOARD_PLATFORM := sun
TARGET_BOOTLOADER_BOARD_NAME := sun

# ── A/B + Virtual A/B ───────────────────────────────────────────────────────
# LP metadata on this device declares groups qti_dynamic_partitions_a/_b,
# i.e. true Virtual A/B. Slot B is currently empty (never OTA'd).
AB_OTA_UPDATER := true
AB_OTA_PARTITIONS := \
    odm \
    product \
    system \
    system_dlkm \
    system_ext \
    vendor \
    vendor_dlkm

# ── Boot header (stock: v4, 4K pages) ───────────────────────────────────────
# Informational: we ship the stock boot chain, nothing here is built.
BOARD_BOOT_HEADER_VERSION := 4
BOARD_KERNEL_BASE := 0x00000000
BOARD_KERNEL_PAGESIZE := 4096
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOT_HEADER_VERSION)
BOARD_INIT_BOOT_HEADER_VERSION := 4
BOARD_MKBOOTIMG_INIT_ARGS += --header_version $(BOARD_INIT_BOOT_HEADER_VERSION)
BOARD_RAMDISK_USE_LZ4 := true
BOARD_USES_GENERIC_KERNEL_IMAGE := true
TARGET_HAS_GENERIC_KERNEL_IMAGE_HEADERS := true

# ── Kernel: prebuilt ────────────────────────────────────────────────────────
# 6.6.143-android15-8-zte-1006-4k, extracted from the port package's boot.img
# (offset 0x1000, 38729088 B, native ARM64 Image). ZTE has NOT published
# NX737J kernel source, so prebuilt is the only route.
# TARGET_FORCE_PREBUILT_KERNEL stops vendor/lineage kernel.mk from trying to
# build from source — without it the build fails looking for kernel sources.
BOARD_KERNEL_IMAGE_NAME := Image
TARGET_KERNEL_ARCH := arm64
TARGET_KERNEL_CONFIG := gki_defconfig
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilts/Image
TARGET_FORCE_PREBUILT_KERNEL := true
# vendor/lineage/config/BoardConfigKernel.mk 会从 TARGET_KERNEL_SOURCE/Makefile
# 里 grep VERSION/PATCHLEVEL 来推 TARGET_KERNEL_VERSION。我们没有内核源码，
# 那个推导结果会是空值（进而算出 KERNEL_PATH=kernel/platform/kernel-.）。
# 该文件第 33-35 行的注释明确写了：预编译内核的场景应在设备树里手工覆盖。
TARGET_KERNEL_VERSION := 6.6

# ── Display (6.85" 2688x1216 BOE AMOLED, 144 Hz, under-display camera) ─────
TARGET_SCREEN_DENSITY := 480

# ── Filesystem ──────────────────────────────────────────────────────────────
TARGET_USERIMAGES_USE_F2FS := true
BOARD_USES_METADATA_PARTITION := true

# ── Partition sizes (from the device's own EDL firmware images) ────────────
BOARD_FLASH_BLOCK_SIZE := 262144
BOARD_BOOTIMAGE_PARTITION_SIZE := 100663296
BOARD_INIT_BOOT_IMAGE_PARTITION_SIZE := 8388608
BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE := 100663296
BOARD_DTBOIMG_PARTITION_SIZE := 25165824
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 104857600

# ── Super / dynamic partitions ─────────────────────────────────────────────
# super = 16 GiB (verified). Group max set to full super minus 4 MiB so the
# rebuilt super has room to grow — the STOCK group max is only 9241726976 B
# (8.61 GiB, exactly the current usage), which cannot hold an AOSP system.img.
# Tooling: reassemble with lpmake (see scripts/assemble-super.sh).
BOARD_SUPER_PARTITION_SIZE := 17179869184
BOARD_SUPER_PARTITION_GROUPS := qti_dynamic_partitions
BOARD_QTI_DYNAMIC_PARTITIONS_SIZE := 17175674880
BOARD_QTI_DYNAMIC_PARTITIONS_PARTITION_LIST := \
    odm \
    product \
    system \
    system_dlkm \
    system_ext \
    vendor \
    vendor_dlkm

# ── Filesystem types: stock ships EROFS for every logical partition ───────
# Without these the erofs image builder is not selected and you get ext4
# images the stock bootloader/vendor will not mount.
BOARD_ODMIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_PRODUCTIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_SYSTEM_DLKMIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_SYSTEM_EXTIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_SYSTEMIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_VENDOR_DLKMIMAGE_FILE_SYSTEM_TYPE := erofs

TARGET_COPY_OUT_ODM := odm
TARGET_COPY_OUT_PRODUCT := product
TARGET_COPY_OUT_SYSTEM_DLKM := system_dlkm
TARGET_COPY_OUT_SYSTEM_EXT := system_ext
TARGET_COPY_OUT_VENDOR := vendor
TARGET_COPY_OUT_VENDOR_DLKM := vendor_dlkm

# ── Properties ──────────────────────────────────────────────────────────────
# MUST be declared, otherwise the device system.prop is silently ignored.
TARGET_SYSTEM_PROP += $(DEVICE_PATH)/system.prop

# ── Security patch — match the stock A15 vendor ────────────────────────────
VENDOR_SECURITY_PATCH := 2026-05-01

# ── SELinux ─────────────────────────────────────────────────────────────────
# Stock-vendor-ride device: no vendor.img is flashed from this build, so the
# dynamic HAL policy has to be routed system-side (same pattern as NX789J /
# NX809J). sun is in UM_6_6_FAMILY upstream so the qcom vndr include works.
TARGET_USES_PREBUILT_VENDOR_SEPOLICY := true
include device/qcom/sepolicy_vndr/SEPolicy.mk
SYSTEM_EXT_PRIVATE_SEPOLICY_DIRS := \
    $(filter-out device/lineage/sepolicy/qcom/dynamic,$(SYSTEM_EXT_PRIVATE_SEPOLICY_DIRS))

# ── Verified Boot ───────────────────────────────────────────────────────────
# --flags 3 = disable verification + disable verity. The flash kit also ships
# the STOCK vbmeta with these flags patched in; both must agree or the device
# halts with "Your device is corrupt".
BOARD_AVB_ENABLE := true
BOARD_AVB_MAKE_VBMETA_IMAGE_ARGS += --flags 3
BOARD_AVB_VBMETA_SYSTEM := system system_ext product
BOARD_AVB_VBMETA_SYSTEM_KEY_PATH := external/avb/test/data/testkey_rsa2048.pem
BOARD_AVB_VBMETA_SYSTEM_ALGORITHM := SHA256_RSA2048
BOARD_AVB_VBMETA_SYSTEM_ROLLBACK_INDEX := $(PLATFORM_SECURITY_PATCH_TIMESTAMP)
BOARD_AVB_VBMETA_SYSTEM_ROLLBACK_INDEX_LOCATION := 2

# ── LineageOS shared BoardConfig ────────────────────────────────────────────
include vendor/lineage/config/BoardConfigLineage.mk

# ── WiFi (qcwcn pattern, same as sm8750-common) ─────────────────────────────
BOARD_WLAN_DEVICE := qcwcn
BOARD_HOSTAPD_DRIVER := NL80211
BOARD_HOSTAPD_PRIVATE_LIB := lib_driver_cmd_$(BOARD_WLAN_DEVICE)
BOARD_WPA_SUPPLICANT_DRIVER := $(BOARD_HOSTAPD_DRIVER)
BOARD_WPA_SUPPLICANT_PRIVATE_LIB := $(BOARD_HOSTAPD_PRIVATE_LIB)
BOARD_WPA_SUPPLICANT_PRIVATE_LIB_EVENT := "ON"
WIFI_DRIVER_STATE_CTRL_PARAM := "/dev/wlan"
WIFI_DRIVER_STATE_OFF := "OFF"
WIFI_DRIVER_STATE_ON := "ON"
WIFI_FEATURE_HOSTAPD_11AX := true
WIFI_HIDL_FEATURE_AWARE := true
WIFI_HIDL_FEATURE_DUAL_INTERFACE := true
WIFI_HIDL_UNIFIED_SUPPLICANT_SERVICE_RC_ENTRY := true
WPA_SUPPLICANT_VERSION := VER_0_8_X
