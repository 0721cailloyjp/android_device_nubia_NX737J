# NX737J 刷机救砖指南

> 这份文件会随编译产物一起打包。**刷机前必读。**

## ⚠️ 刷机前三条铁律

1. **E:\NX737J_HyperOS_4.0.0.10_A17_10.12\ 是原厂救砖包（17 GB），千万别删！**
   这是刷挂了之后唯一的恢复手段，删了就只能找人要。
2. **第一次刷一定 `fastboot -w`**（清 data）。不清 data 的典型表现是黑屏/卡动画。
3. Slot B 是空的，**没有 A/B 回退**——super 写坏了只能 EDL 恢复，所以下面三种情况都要看懂。

---

## 情况 A：还能进 fastboot / bootloader

这是最轻的情况（系统起不来但 bootloader 还在）。

用 fastboot 单独刷回**原厂** super 即可：

```bash
# 如果 E 盘的是 super.img.zst，先解压（一键刷机.bat 也会自动做这步）
E:\NX737J_HyperOS_4.0.0.10_A17_10.12\FlashTool\zstd -d \
    E:\NX737J_HyperOS_4.0.0.10_A17_10.12\Firmware\super.img.zst \
    -o E:\NX737J_HyperOS_4.0.0.10_A17_10.12\Firmware\super.img

fastboot flash super E:\NX737J_HyperOS_4.0.0.10_A17_10.12\Firmware\super.img
fastboot --set-active=a
fastboot -w
fastboot reboot
```

---

## 情况 B：完全黑屏 / 进不了 fastboot（EDL 9008 救砖）

用原厂**一键刷机.bat**恢复整套固件。

**① 进 EDL（9008）模式**

- 手机完全关机
- 按住 **音量上 + 音量下**，同时插 USB 线到电脑
- （或者在 bootloader 下执行 `fastboot oem edl`）

**② 确认驱动**

打开「设备管理器」，应该出现带感叹号的 `Qualcomm HS-USB QDLoader 9008 (COMxx)`。
Windows 驱动在 `E:\NX737J_HyperOS_4.0.0.10_A17_10.12\WindowsDriver\`，
先装好驱动再继续。

**③ 跑一键刷机**

双击 `E:\NX737J_HyperOS_4.0.0.10_A17_10.12\一键刷机.bat`：

1. 它会先问「是否需要 root」——恢复原厂选 **1**（不需要）
2. 提示输入端口号：看设备管理器里 9008 的 COM 号，例如 `COM3` 就输入 `3`
3. 然后自动刷 Firmware 下所有分区（rawprogram0~5 + patch0~5）+ 清 data + 解锁 FRP
4. 跑完自动重启进原厂系统

**这个过程是整套固件恢复，刷完就是干净的原厂澎湃4。**

---

## 情况 C：提示 "Your device is corrupt"

AVB 校验没关掉。两个 vbmeta 都要打 `--flags 3`：

```bash
python scripts/patch-vbmeta.py --flags 3 --out-dir patched/ \
    Firmware/vbmeta_system.img Firmware/vbmeta.img

fastboot flash vbmeta_system patched/vbmeta_system_patched.img
fastboot flash vbmeta       patched/vbmeta_patched.img
fastboot --set-active=a
fastboot -w
fastboot reboot
```

> flags 在 vbmeta 的 **offset 120（大端 u32）**，不是网上说的 offset 12。
> offset 12 是 `authentication_data_block_size`，改那里直接刷坏。

---

## 情况 D：刷进去了但起不来（要抓日志）

```bash
bash scripts/07-capture-bootlog.sh
```

它会抓 logcat / dmesg / pstore / avc denial / HAL 列表，先看 `SUMMARY.txt`。
**把日志贴出来，别自己反复盲刷**——重编一次 ¥9.4，比多花两分钟分析贵得多。

---

## 备份建议（可选，但能省很多时间）

如果硬盘空间够，刷我们的 ROM 前先备份原厂 super：

```bash
mkdir F:\nx737j-backup
cp "E:\NX737J_HyperOS_4.0.0.10_A17_10.12\Firmware\super.img" F:\nx737j-backup\
```

16 GB 占空间，但 super 写坏时用 fastboot 直接刷回去（几秒），
比走 EDL 9008 整套恢复快得多。
