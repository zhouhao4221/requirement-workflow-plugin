#!/bin/bash
# validate-hooks.sh — PreToolUse Bash Hook（首次调用校验完整性）
# 确保 Diag 所有 Hook 已注册且可执行，防止被人为禁用

INPUT=$(cat)
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

# 只对 Bash 工具中的 ssh 命令做校验（其他 bash 不触发，节约开销）
CMD=$(diag_read_command "$INPUT")
if [ -z "$CMD" ]; then
    exit 0
fi

# 会话内只校验一次（marker 按 session + pid 隔离）
SESSION="${CLAUDE_SESSION_ID:-unknown}"
MARKER="/tmp/diag-validated-${SESSION}-$$"
if [ -f "$MARKER" ]; then
    exit 0
fi

HOOKS_DIR="$DIAG_PLUGIN_ROOT/hooks"
REQUIRED_HOOKS=(
    "sensitive-input-guard.sh"
    "host-whitelist.sh"
    "command-whitelist.sh"
    "write-guard.sh"
    "audit-log.sh"
)

MISSING=()
for h in "${REQUIRED_HOOKS[@]}"; do
    if [ ! -x "$HOOKS_DIR/$h" ]; then
        MISSING+=("$h(不可执行或缺失)")
    fi
done

if [ "${#MISSING[@]}" -gt 0 ]; then
    diag_deny "Diag 风控 Hook 完整性校验失败：$(IFS=,; echo "${MISSING[*]}")。请检查 plugins/diag/hooks/ 目录和文件权限。"
fi

HOOKS_JSON="$HOOKS_DIR/hooks.json"
if [ ! -f "$HOOKS_JSON" ]; then
    diag_deny "Diag hooks.json 未找到：$HOOKS_JSON"
fi

for h in "${REQUIRED_HOOKS[@]}"; do
    if ! grep -q "$h" "$HOOKS_JSON"; then
        diag_deny "Hook $h 未在 hooks.json 中注册，风控链可能被绕过。"
    fi
done

touch "$MARKER" 2>/dev/null || true
exit 0
