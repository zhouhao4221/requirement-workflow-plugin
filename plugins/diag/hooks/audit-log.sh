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

# 读 tmp 白名单 marker（由 write-guard PreToolUse 落盘，以远端命令哈希为 key）
DIAG_SESSION=$(diag_read_session)
REMOTE=$(diag_parse_ssh "$CMD" | jq -r '.remote // empty')
TMP_PATHS="[]"
TMP_VERBS="[]"
DOCKER_CONTAINERS="[]"
DB_QUERIES="[]"
if [ -n "$REMOTE" ] && [ -n "$DIAG_SESSION" ]; then
    KEY=$(printf '%s' "$REMOTE" | shasum -a 256 | awk '{print $1}')
    MARKER="${DIAG_HOME:-$HOME/.claude-diag}/runtime/tmp-${KEY}.json"
    if [ -f "$MARKER" ]; then
        TMP_PATHS=$(jq -c '.tmp_paths // []' "$MARKER")
        TMP_VERBS=$(jq -c '.tmp_verbs // []' "$MARKER")
        DOCKER_CONTAINERS=$(jq -c '.docker_containers // []' "$MARKER")
        DB_QUERIES=$(jq -c '.db_queries // []' "$MARKER")
        rm -f "$MARKER" 2>/dev/null || true
    fi
fi

jq -cn \
    --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --arg host "$HOST" \
    --arg service "$SERVICE" \
    --arg cmd "$CMD" \
    --arg hash "$SNIPPET_HASH" \
    --arg op "$(whoami)" \
    --arg sid "${CLAUDE_SESSION_ID:-}" \
    --arg dsid "$DIAG_SESSION" \
    --argjson exit "$EXIT_CODE" \
    --argjson slen "$SNIPPET_LEN" \
    --argjson tpaths "$TMP_PATHS" \
    --argjson tverbs "$TMP_VERBS" \
    --argjson dcontainers "$DOCKER_CONTAINERS" \
    --argjson dqueries "$DB_QUERIES" \
    '{
        timestamp: $ts,
        session_id: $sid,
        diag_session_id: $dsid,
        operator: $op,
        host: $host,
        service: $service,
        command: $cmd,
        exit_code: $exit,
        stdout_length: $slen,
        log_snippet_hash: $hash,
        tmp_write:     (if ($tpaths | length) > 0 then {paths: $tpaths, verbs: $tverbs} else null end),
        docker_exec:   (if ($dcontainers | length) > 0 then {containers: $dcontainers} else null end),
        db_readonly:   (if ($dqueries | length) > 0 then {queries: $dqueries} else null end),
        hooks_passed: ["validate-hooks", "host-whitelist", "command-whitelist", "write-guard"]
    }' >> "$AUDIT_FILE" 2>/dev/null

# 30 天清理
find "$AUDIT_DIR" -name 'command_audit-*.jsonl' -mtime +30 -delete 2>/dev/null

exit 0
