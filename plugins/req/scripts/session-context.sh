#!/bin/bash
# session-context.sh
# SessionStart Hook：在会话启动时自动加载当前需求上下文
#
# 加载内容：
#   1. 项目绑定信息（requirementProject / requirementRole）
#   2. 当前分支名推断出的需求编号
#   3. 对应需求的状态、标题、模块
#   4. 进行中的需求总数
#
# 输出格式：stdout 纯文本，会作为 additionalContext 注入到会话

set -e

# 仅在 git 仓库内执行
if ! git rev-parse --git-dir >/dev/null 2>&1; then
    exit 0
fi

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$REPO_ROOT" ]; then
    exit 0
fi

cd "$REPO_ROOT"

# ============ 1. 读取项目绑定 ============
SETTINGS_FILE=".claude/settings.local.json"
PROJECT_NAME=""
PROJECT_ROLE=""

if [ -f "$SETTINGS_FILE" ] && command -v python3 >/dev/null 2>&1; then
    PROJECT_NAME=$(python3 -c "
import json, sys
try:
    with open('$SETTINGS_FILE') as f:
        d = json.load(f)
    print(d.get('requirementProject', ''))
except Exception:
    pass
" 2>/dev/null)

    PROJECT_ROLE=$(python3 -c "
import json, sys
try:
    with open('$SETTINGS_FILE') as f:
        d = json.load(f)
    print(d.get('requirementRole', ''))
except Exception:
    pass
" 2>/dev/null)
fi

# 未绑定项目，静默退出
if [ -z "$PROJECT_NAME" ]; then
    exit 0
fi

# ============ 2. 当前分支 → 需求编号 ============
BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
REQ_ID=""

if [ -n "$BRANCH" ]; then
    # 匹配 feat/REQ-123-xxx、fix/QUICK-045-xxx 等
    REQ_ID=$(echo "$BRANCH" | grep -oE '(REQ|QUICK)-[0-9]+' | head -1)
fi

# ============ 3. 读取需求文档 ============
REQ_TITLE=""
REQ_STATUS=""
REQ_MODULE=""
REQ_FILE=""

find_req_file() {
    local id="$1"
    # 优先本地
    if [ "$PROJECT_ROLE" != "readonly" ] && [ -d "docs/requirements" ]; then
        local found
        found=$(find docs/requirements/active docs/requirements/completed -maxdepth 1 -type f -name "${id}-*.md" 2>/dev/null | head -1)
        if [ -n "$found" ]; then
            echo "$found"
            return
        fi
    fi
    # 回退缓存
    local cache_dir="$HOME/.claude-requirements/projects/$PROJECT_NAME"
    if [ -d "$cache_dir" ]; then
        local found
        found=$(find "$cache_dir/active" "$cache_dir/completed" -maxdepth 1 -type f -name "${id}-*.md" 2>/dev/null | head -1)
        if [ -n "$found" ]; then
            echo "$found"
            return
        fi
    fi
}

if [ -n "$REQ_ID" ]; then
    REQ_FILE=$(find_req_file "$REQ_ID")
    if [ -n "$REQ_FILE" ] && [ -f "$REQ_FILE" ]; then
        # 提取元信息（兼容 | 状态 | xxx | 或 状态: xxx 两种格式）
        REQ_TITLE=$(grep -m1 '^# ' "$REQ_FILE" | sed 's/^# //' | sed "s/${REQ_ID}[:： ]*//" )
        REQ_STATUS=$(grep -m1 -E '(状态|Status)' "$REQ_FILE" | grep -oE '(草稿|待评审|评审通过|开发中|测试中|已完成|Draft|Review|Approved|InProgress|Testing|Done)' | head -1)
        REQ_MODULE=$(grep -m1 -E '(模块|Module)' "$REQ_FILE" | sed -E 's/.*[:：|][[:space:]]*//' | sed 's/[[:space:]]*|.*//' | head -1)
    fi
fi

# ============ 4. 进行中需求数量 ============
ACTIVE_COUNT=0
if [ "$PROJECT_ROLE" != "readonly" ] && [ -d "docs/requirements/active" ]; then
    ACTIVE_COUNT=$(find docs/requirements/active -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
elif [ -d "$HOME/.claude-requirements/projects/$PROJECT_NAME/active" ]; then
    ACTIVE_COUNT=$(find "$HOME/.claude-requirements/projects/$PROJECT_NAME/active" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
fi

# ============ 5. 输出 system-reminder ============
echo "# DevFlow 需求上下文"
echo ""
echo "- 项目：\`$PROJECT_NAME\` (${PROJECT_ROLE:-primary})"
echo "- 分支：\`${BRANCH:-<detached>}\`"

if [ -n "$REQ_ID" ]; then
    if [ -n "$REQ_FILE" ]; then
        echo "- 当前需求：**$REQ_ID** ${REQ_TITLE}"
        [ -n "$REQ_STATUS" ] && echo "  - 状态：$REQ_STATUS"
        [ -n "$REQ_MODULE" ] && echo "  - 模块：$REQ_MODULE"
        echo "  - 文档：\`$REQ_FILE\`"
    else
        echo "- 当前分支指向 **$REQ_ID**，但未找到需求文档（可能已归档或未创建）"
    fi
else
    echo "- 当前不在需求分支上"
fi

echo "- 进行中需求：$ACTIVE_COUNT 条"
echo ""
echo "💡 可用命令：\`/req\` 列表 · \`/req:status\` 详情 · \`/req:dev\` 继续开发"
