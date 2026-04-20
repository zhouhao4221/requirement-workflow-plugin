#!/usr/bin/env python3
"""
check-remote.py — 校验 SSH 远程命令：白名单 + 写操作。

输入：stdin 读取 remote command 字符串（已由 parse-ssh.py 提取）
输出：stdout JSON {
    whitelist: {allowed: bool, violations: [{verb, context}]},
    write: {allowed: bool, violations: [{kind, token, context}]}
}
"""
import sys
import json
import re
import shlex

WHITELIST_VERBS = {
    "tail", "head", "cat", "grep", "egrep", "fgrep", "zgrep",
    "awk", "gawk", "sed", "less", "more", "wc", "find", "ls",
    "ps", "df", "du", "free", "uptime", "stat", "readlink",
    "file", "echo", "printf", "true", "false", "id", "hostname",
    "date", "which", "whereis", "type", "env", "pwd", "sort",
    "uniq", "cut", "tr", "nl", "rev", "tac", "zcat", "xxd",
    "hexdump", "md5sum", "sha256sum", "basename", "dirname",
    "history",  # 只读查看，不带 -c
}

BLACKLIST_VERBS = {
    "rm", "mv", "cp", "chmod", "chown", "chattr", "truncate", "dd",
    "mkfs", "wipefs", "kill", "pkill", "killall", "tee", "touch",
    "ln", "mkdir", "rmdir", "install", "shred", "unlink",
}

REDIRECT_TOKENS = {">", ">>", ">|", "<>", "|&"}
SEPARATOR_TOKENS = {"|", "||", "&&", ";", "&"}

DANGEROUS_PATTERNS = [
    ("service_control",
     re.compile(r'\b(systemctl|service|/etc/init\.d/\S+)\s+(start|stop|restart|reload|enable|disable|mask|unmask)\b', re.I)),
    ("docker_write",
     re.compile(r'\bdocker\s+(run|stop|rm\b|rmi|kill|system\s+prune|container\s+(rm|stop|kill|prune)|image\s+rm|network\s+rm|volume\s+rm|build|pull|push|tag)\b')),
    ("kubectl_write",
     re.compile(r'\bkubectl\s+(apply|delete|patch|scale|create|replace|rollout|drain|cordon|uncordon|taint)\b')),
    ("package_mgmt",
     re.compile(r'\b(apt|apt-get|yum|dnf|pacman|brew|zypper|apk|pip|pip3|npm|gem|cargo)\s+(install|remove|uninstall|upgrade|update|purge|autoremove|dist-upgrade)\b')),
    ("iptables",
     re.compile(r'\biptables\s+-[ADIRSFXZPN]\b')),
    ("sysctl_write",
     re.compile(r'\bsysctl\s+-w\b')),
    ("ip_route_write",
     re.compile(r'\bip\s+(route|addr|link)\s+(add|del|change|replace|flush)\b')),
    ("find_write",
     re.compile(r'\bfind\b[^|;&]*-(delete|exec|execdir|ok|okdir)\b')),
    ("db_write",
     re.compile(r'\b(mysql|psql|mongo|sqlite3|redis-cli)\b[^|;&]*\b(INSERT|UPDATE|DELETE|DROP|ALTER|CREATE|TRUNCATE|REPLACE|GRANT|REVOKE|FLUSHDB|FLUSHALL|RENAME|SET)\b', re.I)),
    ("privilege_escalation",
     re.compile(r'\b(sudo|su)\b')),
    ("crontab_write",
     re.compile(r'\bcrontab\s+-[er]\b')),
    ("history_clear",
     re.compile(r'\bhistory\s+-c\b')),
    ("curl_post",
     re.compile(r'\bcurl\b[^|;&]*(-X\s+(POST|PUT|DELETE|PATCH)|--request\s+(POST|PUT|DELETE|PATCH)|-d\s|--data|-T\s|--upload-file)\b', re.I)),
    ("wget_post",
     re.compile(r'\bwget\b[^|;&]*(--post-data|--method=(POST|PUT|DELETE))\b', re.I)),
]


def tokenize(cmd: str):
    try:
        lex = shlex.shlex(cmd, posix=True, punctuation_chars="|&;<>")
        lex.whitespace_split = True
        return list(lex), None
    except ValueError as e:
        return [], str(e)


def split_segments(tokens):
    segs, cur = [], []
    for t in tokens:
        if t in SEPARATOR_TOKENS:
            if cur:
                segs.append(cur)
                cur = []
        else:
            cur.append(t)
    if cur:
        segs.append(cur)
    return segs


def check_whitelist(segments):
    violations = []
    for seg in segments:
        if not seg:
            continue
        verb = seg[0].rsplit("/", 1)[-1]
        if verb not in WHITELIST_VERBS:
            violations.append({
                "verb": verb,
                "context": " ".join(seg[:5]),
            })
    return violations


def check_writes(tokens, segments, original_cmd):
    violations = []

    # Redirect tokens（punctuation_chars 下会独立 token）
    for i, t in enumerate(tokens):
        if t in REDIRECT_TOKENS:
            violations.append({
                "kind": "redirect",
                "token": t,
                "context": " ".join(tokens[max(0, i - 2): i + 3]),
            })

    # Blacklist verbs per segment
    for seg in segments:
        if not seg:
            continue
        verb = seg[0].rsplit("/", 1)[-1]
        if verb in BLACKLIST_VERBS:
            violations.append({
                "kind": "write_verb",
                "token": verb,
                "context": " ".join(seg[:5]),
            })

    # Regex patterns（在原始字符串上匹配，避免 tokenize 改变语义）
    for kind, pat in DANGEROUS_PATTERNS:
        for m in pat.finditer(original_cmd):
            violations.append({
                "kind": kind,
                "token": m.group(0),
                "context": original_cmd[max(0, m.start() - 10): m.end() + 10],
            })

    return violations


def main():
    cmd = sys.stdin.read()
    if not cmd.strip():
        print(json.dumps({
            "whitelist": {"allowed": True, "violations": []},
            "write": {"allowed": True, "violations": []},
        }))
        return

    tokens, err = tokenize(cmd)
    if err:
        # 无法 tokenize → 保守拒绝
        print(json.dumps({
            "whitelist": {"allowed": False, "violations": [{"verb": "", "context": f"parse error: {err}"}]},
            "write": {"allowed": False, "violations": [{"kind": "parse_error", "token": "", "context": err}]},
        }, ensure_ascii=False))
        return

    segments = split_segments(tokens)
    whitelist_violations = check_whitelist(segments)
    write_violations = check_writes(tokens, segments, cmd)

    print(json.dumps({
        "whitelist": {"allowed": len(whitelist_violations) == 0, "violations": whitelist_violations},
        "write": {"allowed": len(write_violations) == 0, "violations": write_violations},
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
