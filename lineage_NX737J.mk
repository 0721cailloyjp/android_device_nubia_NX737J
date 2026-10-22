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
# 型号用市场名，别用 NX737J 这种开发代号 —— 否则设置里、App 小尾巴都显得怪。
# 真机 EXIF 实测就是 "nubia Z70S Ultra"（ro.vendor.feature.camera_zte_exif_model）。
PRODUCT_MODEL := nubia Z70S Ultra

PRODUCT_GMS_CLIENTID_BASE := android-zte

# ro.product.marketname 不是 build 自动生成的，手动补进 system.prop。
# 其它身份（brand/manufacturer/device）在上面已经是对的，不用覆盖。
