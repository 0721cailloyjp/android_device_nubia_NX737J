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

**sync 完成后先别急着升配**，跑完整性检查确认树是好的：

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
bash scripts/03-build.sh
tmux wait-for build-done

# 看进度
tail -f /data/build.log
bash scripts/cost.sh
```

**16核32G 上编译约 100~160 分钟。**

**OOM 了就这样增量续编**（不用重新 sync）：

```bash
JOBS=8 bash scripts/03-build.sh
tmux wait-for build-done
```

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

### 7.4 若编译报 `hardware/qcom-caf/common/BoardConfigQcom.mk` 缺失

`vendor/lineage/config/BoardConfigLineage.mk` 里有一段：
```make
ifeq ($(BOARD_USES_QCOM_HARDWARE),true)
    include hardware/qcom-caf/common/BoardConfigQcom.mk
endif
```
我没设 `BOARD_USES_QCOM_HARDWARE`，理论上不触发。真报了就把 `local_manifests/nx737j.xml` 里那段注释掉的
`hardware/qcom-caf/common`（`LineageOS/android_hardware_qcom-caf_common @ lineage-24.0`）打开。
