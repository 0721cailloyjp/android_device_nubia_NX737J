#!/usr/bin/env python3
"""
gh-push.py — 增量推送设备树到 GitHub（走 Git Data API）

为什么要这个脚本：
  github.com 直连不通（本机 HTTP 000），只能走 api.github.com。
  但 naive 的推法每次都重传全部 blob —— 包括 38 MB 的 prebuilts/Image。
  新账号（<30 天）反复大流量写操作容易触发 abuse detection。

  这个版本的做法：
    1. 本地算每个文件的 git blob sha（sha1("blob <len>\\0" + content)）
    2. 拉远端当前 tree（recursive），比对 path -> sha
    3. 只上传 sha 变了的文件
    4. tree 里未变的文件直接引用远端已有 sha
    5. 建 commit + 移动 ref

  结果：改一个 mk 文件只需要 1 次 GET(tree) + 1 次 POST(tree)
        + 1 次 POST(commit) + 1 次 PATCH(ref)，共 4 次请求，0 字节重传。

用法：
    export GH_TOKEN=ghp_xxx
    python3 gh-push.py                       # 推到默认仓库
    python3 gh-push.py --dry-run             # 只看会传什么
    python3 gh-push.py --repo owner/name     # 指定仓库
    python3 gh-push.py --token-file <path>   # 从文件读 token（避免进 shell 历史）

依赖：只用标准库。
"""
import argparse
import base64
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request

API = "https://api.github.com"


def git_blob_sha(data: bytes) -> str:
    """Git 的 blob 对象 sha：sha1("blob <len>\\0" + content)"""
    h = hashlib.sha1()
    h.update(b"blob %d\0" % len(data))
    h.update(data)
    return h.hexdigest()


class GH:
    def __init__(self, token: str, repo: str):
        self.token = token
        self.repo = repo
        self.calls = 0

    def call(self, method, path, body=None, timeout=300, retries=3):
        url = API + path
        data = json.dumps(body).encode() if body is not None else None
        for attempt in range(retries):
            req = urllib.request.Request(
                url, data=data, method=method,
                headers={
                    "Authorization": "Bearer " + self.token,
                    "Accept": "application/vnd.github+json",
                    "User-Agent": "curl",
                    "Content-Type": "application/json",
                },
            )
            try:
                with urllib.request.urlopen(req, timeout=timeout) as r:
                    self.calls += 1
                    raw = r.read()
                    return r.status, (json.loads(raw) if raw else {})
            except urllib.error.HTTPError as e:
                raw = e.read()
                self.calls += 1
                try:
                    msg = json.loads(raw)
                except Exception:
                    msg = {"raw": raw[:300].decode(errors="replace")}
                # 429 / 403 二级限制：退避重试
                if e.code in (403, 429) and attempt < retries - 1:
                    wait = 2 ** (attempt + 2)
                    print("     ..HTTP %d，退避 %ds 重试" % (e.code, wait))
                    time.sleep(wait)
                    continue
                return e.code, msg

    def rate_left(self):
        st, d = self.call("GET", "/rate_limit", timeout=15)
        if st == 200:
            c = d["resources"]["core"]
            return c["remaining"], c["limit"]
        return None, None


# 仓库内路径映射：本地目录 -> 仓库路径
def build_file_map(root: str, device_dir: str):
    """
    设备树文件放仓库根（repo 会 sync 到 device/nubia/NX737J/），
    scripts 放 build-tools/，顶层文档放根。
    """
    files = []
    skip_dirs = {".git", "__pycache__", ".workbuddy"}

    def add(local, repo_path):
        files.append((local, repo_path))

    dev_root = os.path.join(root, device_dir)
    if os.path.isdir(dev_root):
        for dp, dn, fns in os.walk(dev_root):
            dn[:] = [d for d in dn if d not in skip_dirs]
            for fn in fns:
                if fn.endswith(".pyc"):
                    continue
                p = os.path.join(dp, fn)
                rel = os.path.relpath(p, dev_root).replace("\\", "/")
                add(p, rel)

    scr = os.path.join(root, "scripts")
    if os.path.isdir(scr):
        for fn in sorted(os.listdir(scr)):
            p = os.path.join(scr, fn)
            if os.path.isfile(p) and not fn.endswith(".pyc"):
                add(p, "build-tools/scripts/" + fn)

    lm = os.path.join(root, "local_manifests")
    if os.path.isdir(lm):
        for fn in sorted(os.listdir(lm)):
            p = os.path.join(lm, fn)
            if os.path.isfile(p):
                add(p, "build-tools/local_manifests/" + fn)

    ref = os.path.join(root, "reference")
    if os.path.isdir(ref):
        for dp, dn, fns in os.walk(ref):
            dn[:] = [d for d in dn if d not in skip_dirs]
            for fn in fns:
                pp = os.path.join(dp, fn)
                rel = os.path.relpath(pp, root).replace("\\", "/")
                add(pp, rel)

    for doc in ("README.md", "RUNBOOK.md"):
        p = os.path.join(root, doc)
        if os.path.isfile(p):
            add(p, doc)

    # run-all.sh 是云上入口脚本，和 scripts/ 一起放 build-tools/（保持相对路径 scripts/ 不变）
    ra = os.path.join(root, "run-all.sh")
    if os.path.isfile(ra):
        add(ra, "build-tools/run-all.sh")

    # 去重（同一 repo_path 只留一个）
    seen = {}
    for local, rp in files:
        seen[rp] = local
    return sorted(seen.items(), key=lambda kv: kv[1])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default="0721cailloyjp/android_device_nubia_NX737J")
    ap.add_argument("--root", default=None, help="本地项目根目录（默认脚本上一级）")
    ap.add_argument("--device-dir", default="device-nubia-NX737J")
    ap.add_argument("--branch", default="main")
    ap.add_argument("--message", default=None)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--token-file", default=None)
    args = ap.parse_args()

    token = os.environ.get("GH_TOKEN", "").strip()
    if not token and args.token_file:
        token = open(args.token_file).read().strip()
    if not token:
        sys.exit("缺少 token：export GH_TOKEN=... 或 --token-file <path>")
    if not token.startswith(("ghp_", "github_pat_")):
        sys.exit("token 形态不对（应以 ghp_ 或 github_pat_ 开头）")

    root = args.root or os.path.abspath(
        os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    gh = GH(token, args.repo)

    # ── 认证 + 配额 ─────────────────────────────────────────────────────────
    st, me = gh.call("GET", "/user", timeout=15)
    if st != 200:
        sys.exit("token 无效 HTTP %d" % st)
    left, limit = gh.rate_left()
    print("账号      : %s" % me.get("login"))
    print("仓库      : %s" % args.repo)
    print("REST 配额 : %s / %s" % (left, limit))
    print()

    # ── 收集本地文件 + 算 sha ───────────────────────────────────────────────
    pairs = build_file_map(root, args.device_dir)
    local = []          # (repo_path, sha, size, bytes_or_None)
    total = 0
    for rp, p in pairs:
        data = open(p, "rb").read()
        total += len(data)
        local.append((rp, git_blob_sha(data), len(data), data, p))
    print("本地 %d 个文件，%.1f MB" % (len(local), total / 1048576))

    # ── 拉远端 tree ─────────────────────────────────────────────────────────
    st, ref = gh.call("GET", "/repos/%s/git/ref/heads/%s" % (args.repo, args.branch))
    if st != 200:
        sys.exit("拿不到 ref HTTP %d（分支不存在？）" % st)
    base_sha = ref["object"]["sha"]
    st, commit = gh.call("GET", "/repos/%s/git/commits/%s" % (args.repo, base_sha))
    base_tree = commit["tree"]["sha"]

    remote = {}
    st, t = gh.call("GET", "/repos/%s/git/trees/%s?recursive=1" % (args.repo, base_tree))
    if st == 200:
        for e in t.get("tree", []):
            if e["type"] == "blob":
                remote[e["path"]] = e["sha"]
    print("远端 %d 个文件  base=%s" % (len(remote), base_sha[:8]))

    # ── 差异 ────────────────────────────────────────────────────────────────
    to_upload = [x for x in local if remote.get(x[0]) != x[1]]
    unchanged = [x for x in local if remote.get(x[0]) == x[1]]
    print("需上传 %d 个（%.1f MB），未变 %d 个"
          % (len(to_upload), sum(x[2] for x in to_upload) / 1048576, len(unchanged)))
    for rp, sha, sz, _, _ in to_upload:
        print("  + %-52s %8.1f KB" % (rp, sz / 1024))
    print()

    if not to_upload:
        print("远端已是最新，无需推送。")
        return
    if args.dry_run:
        print("[dry-run] 未实际推送")
        return

    # ── 上传变化的 blob（串行，带退避）────────────────────────────────────────
    entries = []
    for i, (rp, sha, sz, data, _) in enumerate(to_upload, 1):
        st, res = gh.call("POST", "/repos/%s/git/blobs" % args.repo,
                          {"content": base64.b64encode(data).decode(),
                           "encoding": "base64"})
        if st not in (200, 201):
            sys.exit("blob 上传失败 %s HTTP %d %s" % (rp, st, json.dumps(res)[:200]))
        if res["sha"] != sha:
            print("  ! %s 远端 sha 与本地不同（有换行符转换？）" % rp)
        entries.append({"path": rp, "mode": "100644", "type": "blob", "sha": res["sha"]})
        print("  [%d/%d] %-52s ok" % (i, len(to_upload), rp))
        if i < len(to_upload):
            time.sleep(0.4)          # 轻微间隔，避免高频写入
    for rp, sha, sz, _, _ in unchanged:
        entries.append({"path": rp, "mode": "100644", "type": "blob", "sha": sha})

    # 删除远端多余文件
    for rp in sorted(set(remote) - {x[0] for x in local}):
        print("  - %s（远端删除）" % rp)
        entries.append({"path": rp, "mode": "100644", "type": "blob", "sha": None})

    # ── tree / commit / ref ─────────────────────────────────────────────────
    msg = args.message or ("device tree: update %d file(s)" % len(to_upload))
    st, tree = gh.call("POST", "/repos/%s/git/trees" % args.repo,
                       {"base_tree": base_tree, "tree": entries})
    if st not in (200, 201):
        sys.exit("tree 失败 HTTP %d %s" % (st, json.dumps(tree)[:300]))

    st, cm = gh.call("POST", "/repos/%s/git/commits" % args.repo,
                     {"message": msg, "tree": tree["sha"], "parents": [base_sha]})
    if st not in (200, 201):
        sys.exit("commit 失败 HTTP %d %s" % (st, json.dumps(cm)[:300]))

    st, r = gh.call("PATCH", "/repos/%s/git/refs/heads/%s" % (args.repo, args.branch),
                    {"sha": cm["sha"], "force": True})
    if st not in (200, 201):
        sys.exit("ref 更新失败 HTTP %d %s" % (st, json.dumps(r)[:300]))

    left2, _ = gh.rate_left()
    print()
    print("✅ https://github.com/%s/tree/%s" % (args.repo, args.branch))
    print("   commit %s" % cm["sha"][:12])
    print("   本次 API 调用 %d 次，剩余配额 %s" % (gh.calls, left2))


if __name__ == "__main__":
    main()
