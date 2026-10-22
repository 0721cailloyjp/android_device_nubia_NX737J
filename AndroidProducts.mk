#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

PRODUCT_MAKEFILES := \
    $(LOCAL_DIR)/lineage_NX737J.mk

# The bp4a suffix is the release config name. LineageOS 24.0 / PixelOS
# seventeen use bp4a; if `lunch` rejects it, drop the suffix and use
# lineage_NX737J-userdebug instead (03-build.sh auto-detects).
COMMON_LUNCH_CHOICES := \
    lineage_NX737J-bp4a-user \
    lineage_NX737J-bp4a-userdebug \
    lineage_NX737J-bp4a-eng \
    lineage_NX737J-userdebug
