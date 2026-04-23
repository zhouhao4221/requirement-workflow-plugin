#!/bin/bash
# write-guard.sh — PreToolUse Bash Hook
# 阻断 SSH 远程命令中的写操作（重定向、写类动词、服务控制、包管理、DB 写等）

INPUT=$(cat)
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

CMD=$(diag_read_command "$INPUT")
[ -z "$CMD" ] && exit 0

# 独立于 SSH 的本地提权阻断：防止 `sudo ssh ...` / `su -c ssh ...` 等
# 以本地提升权限执行，无论后续 ssh 是否被识别
if echo "$CMD" | grep -qE '^[[:space:]]*(sudo|su|doas|chroot|unshare|nsenter)([[:space:]]|$)'; then
    diag_deny "本地命令以提权工具开头（sudo / su / doas / chroot / unshare / nsenter），已阻断。Diag 插件禁止提权执行。"
fi

PARSED=$(diag_parse_ssh "$CMD")
diag_is_ssh "$PARSED" || exit 0

REMOTE=$(diag_ssh_remote "$PARSED")
[ -z "$REMOTE" ] && exit 0

DIAG_SESSION=$(diag_read_session)
RESULT=$(printf '%s' "$REMOTE" | DIAG_SESSION_ID="$DIAG_SESSION" python3 "$DIAG_PLUGIN_ROOT/scripts/check-remote.py")
WRITE_ALLOWED=$(echo "$RESULT" | jq -r '.write.allowed // false')

if [ "$WRITE_ALLOWED" = "true" ]; then
    # 有特殊放行字段（tmp/docker/db）时写 marker 供 audit-log 补充审计字段
    HAS_EXTRA=$(echo "$RESULT" | jq -r '
        ((.write.tmp_paths | length) > 0) or
        ((.write.docker_containers | length) > 0) or
        ((.write.db_queries | length) > 0)
    ')
    if [ "$HAS_EXTRA" = "true" ] && [ -n "$DIAG_SESSION" ]; then
        RUNTIME_DIR="${DIAG_HOME:-$HOME/.claude-diag}/runtime"
        mkdir -p "$RUNTIME_DIR" 2>/dev/null || true
        KEY=$(printf '%s' "$REMOTE" | shasum -a 256 | awk '{print $1}')
        echo "$RESULT" | jq -c --arg sid "$DIAG_SESSION" '{
            tmp_paths:         .write.tmp_paths,
            tmp_verbs:         .write.tmp_allowed_verbs,
            docker_containers: .write.docker_containers,
            db_queries:        .write.db_queries,
            session:           $sid
        }' > "$RUNTIME_DIR/tmp-${KEY}.json" 2>/dev/null || true
    fi
    exit 0
fi

DETAILS=$(echo "$RESULT" | jq -r '.write.violations | map("\(.kind):[\(.token)]") | join("; ")')
diag_deny "SSH 远程命令含写操作：${DETAILS}。Diag 插件只允许只读命令；如需落临时文件，仅允许在 /diag:diagnose 会话内通过 mktemp / tee -a / rm 操作 /tmp/claude-diag-<session>-* 路径。"
