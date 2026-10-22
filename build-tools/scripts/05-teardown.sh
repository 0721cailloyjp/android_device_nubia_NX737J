#!/usr/bin/env bash
#
# 05-teardown.sh — 打印销毁清单（真正的销毁必须在腾讯云控制台点）
#
# 按量计费的坑：实例"关机"仍可能计费，云硬盘一定会继续计费。
# 必须"销毁/退还实例" + "销毁云硬盘"，不是关机。
#
set -euo pipefail

echo "════════════════════════════════════════════════════════════════"
echo " 销毁清单 —— 按顺序做完，否则继续扣费"
echo "════════════════════════════════════════════════════════════════"
cat <<'EOF'

 ① 先确认产物已经下载到本地
    本地执行（在你 Windows 上）：
      scp -P <端口> root@<IP>:/data/nx737j-img.tar.zst .
      scp -P <端口> root@<IP>:/data/nx737j-img.tar.zst.sha256 .
    校验：
      sha256sum -c nx737j-img.tar.zst.sha256      （Git Bash 可用）
      certutil -hashfile nx737j-img.tar.zst SHA256 （PowerShell）

 ② 控制台 → 云服务器 CVM → 实例
    选实例 → 更多操作 → 实例状态 → **销毁/退还**
      · 选择"立即销毁"
      · 勾选"销毁云硬盘"（系统盘 + 数据盘都要）
    ⚠️ 只关机不销毁 = 继续计费
    ⚠️ 数据盘如果没勾选销毁，会变成"待挂载"状态继续按 GB 计费

 ③ 控制台 → 云硬盘 CBS
    确认列表里没有残留的"待挂载"硬盘。有就删。

 ④ 控制台 → 弹性公网 IP
    如果是独立 EIP（不是实例自带公网 IP），要单独释放，否则闲置也收费。

 ⑤ 控制台 → 快照
    如果创建过自动快照策略，删掉策略 + 删除快照。

 ⑥ 核对账单
    控制台 → 费用中心 → 账单明细，确认当天没有仍在计费的资源。

EOF
echo "════════════════════════════════════════════════════════════════"
echo
echo " 有 tccli 的话可以一条条核对（可选）："
cat <<'EOF'

  tccli cvm DescribeInstances --region ap-guangzhou
  tccli cbs DescribeDisks --region ap-guangzhou
  tccli vpc DescribeAddresses --region ap-guangzhou

  全空 = 清理干净了。

EOF
