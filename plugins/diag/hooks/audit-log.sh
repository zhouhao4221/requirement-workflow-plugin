#!/bin/bash
# audit-log.sh — PostToolUse Bash Hook
# 将 SSH 命令的执行结果记录到 JSONL 审计日志（按日切分，保留 30 天）
# 只记录 ssh 命令，忽略本地 bash

INPUT=$(cat)
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

CMD=$(diag_read_command "$INPUT")
[ -z "$CMD" ] && exit 0

PARSED=$(diag_parse_ssh "$CMD")
diag_is_ssh "$PARSED" || exit 0

HOST=$(diag_ssh_host "$PARSED")
STDOUT=$(printf '%s' "$INPUT" | jq -r '.tool_response.stdout // ""')
EXIT_CODE=$(printf '%s' "$INPUT" | jq -r '.tool_response.exit_code // -1')

# stdout 不落全文，只留哈希（审计可追溯但无敏感泄漏）
if [ -n "$STDOUT" ]; then
    SNIPPET_HASH=$(printf '%s' "$STDOUT" | shasum -a 256 | awk '{print $1}')
    SNIPPET_LEN=${#STDOUT}
else
    SNIPPET_HASH=""
    SNIPPET_LEN=0
fi

AUDIT_DIR="${DIAG_HOME:-$HOME/.claude-diag}/audit"
mkdir -p "$AUDIT_DIR"

DATE=$(date '+%Y-%m-%d')
AUDIT_FILE="$AUDIT_DIR/command_audit-$DATE.jsonl"

# host → service 反查
SERVICE=""
if diag_config_exists; then
    SERVICE=$(_diag_yaml_to_json "$SERVICES_FILE" 2>/dev/null | \
        jq -r --arg h "$HOST" '(.services // []) | map(select(.host == $h)) | .[0].name // ""')
fi

jq -cn \
    --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --arg host "$HOST" \
    --arg service "$SERVICE" \
    --arg cmd "$CMD" \
    --arg hash "$SNIPPET_HASH" \
    --arg op "$(whoami)" \
    --arg sid "${CLAUDE_SESSION_ID:-}" \
    --argjson exit "$EXIT_CODE" \
    --argjson slen "$SNIPPET_LEN" \
    '{
        timestamp: $ts,
        session_id: $sid,
        operator: $op,
        host: $host,
        service: $service,
        command: $cmd,
        exit_code: $exit,
        stdout_length: $slen,
        log_snippet_hash: $hash,
        hooks_passed: ["validate-hooks", "host-whitelist", "command-whitelist", "write-guard"]
    }' >> "$AUDIT_FILE" 2>/dev/null

# 30 天清理
find "$AUDIT_DIR" -name 'command_audit-*.jsonl' -mtime +30 -delete 2>/dev/null

exit 0
