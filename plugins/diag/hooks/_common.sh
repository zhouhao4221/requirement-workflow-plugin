#!/bin/bash
# _common.sh — Diag Hook 共享函数
#
# 由各 Hook 脚本 source，暴露：
# - diag_read_command：从 Hook stdin JSON 中提取 tool_input.command
# - diag_parse_ssh：解析 ssh 命令 → JSON {is_ssh, host, remote}
# - diag_is_ssh / diag_ssh_host / diag_ssh_remote：便捷取值
# - diag_deny / diag_allow：输出 PreToolUse 决策

# 解析插件根（Claude Code 调用 Hook 时注入 CLAUDE_PLUGIN_ROOT）
DIAG_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# 配置读取（提供 diag_list_hosts / diag_host_in_whitelist 等）
# shellcheck disable=SC1091
source "$DIAG_PLUGIN_ROOT/scripts/services-config.sh"

# 从 Hook stdin JSON 中提取 Bash 命令字符串
diag_read_command() {
    local input="$1"
    printf '%s' "$input" | jq -r '.tool_input.command // empty'
}

# 解析 ssh 命令，返回 JSON
diag_parse_ssh() {
    local cmd="$1"
    printf '%s' "$cmd" | python3 "$DIAG_PLUGIN_ROOT/scripts/parse-ssh.py"
}

diag_is_ssh() {
    local parsed="$1"
    [ "$(echo "$parsed" | jq -r '.is_ssh // false')" = "true" ]
}

diag_ssh_host() {
    local parsed="$1"
    echo "$parsed" | jq -r '.host // empty'
}

diag_ssh_remote() {
    local parsed="$1"
    echo "$parsed" | jq -r '.remote // empty'
}

# 输出 PreToolUse deny 决策（不走"ask"，直接阻断）
diag_deny() {
    local reason="$1"
    jq -n --arg reason "$reason" '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "deny",
            permissionDecisionReason: $reason
        }
    }'
    exit 0
}

# 放行（静默）
diag_allow() {
    exit 0
}

# 记录一条"Hook 通过"标记到 Diag 审计流（供 audit-log.sh 最终归集）
# 参数：hook 名称（如 "host-whitelist"）
diag_mark_passed() {
    local hook="$1"
    local marker_dir="${DIAG_HOME:-$HOME/.claude-diag}/runtime"
    mkdir -p "$marker_dir" 2>/dev/null || return 0
    # 以当前 session + pid 做短效 marker（audit-log.sh 会清理）
    local session="${CLAUDE_SESSION_ID:-unknown}"
    echo "$hook" >> "$marker_dir/${session}-$$.passed" 2>/dev/null || true
}
