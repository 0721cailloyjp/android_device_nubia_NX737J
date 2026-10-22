# 明日操作单（省钱版 · 两阶段变配）

> **预算硬约束 ¥25（已充值）。** 目标：第一版能开机，且不超预算。
> 时间不值钱（周末），所以用两次变配换 ¥6 的节省。

---

## 0. 今晚就能做的（不花钱）

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

## 2.5 保留 Z70S 的原厂 product（默认开启）

扫 NX737J 的 super.img 实测，努比亚专有组件分布如下：

| 分区 | 内容 |
|---|---|
| **system** | `com.zte.wallet`（钱包）、`com.zte.mifavor`（NeoVision 框架）、`cn.nubia.identity`、`cn.nubia.accounts`、`com.zte.cloud`、`com.zte.NFC_SIMULATION`、`cn.nubia.neopush` |
| **system_ext** | `cn.nubia.identity` |
| **product** | `cn.nubia.identity`、`cn.nubia.touping`（投屏）、`cn.nubia.provider.deviceid`、`cn.nubia.applearning`、**`com.zte.camera.SpecialTypesProvider`**、**`com.zte.bokeh`**、**`com.zte.imagesegmentation`**、**`com.zte.videosegmentation`**、`cn.nubia.camera.tools` |

**相机算法三件套（bokeh / 图像分割 / 视频分割）全在 product 里。**
换成 AOSP 的 product（几乎空镜像）= 人像虚化、AI 抠像、视频分割直接没了。

而 AOSP 侧基本不往 product 放东西，替换它收益接近零。

### 所以默认不编 product

| 开关 | 行为 |
|---|---|
| `KEEP_STOCK_PRODUCT=1`（**默认**） | 只编 `system.img` + `system_ext.img`，product 保持原厂 |
| `KEEP_STOCK_PRODUCT=0` | 三个都编（完全净化时用，会丢上面那些组件） |

三个脚本都认这个开关：`03-build.sh` / `04-pack.sh` / `assemble-super.sh`。

```bash
# 默认就是保留
bash scripts/03-build.sh

# 想全替换
KEEP_STOCK_PRODUCT=0 bash scripts/03-build.sh
```

**副作用**：原厂 product 的 `build.prop` 是小米的，会带一些 `ro.miui.*` / 产品身份属性。
AOSP 不读这些，理论上不影响开机；万一开机异常，把它设成 0 重编一次
（但重编要 ¥9~15，所以先试默认路径）。

---

### 2.5.1 system 侧的努比亚 App（会丢，可回注）

换 system 分区会丢掉原厂装在 system 里的努比亚 App。实测清单：

| APK | 用途 |
|---|---|
| `NBAccount.apk` | 努比亚账号 |
| `NBUserCenter.apk` | 用户中心 |
| `zteaccount_mfv.apk` | 账号框架（mfv = mifavor） |
| `Nfc_st.apk` | NFC |
| `CameraMind.apk` | 相机 |
| `CameraExtensionsProxy.apk` | 相机扩展 |
| `RomFixCameraCompat.apk` | 相机兼容修正 |

（对照：`MiuiSystemUI.apk` / `Joyose.apk` 是小米的，不用管）

**移植包作者特意把这批留在 system 里**，说明摘掉会出问题。回注成本很低：

**两条路拿 APK，任选其一：**

```bash
# 【快】直接从手机拉（几十 MB，几秒钟，本地跑）
bash scripts/09-pull-nubia-apps.sh --list   # 先看找到什么
bash scripts/09-pull-nubia-apps.sh          # 再拉

# 【慢】从 super.img 解包（16 GB，服务器上跑）
bash scripts/08-extract-nubia-apps.sh /path/to/super.img
```

两个脚本都会产出：
- `device/nubia/NX737J/prebuilts/nubia-apps/*.apk`（+ 相关 privapp-permissions XML）
- `device/nubia/NX737J/nubia-apps.mk`（PRODUCT_COPY_FILES 规则）

`device.mk` 末尾已经写好了：

```make
-include $(LOCAL_PATH)/nubia-apps.mk
```

**带减号的 `-include`：文件不存在就静默跳过，不会编译失败。**
所以只要产物在就自动带上；没有就编纯 AOSP。不需要手动改 device.mk。

**流程**：跑完提取 → `python scripts/gh-push.py` 推 GitHub → 云端 sync 时自动拉到。

⚠️ 如果某个 App 闪退，logcat 搜 `NoClassDefFoundError` / `NoSuchMethodError`，
看是不是指向 `com.zte.mifavor.*`（努比亚自己的 framework）。那种 AOSP 补不了，
把 `nubia-apps.mk` 里对应的 PRODUCT_COPY_FILES 行删掉即可，不影响其他 App。

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
| API level | `:= 36` | `35` + `BOARD_SHIPPING_API_LEVEL := 202404` |
| sepolicy | 空 | `TARGET_USES_PREBUILT_VENDOR_SEPOLICY` + qcom vndr include |
| AVB | 无 | `--flags 3` |
| 无效模块 | `PRODUCT_PACKAGES += init.nx737j.rc` | 已删（会直接编译失败） |
| 错误 copy | `PRODUCT_COPY_FILES` 到 vendor | 改到 system |
| 多余继承 | inherit sm8750-common | 删掉 |

外加：自造 overlay 的资源类型写错（`config_mainBuiltInDisplayCutout` 是 string 不是 bool），整目录已删。

### 7.2 仓库依赖（2026-10-22 审计发现，会让编译直接挂）

`repo sync` 完成后这三个路径原本会不存在，因为**它们不在 PixelOS / LineageOS 的默认 manifest 里**：

| 路径 | 谁引用 | 处置 |
|---|---|---|
| `device/qcom/sepolicy_vndr` | BoardConfig `include .../SEPolicy.mk` | **已加入 local manifest**，分支必须是 `lineage-24.0-caf-sm8750`（SM8750 专用，不是通用 lineage-24.0） |
| `device/lineage/sepolicy` | BoardConfig `SYSTEM_EXT_PRIVATE_SEPOLICY_DIRS` | **已加入 local manifest**，`lineage-24.0` |
| `hardware/qcom-caf/wlan` | device.mk `PRODUCT_SOONG_NAMESPACES` + `libwifi-hal-qcom` | **已从设备树删除** —— 该路径在 LineageOS 组织下 **404，仓库不存在** |

wifi 第一次开机不依赖它（stock vendor 提供 HAL）。等能开机了再找正确仓库补。

### 7.3 已核实存在的依赖

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
