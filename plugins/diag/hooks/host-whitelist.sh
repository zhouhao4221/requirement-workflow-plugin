#!/bin/bash
# host-whitelist.sh — PreToolUse Bash Hook
# SSH 目标主机必须在 ~/.claude-diag/config/services.yaml 中登记，否则阻断

INPUT=$(cat)
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

CMD=$(diag_read_command "$INPUT")
[ -z "$CMD" ] && exit 0

PARSED=$(diag_parse_ssh "$CMD")
diag_is_ssh "$PARSED" || exit 0

HOST=$(diag_ssh_host "$PARSED")
if [ -z "$HOST" ]; then
    diag_deny "SSH 命令未能识别目标主机，已阻断。"
fi

# 配置未初始化 → 拒绝所有 SSH（显式比默认放行更安全）
if ! diag_config_exists; then
    diag_deny "服务清单未初始化（$SERVICES_FILE 不存在）。请先执行 /diag:init。"
fi

if diag_host_in_whitelist "$HOST"; then
    exit 0
fi

WHITELIST=$(diag_list_hosts | paste -sd ',' -)
diag_deny "SSH 目标主机 '${HOST}' 未在服务清单中登记。已登记：${WHITELIST:-（空）}。请在 ~/.claude-diag/config/services.yaml 中添加，或修改当前命令。"
