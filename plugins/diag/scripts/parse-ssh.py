#!/usr/bin/env python3
"""
parse-ssh.py — 从 bash 命令字符串中提取首个 ssh 段的主机和远程命令。

输入：stdin 读取完整 bash 命令
输出：stdout JSON {is_ssh, host, remote, error?}

原则：
- 只做 shlex 词法拆分 + 线性扫描，绝不 eval
- 使用 punctuation_chars 让 shell 分隔符（| & ;）成为独立 token，
  正确区分"本地管道"和"SSH 远程命令"：
    `ssh host cmd | head` 的 `| head` 属于本地，不纳入 remote。
- 不处理 scp/rsync（本期只拦 ssh）
"""
import sys
import json
import shlex

OPTS_WITH_ARG = {
    "-b", "-B", "-c", "-D", "-E", "-e", "-F", "-I", "-i", "-J", "-L",
    "-l", "-m", "-O", "-o", "-p", "-Q", "-R", "-S", "-W", "-w",
}

SEPARATORS = {"|", "||", "&&", ";", "&"}

# 已知本地包装器，允许出现在 ssh 之前而不影响 ssh 的识别
# (例: `nohup ssh host cmd`、`env FOO=bar ssh ...`、`timeout 60 ssh ...`)
# sudo / su / doas 等提权工具不在此列，由 write-guard 的本地提权检查独立阻断
SAFE_WRAPPERS = {
    "nohup", "exec", "setsid", "time", "chronic",
    "env", "timeout", "nice", "ionice", "taskset",
    "stdbuf", "tsp",
}


def _is_safe_prefix(tokens):
    """判断 ssh 之前的 tokens 是否全部是安全包装器 / 环境变量赋值 / 选项 / 数值参数。

    True  → 可以把 ssh 当作命令动词
    False → 前缀里有未知命令（避免 `grep ssh file` / `man ssh` 误判为 ssh 调用）
    """
    for t in tokens:
        if t in SAFE_WRAPPERS:
            continue
        if t.startswith("-"):
            continue
        # 环境变量赋值 VAR=value
        if "=" in t and not t.startswith("="):
            name = t.split("=", 1)[0]
            if name and name[0].isalpha() and all(c.isalnum() or c == "_" for c in name):
                continue
        # 数值参数 (如 timeout 60 / nice 10)
        if t.replace(".", "", 1).isdigit():
            continue
        return False
    return True


def parse(cmd: str) -> dict:
    try:
        lex = shlex.shlex(cmd, posix=True, punctuation_chars="|&;")
        lex.whitespace_split = True
        tokens = list(lex)
    except ValueError as e:
        return {"is_ssh": False, "error": f"shlex: {e}"}

    segments, cur = [], []
    for t in tokens:
        if t in SEPARATORS:
            segments.append(cur)
            cur = []
        else:
            cur.append(t)
    segments.append(cur)

    # 在每个段中找 ssh 命令动词（允许前缀有 nohup/env/timeout 等安全包装器）
    ssh_seg = None
    ssh_start = 0
    for seg in segments:
        for idx, tok in enumerate(seg):
            if tok == "ssh" and _is_safe_prefix(seg[:idx]):
                ssh_seg = seg
                ssh_start = idx
                break
        if ssh_seg is not None:
            break

    if ssh_seg is None:
        return {"is_ssh": False}

    tokens = ssh_seg
    i = ssh_start + 1  # skip "ssh"
    while i < len(tokens):
        t = tokens[i]
        if t == "--":
            i += 1
            break
        if not t.startswith("-"):
            break
        if len(t) > 2 and t[:2] in OPTS_WITH_ARG:
            i += 1
            continue
        if t in OPTS_WITH_ARG:
            i += 2
            continue
        i += 1  # 布尔或未知短选项

    if i >= len(tokens):
        return {"is_ssh": True, "error": "no_host"}

    host = tokens[i]
    remote_tokens = tokens[i + 1:]
    remote = " ".join(remote_tokens)

    result = {"is_ssh": True, "host": host, "remote": remote}
    if ssh_start > 0:
        result["local_prefix"] = " ".join(tokens[:ssh_start])
    return result


if __name__ == "__main__":
    cmd = sys.stdin.read()
    sys.stdout.write(json.dumps(parse(cmd), ensure_ascii=False))
