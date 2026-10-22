# 自动生成，勿手改 —— 由 scripts/09-pull-nubia-apps.sh 产出
#
# 回注的努比亚 / ZTE 组件。每一项都做过 dex 检查，确认不依赖 miui/xiaomi 框架类。
#
# 为什么要回注：我们把 /system 和 /system_ext 换成 AOSP，这两个分区里的
# 厂商 App 会一起消失。账号、钱包这类东西是跟努比亚账号体系绑的，
# AOSP 补不出来，只能原样搬回去。
#
# 为什么放在同一分区：privapp-permissions XML 是按分区的 etc/permissions 扫描的。
# 把 priv-app 的 App 挪到别处会让它的特权权限失配，开机后 Signature|privileged 报错。

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/prebuilts/nubia-apps/NBAccount.apk:$(TARGET_COPY_OUT_SYSTEM)/app/NBAccount/NBAccount.apk

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/prebuilts/nubia-apps/NBUserCenter.apk:$(TARGET_COPY_OUT_SYSTEM)/app/NBUserCenter/NBUserCenter.apk

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/prebuilts/nubia-apps/zteaccount_mfv.apk:$(TARGET_COPY_OUT_SYSTEM)/app/zteaccount_mfv/zteaccount_mfv.apk

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/prebuilts/nubia-apps/Wallet.apk:$(TARGET_COPY_OUT_SYSTEM)/priv-app/Wallet/Wallet.apk

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/prebuilts/nubia-apps/WalletCore.apk:$(TARGET_COPY_OUT_SYSTEM)/priv-app/WalletCore/WalletCore.apk

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/prebuilts/nubia-apps/vendor.zte.hardware.camera.transferclient.jar:$(TARGET_COPY_OUT_SYSTEM_EXT)/framework/vendor.zte.hardware.camera.transferclient.jar

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/prebuilts/nubia-apps/privapp_permissions_whitelist_com.zte.wallet.xml:$(TARGET_COPY_OUT_SYSTEM)/etc/permissions/privapp_permissions_whitelist_com.zte.wallet.xml

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/prebuilts/nubia-apps/vendor.zte.hardware.camera.transferclient.xml:$(TARGET_COPY_OUT_SYSTEM_EXT)/etc/permissions/vendor.zte.hardware.camera.transferclient.xml

