# nubia Z70S Ultra 摄影师版 — 类原生 ROM

> **设备**：努比亚 Z70S Ultra 摄影师版（NX737J）
> **基础**：PixelOS 17 / LineageOS 24.0（Android 17 / SDK 37）
> **类型**：类原生（AOSP 风格，无厂商定制 UI）

---

## 这是什么

把 Z70S Ultra 从 HyperOS 4 换成**干净的类原生系统**（PixelOS / LineageOS / AviumUI 三选一）。

核心思路是 **system-side hybrid**：只替换 `system` 和 `system_ext` 两个分区，**原样保留** vendor（硬件驱动层）和内核。所以——

- **硬件功能一个不丢**：相机、指纹、充电、NFC、红外、激光对焦……全部由原厂 vendor 提供，AOSP 框架自动对接
- **稳定性有保障**：内核、boot、vendor 一个字节不动，底层和原厂完全一致

---

## 特性

### 类原生侧（AOSP 原生）

- 纯净 AOSP 界面，无 HyperOS 的广告、预装、定制 UI
- 完整的 GKI 生态，可刷 Magisk / KernelSU 等
- 5G SA 默认开启（双卡 NR SA）

### 保留的努比亚功能

| 功能 | 说明 |
|---|---|
| **相机算法** | ZTE EEPROM HAL + 努比亚图像算法（人像虚化、AI 抠像、视频分割）全保留 |
| **指纹** | goodix G7 屏下指纹，ifaa 支付指纹 |
| **充电分离 / 涡轮充电** | 原厂充电协议完整 |
| **NFC 钱包** | ST54L eSE，门禁卡 / 公交卡（含 ZTE 钱包 App） |
| **努比亚账号** | NBAccount / NBUserCenter / 统一认证组件 |
| **高级设置** | 移植者「高级设置」App（风扇 / 充电 / 灯效 / SAR 开关） |
| **相机流转** | 相机画面投屏（transferclient） |

---

## 已知问题

| 问题 | 说明 | 影响 |
|---|---|---|
| **32 位 App 不兼容** | 骁龙 8 Elite 无 AArch32 执行单元，HyperOS 靠闭源 Tango 转译器跑 32 位，AOSP 无法复刻 | 纯 32 位的老 App 装不上/闪退，绝大多数 App 早就有 64 位版 |
| **MIUI 残留 App 会崩** | 保留了原厂 product，里面的小米 App 在 AOSP 下缺 miui 框架类 | 只影响那些 App 本身，不影响系统 |
| **QTI 性能服务可能失效** | system 侧 perfservice 依赖被换掉的 system_ext | 性能调度用 AOSP 默认，无感 |
| **ZTE 钱包部分功能** | 缺 `com.zte.aimodel.*` 等类（原厂移植包也缺） | AI 语音类功能不可用，刷卡/门禁正常 |

> 以上都是"移植包的现状"延续，**不是本包引入的退化**。

---

## 刷机方法

> ⚠️ **前提**：刷机前备份好数据，**必须清 data**（`fastboot -w`），否则黑屏。

```bash
# 1. 关 AVB 校验（两个 vbmeta 都要打 flags=3）
# 2. 刷 super（含新 system + system_ext）
fastboot flash super nx737j-super.img
fastboot --set-active=a
fastboot -w
fastboot reboot
```

**只刷 super，boot / vendor / dtbo 一个字节不动。**

刷挂了恢复：EDL 9008 + 原厂一键刷机（原厂包在 E 盘）。

完整步骤见 `RECOVERY.md`（随包附带）。

---

## 致谢 & 免责

- 内核 / vendor 来自 nubia Z70S Ultra 原厂，未改动
- 设备树参考 IronShing 的 NX789J（红魔 10，同平台）

**刷机有风险，操作前请确认已备份。** 变砖可 EDL 恢复，但请自行承担操作后果。

---

*本包为学习交流用途，不用于商业目的。*
