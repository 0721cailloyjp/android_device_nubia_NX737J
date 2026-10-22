# 明日操作单（省钱版 · 两阶段变配）

> **预算硬约束 ¥25（已充值）。** 目标：第一版能开机，且不超预算。
> 时间不值钱（周末），所以用两次变配换 ¥6 的节省。

---

## 0. 设备身份：确认是 Z70S Ultra（2026-10-22 实测留档）

`ro.product.brand/model/device` 读出来是 `Xiaomi / 2410DPN6CC / haotian`，
**这不代表硬件是小米** —— 这是**移植包作者刻意把设备标识改成小米 15 Pro** 的结果。

移植包的底子是小米 15 Pro（代号 `haotian`）的 HyperOS，作者在打包时把这些身份属性
保持/设成了 `haotian` / `2410DPN6CC` / `Xiaomi`。所以**这台机器的"设备标识名"不是 Z70S，
是作者改的** —— 硬件是 Z70S Ultra，标识是小米 15 Pro，两码事。

> 归因修正记录：这个问题我错过两次。
> 第一次以为"移植包保留源 ROM 身份"（说法含糊），
> 第二次听用户说"改了设备名叫 mix7"就误判成机型伪装模块在改 `ro.product.*`（错）。
> 现在按用户确认的事实写：**标识属性是移植包作者改的；用户改的只是"设备名"这个显示名。**

真正的证据在硬件层：

| 属性 | 值 | 说明 |
|---|---|---|
| `ro.vendor.feature.zte_feature_nfcname` | **`NX737J`** | 直接就是我们的机型号 |
| `ro.vendor.feature.camera_zte_exif_model` | **`nubia Z70S Ultra`** | 相机 EXIF 里写的就是这个 |
| `ro.vendor.feature.nubia.exif.module` | `NUBIA_Z70S_ULTRA` | 同上 |
| `ro.vendor.feature.camera_series_info` | `NubiaPQ84A02` | PQ84A02 = Z70S Ultra 内部代号 |
| `ro.vendor.feature.zte_strategy_control_str` | `PQ84A02_W` | 同上 |
| `ro.vendor.feature.zte_feature_nfcmodle` | `Z70SU` | 同上 |
| `ro.vendor.feature.baseline_name` | `NebulaOS2.0` | 努比亚 MyOS 的基线名 |
| `ro.vendor.feature.zte_usb_iso` | `NUBIA` | USB 厂商标识 |
| `ro.bootimage.build.fingerprint` | `nubia/CN_PQ84A02/PQ84A02:15/...` | bootimage 是努比亚的 |
| `ro.product.system_dlkm.brand` | `nubia` | |
| `ro.product.vendor_dlkm.brand` | `nubia` | |

### 各分区的真实归属（这个很重要，别搞错）

| 分区 | 归属 | 内容特征 |
|---|---|---|
| boot / bootloader / kernel | **努比亚 Z70S** | `nubia/CN_PQ84A02`，A15 基线 |
| **vendor** | **ZTE 的** | 200+ 个 `vendor.zte.*` HAL；`libNubiaImageAlgorithmVD.so`、`libztednn.so`、`libztellm.so`；`/vendor/lib64/camera/com.zte.eeprom.*_qvburdock.so` 等 ZTE EEPROM HAL |
| odm | 小米的（薄分区） | 只有 bin/etc/lib64，**无任何 zte 内容** |
| system / system_ext / product | 小米 HyperOS | 见 2.5 / 2.5.1 |
| system_dlkm / vendor_dlkm | 努比亚 | `ro.product.*_dlkm.brand = nubia` |

**结论：努比亚的"特性"绝大部分活在 `/vendor` 里**（相机算法、指纹 ifaa、激光对焦、
AI 模型、充电、触控、显示、NFC、电话特性），而我们的方案原样保留 vendor
→ 这就是 system-side hybrid 架构最大的价值。

`/vendor/lib64` 里能直接看到的 ZTE 组件（部分）：

```
libNubiaImageAlgorithmVD.so              努比亚图像算法（视频人像）
libztebert.so / libztebge.so / libztellm.so / libztevitllm.so   ZTE 端侧大模型
libztednn.so / libztesensevoice.so       推理引擎 / 语音
vendor.zte.aimodel-V1-ndk.so             AI 模型服务（就是 App 里 com.zte.aimodel 的 HAL 端）
vendor.zte.fingerprint.ifaaaidl-V1-ndk_platform.so   指纹 ifaa
vendor.zte.fingerprint.ztecmdaidl-V1-ndk.so          指纹命令通道（init.svc.ztecmdaidl）
vendor.zte.hardware.camera.transfer-V1-ndk.so        相机流转
vendor.zte.hardware.laser2-V1-ndk_platform.so        激光对焦
vendor.zte.ldd.cmd-V2-ndk.so / vendor.zte.modem-V1-ndk.so / vendor.zte.radio-V1-ndk.so
vendor.zte.nook.modem-V2-ndk.so / vendor.zte.subsys-V1-ndk.so
```

**注意一个容易误解的点**：App dex 里"缺"的 `com.zte.aimodel.*` 是 **HAL 的 Java 侧封装**，
真身是 `/vendor/lib64/vendor.zte.aimodel-V1-ndk.so`。vendor 里没有对应的 `-java.jar`，
所以 Java 层那几个类确实没人提供 —— 这与现有移植包的状态一致，不是我们引入的问题。

### 两件容易混的事：型号属性 vs 设备显示名

| | 是什么 | 现在从哪来 | 刷完我们的包之后 |
|---|---|---|---|
| **型号属性** | `ro.product.model=2410DPN6CC`、`ro.product.device=haotian`、`ro.product.brand=Xiaomi` | **移植包自带的**（system/product 就是小米 15 Pro 的 HyperOS） | **变成 `nubia Z70S Ultra` / `nubia`** —— 由我们的 `lineage_NX737J.mk` 定义 |
| **设备显示名** | 设置里那个"设备名称"，用户可见；应用小尾巴也读它 | **用户自己在设置里改成 `mix7`**，存在 `persist.cc.device.name` | **清 data 后回到默认**，在设置里重改一次即可 |

所以：**"应用小尾巴显示小米15Pro" 不是伪装，是移植包 build.prop 里的型号本来就是那个。**
刷完之后小尾巴会自然变成 **`nubia Z70S Ultra`**（`ro.product.model` 直接设成了市场名，
`ro.product.marketname` 也一起设了），不需要任何额外处理。

> 为什么 model 不用 `NX737J`：NX737J 是开发代号，设置里和 App 小尾巴显示它会显得怪。
> 真机 EXIF 实测市场名就是 "nubia Z70S Ultra"（`ro.vendor.feature.camera_zte_exif_model`）。
> 所以 `PRODUCT_MODEL := nubia Z70S Ultra` + `ro.product.marketname=nubia Z70S Ultra`。

---

## 0.1 今晚就能做的（不花钱）

```bash
cd F:\2026-10-18-14-35-15\nx737j-pixelos\device-nubia-NX737J
git init && git add -A && git commit -m "NX737J bootstrap device tree"
# 推到你的 GitHub，然后把 local_manifests/nx737j.xml 的 name 改成你的仓库
```

不推也行 —— `02-sync.sh` 会检测到 `device/nubia/NX737J` 不存在，自动从本地目录 clone。

另外：确认腾讯云余额 ¥25 已到账，按量付费能开 8核16G 和 16核32G。

---

## 1. 阶段 A：低配拉源码

| 项 | 值 |
|---|---|
| 规格 | **8核16G**（¥1.89/h） |
| 镜像 | **Ubuntu 24.04 LTS** 64 位（不要 22.04，见下方说明） |
| 系统盘 | 50G 通用型 SSD |
| **数据盘** | **500G 通用型 SSD** |
| 公网 | 按使用流量，带宽 100M |
| 安全组 | 放行 22 |

> **为什么必须 24.04 而不是 22.04**
>
> 我们的设备树设了 `BOARD_*_FILE_SYSTEM_TYPE := erofs`，build_image.py 会用
> `mkfs.erofs` 生成镜像。它可能带 `-C`（pcluster）或 `--chunksize` 参数，
> **这些需要 erofs-utils ≥ 1.6**。
> Ubuntu 22.04 自带 **1.4**，会在编译最后阶段报 `unknown option -C`，
> 前面的钱白烧。24.04 自带 1.7，直接可用。
>
> `00-prep.sh` 会检查版本并提前告警。

```bash
# 本地
cd F:\2026-10-18-14-35-15
scp -P <端口> -r nx737j-pixelos root@<IP>:/root/

# 服务器
ssh -p <端口> root@<IP>
cd /root/nx737j-pixelos
bash scripts/cost.sh reset          # 记起点
tmux new -s sync
bash scripts/00-prep.sh && bash scripts/02-sync.sh
# Ctrl-b d 退出，SSH 断了也继续

# 看进度
tail -f /data/sync.log
bash scripts/cost.sh                # 随时看花了多少
```

**sync 完成后先跑体检，别急着升配。** `01-preflight.sh` 会在 2 分钟内验 6 组东西：
源码树完整性、设备树与依赖仓库、**lunch 能否解析所有 .mk**、关键变量回读（`get_build_var`）、
工具链版本（尤其 `mkfs.erofs`）、资源余量。

```bash
bash scripts/01-preflight.sh
```

`lunch` 那一步最有价值——它真的会解析全部 .mk，缺文件/写错变量会在几秒内报错，
而不是等你升到 16核32G 编了半小时才炸。

体检不过就按 ✗ 逐项修，别往下走。手动做同样的事：

```bash
for d in build frameworks/base hardware/interfaces prebuilts/clang prebuilts/tools device/nubia/NX737J; do
  [ -d /data/pixelos/$d ] && echo "OK      $d" || echo "MISSING $d"
done
```

有 MISSING 就重跑 sync，别升配。

---

## 2. 阶段 B：升配编译

**控制台操作：**

```
实例 → 关机 → 选「关机不收费」→ 状态变成「已关机」
→ 更多操作 → 调整配置 → 内存/CPU 改成 16核32G → 确认
→ 开机
```

> ⚠️ 关机期间实例费免，**但云硬盘照收**（~¥0.24/h）。别挂太久。

```bash
ssh 进去
cd /root/nx737j-pixelos
bash scripts/cost.sh reset          # 换机器后重置起点

tmux new -s build
bash scripts/01-preflight.sh        # 2 分钟体检，不过就别编
bash scripts/03-build.sh            # 前台跑，日志同时进 /data/build.log
# 中途可按 Ctrl-b 再按 d 退出，编译继续
# 回来： tmux attach -t build
```

**16核32G 上编译约 100~160 分钟。**

**OOM 了就这样增量续编**（不用重新 sync）：

```bash
JOBS=8 bash scripts/03-build.sh
```

脚本会自己判断失败原因：OOM / 缺模块 / 缺 .mk，并给出对应处置。

---

## 2.5 保留原厂 product（默认开启）—— 理由已更正

> ⚠️ **这一节之前写错过，2026-10-22 在真机上重新核对后重写。**
> 旧版本说「相机算法三件套 bokeh / 图像分割 / 视频分割全在 product 里」，
> 那是扫 **Z70S 原厂包** 得到的结论，不适用于 **澎湃4 移植包**。
> 移植包已经把 product 换成了小米的，真机上验证如下。

### 真机实测（当前跑澎湃4 移植包的 Z70S）

| 检查项 | 结果 |
|---|---|
| `/product` 包数量 | 152 个，全是小米的（`GmsCore`、`MIUIBrowser`、`MIUIAod`、`MISettings` …） |
| `/product/lib64` 里 zte/nubia 库 | **0 个**（共 46 个文件，无一是 zte） |
| `/product/etc/permissions` 里 zte/nubia | **0 个** |
| 全机 `com.zte.*` / `cn.nubia.*` 包 | 只有 5 个，**都在 /system 或 /system_ext**（已回注，见 2.5.1） |

结论：**product 里没有努比亚的东西**，之前那个理由不成立。

### 但仍然要保留 product，真正的理由是这三个

| 理由 | 具体内容 | 丢了会怎样 |
|---|---|---|
| **① IMS / VoLTE / eSIM 的 Java 层** | `/product/etc/permissions/` 里 30 个 XML，含 `qti_telephony_hidl_wrapper_prd.xml`、`qti_telephony_utils_prd.xml`、`vendor.qti.hardware.data.connection*.xml`、`telephony_product_privapp-permissions-qti.xml`、`lpa.xml`、`UimGba*.xml` | AOSP 的 product 没有这些。能打电话，但 **VoLTE / 5G 通话 / eSIM 大概率废** |
| **② VINTF 片段** | `/product/etc/vintf/compatibility_matrix.xml` + `/product/etc/vintf/manifest/` + `touch_framework_compatibility_matrix.xml` | 框架兼容性矩阵少一块，VINTF 组合结果与现在不同，风险不可控 |
| **③ 设备配置 RRO** | `/product/overlay/` 71 个，含 `GestureLineOverlay`、`NavigationBarModeGestural`、`DevicesAndroidOverlay` 等 | 导航栏 / 手势条 / 显示参数可能不对 |

**顺带省钱**：product 有 4.2 GB，不编 = 不传 = 不下，对 ¥25 预算是实打实的节省。

### 保留它的代价（已知、可接受）

product 里那堆 MIUI App 在 AOSP 框架下会崩（缺 `miui.*` 类）。
它们的特权权限请求靠 `system.prop` 里这行降级，**不会阻塞开机**：

```properties
ro.control_privapp_permissions=log
```

桌面不受影响：`com.miui.home` 装在 **/data/app**（用户安装的），清 data 后自然消失，
开机后是 AOSP 的 Launcher3 接管。

### 开关

| 开关 | 行为 |
|---|---|
| `KEEP_STOCK_PRODUCT=1`（**默认**） | 只编 `system.img` + `system_ext.img`，product 保持原样 |
| `KEEP_STOCK_PRODUCT=0` | 三个都编（完全净化时用，会丢上面 ①②③） |

三个脚本都认这个开关：`03-build.sh` / `04-pack.sh` / `assemble-super.sh`。

```bash
# 默认就是保留
bash scripts/03-build.sh

# 想全替换（v2 再考虑）
KEEP_STOCK_PRODUCT=0 bash scripts/03-build.sh
```

---

### 2.5.1 system / system_ext 侧的努比亚组件（会丢，已回注）

换掉这两个分区会丢掉厂商 App。**注意：不能靠目录名猜**——手机当前跑的是澎湃4 移植包，
它的 `/system`、`/system_ext` 本身就是小米的，里面混着一批「长得像努比亚、其实是小米」的东西。

所以清单是**逐个解析 dex 交叉验证**出来的（`scripts/apk-dep-scan.py`，
读 type_ids − class_defs 得出真实外部依赖，不是字符串搜索）：

**保留（dex 里没有任何 miui/xiaomi 外部依赖）**

| APK | 包名 | 自包含类数 | 用途 |
|---|---|---|---|
| `NBAccount.apk` | `cn.nubia.accounts` | 751 + 82 | 努比亚账号 |
| `NBUserCenter.apk` | `cn.nubia.usercenter` | 787 + 74 | 用户中心 |
| `zteaccount_mfv.apk` | `org.zx.AuthComp` | 687 + 509 + 65 | 统一认证（登录依赖它） |
| `Wallet.apk` | `com.zte.wallet` | 1512 + 41 | ZTE 钱包（priv-app） |
| `WalletCore.apk` | `com.zte.wallet.core` | 11 | 钱包核心（priv-app） |
| **`cc.apk`** | **`com.cc.setting`** | **1561（全自包含）** | **★ 移植者的「高级设置」**，见下 |
| `vendor.zte.hardware.camera.transferclient.jar` | — | — | 相机流转的 Java 层 API |
| `com.st.android.nfc_extensions.jar` | — | — | ST54L 的 NFC 扩展 API（130 KB） |
| `com.st.android.nfc_extensions_16.jar` | — | — | 同上，16 版（195 KB） |

> **为什么要带 ST 的两个库**：这台机器的 NFC 芯片是意法半导体 **ST54L**
> （实测 `ro.vendor.feature.board_uses_nfc = ST54L`），而且 ZTE 钱包的 dex 里有
> 4 处 `Lcom/st/...` 引用——说明刷卡（eSE）走的就是这套扩展 API。
> AOSP 的 `NfcNci` 只能做基础 NFC 读写，门禁卡 / 公交卡这类必须靠这两个库。
> 325 KB，纯 Java 库、不占包名、不会和 AOSP 撞车。
> 对应还有 `com.st.android.nfc_extensions{, _16}.xml` 两个 `<library>` 声明，必须一起带。

### ★ `com.cc.setting`（`/system/app/cc/cc.apk`）—— 移植者的「高级设置」

这是移植包作者自己写的努比亚功能开关，**不是系统设置的一部分**，
所以之前按「努比亚包名」扫是扫不到的（包名 `com.cc.setting`，和 `com.cc.romfix.cameracompat` 同一个作者命名空间）。

实测规格：v2.0 / versionCode 3 / minSdk 26 / **targetSdk 29**，
只申请普通权限（`INTERNET`、`VIBRATE`、`ACCESS_WIFI_STATE`、存储读），
**没有任何 priv-app 特权权限** → 放 `/system/app` 零风险。
dex **完全自包含**（1561 个类，零 `miui`/`xiaomi`/`zte` 外部依赖）→ 搬到 AOSP 照样能跑。

它靠 `su` 提权直接写 sysfs，控制这些硬件开关：

| 功能 | sysfs 节点 |
|---|---|
| 风扇转速 | `/sys/kernel/fan/fan_enable`、`fan_speed_level` |
| 充电分离 / 旁路充电 | `/sys/kernel/nubia_charge/charger_bypass`、`/sys/class/qcom-battery/charge_mode` |
| 电池充电开关 | `/sys/class/qcom-battery/battery_charging_enabled`、`wireless_boost_en` |
| RGB 灯效 | `/sys/class/leds/aw22xxx_led/cfg`、`effect` |
| SAR 天线功率 | `/sys/class/leds/sar0/mode_operation`、`sar1/mode_operation` |
| CPU 频率 | `/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq` |
| 设备显示名 | `persist.cc.device.name` ← 设置里那个"设备名称"（用户改成 mix7 的） |
| 显示相机型号 | 读 `ro.vendor.feature.camera_zte_exif_model` |

> ⚠️ **它写 sysfs 需要 root。** 刷完我们的包之后，如果没装 KernelSU 管理器并授权，
> 这个 App 界面能打开，但开关点了不生效。
> 换句话说：**「高级设置」能不能用，取决于你刷完后还 root 不 root。**

> `WalletSupport.apk`（`com.zte.wallet.support`，47 MB）**故意不带**：
> 缺 6 个 `com.zte.aimodel.*` / `com.zte.ctsutils.CtsUtils` / `com.zte.feature.Feature`，
> 核心 AI 能力在 AOSP 上跑不起来；而且 47 MB 单个 blob 过不了 GitHub Git Data API
> （实测 `HTTP 422 input was too large to process`，JSON base64 的实际上限 40~50 MB）。
> 要加就等真正需要时走 Release 资产（单文件 2 GB）。

**剔除（并写明为什么）**

| 文件 | 真实身份 | 剔除原因 |
|---|---|---|
| `Nfc_st.apk` | `com.android.nfc` | 是 AOSP NFC 应用的小米定制版，引用 `Lcom/xiaomi/nfc/IMiNfcAdapter`、`Lmiui/os/HyperOSCustFeatureResolve`；而且包名和 AOSP 的 `NfcNci` **完全一样**，带上去就是撞包 |
| `CameraMind.apk` | `com.xiaomi.cameramind` | 小米「相机大脑」，1296 处自有类 + 24 处 `Lmiui/app/MiuiFreeFormManager`，是随 HyperOS 带来的，跟努比亚无关 |
| `CameraExtensionsProxy.apk` | `com.android.cameraextensions` | 与 AOSP 同名包冲突的风险大于收益，v1 不带 |
| `RomFixCameraCompat.apk` | `com.cc.romfix.cameracompat` | 移植者自己加的相机兼容补丁，跟我们的构建无关 |

**已知缺失的类（不影响开机，且与现在的移植包状态一致）**

| APK | 缺什么 |
|---|---|
| `Wallet` | `com.zte.feature.Feature` |
| `zteaccount_mfv` | `com.zte.aimodel.*`（4 个） |

这几个类在你**现在的澎湃4 移植包里同样不存在**（我们扫过 `/system`、`/system_ext`，
除 transferclient 外没有任何 zte 的 jar）。也就是说这几个 App 今天是同样的残缺状态，
搬过去不会产生新的退化——只是"维持现状"，不是"变差"。

**两条路拿 APK，任选其一：**

```bash
# 【快】直接从手机拉（约 107 MB，本地跑，已实测通过）
bash scripts/09-pull-nubia-apps.sh --list   # 先看找到什么
bash scripts/09-pull-nubia-apps.sh          # 再拉

# 【慢】从 super.img 解包（16 GB，服务器上跑）
bash scripts/08-extract-nubia-apps.sh /path/to/super.img
```

两个脚本都会产出：
- `device/nubia/NX737J/prebuilts/nubia-apps/`（APK + jar + privapp-permissions XML）
- `device/nubia/NX737J/nubia-apps.mk`（PRODUCT_COPY_FILES 规则）

`device.mk` 末尾已经写好了：

```make
-include $(LOCAL_PATH)/nubia-apps.mk
```

**带减号的 `-include`：文件不存在就静默跳过，不会编译失败。**
所以只要产物在就自动带上；没有就编纯 AOSP。不需要手动改 device.mk。

**流程**：跑完提取 → `python scripts/gh-push.py` 推 GitHub → 云端 sync 时自动拉到。

⚠️ 两个配套的权限文件必须一起回注，缺一个就会静默失效：

1. `privapp_permissions_whitelist_com.zte.wallet.xml` → `/system/etc/permissions/`
   钱包是 priv-app，用户构建 default `enforce` 时，请求了 `Signature|privileged` 权限却没在
   白名单里，**PackageManager 扫描阶段直接抛异常，开不了机**。
   白名单只覆盖 `com.zte.wallet` 和 `.core`，没覆盖 `.support` ——
   所以 `system.prop` 里加了 `ro.control_privapp_permissions=log` 兜底，开机确认后再删。

2. `vendor.zte.hardware.camera.transferclient.xml` → `/system_ext/etc/permissions/`
   它用 `<library file="...">` 指向同目录的那个 jar。少一个，声明就指向空文件，
   PackageManager 报 "Could not find library"，用到它的 App 直接崩。

⚠️ 如果某个 App 闪退，logcat 搜 `NoClassDefFoundError` / `NoSuchMethodError`，
对照上面「已知缺失的类」那张表——已经在表里的就是移植包也补不了的东西，
把 `nubia-apps.mk` 里对应的 PRODUCT_COPY_FILES 行删掉即可，不影响其他 App、也不影响开机。

---

### 2.6 A17 system 配 A15 vendor：为什么能成立，以及我们绝不能搞丢的一条属性

这是整个方案成立的前提，值得单独讲清楚。

**先说结论**：这套组合不是我们硬凑的，是小米官方出货状态。MIX 7 实机同时满足

```
ro.build.fingerprint     = ... :17/CP2A.260605.016/...     ← system 是 A17
ro.odm.build.fingerprint = ... :15/AQ3A.250226.002/...     ← odm/vendor 是 A15
ro.board.api_level       = 202404
ro.vndk.version          = （空）
ro.product.first_api_level = 35
```

**`ro.vndk.version` 是空的，这一点很关键。** 说明这台机器根本不走 VNDK 机制，
vendor 是靠 LLNDK 的稳定 ABI + vendor snapshot 跟 system 对接的。
正因为不锁 VNDK 版本，A17 的 system 才能配 A15 的 vendor —— 否则
vendor 会要求 `com.android.vndk.v35`，而 A17 只提供 v37，直接就起不来。

所以我们的设备树**不能设** `BOARD_VNDK_VERSION`（设了就会往 build.prop 里写
`ro.vndk.version`，等于把 VNDK 机制重新打开）。目前树里没设，保持原样。

**必须显式保住的是 `ro.board.api_level`。** 开机时 system_server 会做 VINTF 检查：

```
厂商 manifest 的 target-level  <=  ro.board.api_level
```

`ro.board.api_level` 缺失时的回退顺序是 `ro.vndk.version` → `ro.build.version.sdk`。
这台机器前两个都拿不到，于是一路退到 sdk=37，去和厂商 manifest 的 `202404` 比 ——
202404 > 37，**判为不兼容，直接起不来**。

我们只编 system 不编 vendor，所以这条已经显式写进 `system.prop`：

```properties
ro.board.api_level=202404
ro.board.first_api_level=202404
```

值与原厂完全一致，不改变任何行为，只是补上兜底。

**编译完会自动校验**（`scripts/03-build.sh` 末尾会调 `10-verify-out.sh`）：

| 检查项 | 判据 |
|---|---|
| `ro.board.api_level` | 必须 = 202404，缺失直接 FAIL |
| `ro.vndk.version` | 必须为空，有值只给警告 |
| `ro.product.first_api_level` | 必须 = 35 |
| 努比亚组件 | 9 个文件逐个检查是否真的进了镜像 |
| `<library>` 指向 | XML 里 `file=` 指的 jar 必须真实存在 |
| 不该出现的东西 | `Nfc_st` / `CameraMind` / miui jar 出现就报警 |
| 镜像大小 | 三个 img 是否超出各自的 super 槽位 |
| 文件系统 | 魔数是否为 erofs（`e2e1f5e0`） |

自检有 FAIL 时 `03-build.sh` 会以退出码 9 停下，不往下进打包 —— 避免带着病刷机。

---

## 3. 阶段 C：降配打包下载

**控制台：关机（不收费）→ 调整配置 → 8核16G → 开机**

```bash
bash scripts/04-pack.sh
bash scripts/cost.sh                # 最后确认花了多少

# 本地
scp -P <端口> root@<IP>:/data/nx737j-img.tar.zst .
scp -P <端口> root@<IP>:/data/nx737j-img.tar.zst.sha256 .
tar -I zstd -xf nx737j-img.tar.zst
```

---

## 4. 验证 → 销毁 → 清本地（顺序不能乱）

### 4.1 先验证产物（在云机上，销毁之前）

```bash
bash scripts/04-pack.sh
```

它现在会做三级校验：

| 检查 | 不过说明什么 |
|---|---|
| 文件存在 + 大小 | 编译没产出 |
| **EROFS 魔数**（offset 1024 应是 `e2e1f5e0`） | `BOARD_*_FILE_SYSTEM_TYPE` 没设成 erofs，出了 ext4 镜像 |
| **`fsck.erofs` 全文校验** | 镜像内部损坏，编译中途出过错 |

**任何一项不过就别销毁云机**——重编一次 ¥9.4，比重跑两分钟验证贵得多。

### 4.2 下载 + 本地复核

```bash
# 本地
scp -P <端口> root@<IP>:/data/nx737j-img.tar.zst .
scp -P <端口> root@<IP>:/data/nx737j-img.tar.zst.sha256 .
sha256sum -c nx737j-img.tar.zst.sha256     # Git Bash 可用
tar -I zstd -xf nx737j-img.tar.zst
```

### 4.3 销毁云资源

```bash
bash scripts/05-teardown.sh     # 打印 6 步清单
```

按清单在控制台做：**销毁实例（勾选销毁云硬盘）→ 检查 CBS 有无待挂载盘 → 释放独立 EIP → 删快照 → 核对账单**

> 只关机 ≠ 停止计费。云硬盘一定继续收。

### 4.4 最后清本地

```bash
bash scripts/06-cleanup-local.sh
```

它会检查两个前置条件，**都满足才告诉你哪些能删**：

| 条件 | 不满足的后果 |
|---|---|
| 设备树已推到 GitHub（remote 可达） | 本地这份是唯一副本，删了明天没东西可编 |
| 产物已下载且 sha256 通过 | 云端已销毁，产物没了 = 白花钱 |

**可以删**：`nx737j-pixelos/` 整个目录（`prebuilts/Image` 38 MB 也能一条 `dd` 重现）
**保留**：`.workbuddy/memory/` 里的项目记忆

> ⚠️ 唯一不可重现的是 `scripts/` 那几个脚本。要么随设备树一起推 GitHub，要么单独留一份。

---

## 4.5 红魔10 移植包交叉验证结论（2026-10-22 实测量化）

拿 `E://NX789J_HyperOS_4.0.0.10_A17_10.12`（红魔10，同 SM8750）与 NX737J 的包逐项比对：

| 项目 | 结果 |
|---|---|
| **内核 Image** | **sha256 完全相同** `96e5b2e4…`<br>两边都是 `6.6.143-android15-8-zte-1006-4k`、38729088 B、`image_size 0x2350000`、`flags 0xa` |
| **rawprogram / patch XML** | **12 个文件字节级完全相同** → GPT 布局 100% 一致 |
| **super 内 system/system_ext/product/odm** | 起始与大小**完全一致** |
| **extent 单位** | 两边都是 **512 B**（不是 geometry 写的 4096） |
| **Slot B** | 两边都全空（无 A/B 回退） |
| **唯一差异** | `vendor` 2.558 vs 2.694 GiB、`vendor_dlkm`、`system_dlkm` —— 硬件不同 |
| **boot.img** | 内核段相同，首个差异 `0x24f101b`（正好在内核结束 `0x24f0580` 之后），差的是 AVB vbmeta payload |

**三条实证结论：**

1. 两台是**同一套 ZTE 固件模板**，不是"相似"，是字节级一致
2. **内核跨机型通用** —— ZTE 用同一个构建给两台用，这解释了"同内核能编类原生"
3. `BOARD_BOOTIMAGE_PARTITION_SIZE` 等分区大小可放心复用

反过来说，这也证明了 `assemble-super.sh` **必须运行时读偏移**：`vendor` 大小两台不同，
任何硬编码换台机器就错位 —— 正是第三轮修掉的那个 bug。

---

## 5. 费用账（¥25 硬顶）

| 项目 | 单价 | 时长 | 费用 |
|---|---|---|---|
| 8核16G（sync） | ¥1.89/h | 1.5h | ¥2.8 |
| 16核32G（编译） | ¥3.77/h | 2.5h | ¥9.4 |
| 8核16G（下载） | ¥1.89/h | 0.3h | ¥0.6 |
| 500G 通用型 SSD | ¥0.24/h | 4.3h | ¥1.0 |
| 公网出流量 | ¥0.8/GB | 3GB | ¥2.4 |
| **合计** | | | **¥16.2** |

| 意外情况 | 额外费用 | 累计 |
|---|---|---|
| 编译拖到 4.5h | +¥7.5 | ¥23.7 ✅ |
| sync 拖到 3h | +¥2.8 | ¥19.0 ✅ |
| 编译超时重跑一次（+2.5h） | +¥9.4 | ¥25.6 ❌ |

**结论：单次线性流程安全，重复编译会超。所以第一次编译的报错必须贴给我，别自己盲改重跑。**

**止损点**：任何时刻 `bash scripts/cost.sh` 显示余量 < ¥5，立刻 `04-pack.sh` 收尾（哪怕只编出一部分），然后销毁。

---

## 6. 刷回前先量尺寸

> ⚠️ **刷机前必须清 data，这条不是可选项。**
>
> 换掉 system / system_ext 之后，`/data` 里还留着旧系统的 dex 缓存、ART 镜像、
> 以及一批「包名还在但签名全变了」的记录。不清 data 的典型表现是
> 黑屏、反复重启、或卡在开机动画——看起来像"编译失败"，其实是数据层不兼容。
>
> 而且你的机器上 **`com.miui.home`（小米桌面）是装在 `/data/app` 的用户应用**，
> 不清 data 的话它会继续被当默认桌面，在 AOSP 框架下必然崩 → 开机后就是黑屏。
>
> 清 data 顺带把它一起清掉，开机后是 AOSP 的 Launcher3。
>
> 所以：**第一次刷一定 `fastboot -w`（或恢复出厂）**，别抱侥幸。

| 槽位 | 上限 |
|---|---|
| `system_a` | 1,109,176,320 B (1.033 GiB) |
| `system_ext_a` | 885,358,592 B (0.825 GiB) |
| `product_a` | 4,215,025,664 B (3.926 GiB) |

AOSP 的 system.img 通常 1.5~2.5 GB，**大概率超 1.033 GiB**。超了：

```bash
bash scripts/assemble-super.sh <产物目录> <原super.img> <新super.img>
```

脚本自动检测溢出并给出 lpmake 命令。空闲 7.39 GiB + Slot B 全空，有空间重组。

> 已做缓解：BoardConfig 加了 `WITH_DEXPREOPT_BOOT_IMG_AND_SYSTEM_SERVER_ONLY := true`，
> system.img 会明显缩小，很可能直接塞进 1.033 GiB（in-place 最稳，不需要 lpmake）。

---

### 6.1 周六实际刷机步骤（照着做）

> 前置：救砖包已核对完整 —— `E:\NX737J_HyperOS_4.0.0.10_A17_10.12\`，
> 60 个文件 17 GB，`FlashTool\res\firehose.elf`(1.66 MB) + rawprogram0~5.xml 齐全。
> 刷挂随时能用 `一键刷机.bat` 回原厂。

**第 0 步：把产物和原厂文件摆到一起**

```bash
# 本地，假设产物已解压到 F:\nx737j-img\，原厂包在 E 盘
cp -r F:\nx737j-img F:\fl
cp "E:\NX737J_HyperOS_4.0.0.10_A17_10.12\Firmware\super.img" F:\fl\
cp "E:\NX737J_HyperOS_4.0.0.10_A17_10.12\Firmware\vbmeta.img"        F:\fl\
cp "E:\NX737J_HyperOS_4.0.0.10_A17_10.12\Firmware\vbmeta_system.img" F:\fl\
```

**第 1 步：合成新 super（在本地跑，不用云）**

```bash
cd F:\2026-10-18-14-35-15\nx737j-pixelos
bash scripts/assemble-super.sh F:\fl F:\fl\super.img F:\fl\nx737j-super.img
```

- 只要 system.img ≤ 1.033 GiB 就走 **in-place 原地覆盖**（十几秒，最稳）
- 超了会打印现成的 lpmake 命令；真走到那一步再单独处理

**第 2 步：关 AVB 校验（两个 vbmeta 都要）**

```bash
python scripts/patch-vbmeta.py --flags 3 --out-dir F:\fl F:\fl\vbmeta.img F:\fl\vbmeta_system.img
# 产出 vbmeta_patched.img / vbmeta_system_patched.img，flags 都应是 0x03
```

flags=3 = 关闭 verity + 关闭 verification。**不改这一步，刷进去就是"Your device is corrupt"红字。**

**第 3 步：进 bootloader 刷**

```bash
adb reboot bootloader
fastboot getvar current-slot      # 记下来，确认设备当前在哪个槽

fastboot flash vbmeta        F:\fl\vbmeta_patched.img
fastboot flash vbmeta_system F:\fl\vbmeta_system_patched.img
fastboot flash super         F:\fl\nx737j-super.img    # 16 GiB，USB3 约 2~5 分钟
fastboot --set-active=a
fastboot -w                     # 清 data，必须做（见本节开头）
fastboot reboot
```

> 如果 `fastboot flash super` 报 `unknown partition` 或拒绝：
> 走 EDL 回原厂再重来，或者用 fastbootd（`adb reboot fastboot` 后 `fastboot flash system system.img` 逐分区刷）。
> 我们的 super 只填了 **slot A**，所以 `--set-active=a` 不能省，否则起不来。

**第 4 步：首启等待**

- 首启要跑 dex2oat（因为只预编译了 boot+system_server），**等 5~15 分钟正常**
- 别看到开机动画不动就拔电

**第 5 步：没起来就抓日志，别盲刷**

```bash
bash scripts/07-capture-bootlog.sh     # 循环等 adb、抓 logcat + dmesg
```

抓到的日志贴给我，**千万别自己乱改重刷** —— 重编一次 ¥9.4。

**回原厂（任何时候刷挂了）**：把 `F:\fl\super.img` 换回原厂那份 → 运行 `E:\...\一键刷机.bat`（EDL 全量刷 6 个 LUN）。

---

## 7. 已排除的坑

### 7.1 设备树配置（对照 NX789J 验证树修正的 12 处）

| 项 | 我原来写的（错） | 现在（对） |
|---|---|---|
| A/B | `AB_OTA_UPDATER := false` | `true` + 列全 7 个 `AB_OTA_PARTITIONS` |
| Boot 头版本 | `BOARD_BOOTIMG_HEADER_VERSION` | `BOARD_BOOT_HEADER_VERSION` |
| 内核 | 只有 `TARGET_PREBUILT_KERNEL` | 加 `TARGET_FORCE_PREBUILT_KERNEL := true` |
| system.prop | 没声明 | `TARGET_SYSTEM_PROP +=` |
| 分区表 | 全缺 | 6 个分区大小 + super/group 配置 |
| EROFS | 全缺 | 7 个 `BOARD_*_FILE_SYSTEM_TYPE := erofs` |
| API level | `:= 36` | `PRODUCT_SHIPPING_API_LEVEL := 35` + system.prop 写 `ro.board.api_level=202404` |
| sepolicy | 空 | `TARGET_USES_PREBUILT_VENDOR_SEPOLICY` + qcom vndr include |
| AVB | 无 | `--flags 3` |
| 无效模块 | `PRODUCT_PACKAGES += init.nx737j.rc` | 已删（会直接编译失败） |
| 错误 copy | `PRODUCT_COPY_FILES` 到 vendor | 改到 system |
| 多余继承 | inherit sm8750-common | 删掉 |

外加：自造 overlay 的资源类型写错（`config_mainBuiltInDisplayCutout` 是 string 不是 bool），整目录已删。

### 7.2 仓库依赖（2026-10-23 修正，之前这里写错过一次）

⚠️ **旧版本说"要把 sepolicy_vndr 和 device/lineage/sepolicy 加进 local manifest"——这是错的，**
会导致 `repo sync` 报 Nested projects / duplicate project。2026-10-23 走 api.github.com 核实后重写：

| 路径 | 谁引用 | 实际情况 | 处置 |
|---|---|---|---|
| `device/qcom/sepolicy_vndr/sm8750` | BoardConfig `include .../SEPolicy.mk` | **ROM 自带**（PixelOS/LineageOS 的 snippets/lineage.xml 都有，路径带 `/sm8750`） | 不进 local manifest；BoardConfig 改成条件包含，见下 |
| `device/lineage/sepolicy` | BoardConfig `SYSTEM_EXT_PRIVATE_SEPOLICY_DIRS` | **ROM 自带**（snippets/lineage.xml） | 不进 local manifest |
| `hardware/qcom/wlan` | device.mk `libwifi-hal-qcom` + BoardConfig `lib_driver_cmd_qcwcn` | **ROM 自带**（`LineageOS/android_hardware_qcom_wlan`，PixelOS/LineageOS 都引） | 不额外加；按官方 sm8750-common 恢复 WiFi 配置 |

**local manifest 现在只剩一个项目：设备树本身。**

BoardConfig 里 sepolicy 的包含写成了容错形式（路径不存在就跳过并警告，不会挂）：

```make
ifneq ($(wildcard device/qcom/sepolicy_vndr/sm8750/SEPolicy.mk),)
  include device/qcom/sepolicy_vndr/sm8750/SEPolicy.mk
else ifneq ($(wildcard device/qcom/sepolicy_vndr/SEPolicy.mk),)
  include device/qcom/sepolicy_vndr/SEPolicy.mk
endif
```

> WiFi 结论（2026-10-23 更正，之前"404"是查错了仓库名）：
> `LineageOS/android_hardware_qcom_wlan` 提供 `libwifi-hal-qcom` / `libwifi-hal-ctrl` /
> `lib_driver_cmd_qcwcn`。不设 `BOARD_WLAN_CHIP` 时走 legacy 分支（官方 sm8750 树同款做法），
> 系统侧 shim + stock vendor 的驱动/HAL 一起构成完整 WiFi 栈。

### 7.3 已核实存在的依赖（api.github.com 实测，2026-10-23）

| 路径 | 来源 | 状态 |
|---|---|---|
| `vendor/lineage/config/BoardConfigLineage.mk` | PixelOS `android_vendor_lineage@seventeen` | ✅ 443 B |
| `vendor/lineage/config/BoardConfigKernel.mk` | 同上 | ✅ 10.5 KB |
| `vendor/lineage/config/BoardConfigSoong.mk` | 同上 | ✅ 2.2 KB |
| `vendor/lineage/config/common_full_phone.mk` | 同上 | ✅ 279 B |
| `external/avb/test/data/testkey_rsa2048.pem` | AOSP | ✅ 在 `external/avb` |
| `PRODUCT_PACKAGES` 里 5 个模块 | AOSP | ✅ 全部为标准模块 |

### 7.4 编译目标名（这条会让你第一次编译就失败）

**不能**写：
```
--make-mode systemimage systemextimage productimage
```
（NX789J 的 README 就是这么写的，但那是错的）

查 PixelOS `build/make/core/Makefile` 实际定义：

| 目标 | 是否存在 | 说明 |
|---|---|---|
| `systemimage` | ✅ L3932 | `systemimage: $(INSTALLED_SYSTEMIMAGE_TARGET)`，设备构建可用 |
| `systemextimage` | ❌ 仅 L7905 | `systemextimage: $(INSTALLED_QEMU_SYSTEM_EXTIMAGE)` —— **只在 QEMU 分支** |
| `productimage` | ❌ 仅 L7896 | `productimage: $(INSTALLED_QEMU_PRODUCTIMAGE)` —— **只在 QEMU 分支** |
| `systemextimage-nodeps` | ✅ L4411 | 存在，但**不依赖 `INTERNAL_SYSTEM_EXTIMAGE_FILES`** |
| `productimage-nodeps` | ✅ L4343 | 同上 |

`nodeps` 变体不会先把模块装进 `TARGET_OUT_*` 就直接跑 `build_image.py`，
首次编译会产出**空镜像**。

**正确做法：用产物文件路径当目标。**
```bash
build/soong/soong_ui.bash --make-mode \
    systemimage \
    "$OUT/system_ext.img" \
    "$OUT/product.img" \
    -j$(nproc)
```

`03-build.sh` 已按此实现，并带"绝对路径被拒 → 退相对路径"的自动重试。

### 7.5 若编译报 `hardware/qcom-caf/common/BoardConfigQcom.mk` 缺失

`vendor/lineage/config/BoardConfigLineage.mk` 里有一段：
```make
ifeq ($(BOARD_USES_QCOM_HARDWARE),true)
    include hardware/qcom-caf/common/BoardConfigQcom.mk
endif
```
我没设 `BOARD_USES_QCOM_HARDWARE`，理论上不触发。真报了就把 `local_manifests/nx737j.xml` 里那段注释掉的
`hardware/qcom-caf/common`（`LineageOS/android_hardware_qcom-caf_common @ lineage-24.0`）打开。
