#!/bin/bash
# command-whitelist.sh — PreToolUse Bash Hook
# SSH 远程命令的动词必须在白名单内

INPUT=$(cat)
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

CMD=$(diag_read_command "$INPUT")
[ -z "$CMD" ] && exit 0

PARSED=$(diag_parse_ssh "$CMD")
diag_is_ssh "$PARSED" || exit 0

REMOTE=$(diag_ssh_remote "$PARSED")

# 空远程命令 = 交互式登录，禁止
if [ -z "$REMOTE" ]; then
    diag_deny "SSH 交互式登录被拒绝。Diag 插件只允许带明确只读命令的 ssh 调用（如 ssh host tail -n 100 file）。"
fi

DIAG_SESSION=$(diag_read_session)
RESULT=$(printf '%s' "$REMOTE" | DIAG_SESSION_ID="$DIAG_SESSION" python3 "$DIAG_PLUGIN_ROOT/scripts/check-remote.py")
ALLOWED=$(echo "$RESULT" | jq -r '.whitelist.allowed // false')

if [ "$ALLOWED" = "true" ]; then
    exit 0
fi

VIOLATIONS=$(echo "$RESULT" | jq -r '.whitelist.violations | map("\(.verb)  (context: \(.context))") | join("; ")')
diag_deny "SSH 远程命令含非白名单动词：${VIOLATIONS}。白名单包含 tail/head/cat/grep/awk/sed/less/wc/find/ls/ps/df/free/uptime/stat/readlink/file/echo/sort/uniq/cut/tr 等只读命令；/diag:diagnose 会话内额外允许 mktemp / tee -a / rm 操作 /tmp/claude-diag-<session>-* 路径。"
