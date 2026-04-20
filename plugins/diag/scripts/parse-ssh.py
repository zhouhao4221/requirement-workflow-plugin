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

    ssh_seg = None
    for seg in segments:
        if seg and seg[0] == "ssh":
            ssh_seg = seg
            break

    if ssh_seg is None:
        return {"is_ssh": False}

    tokens = ssh_seg
    i = 1  # skip "ssh"
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

    return {"is_ssh": True, "host": host, "remote": remote}


if __name__ == "__main__":
    cmd = sys.stdin.read()
    sys.stdout.write(json.dumps(parse(cmd), ensure_ascii=False))
