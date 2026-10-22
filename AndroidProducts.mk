#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

PRODUCT_MAKEFILES := \
    $(LOCAL_DIR)/lineage_NX737J.mk

# 只列不带 release-config 的形式。
# 原因：release config 名随 Android 版本变化（A15=ap3a、A16=bp4a、A17=cp2a…），
# 硬编码写错会让 lunch 菜单失效。`breakfast NX737J userdebug` 会自动从
# PRODUCT_MAKEFILES 推导产品名并选对 release config，不依赖这里的列表。
#
# 03-build.sh 走 breakfast 优先，这条列表只作兜底。
COMMON_LUNCH_CHOICES := \
    lineage_NX737J-userdebug \
    lineage_NX737J-user \
    lineage_NX737J-eng
