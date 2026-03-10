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
