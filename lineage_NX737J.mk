#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

# Inherit from those products. Most specific first.
#
# ⚠️ 用 core_64_bit_only（纯 64 位），**不是** core_64_bit。实测依据（2026-10-23 真机）：
#   移植包顶层 ro.product.cpu.abilist = arm64-v8a（只有 64 位），虽然它的 /system/lib
#   有 801 个 32 位库 + 213 个 .so.tango（Tango 转译缓存）+ app_process32，但真正让
#   32 位 App 跑起来的是 HyperOS 集成的 Tango 转译器（Amanieu Systems，闭源 + 深度集成），
#   AOSP 搬不过来。切 core_64_bit 只会让我们的 abilist 带上 armeabi-v7a，
#   32 位 App 能装但没 Tango 跑不了（闪退），还让 system.img 变大、可能超 1.033 GiB 槽位。
#   所以和移植包顶层保持一致：64 位 only。真有刚需 32 位 App，找 64 位版/替代。
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
