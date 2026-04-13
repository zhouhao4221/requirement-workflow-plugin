#!/bin/bash
# sync-cache.sh
# 需求文档写入后自动同步到全局缓存
# 由 PostToolUse Hook 触发（Write/Edit 工具操作后）
#
# 触发缓存更新的命令（涉及需求文档修改）：
#   - /req:new        创建需求文档
#   - /req:new-quick  创建快速修复文档
#   - /req:edit       编辑需求文档
#   - /req:review     更新评审状态
#   - /req:dev        更新开发状态和进度
#   - /req:test       更新测试状态和结果
#   - /req:done       完成归档（移动到 completed/）
#   - /req:upgrade    升级 QUICK 为 REQ
#   - /req:modules new 创建模块文档
#   - /req:prd-edit    编辑 PRD 文档
#   - /req:specs new   创建规范文档
#   - /req:specs edit  编辑规范文档
#
# 不触发缓存更新的命令（只读操作）：
#   - /req, /req:status, /req:projects, /req:cache, /req:use
#   - /req:init, /req:migrate, /req:test_regression, /req:test_new
#   - /req:prd

# 从 stdin JSON 中提取文件路径（PostToolUse hook 通过 stdin 传入工具信息）
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# 空路径或文件不存在，静默跳过
if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

# 仅处理 docs/requirements/ 目录下的 .md 文件
if [[ ! "$FILE_PATH" =~ docs/requirements/.+\.md$ ]]; then
    exit 0
fi

# 检查文件类型
FILENAME=$(basename "$FILE_PATH")
IS_REQUIREMENT=false
IS_MODULE=false
IS_PRD=false
IS_SPEC=false

# REQ 或 QUICK 需求文档
if [[ "$FILENAME" =~ ^(REQ|QUICK)-[0-9]+ ]]; then
    IS_REQUIREMENT=true
# 模块文档
elif [[ "$FILE_PATH" =~ docs/requirements/modules/ ]]; then
    IS_MODULE=true
# 规范文档
elif [[ "$FILE_PATH" =~ docs/requirements/specs/ ]]; then
    IS_SPEC=true
# PRD 文档
elif [[ "$FILENAME" = "PRD.md" ]]; then
    IS_PRD=true
# 其他文件（INDEX.md、template.md 等）不同步
else
    exit 0
fi

# 查找项目根目录（向上查找 .claude 目录）
find_project_root() {
    local dir="$1"
    while [ "$dir" != "/" ]; do
        if [ -d "$dir/.claude" ]; then
            echo "$dir"
            return 0
        fi
        dir=$(dirname "$dir")
    done
    return 1
}

PROJECT_ROOT=$(find_project_root "$(dirname "$FILE_PATH")")
if [ -z "$PROJECT_ROOT" ]; then
    exit 0
fi

# 读取绑定的项目名称
SETTINGS_FILE="$PROJECT_ROOT/.claude/settings.local.json"
if [ ! -f "$SETTINGS_FILE" ]; then
    exit 0
fi

PROJECT_NAME=$(grep -o '"requirementProject"[[:space:]]*:[[:space:]]*"[^"]*"' "$SETTINGS_FILE" | sed 's/.*"requirementProject"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
if [ -z "$PROJECT_NAME" ]; then
    exit 0
fi

# 只读仓库不执行缓存同步
ROLE=$(grep -o '"requirementRole"[[:space:]]*:[[:space:]]*"[^"]*"' "$SETTINGS_FILE" | sed 's/.*"requirementRole"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
if [ "$ROLE" = "readonly" ]; then
    exit 0
fi

# 全局缓存目录
CACHE_ROOT="$HOME/.claude-requirements/projects/$PROJECT_NAME"
if [ ! -d "$CACHE_ROOT" ]; then
    # 缓存目录不存在，可能项目尚未初始化，跳过
    exit 0
fi

# 计算相对路径并确定目标路径
# FILE_PATH: /path/to/project/docs/requirements/active/REQ-001-xxx.md
# 需要转换为: ~/.claude-requirements/projects/xxx/active/REQ-001-xxx.md
REL_PATH="${FILE_PATH#$PROJECT_ROOT/docs/requirements/}"

# 检查是活跃需求还是已完成需求
if [[ "$REL_PATH" =~ ^active/ ]]; then
    TARGET_DIR="$CACHE_ROOT/active"
elif [[ "$REL_PATH" =~ ^completed/ ]]; then
    TARGET_DIR="$CACHE_ROOT/completed"
elif [[ "$REL_PATH" =~ ^modules/ ]]; then
    TARGET_DIR="$CACHE_ROOT/modules"
elif [[ "$REL_PATH" =~ ^specs/ ]]; then
    TARGET_DIR="$CACHE_ROOT/specs"
else
    # 可能是根目录下的文件（如 INDEX.md），同步到缓存根目录
    TARGET_DIR="$CACHE_ROOT"
fi

# 确保目标目录存在
mkdir -p "$TARGET_DIR"

# 同步文件
TARGET_FILE="$TARGET_DIR/$FILENAME"
cp "$FILE_PATH" "$TARGET_FILE"

if [ $? -eq 0 ]; then
    echo "已同步到缓存: $PROJECT_NAME"
else
    echo "缓存同步失败: $TARGET_FILE" >&2
    exit 1
fi
