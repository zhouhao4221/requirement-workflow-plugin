#!/usr/bin/env python3
"""
check-remote.py — 校验 SSH 远程命令：白名单 + 写操作。

输入：stdin 读取 remote command 字符串（已由 parse-ssh.py 提取）
环境变量：
  DIAG_SESSION_ID  若设置，则开启 tmp 白名单（受限 mktemp / tee -a / rm）
                   允许的路径前缀：/tmp/claude-diag-<session>-

输出：stdout JSON {
    whitelist: {allowed: bool, violations: [{verb, context}]},
    write: {
        allowed: bool,
        violations: [{kind, token, context}],
        tmp_paths: [str],
        tmp_allowed_verbs: [str],
        docker_containers: [str],
        db_queries: [str],
    }
}

特殊段类型（优先级依次检测）：
  tmp        — mktemp/tee -a/rm 操作 /tmp/claude-diag-<session>-* 路径（需 DIAG_SESSION_ID）
  docker_exec— docker exec <container> <readonly_cmd>（inner_cmd 再过白名单+写检测）
  db_readonly— mysql/psql/sqlite3/clickhouse-client 执行只读 SQL（SELECT/SHOW/DESCRIBE/EXPLAIN/WITH）
  normal     — 普通段，走标准白名单检测
  denied     — 解析失败或检测不通过的 docker/db 段
"""
import os
import sys
import json
import re
import shlex

# ──────────────────────────────────────────────
# 白名单 / 黑名单动词
# ──────────────────────────────────────────────
WHITELIST_VERBS = {
    "tail", "head", "cat", "grep", "egrep", "fgrep", "zgrep",
    "awk", "gawk", "sed", "less", "more", "wc", "find", "ls",
    "ps", "df", "du", "free", "uptime", "stat", "readlink",
    "file", "echo", "printf", "true", "false", "id", "hostname",
    "date", "which", "whereis", "type", "env", "pwd", "sort",
    "uniq", "cut", "tr", "nl", "rev", "tac", "zcat", "xxd",
    "hexdump", "md5sum", "sha256sum", "basename", "dirname",
    "history",
}

BLACKLIST_VERBS = {
    "rm", "mv", "cp", "chmod", "chown", "chattr", "truncate", "dd",
    "mkfs", "wipefs", "kill", "pkill", "killall", "tee", "touch",
    "ln", "mkdir", "rmdir", "install", "shred", "unlink",
}

TMP_WHITELIST_VERBS = {"mktemp", "tee", "rm"}

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


# ──────────────────────────────────────────────
# Tmp 白名单
# ──────────────────────────────────────────────

def tmp_path_prefix():
    sid = os.environ.get("DIAG_SESSION_ID", "").strip()
    if not sid:
        return None
    if not re.fullmatch(r'[A-Za-z0-9-]{4,64}', sid):
        return None
    return f"/tmp/claude-diag-{sid}-"


def is_tmp_path(token, prefix):
    return bool(prefix and token and token.startswith(prefix))


def check_tmp_segment(seg, prefix):
    """返回 (ok, reason, paths)"""
    if not prefix:
        return False, "tmp whitelist disabled (no DIAG_SESSION_ID)", []
    verb = seg[0].rsplit("/", 1)[-1]
    args = seg[1:]
    paths = []

    if verb == "mktemp":
        for a in args:
            if a.startswith("-"):
                return False, f"mktemp options disallowed: {a}", []
            if not is_tmp_path(a, prefix):
                return False, f"mktemp target not in tmp whitelist: {a}", []
            paths.append(a)
        if not paths:
            return False, "mktemp requires explicit template under tmp prefix", []
        return True, None, paths

    if verb == "tee":
        has_append = False
        for a in args:
            if a in ("-a", "--append"):
                has_append = True
                continue
            if a.startswith("-"):
                return False, f"tee only allows -a/--append, got: {a}", []
            if not is_tmp_path(a, prefix):
                return False, f"tee target not in tmp whitelist: {a}", []
            paths.append(a)
        if not has_append:
            return False, "tee must use -a (naked tee overwrites)", []
        if not paths:
            return False, "tee needs at least one tmp target", []
        return True, None, paths

    if verb == "rm":
        for a in args:
            if a == "-f":
                continue
            if a.startswith("-"):
                return False, f"rm only allows -f (no recursive/interactive flags): {a}", []
            if not is_tmp_path(a, prefix):
                return False, f"rm target not in tmp whitelist: {a}", []
            paths.append(a)
        if not paths:
            return False, "rm needs at least one tmp target", []
        return True, None, paths

    return False, f"verb not tmp-whitelisted: {verb}", []


# ──────────────────────────────────────────────
# Docker exec 解析
# ──────────────────────────────────────────────

# 允许的 flag 选项（无值）
_DOCKER_EXEC_FLAGS = {'-i', '-t', '-it', '-ti', '--interactive', '--tty', '--no-tty'}
# 允许的带值选项
_DOCKER_EXEC_VALUE_OPTS = {'-e', '--env', '-u', '--user', '-w', '--workdir'}
# 明确拒绝的选项
_DOCKER_EXEC_DENIED = {
    '-d', '--detach', '--privileged',
    '--cap-add', '--cap-drop',
    '--device', '--pid', '--network',
}


def parse_docker_exec(after_exec_tokens):
    """
    解析 docker exec 之后的参数，提取 (container_name, inner_tokens, error)。
    after_exec_tokens: seg[2:]（已去掉 'docker', 'exec'）
    """
    i = 0
    toks = after_exec_tokens
    while i < len(toks):
        tok = toks[i]

        if tok in _DOCKER_EXEC_DENIED:
            return None, None, f"docker exec option not allowed: {tok}"

        # --option=value 形式
        if tok.startswith('--') and '=' in tok:
            key = tok.split('=', 1)[0]
            if key in _DOCKER_EXEC_DENIED:
                return None, None, f"docker exec option not allowed: {tok}"
            i += 1
            continue

        if tok in _DOCKER_EXEC_FLAGS:
            i += 1
            continue

        if tok in _DOCKER_EXEC_VALUE_OPTS:
            i += 2   # 跳过选项和它的值
            continue

        # 短选项组合（如 -it）
        if tok.startswith('-') and not tok.startswith('--') and len(tok) > 1:
            for c in tok[1:]:
                if f'-{c}' in _DOCKER_EXEC_DENIED:
                    return None, None, f"docker exec option not allowed: -{c}"
                if f'-{c}' not in _DOCKER_EXEC_FLAGS and c not in ('i', 't'):
                    return None, None, f"docker exec option not recognized: -{c}"
            i += 1
            continue

        # 第一个非选项 token = 容器名
        container = tok
        inner = toks[i + 1:]
        if not inner:
            return None, None, "docker exec: no command after container name"
        return container, list(inner), None

    return None, None, "docker exec: no container name found"


# ──────────────────────────────────────────────
# DB 只读解析
# ──────────────────────────────────────────────

DB_READONLY_CLIENTS = {'mysql', 'psql', 'sqlite3', 'clickhouse-client', 'clickhouse'}

# 各客户端的"接收 SQL 语句"的命令行选项
_DB_QUERY_OPTS = {
    'mysql':              {'-e', '--execute'},
    'psql':               {'-c', '--command'},
    'sqlite3':            None,   # positional：sqlite3 db.sqlite "SELECT ..."
    'clickhouse-client':  {'-q', '--query'},
    'clickhouse':         {'-q', '--query'},
}

_READONLY_SQL_RE = re.compile(
    r'^\s*(SELECT\b|SHOW\b|DESCRIBE\b|DESC\b|EXPLAIN\b|ANALYZE\b|WITH\s+\w|PRAGMA\b)',
    re.I,
)
_WRITE_SQL_RE = re.compile(
    r'\b(INSERT\s+INTO|UPDATE\s+\w|DELETE\s+FROM|DROP\s+|ALTER\s+|CREATE\s+'
    r'|TRUNCATE\s+|REPLACE\s+INTO|GRANT\s+|REVOKE\s+|FLUSH\b'
    r'|SET\s+(?:GLOBAL|SESSION|PASSWORD|NAMES))\b',
    re.I,
)


def extract_db_query(seg):
    """从 DB 命令参数中提取 SQL 字符串，返回 (query, error)"""
    verb = seg[0].rsplit("/", 1)[-1]
    args = seg[1:]
    opts = _DB_QUERY_OPTS.get(verb)

    if opts is None:
        # positional：取最后一个不像文件路径的 token
        for a in reversed(args):
            if not a.startswith('-') and not re.search(r'\.(db|sqlite|sqlite3)$', a):
                return a, None
        return None, "no SQL found in positional args"

    i = 0
    while i < len(args):
        a = args[i]
        if a in opts:
            if i + 1 < len(args):
                return args[i + 1], None
            return None, f"option {a} requires a value"
        for opt in opts:
            if a.startswith(f"{opt}="):
                return a.split('=', 1)[1], None
        i += 1

    return None, f"no query option ({'/'.join(sorted(opts))}) found — add -e / -c / --query etc."


def check_db_readonly(query):
    """返回 (ok, violation_msg)"""
    if not query or not query.strip():
        return False, "empty query"
    m = _WRITE_SQL_RE.search(query)
    if m:
        return False, f"SQL contains write keyword: {m.group(0)!r}"
    if not _READONLY_SQL_RE.match(query):
        preview = query[:60].replace('\n', ' ')
        return False, (
            f"SQL does not start with a read-only keyword "
            f"(SELECT/SHOW/DESCRIBE/EXPLAIN/WITH/ANALYZE/PRAGMA): {preview!r}"
        )
    return True, None


# ──────────────────────────────────────────────
# Tokenize / segment
# ──────────────────────────────────────────────

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


# ──────────────────────────────────────────────
# Classify segments
# ──────────────────────────────────────────────
# type 枚举：
#   'tmp'         — tmp 白名单放行
#   'docker_exec' — docker exec 放行，inner_seg 需递归检查
#   'db_readonly' — DB 只读查询放行
#   'denied'      — docker/db 解析或检测失败
#   'normal'      — 普通段，走标准检测

def classify_segments(segments, prefix):
    """
    返回 list of (seg, type, meta_dict)
    meta_dict 字段因 type 而异：
      tmp:         paths, verbs
      docker_exec: container, inner_seg
      db_readonly: query (preview)
      denied:      error, verb
      normal:      {}
    """
    out = []
    for seg in segments:
        if not seg:
            out.append((seg, 'normal', {}))
            continue

        verb = seg[0].rsplit("/", 1)[-1]

        # 1. Tmp 白名单
        if verb in TMP_WHITELIST_VERBS and prefix:
            ok, reason, paths = check_tmp_segment(seg, prefix)
            if ok:
                out.append((seg, 'tmp', {'paths': paths, 'verbs': [verb]}))
                continue
            # 不合规的 tmp 动词降回 denied（写动词在黑名单里，让 write-guard 拦）
            out.append((seg, 'denied', {'error': reason, 'verb': verb}))
            continue

        # 2. Docker exec
        if verb == 'docker' and len(seg) > 2 and seg[1] == 'exec':
            container, inner, err = parse_docker_exec(seg[2:])
            if err:
                out.append((seg, 'denied', {'error': err, 'verb': 'docker exec'}))
            else:
                out.append((seg, 'docker_exec', {'container': container, 'inner_seg': inner}))
            continue

        # 3. DB 只读
        if verb in DB_READONLY_CLIENTS:
            query, err = extract_db_query(seg)
            if err:
                out.append((seg, 'denied', {'error': err, 'verb': verb}))
            else:
                ok, reason = check_db_readonly(query)
                if ok:
                    out.append((seg, 'db_readonly', {'query': query[:120]}))
                else:
                    out.append((seg, 'denied', {'error': reason, 'verb': verb}))
            continue

        # 4. Normal
        out.append((seg, 'normal', {}))

    return out


# ──────────────────────────────────────────────
# Whitelist check
# ──────────────────────────────────────────────

def check_whitelist(classified):
    violations = []
    for seg, seg_type, meta in classified:
        if not seg:
            continue

        if seg_type in ('tmp', 'db_readonly'):
            continue  # 已专项验证，放行

        if seg_type == 'docker_exec':
            # docker 本身放行；inner_seg 需要过白名单
            inner = meta.get('inner_seg', [])
            if inner:
                inner_verb = inner[0].rsplit("/", 1)[-1]
                if inner_verb not in WHITELIST_VERBS:
                    violations.append({
                        "verb": f"docker exec → {inner_verb}",
                        "context": " ".join(inner[:5]),
                    })
            continue

        if seg_type == 'denied':
            violations.append({
                "verb": meta.get('verb', seg[0] if seg else '?'),
                "context": meta.get('error', ''),
            })
            continue

        # normal
        verb = seg[0].rsplit("/", 1)[-1]
        if verb not in WHITELIST_VERBS:
            violations.append({"verb": verb, "context": " ".join(seg[:5])})

    return violations


# ──────────────────────────────────────────────
# Write check
# ──────────────────────────────────────────────

def check_writes(tokens, classified, original_cmd):
    violations = []

    # 裸重定向：无论任何类型都禁止
    for i, t in enumerate(tokens):
        if t in REDIRECT_TOKENS:
            violations.append({
                "kind": "redirect",
                "token": t,
                "context": " ".join(tokens[max(0, i - 2): i + 3]),
            })

    # 黑名单动词：tmp/db_readonly/docker_exec 放行，denied/normal 正常检测
    for seg, seg_type, meta in classified:
        if not seg or seg_type in ('tmp', 'db_readonly', 'docker_exec', 'denied'):
            continue
        verb = seg[0].rsplit("/", 1)[-1]
        if verb in BLACKLIST_VERBS:
            violations.append({
                "kind": "write_verb",
                "token": verb,
                "context": " ".join(seg[:5]),
            })

    # docker exec inner_seg 的写检测
    for seg, seg_type, meta in classified:
        if seg_type != 'docker_exec':
            continue
        inner = meta.get('inner_seg', [])
        if inner:
            inner_verb = inner[0].rsplit("/", 1)[-1]
            if inner_verb in BLACKLIST_VERBS:
                violations.append({
                    "kind": "write_verb",
                    "token": f"docker exec → {inner_verb}",
                    "context": " ".join(inner[:5]),
                })

    # 正则模式：db_write 正则只对非 db_readonly 段有效
    has_db_readonly = any(t == 'db_readonly' for _, t, _ in classified)
    for kind, pat in DANGEROUS_PATTERNS:
        if kind == 'db_write' and has_db_readonly:
            # DB 客户端段已通过只读检测，跳过 db_write 正则避免误报
            continue
        for m in pat.finditer(original_cmd):
            violations.append({
                "kind": kind,
                "token": m.group(0),
                "context": original_cmd[max(0, m.start() - 10): m.end() + 10],
            })

    return violations


# ──────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────

def main():
    cmd = sys.stdin.read()
    if not cmd.strip():
        print(json.dumps({
            "whitelist": {"allowed": True, "violations": []},
            "write": {
                "allowed": True, "violations": [],
                "tmp_paths": [], "tmp_allowed_verbs": [],
                "docker_containers": [], "db_queries": [],
            },
        }))
        return

    tokens, err = tokenize(cmd)
    if err:
        msg = f"parse error: {err}"
        print(json.dumps({
            "whitelist": {"allowed": False, "violations": [{"verb": "", "context": msg}]},
            "write": {
                "allowed": False,
                "violations": [{"kind": "parse_error", "token": "", "context": err}],
                "tmp_paths": [], "tmp_allowed_verbs": [],
                "docker_containers": [], "db_queries": [],
            },
        }, ensure_ascii=False))
        return

    prefix = tmp_path_prefix()
    segments = split_segments(tokens)
    classified = classify_segments(segments, prefix)

    # 收集审计字段
    tmp_paths, tmp_verbs, docker_containers, db_queries = [], set(), [], []
    for seg, seg_type, meta in classified:
        if seg_type == 'tmp':
            tmp_paths.extend(meta.get('paths', []))
            tmp_verbs.update(meta.get('verbs', []))
        elif seg_type == 'docker_exec':
            docker_containers.append(meta.get('container', ''))
        elif seg_type == 'db_readonly':
            db_queries.append(meta.get('query', ''))

    whitelist_violations = check_whitelist(classified)
    write_violations = check_writes(tokens, classified, cmd)

    print(json.dumps({
        "whitelist": {
            "allowed": len(whitelist_violations) == 0,
            "violations": whitelist_violations,
        },
        "write": {
            "allowed": len(write_violations) == 0,
            "violations": write_violations,
            "tmp_paths": tmp_paths,
            "tmp_allowed_verbs": sorted(tmp_verbs),
            "docker_containers": docker_containers,
            "db_queries": db_queries,
        },
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
