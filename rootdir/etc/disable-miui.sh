#!/system/bin/sh
# disable-miui.sh — 禁用 product 里残留的 MIUI/小米 App
#
# 为什么：我们保留原厂 product，里面 48 个 MIUI App 缺 miui 框架类（在 system_ext，
# 已被 AOSP 替换），点开会 NoClassDefFoundError 崩。禁用它们 = 根本不运行 = 彻底无感。
#
# 由 init.nx737j.rc 在 boot_completed 后调用。pm disable-user 幂等，每次 boot 执行无害。
# 全部是 MIUI 特有 App，类原生都有 AOSP 替代，禁用无副作用。

for p in \
    com.miui.accessibility \
    com.miui.aod \
    com.miui.backup \
    com.miui.carlink \
    com.miui.cit \
    com.miui.cloudbackup \
    com.miui.contentcatcher \
    com.miui.contentextension \
    com.miui.core \
    com.miui.extraphoto \
    com.miui.face \
    com.miui.greenguard \
    com.miui.mediaviewer \
    com.miui.micloudsync \
    com.miui.misound \
    com.miui.miwallpaper \
    com.miui.nextpay \
    com.miui.notification \
    com.miui.passwords \
    com.miui.phrase \
    com.miui.qr \
    com.miui.securitycore \
    com.miui.securityinputmethod \
    com.miui.thirdappassistant \
    com.miui.touchassistant \
    com.miui.uireporter \
    com.miui.voiceassistProxy \
    com.miui.voicetrigger \
    com.miui.wmsvc \
    com.miui.yellowpage \
    com.xiaomi.ab \
    com.xiaomi.aiasst.service \
    com.xiaomi.aireco \
    com.xiaomi.aon \
    com.xiaomi.app.toolbox \
    com.xiaomi.barrage \
    com.xiaomi.bdsms \
    com.xiaomi.cameratools \
    com.xiaomi.continuity.sdkapp \
    com.xiaomi.devauth \
    com.xiaomi.macro \
    com.xiaomi.metoknlp \
    com.xiaomi.misettings \
    com.xiaomi.registration \
    com.xiaomi.security.onetrack \
    com.xiaomi.trustservice \
    com.xiaomi.ugd \
    com.xiaomi.xmsfkeeper; do
    pm disable-user --user 0 "$p" >/dev/null 2>&1
done
