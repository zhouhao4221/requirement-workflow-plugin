#!/bin/bash
# confirm-before-write.sh
# PreToolUse Hook：在写入需求文档前弹出原生确认对话框
#
# 拦截 Write/Edit 工具对以下文件的操作：
# - docs/requirements/active/REQ-*.md
# - docs/requirements/active/QUICK-*.md
# - docs/requirements/completed/REQ-*.md
# - docs/requirements/completed/QUICK-*.md
# - docs/requirements/PRD.md
# - docs/requirements/modules/*.md
# - docs/requirements/templates/*.md（模板覆盖）
# - docs/changelogs/*.md（版本说明覆盖）
#
# 输出 permissionDecision: "ask" 触发 Claude Code 原生确认

INPUT=$(cat)

# 从 JSON 输入中提取文件路径
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ]; then
    exit 0
fi

# 提取文件名
FILENAME=$(basename "$FILE_PATH")

# 检查是否为需求相关文件
IS_REQ=false

# 需求文档 (REQ-XXX / QUICK-XXX)
if [[ "$FILE_PATH" =~ docs/requirements/ ]]; then
    if [[ "$FILENAME" =~ ^REQ-[0-9]+ ]] || [[ "$FILENAME" =~ ^QUICK-[0-9]+ ]]; then
        IS_REQ=true
        REASON="即将写入需求文档: $FILENAME"
    elif [[ "$FILENAME" == "PRD.md" ]]; then
        IS_REQ=true
        REASON="即将写入 PRD 文档"
    elif [[ "$FILE_PATH" =~ docs/requirements/modules/ ]]; then
        IS_REQ=true
        REASON="即将写入模块文档: $FILENAME"
    elif [[ "$FILE_PATH" =~ docs/requirements/templates/ ]]; then
        IS_REQ=true
        REASON="即将覆盖模板文件: $FILENAME"
    fi
fi

# 版本说明文件（changelog 覆盖已有文件时）
if [[ "$FILE_PATH" =~ docs/changelogs/ ]] && [ -f "$FILE_PATH" ]; then
    IS_REQ=true
    REASON="即将覆盖已有版本说明: $FILENAME"
fi

if [ "$IS_REQ" = true ]; then
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
