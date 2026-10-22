#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

# Inherit from those products. Most specific first.
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit_only.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)

# Inherit from NX737J device
$(call inherit-product, device/nubia/NX737J/device.mk)

# Inherit common Lineage stuff.
# PixelOS / AviumUI both ship android_vendor_lineage, so this path resolves
# on all three ROMs.
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)

PRODUCT_NAME := lineage_NX737J
PRODUCT_DEVICE := NX737J
PRODUCT_MANUFACTURER := nubia
PRODUCT_BRAND := nubia
PRODUCT_MODEL := NX737J

PRODUCT_GMS_CLIENTID_BASE := android-zte

# Stock identity overrides intentionally OMITTED for the bootstrap build.
# NX789J sets BuildFingerprint/BuildDesc to match its stock RedMagicOS vendor.
# We do not know NX737J's stock fingerprint yet, and a wrong one is worse than
# none — AOSP then generates its own. Add these once you have read
# `adb shell getprop ro.build.fingerprint` on the stock/HyperOS build.
#
# PRODUCT_BUILD_PROP_OVERRIDES += \
#     BuildDesc="NX737J-user ..." \
#     BuildFingerprint=nubia/NX737J/NX737J:15/.../...:user/release-keys" \
#     DeviceName=NX737J \
#     DeviceProduct=NX737J \
#     SystemDevice=NX737J \
#     SystemName=NX737J
