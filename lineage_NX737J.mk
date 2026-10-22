#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

# Inherit from those products. Most specific first.
# 用 core_64_bit（而非 core_64_bit_only）→ 编出 32 位 bionic/ART/linker/zygote32，
# ro.product.cpu.abilist 会带上 armeabi-v7a,armeabi，32 位 App 能装上。
#
# ⚠️ 关于 32 位 App 能否真正运行（2026-10-23 更正）：
#   骁龙 8 Elite（SM8750，Oryon）是纯 64 位，没有 32 位执行单元。移植包能跑 32 位 App，
#   是因为它沿用 HyperOS，里面集成了小米的 "Tango" 转译层（Amanieu Systems 的
#   32→64 位二进制翻译器），把 32 位指令实时翻译成 64 位跑。
#   Tango 是深度集成在 HyperOS 的 linker / app_process 里的，不是可独立搬运的 so。
#   我们换成 AOSP 后这层就没了：32 位 App 能装（abilist 有 armeabi-v7a），
#   但纯 32 位 App 启动会崩（SIGILL）。绝大部分 App 早就有 64 位版，影响面很小。
#   若真有某个 32 位 App 是刚需，报名字，我找 64 位版/替代，或评估单独移植 Tango。
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
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
