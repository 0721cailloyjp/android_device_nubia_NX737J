#!/system/bin/sh
# disable-miui.sh — 禁用 product 里残留的 MIUI/小米 App
#
# 为什么：我们保留原厂 product，里面 52 个 MIUI App 缺 miui 框架类（在 system_ext，
# 已被 AOSP 替换），点开会 NoClassDefFoundError 崩。禁用它们 = 根本不运行 = 彻底无感。
#
# 由 init.nx737j.rc 在 boot_completed 后调用。pm disable-user 幂等，每次 boot 执行无害。
# 全部是 MIUI 特有 App，类原生都有 AOSP 替代，禁用无副作用。
#
# 注意 4 个包名不带 miui/xiaomi 前缀、之前按前缀筛漏了，这里补齐：
#   miui.systemui.plugin   = /product/app/MIUISystemUIPlugin（MIUI 系统UI插件）
#   com.miuix.editor       = /product/app/MiuixEditor（MIUI X 编辑器）
#   com.android.camera     = /product/priv-app/MiuiCamera（小米相机，非 AOSP 相机，
#                            类原生相机是 com.android.camera2/Aperture，不撞）
#   com.newcall            = /product/priv-app/NewCall（小米新通话 VoNR）

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
    com.xiaomi.xmsfkeeper \
    miui.systemui.plugin \
    com.miuix.editor \
    com.newcall \
    com.android.camera; do
    pm disable-user --user 0 "$p" >/dev/null 2>&1
done
