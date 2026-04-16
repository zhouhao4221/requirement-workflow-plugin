#!/bin/bash
# confirm-before-commit.sh
# PreToolUse Hook：拦截 Bash 工具中的关键操作，弹出原生确认对话框
#
# 拦截场景：
# 1. git commit — 提交代码
# 2. mv/rm 需求文件 — 归档/删除需求文档（done、upgrade 命令）
# 3. docker/docker-compose — 启动测试环境
#
# 输出 permissionDecision: "ask" 触发 Claude Code 原生确认

INPUT=$(cat)

# 从 JSON 输入中提取命令
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$COMMAND" ]; then
    exit 0
fi

# --auto 模式放行：项目内存在 .claude/.req-auto 且 mtime 在 10 分钟内
# 由 /req:fix --auto（未来可能还有其他命令）在流程开始时创建、结束时清理
# TTL 10 分钟用于防止异常退出后残留标记长期放行
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
[ -z "$CWD" ] && CWD=$(pwd)
MARKER="$CWD/.claude/.req-auto"
if [ -f "$MARKER" ]; then
    NOW=$(date +%s)
    # macOS: stat -f %m; Linux: stat -c %Y
    MTIME=$(stat -f %m "$MARKER" 2>/dev/null || stat -c %Y "$MARKER" 2>/dev/null)
    if [ -n "$MTIME" ] && [ $((NOW - MTIME)) -lt 600 ]; then
        exit 0
    fi
fi

REASON=""

# 1. git commit
if echo "$COMMAND" | grep -qE '^\s*git\s+commit\b'; then
    REASON="即将执行 git commit，请确认提交内容"

# 2. mv 需求文件（done 归档、upgrade 归档）
elif echo "$COMMAND" | grep -qE '\bmv\b.*\b(REQ-|QUICK-).*\.md'; then
    REASON="即将移动需求文档（归档操作）"

# 3. rm 需求文件（upgrade 删除）
elif echo "$COMMAND" | grep -qE '\brm\b.*\b(REQ-|QUICK-).*\.md'; then
    REASON="即将删除需求文档（不可逆操作）"

# 4. git commit 在链式命令中（如 git add && git commit）
elif echo "$COMMAND" | grep -qE '\bgit\s+commit\b'; then
    REASON="即将执行 git commit，请确认提交内容"
fi

if [ -n "$REASON" ]; then
    jq -n --arg reason "$REASON" '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "ask",
            permissionDecisionReason: $reason
        }
    }'
else
    exit 0
fi
